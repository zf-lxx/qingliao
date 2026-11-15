package chat

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func (a *App) round3Routes(mux *http.ServeMux) {
	mux.HandleFunc("PUT /v1/conversations/{id}/username", a.auth(a.setChatUsername))
	mux.HandleFunc("PUT /v1/conversations/{id}/protected", a.auth(a.setProtected))
	mux.HandleFunc("PUT /v1/conversations/{id}/join-by-request", a.auth(a.setJoinByRequest))
	mux.HandleFunc("GET /v1/conversations/{id}/join-requests", a.auth(a.listJoinRequests))
	mux.HandleFunc("POST /v1/conversations/{id}/join-requests", a.auth(a.processJoinRequests))
	mux.HandleFunc("POST /v1/conversations/{id}/join-requests/{user}", a.auth(a.processJoinRequest))
	mux.HandleFunc("GET /v1/conversations/{id}/by-date", a.auth(a.messageByDate))
	mux.HandleFunc("GET /v1/conversations/{id}/polls/{poll_id}/voters", a.auth(a.pollVoters))
	mux.HandleFunc("PATCH /v1/messages/{id}/media", a.auth(a.editMedia))
	mux.HandleFunc("PATCH /v1/scheduled/{id}", a.auth(a.reschedule))
	mux.HandleFunc("POST /v1/scheduled/{id}/send", a.auth(a.sendScheduledNow))
	mux.HandleFunc("GET /v1/public/{username}", a.auth(a.publicLookup))
	mux.HandleFunc("POST /v1/public/{username}/join", a.auth(a.publicJoin))
}

func (a *App) attachDialogFlags(out []map[string]any) error {
	if len(out) == 0 {
		return nil
	}
	ids := make([]any, len(out))
	ph := make([]string, len(out))
	for i, d := range out {
		ids[i] = d["id"]
		ph[i] = "?"
	}
	rows, e := a.DB.Query("SELECT id,IFNULL(upgraded,0),IFNULL(auto_delete,0),IFNULL(history_for_new,0),IFNULL(username,''),IFNULL(protected,0),IFNULL(join_by_request,0),(SELECT count(*) FROM join_requests j WHERE j.chat_id=chats.id) FROM chats WHERE id IN ("+strings.Join(ph, ",")+")", ids...)
	if e != nil {
		return e
	}
	defer rows.Close()
	type flags struct {
		upgraded, auto, history, protected, joinBy, pending int
		username                                            string
	}
	found := map[string]flags{}
	for rows.Next() {
		var id string
		var f flags
		if e = rows.Scan(&id, &f.upgraded, &f.auto, &f.history, &f.username, &f.protected, &f.joinBy, &f.pending); e != nil {
			return e
		}
		found[id] = f
	}
	if e = rows.Err(); e != nil {
		return e
	}
	for _, d := range out {
		f := found[d["id"].(string)]
		d["upgraded"] = f.upgraded == 1
		d["auto_delete_seconds"] = f.auto
		d["history_for_new"] = f.history == 1
		d["username"] = f.username
		d["protected"] = f.protected == 1
		d["join_by_request"] = f.joinBy == 1
		d["pending_join_requests"] = f.pending
	}
	return nil
}

func (a *App) emitPendingJoins(tx *sql.Tx, users []string, cid string) error {
	var n int
	if e := tx.QueryRow("SELECT count(*) FROM join_requests WHERE chat_id=?", cid).Scan(&n); e != nil {
		return e
	}
	return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "pending_join_requests": n})
}

func groupAdmin(tx *sql.Tx, cid, uid string) error {
	role, _, e := member(tx, cid, uid)
	if e != nil {
		return e
	}
	var kind string
	if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
		return e
	}
	if (kind != "group" && kind != "channel") || (role != "owner" && role != "admin") {
		return ErrForbidden
	}
	return nil
}

