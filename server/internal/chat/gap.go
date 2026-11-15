package chat

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

func (a *App) gapRoutes(mux *http.ServeMux) {
	mux.HandleFunc("DELETE /v1/conversations/{id}", a.auth(a.deleteConversation))
	mux.HandleFunc("GET /v1/conversations/{id}", a.auth(a.getConversation))
	mux.HandleFunc("POST /v1/conversations/{id}/invites", a.auth(a.createInvite))
	mux.HandleFunc("GET /v1/conversations/{id}/invites", a.auth(a.listInvites))
	mux.HandleFunc("PATCH /v1/invites/{code}", a.auth(a.editInvite))
	mux.HandleFunc("DELETE /v1/invites/{code}", a.auth(a.revokeInvite))
	mux.HandleFunc("GET /v1/invites/{code}", a.auth(a.previewInvite))
	mux.HandleFunc("POST /v1/invites/{code}/join", a.auth(a.joinInvite))
	mux.HandleFunc("POST /v1/conversations/{id}/messages/by-sender", a.auth(a.deleteBySender))
	mux.HandleFunc("POST /v1/conversations/{id}/polls/{poll_id}/options", a.auth(a.addPollOption))
	mux.HandleFunc("GET /v1/me/wallpapers", a.auth(a.listWallpapers))
	mux.HandleFunc("PUT /v1/me/wallpapers", a.auth(a.putWallpaper))
	mux.HandleFunc("DELETE /v1/me/wallpapers", a.auth(a.deleteWallpaper))
}

func (a *App) getConversation(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var kind, title, description, permissions, username, reactions string
	var slow, history, autoDelete, upgraded, protected, joinBy, sign, show, hidden, joinSend int
	e := a.DB.QueryRow("SELECT c.kind,c.title,IFNULL(c.description,''),IFNULL(c.slow_mode,0),IFNULL(c.permissions_json,''),IFNULL(c.history_for_new,0),IFNULL(c.auto_delete,0),IFNULL(c.upgraded,0),IFNULL(c.username,''),IFNULL(c.protected,0),IFNULL(c.join_by_request,0),IFNULL(c.reactions_json,''),IFNULL(c.sign_messages,0),IFNULL(c.show_sender,0),IFNULL(c.hidden_members,0),IFNULL(c.join_to_send,0) FROM chats c JOIN members b ON b.chat_id=c.id WHERE c.id=? AND b.user_id=?", cid, p.UserID).Scan(&kind, &title, &description, &slow, &permissions, &history, &autoDelete, &upgraded, &username, &protected, &joinBy, &reactions, &sign, &show, &hidden, &joinSend)
	if e != nil {
		fail(w, ErrForbidden)
		return
	}
	var perms any
	if permissions != "" {
		_ = json.Unmarshal([]byte(permissions), &perms)
	}
	var reaction any
	if reactions != "" {
		_ = json.Unmarshal([]byte(reactions), &reaction)
	}
	var pending int
	_ = a.DB.QueryRow("SELECT count(*) FROM join_requests WHERE chat_id=?", cid).Scan(&pending)
	respond(w, 200, map[string]any{"id": cid, "kind": kind, "title": title, "description": description, "slow_mode_seconds": slow, "permissions": perms, "history_for_new": history == 1, "auto_delete_seconds": autoDelete, "upgraded": upgraded == 1, "username": username, "protected": protected == 1, "join_by_request": joinBy == 1, "pending_join_requests": pending, "reactions": reaction, "sign_messages": sign == 1, "show_message_sender": show == 1, "hidden_members": hidden == 1, "join_to_send": joinSend == 1})
}

func (a *App) deleteConversation(w http.ResponseWriter, r *http.Request, p Principal) {
	if e := a.DeleteConversation(p, r.PathValue("id")); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) DeleteConversation(p Principal, cid string) error {
	return a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var kind string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		remove := []string{p.UserID}
		if kind != "direct" && role == "owner" {
			if len(users) > 1 {
				remove = users
			}
		} else if kind != "direct" && role != "owner" {
			return ErrForbidden
		}
		for _, u := range remove {
			if _, e = tx.Exec("DELETE FROM members WHERE chat_id=? AND user_id=?", cid, u); e != nil {
				return e
			}
		}
		return emit(tx, remove, "dialog.removed", cid, map[string]any{"id": cid})
	})
}

