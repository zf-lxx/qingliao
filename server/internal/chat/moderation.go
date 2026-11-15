package chat

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"
)

var ErrRateLimited = errors.New("rate limited")

type GroupSettings struct {
	NewMemberHours int      `json:"new_member_hours"`
	UserRate       int      `json:"user_rate_per_min"`
	ChatRate       int      `json:"chat_rate_per_min"`
	Keywords       []string `json:"keywords"`
}

var linkPattern = regexp.MustCompile(`(?i)(https?://|www\.|(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/|\b))`)

func settings(tx *sql.Tx, cid string) (GroupSettings, error) {
	s := GroupSettings{UserRate: 120, ChatRate: 300, Keywords: []string{}}
	var k string
	e := tx.QueryRow("SELECT new_member_hours,user_rate,chat_rate,keywords_json FROM group_settings WHERE chat_id=?", cid).Scan(&s.NewMemberHours, &s.UserRate, &s.ChatRate, &k)
	if e == sql.ErrNoRows {
		return s, nil
	}
	if e != nil {
		return s, e
	}
	e = json.Unmarshal([]byte(k), &s.Keywords)
	return s, e
}
func modRole(tx *sql.Tx, cid, uid string) error {
	role, _, e := member(tx, cid, uid)
	if e != nil {
		return e
	}
	var kind string
	if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
		return e
	}
	if kind != "group" || (role != "owner" && role != "admin") {
		return ErrForbidden
	}
	return nil
}
func (a *App) checkSend(tx *sql.Tx, p Principal, cid string, s Send) error {
	if e := a.checkBlocked(tx, cid); e != nil {
		return e
	}
	var role string
	var joined, muted int64
	if e := tx.QueryRow("SELECT role,joined_at,muted_until FROM members WHERE chat_id=? AND user_id=?", cid, p.UserID).Scan(&role, &joined, &muted); e != nil {
		return ErrForbidden
	}
	if muted > time.Now().Unix() {
		return ErrForbidden
	}
	var kind string
	if e := tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
		return e
	}
	if kind == "channel" && role != "owner" && role != "admin" {
		return ErrForbidden
	}
	if kind == "group" && role != "owner" && role != "admin" {
		ok, err := memberCan(tx, cid, role, permForKind(s.Kind))
		if err != nil {
			return err
		}
		if !ok {
			return ErrForbidden
		}
		if e := restrictionAllows(tx, cid, p.UserID, permForKind(s.Kind)); e != nil {
			return e
		}
		if s.LinkPreviewID != "" || linkPattern.MatchString(s.Text) {
			ok, err = memberCan(tx, cid, role, "can_add_link_previews")
			if err != nil {
				return err
			}
			if !ok {
				return ErrForbidden
			}
			if e := restrictionAllows(tx, cid, p.UserID, "can_add_link_previews"); e != nil {
				return e
			}
		}
	}
	var slow int
	if e := tx.QueryRow("SELECT IFNULL(slow_mode,0) FROM chats WHERE id=?", cid).Scan(&slow); e != nil {
		return e
	}
	if slow > 0 && role != "owner" && role != "admin" {
		var created string
		e := tx.QueryRow("SELECT created FROM messages WHERE chat_id=? AND sender=? AND deleted=0 ORDER BY seq DESC LIMIT 1", cid, p.UserID).Scan(&created)
		if e == nil {
			sent, err := time.Parse(time.RFC3339Nano, created)
			if err != nil {
				sent, err = time.Parse(time.RFC3339, created)
			}
			if err == nil && time.Since(sent) < time.Duration(slow)*time.Second {
				return ErrRateLimited
			}
		} else if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
	}
	cfg, e := settings(tx, cid)
	if e != nil {
		return e
	}
	for _, k := range cfg.Keywords {
		if strings.Contains(strings.ToLower(s.Text), strings.ToLower(k)) {
			return ErrForbidden
		}
	}
	if role != "owner" && role != "admin" && joined > 0 && time.Now().Unix() < joined+int64(cfg.NewMemberHours)*3600 {
		blocked := s.MediaID != "" || s.ReplyMarkup != nil || linkPattern.MatchString(s.Text)
		for _, ent := range s.Entities {
			if ent.Type == "url" || ent.Type == "text_link" {
				blocked = true
			}
		}
		if blocked {
			return ErrForbidden
		}
	}
	if !a.limiter.allow("message:user:"+p.UserID, 120, time.Minute) || !a.limiter.allow("message:member:"+cid+":"+p.UserID, cfg.UserRate, time.Minute) || !a.limiter.allow("message:chat:"+cid, cfg.ChatRate, time.Minute) {
		return ErrRateLimited
	}
	return nil
}
func (a *App) EditMessage(p Principal, mid string, s Send) error {
	if len(s.Text) > 16384 || strings.TrimSpace(s.Text) == "" {
		return ErrInvalid
	}
	var e error
	s.Entities, e = validateEntities(s.Text, s.Entities)
	if e != nil {
		return e
	}
	if e = validateMarkup(s.ReplyMarkup); e != nil {
		return e
	}
	if s.ViaBotID != "" {
		return ErrForbidden
	}
	return a.transaction(func(tx *sql.Tx) error {
		m, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil || m.Sender != p.UserID || m.Deleted {
			return ErrForbidden
		}
		_, joined, e := member(tx, m.ChatID, p.UserID)
		if e != nil || m.Seq <= joined {
			return ErrForbidden
		}
		if e = a.checkSend(tx, p, m.ChatID, s); e != nil {
			return e
		}
		preview, e := previewForSend(tx, s)
		if e != nil {
			return e
		}
		m.Text = s.Text
		m.Entities = s.Entities
		m.LinkPreview = preview
		m.ReplyMarkup = s.ReplyMarkup
		m.Edited = now()
		_, e = tx.Exec("UPDATE messages SET text=?,entities_json=?,preview_json=?,reply_markup_json=?,edited=? WHERE id=?", m.Text, jsonText(m.Entities, "[]"), jsonText(preview, ""), jsonText(s.ReplyMarkup, ""), m.Edited, mid)
		if e != nil {
			return e
		}
		if _, e = tx.Exec("DELETE FROM message_mentions WHERE message_id=?", mid); e != nil {
			return e
		}
		if e = a.recordMentions(tx, m.ChatID, m); e != nil {
			return e
		}
		users, e := members(tx, m.ChatID)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message.edited", m.ChatID, m); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, m.ChatID)
	})
}
func (a *App) groupSettings(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var cfg GroupSettings
	e := a.transaction(func(tx *sql.Tx) error {
		if e := modRole(tx, cid, p.UserID); e != nil {
			return e
		}
		if r.Method == "GET" {
			var e error
			cfg, e = settings(tx, cid)
			return e
		}
		if !decode(w, r, &cfg) {
			return errResponded
		}
		if cfg.NewMemberHours < 0 || cfg.NewMemberHours > 720 || cfg.UserRate < 1 || cfg.UserRate > 600 || cfg.ChatRate < 1 || cfg.ChatRate > 10000 || len(cfg.Keywords) > 100 {
			return ErrInvalid
		}
		for _, k := range cfg.Keywords {
			if len(k) < 1 || len(k) > 100 {
				return ErrInvalid
			}
		}
		_, e := tx.Exec("INSERT INTO group_settings(chat_id,new_member_hours,user_rate,chat_rate,keywords_json) VALUES(?,?,?,?,?) ON CONFLICT(chat_id) DO UPDATE SET new_member_hours=excluded.new_member_hours,user_rate=excluded.user_rate,chat_rate=excluded.chat_rate,keywords_json=excluded.keywords_json", cid, cfg.NewMemberHours, cfg.UserRate, cfg.ChatRate, jsonText(cfg.Keywords, "[]"))
		if e != nil {
			return e
		}
		if e = audit(tx, cid, p.UserID, "settings.update", cid, cfg); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "settings.updated", cid, map[string]any{"new_member_hours": cfg.NewMemberHours})
	})
	if e == errResponded {
		return
	}
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, cfg)
}

