package chat

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
)

func (a *App) round4Routes(mux *http.ServeMux) {
	mux.HandleFunc("PUT /v1/conversations/{id}/members/{user}/status", a.auth(a.setMemberStatus))
	mux.HandleFunc("GET /v1/conversations/{id}/bans", a.auth(a.listBans))
	mux.HandleFunc("PUT /v1/conversations/{id}/flags", a.auth(a.setChatFlags))
	mux.HandleFunc("PUT /v1/conversations/{id}/members/{user}/tag", a.auth(a.setMemberTag))
	mux.HandleFunc("POST /v1/folders/{id}/invites", a.auth(a.createFolderInvite))
	mux.HandleFunc("GET /v1/folders/{id}/invites", a.auth(a.listFolderInvites))
	mux.HandleFunc("PATCH /v1/folder-invites/{code}", a.auth(a.editFolderInvite))
	mux.HandleFunc("DELETE /v1/folder-invites/{code}", a.auth(a.deleteFolderInvite))
	mux.HandleFunc("GET /v1/folder-invites/{code}", a.auth(a.previewFolderInvite))
	mux.HandleFunc("POST /v1/folder-invites/{code}/join", a.auth(a.joinFolderInvite))
}

func staffRole(tx *sql.Tx, cid, uid string) error {
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

func restrictionAllows(tx *sql.Tx, cid, uid, key string) error {
	if key == "" {
		return nil
	}
	var until int64
	var raw string
	e := tx.QueryRow("SELECT until_unix,permissions_json FROM member_restrictions WHERE chat_id=? AND user_id=?", cid, uid).Scan(&until, &raw)
	if e == sql.ErrNoRows {
		return nil
	}
	if e != nil {
		return e
	}
	nowUnix := time.Now().Unix()
	if until != 0 && until < nowUnix {
		return nil
	}
	var m map[string]any
	if json.Unmarshal([]byte(raw), &m) != nil {
		return nil
	}
	v, ok := m[key]
	if !ok {
		return nil
	}
	if b, ok := v.(bool); ok && !b {
		return ErrForbidden
	}
	return nil
}

func reactionAllowed(raw, emoji string) bool {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return true
	}
	var m map[string]any
	if json.Unmarshal([]byte(raw), &m) != nil {
		return true
	}
	kind, _ := m["@type"].(string)
	if kind == "" || kind == "chatAvailableReactionsAll" {
		return true
	}
	if kind != "chatAvailableReactionsSome" {
		return true
	}
	list, _ := m["reactions"].([]any)
	for _, item := range list {
		switch v := item.(type) {
		case string:
			if v == emoji {
				return true
			}
		case map[string]any:
			if e, _ := v["emoji"].(string); e == emoji {
				return true
			}
		}
	}
	return false
}

func validateReactions(raw json.RawMessage) error {
	if len(raw) == 0 || string(raw) == "null" {
		return nil
	}
	if len(raw) > 4000 || !json.Valid(raw) {
		return ErrInvalid
	}
	var m map[string]any
	if json.Unmarshal(raw, &m) != nil {
		return ErrInvalid
	}
	kind, _ := m["@type"].(string)
	if kind != "" && kind != "chatAvailableReactionsAll" && kind != "chatAvailableReactionsSome" {
		return ErrInvalid
	}
	if kind == "chatAvailableReactionsSome" {
		list, ok := m["reactions"].([]any)
		if !ok || len(list) == 0 || len(list) > 32 {
			return ErrInvalid
		}
	}
	return nil
}

func normalizeBirthdate(raw json.RawMessage) (string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return "", nil
	}
	var b struct {
		Day   int `json:"day"`
		Month int `json:"month"`
		Year  int `json:"year"`
	}
	if json.Unmarshal(raw, &b) != nil {
		return "", ErrInvalid
	}
	if b.Day < 1 || b.Day > 31 || b.Month < 1 || b.Month > 12 || (b.Year != 0 && (b.Year < 1900 || b.Year > 2100)) {
		return "", ErrInvalid
	}
	out, e := json.Marshal(b)
	if e != nil {
		return "", ErrInvalid
	}
	return string(out), nil
}

func intPtr(v int) *int { return &v }