func (a *App) createInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Name               string `json:"name"`
		Expires            int64  `json:"expires"`
		MemberLimit        int    `json:"member_limit"`
		CreatesJoinRequest bool   `json:"creates_join_request"`
	}
	if !decode(w, r, &b) {
		return
	}
	if utf8.RuneCountInString(b.Name) > 32 || b.MemberLimit < 0 || b.MemberLimit > 99999 {
		fail(w, ErrInvalid)
		return
	}
	if b.Expires != 0 && b.Expires < time.Now().Unix() {
		fail(w, ErrInvalid)
		return
	}
	code := id()
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var kind string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
			return e
		}
		if kind != "group" && kind != "channel" {
			return ErrForbidden
		}
		if role != "owner" && role != "admin" {
			ok, err := memberCan(tx, cid, role, "can_invite_users")
			if err != nil {
				return err
			}
			if !ok {
				return ErrForbidden
			}
			if e = restrictionAllows(tx, cid, p.UserID, "can_invite_users"); e != nil {
				return e
			}
		}
		_, e = tx.Exec("INSERT INTO chat_invites(code,chat_id,creator,name,created,expires,member_limit,creates_join_request) VALUES(?,?,?,?,?,?,?,?)", code, cid, p.UserID, b.Name, now(), b.Expires, b.MemberLimit, boolInt(b.CreatesJoinRequest))
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, a.inviteJSON(code))
}

func (a *App) listInvites(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	role, e := a.memberRole(cid, p.UserID)
	if e != nil || (role != "owner" && role != "admin") {
		fail(w, ErrForbidden)
		return
	}
	revoked := r.URL.Query().Get("revoked")
	where := "chat_id=? AND revoked=0"
	args := []any{cid}
	switch revoked {
	case "1":
		where = "chat_id=? AND revoked=1"
	case "all":
		where = "chat_id=?"
	}
	rows, e := a.DB.Query("SELECT code FROM chat_invites WHERE "+where+" ORDER BY created", args...)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	codes := []string{}
	for rows.Next() {
		var code string
		if rows.Scan(&code) == nil {
			codes = append(codes, code)
		}
	}
	if e = rows.Err(); e != nil {
		fail(w, e)
		return
	}
	out := []any{}
	for _, code := range codes {
		out = append(out, a.inviteJSON(code))
	}
	respond(w, 200, map[string]any{"invites": out})
}

func (a *App) editInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	var b struct {
		Name               *string `json:"name"`
		Expires            *int64  `json:"expires"`
		MemberLimit        *int    `json:"member_limit"`
		CreatesJoinRequest *bool   `json:"creates_join_request"`
	}
	if !decode(w, r, &b) {
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		var cid, creator string
		var revoked int
		if e := tx.QueryRow("SELECT chat_id,creator,revoked FROM chat_invites WHERE code=?", code).Scan(&cid, &creator, &revoked); e != nil || revoked == 1 {
			return ErrForbidden
		}
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || (role != "owner" && role != "admin") {
			return ErrForbidden
		}
		if b.Name != nil {
			if utf8.RuneCountInString(*b.Name) > 32 {
				return ErrInvalid
			}
			if _, e = tx.Exec("UPDATE chat_invites SET name=? WHERE code=?", *b.Name, code); e != nil {
				return e
			}
		}
		if b.Expires != nil {
			if _, e = tx.Exec("UPDATE chat_invites SET expires=? WHERE code=?", *b.Expires, code); e != nil {
				return e
			}
		}
		if b.MemberLimit != nil {
			if *b.MemberLimit < 0 || *b.MemberLimit > 99999 {
				return ErrInvalid
			}
			if _, e = tx.Exec("UPDATE chat_invites SET member_limit=? WHERE code=?", *b.MemberLimit, code); e != nil {
				return e
			}
		}
		if b.CreatesJoinRequest != nil {
			if _, e = tx.Exec("UPDATE chat_invites SET creates_join_request=? WHERE code=?", boolInt(*b.CreatesJoinRequest), code); e != nil {
				return e
			}
		}
		return nil
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, a.inviteJSON(code))
}