func (a *App) setChatUsername(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Username string `json:"username"`
	}
	if !decode(w, r, &b) {
		return
	}
	name := strings.ToLower(strings.TrimPrefix(strings.TrimSpace(b.Username), "@"))
	if name != "" && !validHandle(name) {
		fail(w, ErrInvalid)
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || role != "owner" {
			return ErrForbidden
		}
		var kind string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
			return e
		}
		if kind != "group" && kind != "channel" {
			return ErrForbidden
		}
		if name != "" {
			var n int
			if e = tx.QueryRow("SELECT count(*) FROM users WHERE lower(handle)=?", name).Scan(&n); e != nil {
				return e
			}
			if n > 0 {
				return ErrConflict
			}
			if e = tx.QueryRow("SELECT count(*) FROM chats WHERE username=? AND id<>?", name, cid).Scan(&n); e != nil {
				return e
			}
			if n > 0 {
				return ErrConflict
			}
		}
		if _, e = tx.Exec("UPDATE chats SET username=? WHERE id=?", name, cid); e != nil {
			return ErrConflict
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "username": name})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"username": name})
}

func (a *App) setProtected(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Enabled bool `json:"enabled"`
	}
	if !decode(w, r, &b) {
		return
	}
	v := 0
	if b.Enabled {
		v = 1
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if e := groupAdmin(tx, cid, p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("UPDATE chats SET protected=? WHERE id=?", v, cid); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "protected": b.Enabled})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"protected": b.Enabled})
}

func (a *App) setJoinByRequest(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Enabled bool `json:"enabled"`
		Apply   bool `json:"apply_to_invite_links"`
	}
	if !decode(w, r, &b) {
		return
	}
	v := 0
	if b.Enabled {
		v = 1
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if e := groupAdmin(tx, cid, p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("UPDATE chats SET join_by_request=? WHERE id=?", v, cid); e != nil {
			return e
		}
		if b.Apply {
			if _, e := tx.Exec("UPDATE chat_invites SET creates_join_request=? WHERE chat_id=? AND revoked=0", v, cid); e != nil {
				return e
			}
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "join_by_request": b.Enabled})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"join_by_request": b.Enabled})
}

func (a *App) listJoinRequests(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	if e := a.transaction(func(tx *sql.Tx) error { return groupAdmin(tx, cid, p.UserID) }); e != nil {
		fail(w, e)
		return
	}
	rows, e := a.DB.Query("SELECT user_id,created,invite_code FROM join_requests WHERE chat_id=? ORDER BY created,user_id", cid)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var uid, code string
		var created int64
		if e = rows.Scan(&uid, &created, &code); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"user_id": uid, "date": created, "invite_code": code})
	}
	respond(w, 200, map[string]any{"requests": out})
}

func (a *App) decideJoin(tx *sql.Tx, cid, actor, target string, approve bool) error {
	if e := groupAdmin(tx, cid, actor); e != nil {
		return e
	}
	var code string
	if e := tx.QueryRow("SELECT invite_code FROM join_requests WHERE chat_id=? AND user_id=?", cid, target).Scan(&code); e != nil {
		return ErrForbidden
	}
	if _, e := tx.Exec("DELETE FROM join_requests WHERE chat_id=? AND user_id=?", cid, target); e != nil {
		return e
	}
	if !approve {
		return nil
	}
	if _, _, e := member(tx, cid, target); e == nil {
		return nil
	}
	var banned int
	if e := tx.QueryRow("SELECT count(*) FROM bans WHERE chat_id=? AND user_id=?", cid, target).Scan(&banned); e != nil {
		return e
	}
	if banned > 0 {
		return ErrForbidden
	}
	var seq int64
	var history int
	if e := tx.QueryRow("SELECT last_seq,IFNULL(history_for_new,0) FROM chats WHERE id=?", cid).Scan(&seq, &history); e != nil {
		return e
	}
	joined := seq
	if history == 1 {
		joined = 0
	}
	if _, e := tx.Exec("INSERT INTO members(chat_id,user_id,role,joined_seq,read_seq,joined_at) VALUES(?,?,'member',?,?,unixepoch())", cid, target, joined, joined); e != nil {
		return e
	}
	if code != "" {
		if _, e := tx.Exec("UPDATE chat_invites SET uses=uses+1 WHERE code=?", code); e != nil {
			return e
		}
	}
	users, e := members(tx, cid)
	if e != nil {
		return e
	}
	return emit(tx, users, "membership.changed", cid, map[string]any{"user_id": target, "action": "add", "role": "member", "joined_seq": joined})
}