func (a *App) setMemberStatus(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	uid := r.PathValue("user")
	var b struct {
		Status      string          `json:"status"`
		Until       int64           `json:"until"`
		IsMember    *bool           `json:"is_member"`
		Permissions json.RawMessage `json:"permissions"`
	}
	if !decode(w, r, &b) {
		return
	}
	if !keyRE.MatchString(uid) || b.Until < 0 {
		fail(w, ErrInvalid)
		return
	}
	switch b.Status {
	case "banned", "left", "member", "admin", "restricted":
	default:
		fail(w, ErrInvalid)
		return
	}
	if b.Status == "restricted" {
		if len(b.Permissions) == 0 || len(b.Permissions) > 4000 || !json.Valid(b.Permissions) {
			fail(w, ErrInvalid)
			return
		}
		var obj map[string]any
		if json.Unmarshal(b.Permissions, &obj) != nil {
			fail(w, ErrInvalid)
			return
		}
	}
	e := a.transaction(func(tx *sql.Tx) error {
		caller, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		if p.UserID == uid && b.Status != "left" {
			return ErrForbidden
		}
		if p.UserID != uid && caller != "owner" && caller != "admin" {
			return ErrForbidden
		}
		var target string
		err := tx.QueryRow("SELECT role FROM members WHERE chat_id=? AND user_id=?", cid, uid).Scan(&target)
		present := err == nil
		if err != nil && err != sql.ErrNoRows {
			return err
		}
		if caller == "owner" && p.UserID == uid {
			return ErrForbidden
		}
		if target == "owner" {
			return ErrForbidden
		}
		if caller == "admin" && target == "admin" && p.UserID != uid {
			return ErrForbidden
		}
		if b.Status == "admin" && caller != "owner" {
			return ErrForbidden
		}
		if p.UserID == uid && b.Status != "left" {
			return ErrForbidden
		}
		if b.Status == "admin" && !present {
			return ErrForbidden
		}
		var known int
		if e = tx.QueryRow("SELECT count(*) FROM users WHERE id=?", uid).Scan(&known); e != nil {
			return e
		}
		if known != 1 {
			return ErrInvalid
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		removed := false
		action := "member." + b.Status
		switch b.Status {
		case "banned":
			if _, e = tx.Exec("INSERT INTO bans(chat_id,user_id,actor_id,reason,created) VALUES(?,?,?,?,?) ON CONFLICT(chat_id,user_id) DO UPDATE SET actor_id=excluded.actor_id,reason=excluded.reason,created=excluded.created", cid, uid, p.UserID, "", now()); e != nil {
				return e
			}
			if _, e = tx.Exec("DELETE FROM member_restrictions WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
				return e
			}
			if present {
				if _, e = tx.Exec("DELETE FROM members WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
					return e
				}
				removed = true
			}
			action = "member.banned"
		case "left":
			if _, e = tx.Exec("DELETE FROM bans WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
				return e
			}
			if _, e = tx.Exec("DELETE FROM member_restrictions WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
				return e
			}
			if present {
				if _, e = tx.Exec("DELETE FROM members WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
					return e
				}
				removed = true
			}
			action = "member.left"
		case "member":
			if _, e = tx.Exec("DELETE FROM member_restrictions WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
				return e
			}
			if present && target != "member" {
				if _, e = tx.Exec("UPDATE members SET role='member' WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
					return e
				}
			}
			action = "member.role"
		case "admin":
			if _, e = tx.Exec("DELETE FROM member_restrictions WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
				return e
			}
			if _, e = tx.Exec("UPDATE members SET role='admin' WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
				return e
			}
			action = "member.role"
		case "restricted":
			isMember := 1
			if b.IsMember != nil && !*b.IsMember {
				isMember = 0
			}
			if _, e = tx.Exec("INSERT INTO member_restrictions(chat_id,user_id,until_unix,permissions_json,is_member) VALUES(?,?,?,?,?) ON CONFLICT(chat_id,user_id) DO UPDATE SET until_unix=excluded.until_unix,permissions_json=excluded.permissions_json,is_member=excluded.is_member", cid, uid, b.Until, string(b.Permissions), isMember); e != nil {
				return e
			}
			if isMember == 0 && present {
				if _, e = tx.Exec("DELETE FROM members WHERE chat_id=? AND user_id=?", cid, uid); e != nil {
					return e
				}
				removed = true
			}
			action = "member.restricted"
		}
		if e = audit(tx, cid, p.UserID, action, uid, map[string]any{"status": b.Status, "until": b.Until}); e != nil {
			return e
		}
		if removed {
			if e = emit(tx, users, "membership.changed", cid, map[string]any{"user_id": uid, "action": "remove", "role": target}); e != nil {
				return e
			}
			return a.emitDialogStates(tx, users, cid)
		}
		if present && (b.Status == "member" || b.Status == "admin" || b.Status == "restricted") {
			return emit(tx, users, "membership.changed", cid, map[string]any{"user_id": uid, "action": "role", "role": b.Status})
		}
		return nil
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) listBans(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error { return staffRole(tx, cid, p.UserID) })
	if e != nil {
		fail(w, e)
		return
	}
	rows, e := a.DB.Query("SELECT user_id,reason,created FROM bans WHERE chat_id=? ORDER BY created", cid)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var uid, reason, created string
		if e = rows.Scan(&uid, &reason, &created); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"user_id": uid, "reason": reason, "created": created})
	}
	respond(w, 200, map[string]any{"bans": out})
}