func (a *App) revokeInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	e := a.transaction(func(tx *sql.Tx) error {
		var cid string
		if e := tx.QueryRow("SELECT chat_id FROM chat_invites WHERE code=? AND revoked=0", code).Scan(&cid); e != nil {
			return ErrForbidden
		}
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || (role != "owner" && role != "admin") {
			return ErrForbidden
		}
		_, e = tx.Exec("UPDATE chat_invites SET revoked=1 WHERE code=?", code)
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) previewInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	inv, e := a.loadInvite(r.PathValue("code"))
	if e != nil {
		fail(w, e)
		return
	}
	var title, kind string
	var n int
	_ = a.DB.QueryRow("SELECT title,kind FROM chats WHERE id=?", inv.ChatID).Scan(&title, &kind)
	_ = a.DB.QueryRow("SELECT count(*) FROM members WHERE chat_id=?", inv.ChatID).Scan(&n)
	respond(w, 200, map[string]any{"code": inv.Code, "chat_id": inv.ChatID, "title": title, "kind": kind, "member_count": n, "name": inv.Name, "creates_join_request": inv.CreatesJoinRequest == 1})
}

func (a *App) joinInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	var cid string
	e := a.transaction(func(tx *sql.Tx) error {
		inv, e := loadInviteTx(tx, code)
		if e != nil {
			return e
		}
		var banned int
		if e = tx.QueryRow("SELECT count(*) FROM bans WHERE chat_id=? AND user_id=?", inv.ChatID, p.UserID).Scan(&banned); e != nil {
			return e
		}
		if banned > 0 {
			return ErrForbidden
		}
		if _, _, e = member(tx, inv.ChatID, p.UserID); e == nil {
			cid = inv.ChatID
			return nil
		}
		if inv.MemberLimit > 0 && inv.Uses >= inv.MemberLimit {
			return ErrForbidden
		}
		var seq int64
		var history, joinBy int
		if e = tx.QueryRow("SELECT last_seq,IFNULL(history_for_new,0),IFNULL(join_by_request,0) FROM chats WHERE id=?", inv.ChatID).Scan(&seq, &history, &joinBy); e != nil {
			return e
		}
		if inv.CreatesJoinRequest == 1 || joinBy == 1 {
			if _, e = tx.Exec("INSERT INTO join_requests(chat_id,user_id,invite_code,created) VALUES(?,?,?,unixepoch()) ON CONFLICT(chat_id,user_id) DO UPDATE SET invite_code=excluded.invite_code,created=excluded.created", inv.ChatID, p.UserID, code); e != nil {
				return e
			}
			cid = ""
			users, e := members(tx, inv.ChatID)
			if e != nil {
				return e
			}
			return a.emitPendingJoins(tx, users, inv.ChatID)
		}
		joined := seq
		if history == 1 {
			joined = 0
		}
		if _, e = tx.Exec("INSERT INTO members(chat_id,user_id,role,joined_seq,read_seq,joined_at) VALUES(?,?,'member',?,?,unixepoch())", inv.ChatID, p.UserID, joined, joined); e != nil {
			return e
		}
		if _, e = tx.Exec("UPDATE chat_invites SET uses=uses+1 WHERE code=?", code); e != nil {
			return e
		}
		users, e := members(tx, inv.ChatID)
		if e != nil {
			return e
		}
		cid = inv.ChatID
		return emit(tx, users, "membership.changed", cid, map[string]any{"user_id": p.UserID, "action": "add", "role": "member", "joined_seq": joined})
	})
	if e != nil {
		fail(w, e)
		return
	}
	if cid == "" {
		respond(w, 200, map[string]string{"status": "requested"})
		return
	}
	respond(w, 200, map[string]string{"status": "joined", "conversation_id": cid})
}

type chatInvite struct {
	Code, ChatID, Creator, Name, Created string
	Expires                              int64
	MemberLimit, Uses, Revoked           int
	CreatesJoinRequest                   int
}

func (a *App) loadInvite(code string) (chatInvite, error) {
	return loadInviteTx(a.DB, code)
}

type rowQuery interface {
	QueryRow(string, ...any) *sql.Row
}

func loadInviteTx(q rowQuery, code string) (chatInvite, error) {
	var inv chatInvite
	e := q.QueryRow("SELECT code,chat_id,creator,name,created,expires,member_limit,uses,revoked,IFNULL(creates_join_request,0) FROM chat_invites WHERE code=?", code).Scan(&inv.Code, &inv.ChatID, &inv.Creator, &inv.Name, &inv.Created, &inv.Expires, &inv.MemberLimit, &inv.Uses, &inv.Revoked, &inv.CreatesJoinRequest)
	if e != nil || inv.Revoked == 1 {
		return inv, ErrForbidden
	}
	if inv.Expires > 0 && inv.Expires < time.Now().Unix() {
		return inv, ErrForbidden
	}
	return inv, nil
}

