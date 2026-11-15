package chat

import (
	"database/sql"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

const msgColumns = "id,chat_id,seq,sender,client_id,kind,text,media_id,reply_to,created,edited,deleted,entities_json,preview_json,reply_markup_json,via_bot_id,forward_origin_json,media_meta_json,album_id"

type scanner interface{ Scan(...any) error }

func scanMessage(row scanner) (Message, error) {
	var m Message
	var d int
	var entities, preview, markup, origin, meta, album string
	e := row.Scan(&m.ID, &m.ChatID, &m.Seq, &m.Sender, &m.ClientID, &m.Kind, &m.Text, &m.MediaID, &m.ReplyTo, &m.Created, &m.Edited, &d, &entities, &preview, &markup, &m.ViaBotID, &origin, &meta, &album)
	m.Deleted = d == 1
	m.AlbumID = album
	m.Entities = []Entity{}
	json.Unmarshal([]byte(entities), &m.Entities)
	if preview != "" {
		json.Unmarshal([]byte(preview), &m.LinkPreview)
	}
	if markup != "" {
		json.Unmarshal([]byte(markup), &m.ReplyMarkup)
	}
	if origin != "" {
		m.ForwardOrigin = json.RawMessage(origin)
	}
	if meta != "" {
		var info MediaInfo
		if json.Unmarshal([]byte(meta), &info) == nil {
			if info.ID == "" {
				info.ID = m.MediaID
			}
			m.Media = &info
		}
	}
	return m, e
}
func (a *App) CreateChat(p Principal, kind, title string, ids []string) (string, error) {
	if kind != "direct" && kind != "group" && kind != "channel" {
		return "", ErrInvalid
	}
	set := map[string]bool{p.UserID: true}
	for _, u := range ids {
		set[u] = true
	}
	users := []string{}
	for u := range set {
		users = append(users, u)
	}
	sort.Strings(users)
	if len(title) > 200 || (kind == "direct" && (len(users) != 2 || title != "")) || (kind != "direct" && (strings.TrimSpace(title) == "" || len(users) < 1 || len(users) > 1000)) || (kind == "group" && len(users) < 2) {
		return "", ErrInvalid
	}
	cid := id()
	e := a.transaction(func(tx *sql.Tx) error {
		var pair any
		if kind == "direct" {
			pair = strings.Join(users, ":")
			var old string
			e := tx.QueryRow("SELECT id FROM chats WHERE pair=?", pair).Scan(&old)
			if e == nil {
				cid = old
				var seq int64
				if e = tx.QueryRow("SELECT last_seq FROM chats WHERE id=?", cid).Scan(&seq); e != nil {
					return e
				}
				added := false
				for _, u := range users {
					var n int
					if e = tx.QueryRow("SELECT count(*) FROM members WHERE chat_id=? AND user_id=?", cid, u).Scan(&n); e != nil {
						return e
					}
					if n > 0 {
						continue
					}
					if _, e = tx.Exec("INSERT INTO members(chat_id,user_id,role,joined_seq,read_seq,joined_at) VALUES(?,?,'member',?,?,unixepoch())", cid, u, seq, seq); e != nil {
						return e
					}
					added = true
				}
				if !added {
					return nil
				}
				mems, e := members(tx, cid)
				if e != nil {
					return e
				}
				return emit(tx, mems, "conversation.created", cid, map[string]any{"id": cid, "kind": kind, "title": "", "members": mems})
			}
			if !errors.Is(e, sql.ErrNoRows) {
				return e
			}
		}
		if _, e := tx.Exec("INSERT INTO chats(id,kind,title,pair,created_by,last_activity) VALUES(?,?,?,?,?,?)", cid, kind, title, pair, p.UserID, time.Now().UnixMicro()); e != nil {
			return e
		}
		for _, u := range users {
			role := "member"
			if u == p.UserID {
				role = "owner"
			}
			if _, e := tx.Exec("INSERT INTO members(chat_id,user_id,role,joined_at) VALUES(?,?,?,unixepoch())", cid, u, role); e != nil {
				return ErrInvalid
			}
		}
		return emit(tx, users, "conversation.created", cid, map[string]any{"id": cid, "kind": kind, "title": title, "members": users})
	})
	return cid, e
}
func (a *App) ChangeMember(p Principal, cid, user, action, role string) error {
	return a.transaction(func(tx *sql.Tx) error {
		caller, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var kind string
		var seq int64
		if e = tx.QueryRow("SELECT kind,last_seq FROM chats WHERE id=?", cid).Scan(&kind, &seq); e != nil {
			return e
		}
		if kind != "group" && kind != "channel" {
			return ErrForbidden
		}
		target, _, te := member(tx, cid, user)
		if te != nil && !errors.Is(te, ErrForbidden) {
			return te
		}
		if caller != "owner" && caller != "admin" {
			if action != "remove" || user != p.UserID {
				return ErrForbidden
			}
		}
		if target == "owner" {
			return ErrForbidden
		}
		if caller == "admin" && target == "admin" && user != p.UserID {
			return ErrForbidden
		}
		before, e := members(tx, cid)
		if e != nil {
			return e
		}
		switch action {
		case "add":
			var banned int
			if err := tx.QueryRow("SELECT count(*) FROM bans WHERE chat_id=? AND user_id=?", cid, user).Scan(&banned); err != nil {
				return err
			}
			if banned > 0 {
				return ErrForbidden
			}
			if te != nil && len(before) >= 100 {
				return ErrInvalid
			}
			if te == nil {
				return nil
			}
			_, e = tx.Exec("INSERT INTO members(chat_id,user_id,role,joined_seq,read_seq,joined_at) VALUES(?,?,'member',?,?,unixepoch())", cid, user, seq, seq)
			before = append(before, user)
		case "remove":
			if te != nil {
				return te
			}
			_, e = tx.Exec("DELETE FROM members WHERE chat_id=? AND user_id=?", cid, user)
		case "role":
			if caller != "owner" || (role != "admin" && role != "member") || te != nil {
				return ErrForbidden
			}
			_, e = tx.Exec("UPDATE members SET role=? WHERE chat_id=? AND user_id=?", role, cid, user)
		default:
			return ErrInvalid
		}
		if e != nil {
			return e
		}
		if caller == "owner" || caller == "admin" {
			if e = audit(tx, cid, p.UserID, "member."+action, user, map[string]string{"role": role}); e != nil {
				return e
			}
		}
		return emit(tx, before, "membership.changed", cid, map[string]any{"user_id": user, "action": action, "role": role, "joined_seq": seq})
	})
}
func (a *App) SendMessage(p Principal, cid string, s Send) (Message, error) {
	if s.MediaID != "" {
		a.mediaMu.Lock()
		defer a.mediaMu.Unlock()
	}
	if s.Kind == "" {
		s.Kind = "text"
	}
	if len(s.ClientID) < 1 || len(s.ClientID) > 128 || len(s.Text) > 16384 || !utf8.ValidString(s.Text) {
		return Message{}, ErrInvalid
	}
	if s.Kind != "text" && s.Kind != "image" && s.Kind != "voice" && s.Kind != "file" && s.Kind != "video" && s.Kind != "sticker" && s.Kind != "poll" && s.Kind != "checklist" {
		return Message{}, ErrInvalid
	}
	if s.AlbumID != "" && (len(s.AlbumID) > 64 || !albumIDRE.MatchString(s.AlbumID) || s.Kind == "text") {
		return Message{}, ErrInvalid
	}
	if s.Kind == "text" && (strings.TrimSpace(s.Text) == "" || s.MediaID != "") {
		return Message{}, ErrInvalid
	}
	if s.Kind != "text" && s.Kind != "poll" && s.Kind != "checklist" && s.MediaID == "" && s.StickerID == "" {
		return Message{}, ErrInvalid
	}
	var ve error
	s.Entities, ve = validateEntities(s.Text, s.Entities)
	if ve != nil {
		return Message{}, ve
	}
	if ve = validateMarkup(s.ReplyMarkup); ve != nil {
		return Message{}, ve
	}
	if s.ViaBotID != "" {
		return Message{}, ErrForbidden
	}
	body, _ := json.Marshal(struct {
		Chat    string
		Payload Send
	}{cid, s})
	digest := hash(string(body))
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		_, joined, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var oldHash string
		e = tx.QueryRow("SELECT payload_hash FROM messages WHERE sender=? AND client_id=?", p.UserID, s.ClientID).Scan(&oldHash)
		if e == nil {
			if oldHash != digest {
				return ErrConflict
			}
			out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE sender=? AND client_id=?", p.UserID, s.ClientID))
			return e
		}
		if !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		if e = a.checkSend(tx, p, cid, s); e != nil {
			return e
		}
		preview, e := previewForSend(tx, s)
		if e != nil {
			return e
		}
		if s.ReplyTo != "" {
			var n int
			e = tx.QueryRow("SELECT count(*) FROM messages WHERE id=? AND chat_id=? AND seq>? AND deleted=0", s.ReplyTo, cid, joined).Scan(&n)
			if e != nil {
				return e
			}
			if n != 1 {
				return ErrInvalid
			}
		}
		if s.MediaID != "" {
			var mime string
			e = tx.QueryRow(`SELECT mime FROM media WHERE id=? AND (owner=? OR chat_id=? OR EXISTS(SELECT 1 FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.media_id=? AND b.user_id=? AND m.deleted=0))`, s.MediaID, p.UserID, cid, s.MediaID, p.UserID).Scan(&mime)
			if e != nil {
				return ErrInvalid
			}
			if s.Kind == "image" && !strings.HasPrefix(mime, "image/") {
				return ErrInvalid
			}
			if s.Kind == "voice" && !strings.HasPrefix(mime, "audio/") {
				return ErrInvalid
			}
			if s.Kind == "video" && !strings.HasPrefix(mime, "video/") {
				return ErrInvalid
			}
		}
		if s.Kind == "sticker" {
			if s.StickerID == "" {
				return ErrInvalid
			}
			var mid, fid, emoji string
			if e = tx.QueryRow("SELECT media_id,file_id,emoji FROM stickers s JOIN sticker_packs p ON p.id=s.pack_id WHERE s.id=? AND (p.owner='' OR p.owner=?)", s.StickerID, p.UserID).Scan(&mid, &fid, &emoji); e != nil {
				return ErrInvalid
			}
			s.MediaID = mid
			if s.Text == "" {
				s.Text = emoji
			}
		}
		var seq int64
		if e = tx.QueryRow("UPDATE chats SET last_seq=last_seq+1,last_activity=? WHERE id=? RETURNING last_seq", time.Now().UnixMicro(), cid).Scan(&seq); e != nil {
			return e
		}
		out = Message{ID: id(), ChatID: cid, Seq: seq, Sender: p.UserID, ClientID: s.ClientID, Kind: s.Kind, Text: s.Text, MediaID: s.MediaID, AlbumID: s.AlbumID, ReplyTo: s.ReplyTo, Created: now(), Entities: s.Entities, LinkPreview: preview, ReplyMarkup: s.ReplyMarkup, ViaBotID: s.ViaBotID}
		if s.Kind == "sticker" {
			info := MediaInfo{FileName: s.StickerID, MIME: "image/png"}
			if s.MediaID != "" {
				info.ID = s.MediaID
			}
			out.Media = &info
		}
		if out.Entities == nil {
			out.Entities = []Entity{}
		}
		if s.MediaID != "" {
			meta, e2 := mediaSnapshot(tx, s.MediaID)
			if e2 != nil {
				return e2
			}
			out.Media = meta
		}
		if s.ReplyTo != "" {
			_ = tx.QueryRow("SELECT seq FROM messages WHERE id=?", s.ReplyTo).Scan(&out.ReplyToSeq)
		}
		_, e = tx.Exec("INSERT INTO messages(id,chat_id,seq,sender,client_id,kind,text,media_id,reply_to,payload_hash,created,entities_json,preview_json,reply_markup_json,via_bot_id,forward_origin_json,media_meta_json,album_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", out.ID, cid, seq, p.UserID, s.ClientID, s.Kind, s.Text, s.MediaID, s.ReplyTo, digest, out.Created, jsonText(s.Entities, "[]"), jsonText(preview, ""), jsonText(s.ReplyMarkup, ""), s.ViaBotID, "", jsonText(out.Media, ""), s.AlbumID)
		if e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message.created", cid, out); e != nil {
			return e
		}
		if e = a.recordMentions(tx, cid, out); e != nil {
			return e
		}
		if e = a.emitDialogStates(tx, users, cid); e != nil {
			return e
		}
		for _, u := range users {
			if u != p.UserID {
				if _, e = tx.Exec("INSERT INTO push_jobs(id,user_id,chat_id,msg_id,next_at) VALUES(?,?,?,?,?)", id(), u, cid, out.ID, time.Now().Unix()); e != nil {
					return e
				}
			}
		}
		return nil
	})
	return out, e
}
func (a *App) AlterMessage(p Principal, mid, action, text string) error {
	if action == "edit" {
		return a.EditMessage(p, mid, Send{Text: text})
	}
	if len(text) > 16384 || !utf8.ValidString(text) {
		return ErrInvalid
	}
	return a.transaction(func(tx *sql.Tx) error {
		m, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil {
			return ErrForbidden
		}
		role, joined, e := member(tx, m.ChatID, p.UserID)
		if e != nil || m.Seq <= joined {
			return ErrForbidden
		}
		if action == "edit" {
			if m.Sender != p.UserID || m.Deleted || strings.TrimSpace(text) == "" {
				return ErrForbidden
			}
			m.Text = text
			m.Edited = now()
			_, e = tx.Exec("UPDATE messages SET text=?,edited=? WHERE id=?", m.Text, m.Edited, mid)
		} else if action == "delete" {
			if m.Sender != p.UserID && role != "owner" && role != "admin" {
				return ErrForbidden
			}
			m.Deleted = true
			m.Text = ""
			m.MediaID = ""
			m.Entities = []Entity{}
			m.LinkPreview = nil
			m.ReplyMarkup = nil
			if _, e = tx.Exec("DELETE FROM pins WHERE message_id=?", mid); e != nil {
				return e
			}
			if role == "owner" || role == "admin" {
				if e = audit(tx, m.ChatID, p.UserID, "message.delete", mid, nil); e != nil {
					return e
				}
			}
			_, e = tx.Exec("UPDATE messages SET text='',media_id='',media_meta_json='',album_id='',entities_json='[]',preview_json='',reply_markup_json='',deleted=1 WHERE id=?", mid)
		} else {
			return ErrInvalid
		}
		if e != nil {
			return e
		}
		users, e := members(tx, m.ChatID)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message."+map[string]string{"edit": "edited", "delete": "deleted"}[action], m.ChatID, m); e != nil {
			return e
		}
		if action == "delete" {
			if e = emit(tx, users, "pins.changed", m.ChatID, map[string]any{"message_id": mid, "action": "delete"}); e != nil {
				return e
			}
		}
		return a.emitDialogStates(tx, users, m.ChatID)
	})
}
func (a *App) React(p Principal, mid, emoji string, remove bool) error {
	if len(emoji) < 1 || len(emoji) > 32 || !utf8.ValidString(emoji) {
		return ErrInvalid
	}
	return a.transaction(func(tx *sql.Tx) error {
		var cid string
		var seq int64
		if e := tx.QueryRow("SELECT chat_id,seq FROM messages WHERE id=? AND deleted=0", mid).Scan(&cid, &seq); e != nil {
			return ErrForbidden
		}
		_, joined, e := member(tx, cid, p.UserID)
		if e != nil || seq <= joined {
			return ErrForbidden
		}
		if remove {
			_, e = tx.Exec("DELETE FROM reactions WHERE message_id=? AND user_id=? AND emoji=?", mid, p.UserID, emoji)
		} else {
			var n int
			if e = tx.QueryRow("SELECT count(*) FROM reactions WHERE message_id=? AND user_id=?", mid, p.UserID).Scan(&n); e != nil {
				return e
			}
			if n >= 8 {
				var exists int
				if err := tx.QueryRow("SELECT count(*) FROM reactions WHERE message_id=? AND user_id=? AND emoji=?", mid, p.UserID, emoji).Scan(&exists); err != nil {
					return err
				}
				if exists == 0 {
					return ErrInvalid
				}
			}
			_, e = tx.Exec("INSERT OR IGNORE INTO reactions(message_id,user_id,emoji) VALUES(?,?,?)", mid, p.UserID, emoji)
		}
		if e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "reaction.updated", cid, map[string]any{"message_id": mid, "user_id": p.UserID, "emoji": emoji, "removed": remove})
	})
}
func (a *App) Read(p Principal, cid string, seq int64) error {
	return a.transaction(func(tx *sql.Tx) error {
		_, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var high, old int64
		if e = tx.QueryRow("SELECT c.last_seq,m.read_seq FROM chats c JOIN members m ON m.chat_id=c.id WHERE c.id=? AND m.user_id=?", cid, p.UserID).Scan(&high, &old); e != nil {
			return e
		}
		if seq < 0 || seq > high {
			return ErrInvalid
		}
		if seq <= old {
			if _, e = tx.Exec("UPDATE members SET manual_unread=0 WHERE chat_id=? AND user_id=?", cid, p.UserID); e != nil {
				return e
			}
			return a.emitDialogStates(tx, []string{p.UserID}, cid)
		}
		if _, e = tx.Exec("UPDATE members SET read_seq=?,manual_unread=0 WHERE chat_id=? AND user_id=?", seq, cid, p.UserID); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		users, e = a.readRecipients(tx, p.UserID, cid)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "read.updated", cid, map[string]any{"user_id": p.UserID, "last_read_seq": seq}); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, cid)
	})
}
func (a *App) History(p Principal, cid string, before int64, limit int) ([]Message, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if before <= 0 {
		before = 1 << 62
	}
	rows, e := a.DB.Query("SELECT "+prefixColumns("m", msgColumns)+" FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.chat_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.seq<? ORDER BY m.seq DESC LIMIT ?", cid, p.UserID, before, limit)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		m, e := scanMessage(rows)
		if e != nil {
			return nil, e
		}
		out = append(out, m)
	}
	if e = rows.Err(); e != nil {
		return nil, e
	}
	attachReplySeqs(a.DB, out)
	a.attachPolls(out, p.UserID)
	a.attachChecklists(out)
	return out, nil
}
func prefixColumns(p, cols string) string { return p + "." + strings.ReplaceAll(cols, ",", ","+p+".") }