func (a *App) processJoinRequest(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	uid := r.PathValue("user")
	var b struct {
		Approve bool `json:"approve"`
	}
	if !decode(w, r, &b) {
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if e := a.decideJoin(tx, cid, p.UserID, uid, b.Approve); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return a.emitPendingJoins(tx, users, cid)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) processJoinRequests(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Approve bool `json:"approve"`
	}
	if !decode(w, r, &b) {
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if e := groupAdmin(tx, cid, p.UserID); e != nil {
			return e
		}
		rows, e := tx.Query("SELECT user_id FROM join_requests WHERE chat_id=?", cid)
		if e != nil {
			return e
		}
		ids := []string{}
		for rows.Next() {
			var id string
			if e = rows.Scan(&id); e != nil {
				rows.Close()
				return e
			}
			ids = append(ids, id)
		}
		rows.Close()
		if e = rows.Err(); e != nil {
			return e
		}
		for _, id := range ids {
			if e = a.decideJoin(tx, cid, p.UserID, id, b.Approve); e != nil {
				return e
			}
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return a.emitPendingJoins(tx, users, cid)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) messageByDate(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	at, e := strconv.ParseInt(r.URL.Query().Get("at"), 10, 64)
	if e != nil || at <= 0 {
		fail(w, ErrInvalid)
		return
	}
	var joined int64
	if e = a.DB.QueryRow("SELECT joined_seq FROM members WHERE chat_id=? AND user_id=?", cid, p.UserID).Scan(&joined); e != nil {
		fail(w, ErrForbidden)
		return
	}
	m, e := scanMessage(a.DB.QueryRow("SELECT "+prefixColumns("m", msgColumns)+" FROM messages m WHERE m.chat_id=? AND m.deleted=0 AND m.seq>? AND unixepoch(substr(m.created,1,19))<=? ORDER BY m.seq DESC LIMIT 1", cid, joined, at))
	if e == sql.ErrNoRows {
		respond(w, 404, map[string]string{"error": "not_found"})
		return
	}
	if e != nil {
		fail(w, e)
		return
	}
	if e = a.attachPoll(a.DB, p.UserID, &m); e != nil {
		fail(w, e)
		return
	}
	if e = a.attachChecklist(a.DB, &m); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, m)
}

func (a *App) pollVoters(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	pid := r.PathValue("poll_id")
	option, e := strconv.Atoi(r.URL.Query().Get("option_id"))
	if e != nil || option < 0 {
		fail(w, ErrInvalid)
		return
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if offset < 0 {
		offset = 0
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	var anon int
	if e = a.DB.QueryRow("SELECT anonymous FROM polls WHERE id=? AND chat_id=?", pid, cid).Scan(&anon); e != nil {
		fail(w, ErrForbidden)
		return
	}
	if anon == 1 {
		fail(w, ErrForbidden)
		return
	}
	var total int
	if e = a.DB.QueryRow("SELECT count(*) FROM poll_votes WHERE poll_id=? AND option_id=?", pid, option).Scan(&total); e != nil {
		fail(w, e)
		return
	}
	rows, e := a.DB.Query("SELECT user_id FROM poll_votes WHERE poll_id=? AND option_id=? ORDER BY created,user_id LIMIT ? OFFSET ?", pid, option, limit, offset)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	voters := []map[string]string{}
	for rows.Next() {
		var uid string
		if e = rows.Scan(&uid); e != nil {
			fail(w, e)
			return
		}
		voters = append(voters, map[string]string{"user_id": uid})
	}
	respond(w, 200, map[string]any{"total_count": total, "voters": voters})
}

func (a *App) editMedia(w http.ResponseWriter, r *http.Request, p Principal) {
	mid := r.PathValue("id")
	var b struct {
		Kind     string          `json:"kind"`
		Text     string          `json:"text"`
		MediaID  string          `json:"media_id"`
		Entities []Entity        `json:"entities"`
		Extra    json.RawMessage `json:"extra"`
	}
	if !decode(w, r, &b) {
		return
	}
	switch b.Kind {
	case "image", "video", "file", "voice", "animation", "video_note":
	default:
		fail(w, ErrInvalid)
		return
	}
	if b.MediaID == "" || len(b.Text) > 16384 {
		fail(w, ErrInvalid)
		return
	}
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		m, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil || m.Sender != p.UserID || m.Deleted {
			return ErrForbidden
		}
		entities, e := validateEntities(b.Text, b.Entities)
		if e != nil {
			return e
		}
		if e = a.checkSend(tx, p, m.ChatID, Send{Kind: b.Kind, Text: b.Text, MediaID: b.MediaID, Entities: entities}); e != nil {
			return e
		}
		var mime string
		if e = tx.QueryRow(`SELECT mime FROM media WHERE id=? AND (owner=? OR chat_id=?)`, b.MediaID, p.UserID, m.ChatID).Scan(&mime); e != nil {
			return ErrInvalid
		}
		if b.Kind == "image" && !strings.HasPrefix(mime, "image/") {
			return ErrInvalid
		}
		if (b.Kind == "video" || b.Kind == "video_note") && !strings.HasPrefix(mime, "video/") {
			return ErrInvalid
		}
		if b.Kind == "voice" && !strings.HasPrefix(mime, "audio/") {
			return ErrInvalid
		}
		if b.Kind == "animation" && mime != "image/gif" && !strings.HasPrefix(mime, "video/") {
			return ErrInvalid
		}
		extra := ""
		_ = tx.QueryRow("SELECT extra_json FROM messages WHERE id=?", mid).Scan(&extra)
		if len(b.Extra) > 0 && string(b.Extra) != "null" {
			extra = string(b.Extra)
		}
		meta, e := mediaSnapshot(tx, b.MediaID)
		if e != nil {
			return e
		}
		edited := now()
		if _, e = tx.Exec("UPDATE messages SET kind=?,text=?,media_id=?,entities_json=?,media_meta_json=?,extra_json=?,edited=? WHERE id=?", b.Kind, b.Text, b.MediaID, jsonText(entities, "[]"), jsonText(meta, ""), extra, edited, mid); e != nil {
			return e
		}
		out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil {
			return e
		}
		users, e := members(tx, m.ChatID)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message.edited", m.ChatID, out); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, m.ChatID)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, out)
}

func (a *App) reschedule(w http.ResponseWriter, r *http.Request, p Principal) {
	sid := r.PathValue("id")
	var b struct {
		SendAt     int64 `json:"send_at"`
		WhenOnline bool  `json:"when_online"`
	}
	if !decode(w, r, &b) {
		return
	}
	if !b.WhenOnline && b.SendAt <= time.Now().Unix() {
		fail(w, ErrInvalid)
		return
	}
	online := 0
	if b.WhenOnline {
		online = 1
		b.SendAt = 0
	}
	res, e := a.DB.Exec("UPDATE scheduled_messages SET send_at=?,when_online=? WHERE id=? AND sender=?", b.SendAt, online, sid, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fail(w, ErrForbidden)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) sendScheduledNow(w http.ResponseWriter, r *http.Request, p Principal) {
	sid := r.PathValue("id")
	var m Message
	e := a.transaction(func(tx *sql.Tx) error {
		var err error
		m, err = loadScheduled(tx, sid)
		return err
	})
	if e != nil || m.Sender != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	_, e = a.SendMessage(p, m.ChatID, Send{ClientID: m.ClientID, Kind: m.Kind, Text: m.Text, MediaID: m.MediaID, ReplyTo: m.ReplyTo, Extra: m.Extra, TTL: m.TTL})
	if e != nil && e != ErrConflict {
		fail(w, e)
		return
	}
	_, _ = a.DB.Exec("DELETE FROM scheduled_messages WHERE id=? AND sender=?", sid, p.UserID)
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) publicLookup(w http.ResponseWriter, r *http.Request, p Principal) {
	name := strings.ToLower(strings.TrimPrefix(r.PathValue("username"), "@"))
	if !validHandle(name) {
		fail(w, ErrInvalid)
		return
	}
	var u User
	e := a.DB.QueryRow("SELECT id,handle,name,avatar,last_seen FROM users WHERE lower(handle)=? AND IFNULL(deleted,0)=0", name).Scan(&u.ID, &u.Handle, &u.Name, &u.Avatar, &u.LastSeen)
	if e == nil {
		u.Online = a.online(u.ID)
		respond(w, 200, map[string]any{"kind": "user", "user": u})
		return
	}
	if e != sql.ErrNoRows {
		fail(w, e)
		return
	}
	var id, kind, title string
	var joinBy int
	e = a.DB.QueryRow("SELECT id,kind,title,IFNULL(join_by_request,0) FROM chats WHERE username=?", name).Scan(&id, &kind, &title, &joinBy)
	if e == sql.ErrNoRows {
		respond(w, 404, map[string]string{"error": "not_found"})
		return
	}
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"kind": "chat", "chat": map[string]any{"id": id, "kind": kind, "title": title, "username": name, "join_by_request": joinBy == 1}})
}

func (a *App) publicJoin(w http.ResponseWriter, r *http.Request, p Principal) {
	name := strings.ToLower(strings.TrimPrefix(r.PathValue("username"), "@"))
	if !validHandle(name) {
		fail(w, ErrInvalid)
		return
	}
	var cid string
	var requested bool
	e := a.transaction(func(tx *sql.Tx) error {
		var kind string
		var joinBy int
		if e := tx.QueryRow("SELECT id,kind,IFNULL(join_by_request,0) FROM chats WHERE username=?", name).Scan(&cid, &kind, &joinBy); e != nil {
			return ErrForbidden
		}
		if kind != "group" && kind != "channel" {
			return ErrForbidden
		}
		if _, _, e := member(tx, cid, p.UserID); e == nil {
			return nil
		}
		var banned int
		if e := tx.QueryRow("SELECT count(*) FROM bans WHERE chat_id=? AND user_id=?", cid, p.UserID).Scan(&banned); e != nil {
			return e
		}
		if banned > 0 {
			return ErrForbidden
		}
		if joinBy == 1 {
			if _, e := tx.Exec("INSERT INTO join_requests(chat_id,user_id,invite_code,created) VALUES(?,?, '',unixepoch()) ON CONFLICT(chat_id,user_id) DO NOTHING", cid, p.UserID); e != nil {
				return e
			}
			requested = true
			users, e := members(tx, cid)
			if e != nil {
				return e
			}
			return a.emitPendingJoins(tx, users, cid)
		}
		var seq int64
		var history int
		if e := tx.QueryRow("SELECT last_seq,IFNULL(history_for_new,0) FROM chats WHERE id=?", cid).Scan(&seq, &history); e != nil {
			return e
		}
		joined := seq
		if history == 1 {
			joined = 0
		}
		if _, e := tx.Exec("INSERT INTO members(chat_id,user_id,role,joined_seq,read_seq,joined_at) VALUES(?,?,'member',?,?,unixepoch())", cid, p.UserID, joined, joined); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "membership.changed", cid, map[string]any{"user_id": p.UserID, "action": "add", "role": "member", "joined_seq": joined})
	})
	if e != nil {
		fail(w, e)
		return
	}
	if requested {
		respond(w, 200, map[string]string{"status": "requested"})
		return
	}
	respond(w, 200, map[string]string{"status": "joined", "conversation_id": cid})
}