func (a *App) setChatFlags(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Reactions *json.RawMessage `json:"reactions"`
		Sign      *bool            `json:"sign_messages"`
		Show      *bool            `json:"show_message_sender"`
		Hidden    *bool            `json:"hidden_members"`
		JoinSend  *bool            `json:"join_to_send"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.Reactions == nil && b.Sign == nil && b.Show == nil && b.Hidden == nil && b.JoinSend == nil {
		fail(w, ErrInvalid)
		return
	}
	if b.Reactions != nil {
		if e := validateReactions(*b.Reactions); e != nil {
			fail(w, e)
			return
		}
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if e := staffRole(tx, cid, p.UserID); e != nil {
			return e
		}
		if b.Reactions != nil {
			stored := ""
			if string(*b.Reactions) != "null" {
				stored = string(*b.Reactions)
			}
			if _, e := tx.Exec("UPDATE chats SET reactions_json=? WHERE id=?", stored, cid); e != nil {
				return e
			}
		}
		if b.Sign != nil {
			if _, e := tx.Exec("UPDATE chats SET sign_messages=? WHERE id=?", boolInt(*b.Sign), cid); e != nil {
				return e
			}
		}
		if b.Show != nil {
			if _, e := tx.Exec("UPDATE chats SET show_sender=? WHERE id=?", boolInt(*b.Show), cid); e != nil {
				return e
			}
		}
		if b.Hidden != nil {
			if _, e := tx.Exec("UPDATE chats SET hidden_members=? WHERE id=?", boolInt(*b.Hidden), cid); e != nil {
				return e
			}
		}
		if b.JoinSend != nil {
			if _, e := tx.Exec("UPDATE chats SET join_to_send=? WHERE id=?", boolInt(*b.JoinSend), cid); e != nil {
				return e
			}
		}
		return audit(tx, cid, p.UserID, "conversation.flags", cid, map[string]any{"sign_messages": b.Sign, "hidden_members": b.Hidden, "join_to_send": b.JoinSend})
	})
	if e != nil {
		fail(w, e)
		return
	}
	a.getConversation(w, r, p)
}

func (a *App) setMemberTag(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	uid := r.PathValue("user")
	var b struct {
		Tag string `json:"tag"`
	}
	if !decode(w, r, &b) {
		return
	}
	tag := strings.TrimSpace(b.Tag)
	if !keyRE.MatchString(uid) || utf8.RuneCountInString(tag) > 16 {
		fail(w, ErrInvalid)
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		caller, _, e := member(tx, cid, p.UserID)
		if e != nil || (caller != "owner" && caller != "admin") {
			return ErrForbidden
		}
		target, _, e := member(tx, cid, uid)
		if e != nil {
			return e
		}
		if caller == "admin" && target == "owner" {
			return ErrForbidden
		}
		if _, e = tx.Exec("UPDATE members SET tag=? WHERE chat_id=? AND user_id=?", tag, cid, uid); e != nil {
			return e
		}
		return audit(tx, cid, p.UserID, "member.tag", uid, map[string]string{"tag": tag})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"ok": true, "tag": tag})
}

func folderChatAllowed(filter FolderFilter, cid string) bool {
	for _, id := range filter.Include {
		if id == cid {
			return true
		}
	}
	return false
}

func (a *App) loadOwnedFolder(tx *sql.Tx, fid, uid string) (string, FolderFilter, error) {
	var name, raw string
	if e := tx.QueryRow("SELECT name,filter_json FROM folders WHERE id=? AND user_id=?", fid, uid).Scan(&name, &raw); e != nil {
		return "", FolderFilter{}, ErrForbidden
	}
	var f FolderFilter
	if json.Unmarshal([]byte(raw), &f) != nil {
		f = FolderFilter{}
	}
	return name, f, nil
}

func cleanFolderChats(tx *sql.Tx, owner string, filter FolderFilter, ids []string) ([]string, error) {
	if len(ids) == 0 || len(ids) > 100 {
		return nil, ErrInvalid
	}
	seen := map[string]bool{}
	out := []string{}
	for _, id := range ids {
		if !keyRE.MatchString(id) || seen[id] || !folderChatAllowed(filter, id) {
			return nil, ErrInvalid
		}
		var n int
		if e := tx.QueryRow("SELECT count(*) FROM members WHERE chat_id=? AND user_id=?", id, owner).Scan(&n); e != nil {
			return nil, e
		}
		if n != 1 {
			return nil, ErrForbidden
		}
		seen[id] = true
		out = append(out, id)
	}
	return out, nil
}

func (a *App) createFolderInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	fid := r.PathValue("id")
	var b struct {
		Name    string   `json:"name"`
		ChatIDs []string `json:"chat_ids"`
	}
	if !decode(w, r, &b) {
		return
	}
	if utf8.RuneCountInString(b.Name) > 32 {
		fail(w, ErrInvalid)
		return
	}
	code := id()
	e := a.transaction(func(tx *sql.Tx) error {
		_, filter, e := a.loadOwnedFolder(tx, fid, p.UserID)
		if e != nil {
			return e
		}
		chats, e := cleanFolderChats(tx, p.UserID, filter, b.ChatIDs)
		if e != nil {
			return e
		}
		var n int
		if e = tx.QueryRow("SELECT count(*) FROM folder_invites WHERE folder_id=? AND revoked=0", fid).Scan(&n); e != nil {
			return e
		}
		if n >= 20 {
			return ErrInvalid
		}
		_, e = tx.Exec("INSERT INTO folder_invites(code,folder_id,creator,name,chat_ids_json,created) VALUES(?,?,?,?,?,?)", code, fid, p.UserID, b.Name, jsonText(chats, "[]"), now())
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, a.folderInviteJSON(code))
}

func (a *App) folderInviteJSON(code string) map[string]any {
	var fid, creator, name, raw, created string
	var revoked int
	e := a.DB.QueryRow("SELECT folder_id,creator,name,chat_ids_json,created,revoked FROM folder_invites WHERE code=?", code).Scan(&fid, &creator, &name, &raw, &created, &revoked)
	if e != nil {
		return map[string]any{"code": code, "revoked": true}
	}
	var chats []string
	_ = json.Unmarshal([]byte(raw), &chats)
	if chats == nil {
		chats = []string{}
	}
	return map[string]any{
		"code": code, "invite_link": "ql://folder/" + code, "folder_id": fid, "creator_id": creator,
		"name": name, "chat_ids": chats, "created": created, "revoked": revoked == 1,
	}
}

func (a *App) listFolderInvites(w http.ResponseWriter, r *http.Request, p Principal) {
	fid := r.PathValue("id")
	var owned int
	if e := a.DB.QueryRow("SELECT count(*) FROM folders WHERE id=? AND user_id=?", fid, p.UserID).Scan(&owned); e != nil || owned != 1 {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT code,creator,name,chat_ids_json,created,revoked FROM folder_invites WHERE folder_id=? AND revoked=0 ORDER BY created", fid)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var code, creator, name, raw, created string
		var revoked int
		if e = rows.Scan(&code, &creator, &name, &raw, &created, &revoked); e != nil {
			fail(w, e)
			return
		}
		var chats []string
		_ = json.Unmarshal([]byte(raw), &chats)
		if chats == nil {
			chats = []string{}
		}
		out = append(out, map[string]any{
			"code": code, "invite_link": "ql://folder/" + code, "folder_id": fid, "creator_id": creator,
			"name": name, "chat_ids": chats, "created": created, "revoked": false,
		})
	}
	respond(w, 200, map[string]any{"invites": out})
}

func (a *App) editFolderInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	var b struct {
		Name    *string  `json:"name"`
		ChatIDs []string `json:"chat_ids"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.Name != nil && utf8.RuneCountInString(*b.Name) > 32 {
		fail(w, ErrInvalid)
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		var fid string
		var revoked int
		if e := tx.QueryRow("SELECT folder_id,revoked FROM folder_invites WHERE code=?", code).Scan(&fid, &revoked); e != nil || revoked == 1 {
			return ErrForbidden
		}
		_, filter, e := a.loadOwnedFolder(tx, fid, p.UserID)
		if e != nil {
			return e
		}
		if b.Name != nil {
			if _, e = tx.Exec("UPDATE folder_invites SET name=? WHERE code=?", *b.Name, code); e != nil {
				return e
			}
		}
		if b.ChatIDs != nil {
			chats, e := cleanFolderChats(tx, p.UserID, filter, b.ChatIDs)
			if e != nil {
				return e
			}
			if _, e = tx.Exec("UPDATE folder_invites SET chat_ids_json=? WHERE code=?", jsonText(chats, "[]"), code); e != nil {
				return e
			}
		}
		return nil
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, a.folderInviteJSON(code))
}

