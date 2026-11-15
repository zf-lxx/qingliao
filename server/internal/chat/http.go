package chat

import (
	"database/sql"
	"encoding/json"
	"errors"
	"golang.org/x/crypto/bcrypt"
	"io"
	"net"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

var handleRE = regexp.MustCompile(`^[a-zA-Z0-9_]{3,32}$`)

func validHandle(s string) bool { return handleRE.MatchString(s) }
func respond(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}
func fail(w http.ResponseWriter, e error) {
	status := 400
	code := "invalid_request"
	if errors.Is(e, ErrRateLimited) {
		status = 429
		code = "rate_limited"
	} else if errors.Is(e, ErrForbidden) || errors.Is(e, sql.ErrNoRows) {
		status = 403
		code = "forbidden"
	} else if errors.Is(e, ErrConflict) {
		status = 409
		code = "conflict"
	} else if !errors.Is(e, ErrInvalid) {
		status = 500
		code = "internal_error"
	}
	respond(w, status, map[string]any{"error": code})
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		fail(w, ErrInvalid)
		return false
	}
	if d.Decode(new(any)) != io.EOF {
		fail(w, ErrInvalid)
		return false
	}
	return true
}

type authed func(http.ResponseWriter, *http.Request, Principal)

func (a *App) auth(fn authed) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		p, e := a.authenticate(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		if e != nil {
			respond(w, 401, map[string]string{"error": "unauthorized"})
			return
		}
		fn(w, r, p)
	}
}
func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()
	a.discoveryRoutes(mux)
	a.p2Routes(mux)
	a.p3Routes(mux)
	a.storyRoutes(mux)
	a.securityRoutes(mux)
	a.albumRoutes(mux)
	a.botManageRoutes(mux)
	a.gapRoutes(mux)
	a.round2Routes(mux)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		if e := a.Ping(r.Context()); e != nil {
			respond(w, 503, map[string]bool{"ok": false})
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	})
	mux.HandleFunc("POST /v1/auth/register", a.register)
	mux.HandleFunc("POST /v1/auth/login", a.login)
	mux.HandleFunc("POST /v1/auth/logout", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		_, e := a.DB.Exec("UPDATE sessions SET revoked=1 WHERE id=?", p.SessionID)
		if e != nil {
			fail(w, e)
			return
		}
		a.hub.closeSession(p.SessionID)
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("POST /v1/invites", a.auth(a.invite))
	mux.HandleFunc("GET /v1/me", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		u, e := a.getUser(p.UserID)
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, u)
	}))
	mux.HandleFunc("PATCH /v1/me", a.auth(a.profile))
	mux.HandleFunc("GET /v1/me/privacy", a.auth(a.privacy))
	mux.HandleFunc("PUT /v1/me/privacy", a.auth(a.privacy))
	mux.HandleFunc("GET /v1/users", a.auth(a.users))
	mux.HandleFunc("GET /v1/users/{id}", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		u, e := a.getUser(r.PathValue("id"))
		if e != nil {
			fail(w, e)
			return
		}
		a.hideBlockedPresence(p.UserID, &u)
		respond(w, 200, u)
	}))
	mux.HandleFunc("GET /v1/devices", a.auth(a.listDevices))
	mux.HandleFunc("PUT /v1/devices/current/push", a.auth(a.devicePush))
	mux.HandleFunc("DELETE /v1/devices/{id}", a.auth(a.revokeDevice))
	mux.HandleFunc("POST /v1/ws-ticket", a.auth(a.wsTicket))
	mux.HandleFunc("GET /v1/ws", a.websocket)
	mux.HandleFunc("GET /v1/sync", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		after, e := strconv.ParseInt(r.URL.Query().Get("after"), 10, 64)
		if e != nil {
			fail(w, ErrInvalid)
			return
		}
		d, e := a.Difference(p.UserID, after, num(r, "limit"))
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, d)
	}))
	mux.HandleFunc("GET /v1/conversations", a.auth(a.dialogs))
	mux.HandleFunc("POST /v1/conversations", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b struct {
			Kind    string   `json:"kind"`
			Title   string   `json:"title"`
			Members []string `json:"member_ids"`
		}
		if !decode(w, r, &b) {
			return
		}
		id, e := a.CreateChat(p, b.Kind, b.Title, b.Members)
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 201, map[string]string{"id": id})
	}))
	mux.HandleFunc("POST /v1/link-previews", a.auth(a.preview))
	mux.HandleFunc("GET /v1/conversations/{id}/pins", a.auth(a.pins))
	mux.HandleFunc("PUT /v1/conversations/{id}/pins", a.auth(a.pin))
	mux.HandleFunc("GET /v1/conversations/{id}/settings", a.auth(a.groupSettings))
	mux.HandleFunc("PUT /v1/conversations/{id}/settings", a.auth(a.groupSettings))
	mux.HandleFunc("POST /v1/conversations/{id}/moderation", a.auth(a.moderate))
	mux.HandleFunc("GET /v1/conversations/{id}/audit", a.auth(a.auditList))
	mux.HandleFunc("PATCH /v1/conversations/{id}/state", a.auth(a.dialogState))
	mux.HandleFunc("PATCH /v1/conversations/{id}", a.auth(a.patchConversation))
	mux.HandleFunc("GET /v1/folders", a.auth(a.folders))
	mux.HandleFunc("POST /v1/folders", a.auth(a.folders))
	mux.HandleFunc("PATCH /v1/folders/{id}", a.auth(a.folders))
	mux.HandleFunc("DELETE /v1/folders/{id}", a.auth(a.deleteFolder))
	mux.HandleFunc("POST /v1/conversations/{id}/polls", a.auth(a.createPoll))
	mux.HandleFunc("GET /v1/conversations/{id}/polls/{poll_id}", a.auth(a.getPoll))
	mux.HandleFunc("POST /v1/conversations/{id}/polls/{poll_id}/vote", a.auth(a.votePoll))
	mux.HandleFunc("POST /v1/conversations/{id}/polls/{poll_id}/close", a.auth(a.closePoll))
	mux.HandleFunc("POST /v1/messages/{id}/callback", a.auth(a.callbackStub))
	mux.HandleFunc("GET /v1/conversations/{id}/members", a.auth(a.listMembers))
	mux.HandleFunc("POST /v1/conversations/{id}/members", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b struct {
			User   string `json:"user_id"`
			Action string `json:"action"`
			Role   string `json:"role"`
		}
		if !decode(w, r, &b) {
			return
		}
		if e := a.ChangeMember(p, r.PathValue("id"), b.User, b.Action, b.Role); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("GET /v1/conversations/{id}/messages", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		cid := r.PathValue("id")
		if !a.isMember(cid, p.UserID) {
			fail(w, ErrForbidden)
			return
		}
		m, e := a.History(p, cid, int64(num(r, "before")), num(r, "limit"))
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]any{"messages": m})
	}))
	mux.HandleFunc("POST /v1/conversations/{id}/messages", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b Send
		if !decode(w, r, &b) {
			return
		}
		m, e := a.SendMessage(p, r.PathValue("id"), b)
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, m)
	}))
	mux.HandleFunc("PATCH /v1/messages/{id}", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b Send
		if !decode(w, r, &b) {
			return
		}
		if e := a.EditMessage(p, r.PathValue("id"), b); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("DELETE /v1/messages/{id}", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		if e := a.AlterMessage(p, r.PathValue("id"), "delete", ""); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("PUT /v1/messages/{id}/reactions", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b struct {
			Emoji  string `json:"emoji"`
			Remove bool   `json:"remove"`
		}
		if !decode(w, r, &b) {
			return
		}
		if e := a.React(p, r.PathValue("id"), b.Emoji, b.Remove); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("GET /v1/messages/{id}/reactions", a.auth(a.reactions))
	mux.HandleFunc("POST /v1/conversations/{id}/read", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b struct {
			Seq int64 `json:"last_read_seq"`
		}
		if !decode(w, r, &b) {
			return
		}
		if e := a.Read(p, r.PathValue("id"), b.Seq); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("POST /v1/media", a.auth(a.upload))
	mux.HandleFunc("GET /v1/media/{id}", a.auth(a.download))
	mux.HandleFunc("DELETE /v1/media/{id}", a.auth(a.deleteMedia))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/bot") || strings.HasPrefix(r.URL.Path, "/file/bot") {
			a.serveBotAPI(w, r)
			return
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		origin := r.Header.Get("Origin")
		if origin != "" && origin != a.C.AllowedOrigin {
			respond(w, 403, map[string]string{"error": "origin_denied"})
			return
		}
		if origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Conversation-ID")
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PATCH,PUT,DELETE,OPTIONS")
		}
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		strict := strings.HasPrefix(r.URL.Path, "/v1/auth/")
		key := host
		max := 600
		if strict {
			key += "auth"
			max = 20
		}
		if !a.limiter.allow(key, max, time.Minute) {
			respond(w, 429, map[string]string{"error": "rate_limited"})
			return
		}
		mux.ServeHTTP(w, r)
	})
}
func num(r *http.Request, key string) int { n, _ := strconv.Atoi(r.URL.Query().Get(key)); return n }
func (a *App) register(w http.ResponseWriter, r *http.Request) {
	var b struct {
		Handle   string `json:"handle"`
		Name     string `json:"display_name"`
		Password string `json:"password"`
		Invite   string `json:"invite_code"`
		Platform string `json:"platform"`
	}
	if !decode(w, r, &b) {
		return
	}
	b.Handle = strings.ToLower(b.Handle)
	if !validHandle(b.Handle) || len(b.Password) < 12 || len(b.Password) > 72 || len(b.Name) > 120 || len(b.Platform) > 32 {
		fail(w, ErrInvalid)
		return
	}
	if b.Name == "" {
		b.Name = b.Handle
	}
	// Check invite before expensive bcrypt; consumption is still atomic below.
	var valid int
	if e := a.DB.QueryRow("SELECT count(*) FROM invites WHERE code_hash=? AND uses>0 AND expires>?", hash(b.Invite), time.Now().Unix()).Scan(&valid); e != nil {
		fail(w, e)
		return
	}
	if valid != 1 {
		fail(w, ErrForbidden)
		return
	}
	pass, e := bcrypt.GenerateFromPassword([]byte(b.Password), bcrypt.DefaultCost)
	if e != nil {
		fail(w, e)
		return
	}
	uid := id()
	var result map[string]any
	e = a.transaction(func(tx *sql.Tx) error {
		res, e := tx.Exec("UPDATE invites SET uses=uses-1 WHERE code_hash=? AND uses>0 AND expires>?", hash(b.Invite), time.Now().Unix())
		if e != nil {
			return e
		}
		n, _ := res.RowsAffected()
		if n != 1 {
			return ErrForbidden
		}
		_, e = tx.Exec("INSERT INTO users(id,handle,name,password,last_seen) VALUES(?,?,?,?,?)", uid, b.Handle, b.Name, string(pass), now())
		if e != nil {
			return ErrConflict
		}
		result, e = a.newSessionMeta(tx, uid, deviceMeta{Platform: b.Platform, AppName: "轻聊"})
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, result)
}
func (a *App) invite(w http.ResponseWriter, r *http.Request, p Principal) {
	if !p.Admin {
		fail(w, ErrForbidden)
		return
	}
	var b struct {
		Uses  int `json:"uses"`
		Hours int `json:"expires_hours"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.Uses < 1 || b.Uses > 100 || b.Hours < 1 || b.Hours > 720 {
		fail(w, ErrInvalid)
		return
	}
	code := id()
	_, e := a.DB.Exec("INSERT INTO invites(code_hash,uses,expires,created_by) VALUES(?,?,?,?)", hash(code), b.Uses, time.Now().Add(time.Duration(b.Hours)*time.Hour).Unix(), p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, map[string]string{"invite_code": code})
}
func isProfileAvatarMIME(mime string) bool {
	switch mime {
	case "image/png", "image/jpeg", "image/webp", "image/gif", "video/mp4", "video/webm":
		return true
	default:
		return false
	}
}

func (a *App) getUser(uid string) (User, error) {
	var u User
	e := a.DB.QueryRow("SELECT users.id,users.handle,users.name,users.avatar,users.last_seen,COALESCE(media.mime,''),COALESCE(users.bio,'') FROM users LEFT JOIN media ON media.id=users.avatar WHERE users.id=?", uid).Scan(&u.ID, &u.Handle, &u.Name, &u.Avatar, &u.LastSeen, &u.AvatarMIME, &u.Bio)
	u.Online = a.online(uid)
	return u, e
}
func (a *App) profile(w http.ResponseWriter, r *http.Request, p Principal) {
	a.mediaMu.Lock()
	defer a.mediaMu.Unlock()
	var b struct {
		Name     *string `json:"display_name"`
		Avatar   *string `json:"avatar_media_id"`
		Bio      *string `json:"bio"`
		Username *string `json:"username"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.Name == nil && b.Avatar == nil && b.Bio == nil && b.Username == nil {
		fail(w, ErrInvalid)
		return
	}
	if b.Name != nil && (len(*b.Name) < 1 || len(*b.Name) > 120) {
		fail(w, ErrInvalid)
		return
	}
	if b.Bio != nil && utf8.RuneCountInString(*b.Bio) > 70 {
		fail(w, ErrInvalid)
		return
	}
	if b.Username != nil {
		handle := strings.ToLower(strings.TrimSpace(*b.Username))
		if !validHandle(handle) {
			fail(w, ErrInvalid)
			return
		}
		b.Username = &handle
	}
	var avatarMIME string
	if b.Avatar != nil && *b.Avatar != "" {
		var mime string
		if e := a.DB.QueryRow("SELECT mime FROM media WHERE id=? AND owner=?", *b.Avatar, p.UserID).Scan(&mime); e != nil || !isProfileAvatarMIME(mime) {
			fail(w, ErrForbidden)
			return
		}
		avatarMIME = mime
	}
	var e error
	e = a.transaction(func(tx *sql.Tx) error {
		if b.Username != nil {
			var n int
			if e := tx.QueryRow("SELECT count(*) FROM users WHERE handle=? AND id<>?", *b.Username, p.UserID).Scan(&n); e != nil {
				return e
			}
			if n > 0 {
				return ErrConflict
			}
			if _, e := tx.Exec("UPDATE users SET handle=? WHERE id=?", *b.Username, p.UserID); e != nil {
				return e
			}
		}
		if b.Name != nil || b.Avatar != nil {
			name := ""
			avatar := ""
			if b.Name != nil {
				name = *b.Name
			}
			if b.Avatar != nil {
				avatar = *b.Avatar
			}
			if b.Name != nil && b.Avatar != nil {
				if _, e := tx.Exec("UPDATE users SET name=?,avatar=? WHERE id=?", name, avatar, p.UserID); e != nil {
					return e
				}
			} else if b.Name != nil {
				if _, e := tx.Exec("UPDATE users SET name=? WHERE id=?", name, p.UserID); e != nil {
					return e
				}
			} else if _, e := tx.Exec("UPDATE users SET avatar=? WHERE id=?", avatar, p.UserID); e != nil {
				return e
			}
		}
		if b.Bio != nil {
			if _, e := tx.Exec("UPDATE users SET bio=? WHERE id=?", *b.Bio, p.UserID); e != nil {
				return e
			}
		}
		audience, e := profileAudience(tx, p.UserID)
		if e != nil {
			return e
		}
		payload := map[string]any{"id": p.UserID}
		if b.Name != nil {
			payload["display_name"] = *b.Name
		}
		if b.Avatar != nil {
			payload["avatar_media_id"] = *b.Avatar
			payload["avatar_mime"] = avatarMIME
		}
		if b.Bio != nil {
			payload["bio"] = *b.Bio
		}
		if b.Username != nil {
			payload["handle"] = *b.Username
		}
		return emit(tx, audience, "user.updated", "", payload)
	})
	if e != nil {
		fail(w, e)
		return
	}
	u, _ := a.getUser(p.UserID)
	respond(w, 200, u)
}

// profileAudience lists the user and everyone sharing a conversation with
// them, so a profile edit reaches every client that can render it.
func profileAudience(tx *sql.Tx, uid string) ([]string, error) {
	rows, e := tx.Query(
		`SELECT DISTINCT m.user_id FROM members m WHERE m.chat_id IN (SELECT chat_id FROM members WHERE user_id=?)`,
		uid,
	)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	seen := map[string]bool{uid: true}
	out := []string{uid}
	for rows.Next() {
		var id string
		if e = rows.Scan(&id); e != nil {
			return nil, e
		}
		if id != "" && !seen[id] {
			seen[id] = true
			out = append(out, id)
		}
	}
	return out, rows.Err()
}
func (a *App) users(w http.ResponseWriter, r *http.Request, p Principal) {
	q := r.URL.Query().Get("q")
	if len(q) < 2 || len(q) > 32 {
		fail(w, ErrInvalid)
		return
	}
	rows, e := a.DB.Query("SELECT id,handle,name,avatar,last_seen,EXISTS(SELECT 1 FROM user_blocks x WHERE (x.owner=? AND x.target=users.id) OR (x.target=? AND x.owner=users.id)) FROM users WHERE instr(handle,?)>0 ORDER BY handle LIMIT 30", p.UserID, p.UserID, strings.ToLower(q))
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []User{}
	for rows.Next() {
		var u User
		var blocked int
		if e = rows.Scan(&u.ID, &u.Handle, &u.Name, &u.Avatar, &u.LastSeen, &blocked); e != nil {
			fail(w, e)
			return
		}
		u.Online = a.online(u.ID)
		if blocked > 0 {
			u.Online = false
			u.LastSeen = ""
		}
		out = append(out, u)
	}
	respond(w, 200, map[string]any{"users": out})
}
func (a *App) devicePush(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Provider string `json:"provider"`
		Token    string `json:"token"`
	}
	if !decode(w, r, &b) {
		return
	}
	valid := map[string]bool{"mipush": true, "fcm": true, "huawei": true, "oppo": true, "vivo": true, "none": true}
	if !valid[b.Provider] || len(b.Token) > 4096 || (b.Provider == "none" && b.Token != "") || (b.Provider != "none" && b.Token == "") {
		fail(w, ErrInvalid)
		return
	}
	_, e := a.DB.Exec("UPDATE devices SET push_provider=?,push_token=? WHERE id=?", b.Provider, b.Token, p.DeviceID)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
func (a *App) revokeDevice(w http.ResponseWriter, r *http.Request, p Principal) {
	did := r.PathValue("id")
	res, e := a.DB.Exec("UPDATE devices SET revoked=1,push_token='' WHERE id=? AND user_id=?", did, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fail(w, ErrForbidden)
		return
	}
	a.hub.closeDevice(did)
	respond(w, 200, map[string]bool{"ok": true})
}
func (a *App) isMember(cid, uid string) bool {
	var n int
	e := a.DB.QueryRow("SELECT count(*) FROM members WHERE chat_id=? AND user_id=?", cid, uid).Scan(&n)
	return e == nil && n == 1
}
func (a *App) listMembers(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	if len(q) > 64 {
		fail(w, ErrInvalid)
		return
	}
	rows, e := a.DB.Query("SELECT b.user_id,b.role,b.joined_seq,CASE WHEN b.user_id=? OR (?=1 AND u.read_receipts_enabled=1 AND (SELECT read_receipts_enabled FROM users WHERE id=?)=1) THEN b.read_seq ELSE NULL END FROM members b JOIN users u ON u.id=b.user_id WHERE b.chat_id=? AND (?='' OR instr(lower(u.handle),?)>0 OR instr(lower(u.name),?)>0) ORDER BY b.user_id", p.UserID, a.C.ReadReceiptsEnabled, p.UserID, cid, q, q, q)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var u, role string
		var j int64
		var read sql.NullInt64
		if e = rows.Scan(&u, &role, &j, &read); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"user_id": u, "role": role, "joined_seq": j, "last_read_seq": func() any {
			if read.Valid {
				return read.Int64
			}
			return nil
		}()})
	}
	respond(w, 200, map[string]any{"members": out})
}
func (a *App) reactions(w http.ResponseWriter, r *http.Request, p Principal) {
	mid := r.PathValue("id")
	var n int
	e := a.DB.QueryRow("SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0", mid, p.UserID).Scan(&n)
	if e != nil {
		fail(w, e)
		return
	}
	if n != 1 {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT user_id,emoji FROM reactions WHERE message_id=?", mid)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]string{}
	for rows.Next() {
		var uid, emoji string
		rows.Scan(&uid, &emoji)
		out = append(out, map[string]string{"user_id": uid, "emoji": emoji})
	}
	respond(w, 200, map[string]any{"reactions": out})
}

type bucket struct {
	n     int
	until time.Time
}
type limiter struct {
	mu    sync.Mutex
	items map[string]bucket
}

func newLimiter() *limiter { return &limiter{items: map[string]bucket{}} }
func (l *limiter) allow(key string, max int, window time.Duration) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	t := time.Now()
	if len(l.items) > 10000 {
		for k, b := range l.items {
			if t.After(b.until) {
				delete(l.items, k)
			}
		}
		if len(l.items) > 10000 {
			return false
		}
	}
	b := l.items[key]
	if t.After(b.until) {
		b = bucket{until: t.Add(window)}
	}
	b.n++
	l.items[key] = b
	return b.n <= max
}