func (a *App) inviteJSON(code string) map[string]any {
	inv, e := a.loadInvite(code)
	if e != nil {
		return map[string]any{"code": code, "revoked": true}
	}
	var pending int
	_ = a.DB.QueryRow("SELECT count(*) FROM join_requests WHERE invite_code=?", code).Scan(&pending)
	return map[string]any{
		"code": inv.Code, "invite_link": "ql://join/" + inv.Code, "chat_id": inv.ChatID,
		"creator_id": inv.Creator, "name": inv.Name, "created": inv.Created,
		"expires": inv.Expires, "member_limit": inv.MemberLimit, "uses": inv.Uses, "revoked": false,
		"creates_join_request": inv.CreatesJoinRequest == 1, "pending_join_request_count": pending,
	}
}

func (a *App) memberRole(cid, uid string) (string, error) {
	var role string
	e := a.DB.QueryRow("SELECT role FROM members WHERE chat_id=? AND user_id=?", cid, uid).Scan(&role)
	if e != nil {
		return "", ErrForbidden
	}
	return role, nil
}

func (a *App) deleteBySender(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		UserID string `json:"user_id"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.UserID == "" {
		fail(w, ErrInvalid)
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		if b.UserID != p.UserID && role != "owner" && role != "admin" {
			return ErrForbidden
		}
		var high int64
		if e = tx.QueryRow("SELECT last_seq FROM chats WHERE id=?", cid).Scan(&high); e != nil {
			return e
		}
		if _, e = tx.Exec("UPDATE messages SET deleted=1,text='',media_id='',media_meta_json='',entities_json='[]',preview_json='',reply_markup_json='' WHERE chat_id=? AND sender=? AND deleted=0", cid, b.UserID); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "messages.deleted", cid, map[string]any{"sender_id": b.UserID, "through_seq": high})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) addPollOption(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	pid := r.PathValue("poll_id")
	var b struct {
		Text string `json:"text"`
	}
	if !decode(w, r, &b) {
		return
	}
	text := strings.TrimSpace(b.Text)
	if text == "" || utf8.RuneCountInString(text) > 100 {
		fail(w, ErrInvalid)
		return
	}
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		if !isMemberTx(tx, cid, p.UserID) {
			return ErrForbidden
		}
		var mid, creator string
		var closed int
		if e := tx.QueryRow("SELECT message_id,creator_id,closed FROM polls WHERE id=? AND chat_id=?", pid, cid).Scan(&mid, &creator, &closed); e != nil || closed == 1 || creator != p.UserID {
			return ErrForbidden
		}
		var n int
		if e := tx.QueryRow("SELECT count(*) FROM poll_options WHERE poll_id=?", pid).Scan(&n); e != nil {
			return e
		}
		if n >= 10 {
			return ErrInvalid
		}
		if _, e := tx.Exec("INSERT INTO poll_options(poll_id,option_id,text) VALUES(?,?,?)", pid, n, text); e != nil {
			return e
		}
		m, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil {
			return e
		}
		if e = a.attachPoll(tx, p.UserID, &m); e != nil {
			return e
		}
		out = m
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "message.edited", cid, m)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, out)
}

func (a *App) listWallpapers(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT chat_id,document FROM chat_wallpapers WHERE user_id=?", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []any{}
	for rows.Next() {
		var cid, doc string
		if rows.Scan(&cid, &doc) != nil {
			continue
		}
		out = append(out, map[string]any{"chat_id": cid, "background": json.RawMessage(doc)})
	}
	respond(w, 200, map[string]any{"wallpapers": out})
}

func (a *App) putWallpaper(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		ChatID     string          `json:"chat_id"`
		Background json.RawMessage `json:"background"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.ChatID == "" || len(b.Background) == 0 || len(b.Background) > 8000 || !json.Valid(b.Background) {
		fail(w, ErrInvalid)
		return
	}
	if b.ChatID != "@default" && b.ChatID != "@default-dark" && !a.isMember(b.ChatID, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	_, e := a.DB.Exec("INSERT INTO chat_wallpapers(user_id,chat_id,document) VALUES(?,?,?) ON CONFLICT(user_id,chat_id) DO UPDATE SET document=excluded.document", p.UserID, b.ChatID, string(b.Background))
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"chat_id": b.ChatID, "background": b.Background})
}

func (a *App) deleteWallpaper(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.URL.Query().Get("chat_id")
	if _, e := a.DB.Exec("DELETE FROM chat_wallpapers WHERE user_id=? AND chat_id=?", p.UserID, cid); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