func (a *App) deleteFolderInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	e := a.transaction(func(tx *sql.Tx) error {
		var fid string
		if e := tx.QueryRow("SELECT folder_id FROM folder_invites WHERE code=? AND revoked=0", code).Scan(&fid); e != nil {
			return ErrForbidden
		}
		if _, _, e := a.loadOwnedFolder(tx, fid, p.UserID); e != nil {
			return e
		}
		_, e := tx.Exec("UPDATE folder_invites SET revoked=1 WHERE code=?", code)
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) previewFolderInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	if !keyRE.MatchString(code) {
		fail(w, ErrInvalid)
		return
	}
	var name, raw, title string
	var revoked int
	e := a.DB.QueryRow("SELECT i.name,i.chat_ids_json,i.revoked,f.name FROM folder_invites i JOIN folders f ON f.id=i.folder_id WHERE i.code=?", code).Scan(&name, &raw, &revoked, &title)
	if e != nil || revoked == 1 {
		fail(w, ErrForbidden)
		return
	}
	var chats []string
	_ = json.Unmarshal([]byte(raw), &chats)
	if chats == nil {
		chats = []string{}
	}
	if name == "" {
		name = title
	}
	respond(w, 200, map[string]any{"invite_link": "ql://folder/" + code, "name": name, "title": title, "chat_ids": chats})
}