var errResponded = errors.New("response already written")

func (a *App) moderate(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Action  string `json:"action"`
		UserID  string `json:"user_id"`
		Minutes int    `json:"duration_minutes"`
		Reason  string `json:"reason"`
	}
	if !decode(w, r, &b) {
		return
	}
	if len(b.Reason) > 300 {
		fail(w, ErrInvalid)
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if e := modRole(tx, cid, p.UserID); e != nil {
			return e
		}
		caller, _, _ := member(tx, cid, p.UserID)
		target, _, _ := member(tx, cid, b.UserID)
		if b.UserID == p.UserID || target == "owner" || (caller == "admin" && target == "admin") {
			return ErrForbidden
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		switch b.Action {
		case "ban":
			_, e = tx.Exec("INSERT INTO bans(chat_id,user_id,actor_id,reason,created) VALUES(?,?,?,?,?) ON CONFLICT(chat_id,user_id) DO UPDATE SET actor_id=excluded.actor_id,reason=excluded.reason,created=excluded.created", cid, b.UserID, p.UserID, b.Reason, now())
			if e == nil {
				_, e = tx.Exec("DELETE FROM members WHERE chat_id=? AND user_id=?", cid, b.UserID)
			}
		case "unban":
			_, e = tx.Exec("DELETE FROM bans WHERE chat_id=? AND user_id=?", cid, b.UserID)
		case "mute", "unmute":
			until := int64(0)
			if b.Action == "mute" {
				if b.Minutes < 1 || b.Minutes > 43200 {
					return ErrInvalid
				}
				until = time.Now().Add(time.Duration(b.Minutes) * time.Minute).Unix()
			}
			res, err := tx.Exec("UPDATE members SET muted_until=? WHERE chat_id=? AND user_id=?", until, cid, b.UserID)
			e = err
			if err == nil {
				n, _ := res.RowsAffected()
				if n == 0 {
					return ErrForbidden
				}
			}
		case "delete_all":
			var high int64
			if e = tx.QueryRow("SELECT last_seq FROM chats WHERE id=?", cid).Scan(&high); e != nil {
				return e
			}
			if _, e = tx.Exec("DELETE FROM pins WHERE message_id IN(SELECT id FROM messages WHERE chat_id=? AND sender=?)", cid, b.UserID); e != nil {
				return e
			}
			_, e = tx.Exec("UPDATE messages SET deleted=1,text='',media_id='',entities_json='[]',preview_json='',reply_markup_json='' WHERE chat_id=? AND sender=?", cid, b.UserID)
			if e == nil {
				e = emit(tx, users, "messages.deleted", cid, map[string]any{"sender_id": b.UserID, "through_seq": high})
			}
			if e == nil {
				e = emit(tx, users, "pins.changed", cid, map[string]string{"action": "purge"})
			}
		default:
			return ErrInvalid
		}
		if e != nil {
			return e
		}
		if b.Action == "ban" {
			if e = emit(tx, users, "membership.changed", cid, map[string]string{"user_id": b.UserID, "action": "remove", "reason": "ban"}); e != nil {
				return e
			}
		}
		if e = audit(tx, cid, p.UserID, "moderation."+b.Action, b.UserID, map[string]any{"reason": b.Reason, "duration_minutes": b.Minutes}); e != nil {
			return e
		}
		if e = emit(tx, users, "moderation.updated", cid, map[string]any{"action": b.Action, "user_id": b.UserID, "duration_minutes": b.Minutes}); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, cid)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
func (a *App) auditList(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error { return modRole(tx, cid, p.UserID) })
	if e != nil {
		fail(w, e)
		return
	}
	rows, e := a.DB.Query("SELECT id,actor_id,action,target_id,details_json,created FROM audit_log WHERE chat_id=? ORDER BY id DESC LIMIT 100", cid)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id int64
		var actor, action, target, details, created string
		if e = rows.Scan(&id, &actor, &action, &target, &details, &created); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"id": id, "actor_id": actor, "action": action, "target_id": target, "details": json.RawMessage(details), "created_at": created})
	}
	respond(w, 200, map[string]any{"audit": out})
}

func (a *App) uploadPermission(p Principal, cid string) error {
	return a.transaction(func(tx *sql.Tx) error {
		if e := a.checkBlocked(tx, cid); e != nil {
			return e
		}
		var role string
		var joined, muted int64
		if e := tx.QueryRow("SELECT role,joined_at,muted_until FROM members WHERE chat_id=? AND user_id=?", cid, p.UserID).Scan(&role, &joined, &muted); e != nil {
			return ErrForbidden
		}
		if muted > time.Now().Unix() {
			return ErrForbidden
		}
		cfg, e := settings(tx, cid)
		if e != nil {
			return e
		}
		if role != "owner" && role != "admin" && joined > 0 && time.Now().Unix() < joined+int64(cfg.NewMemberHours)*3600 {
			return ErrForbidden
		}
		return nil
	})
}