func (a *App) joinFolderInvite(w http.ResponseWriter, r *http.Request, p Principal) {
	code := r.PathValue("code")
	if !keyRE.MatchString(code) {
		fail(w, ErrInvalid)
		return
	}
	var fid string
	var included []string
	e := a.transaction(func(tx *sql.Tx) error {
		var raw, inviteName, folderName string
		var revoked int
		if e := tx.QueryRow("SELECT i.folder_id,i.name,i.chat_ids_json,i.revoked,f.name FROM folder_invites i JOIN folders f ON f.id=i.folder_id WHERE i.code=?", code).Scan(&fid, &inviteName, &raw, &revoked, &folderName); e != nil || revoked == 1 {
			return ErrForbidden
		}
		var chats []string
		if json.Unmarshal([]byte(raw), &chats) != nil {
			return ErrInvalid
		}
		rows, e := tx.Query("SELECT chat_id FROM members WHERE user_id=?", p.UserID)
		if e != nil {
			return e
		}
		mine := map[string]bool{}
		for rows.Next() {
			var id string
			if e = rows.Scan(&id); e != nil {
				rows.Close()
				return e
			}
			mine[id] = true
		}
		if e = rows.Err(); e != nil {
			rows.Close()
			return e
		}
		rows.Close()
		for _, id := range chats {
			if mine[id] {
				included = append(included, id)
			}
		}
		if included == nil {
			included = []string{}
		}
		var count int
		if e = tx.QueryRow("SELECT count(*) FROM folders WHERE user_id=?", p.UserID).Scan(&count); e != nil {
			return e
		}
		if count >= 20 {
			return ErrInvalid
		}
		name := inviteName
		if name == "" {
			name = folderName
		}
		if name == "" {
			name = "文件夹"
		}
		if utf8.RuneCountInString(name) > 100 {
			name = string([]rune(name)[:100])
		}
		fid = id()
		filter := FolderFilter{Include: included, Exclude: []string{}, Types: []string{}}
		if _, e = tx.Exec("INSERT INTO folders(id,user_id,name,filter_json,sort_order) VALUES(?,?,?,?,?)", fid, p.UserID, name, jsonText(filter, "{}"), count); e != nil {
			return e
		}
		return emit(tx, []string{p.UserID}, "folder.updated", "", map[string]any{"id": fid, "name": name, "filter": filter, "sort_order": count})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"id": fid, "chat_ids": included})
}
