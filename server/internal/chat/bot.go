package chat

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
)

const maxBotsPerOwner = 20

var (
	errBotUnauthorized = errors.New("unauthorized")
	errBotNotFound     = errors.New("bot not found")
	errWebhookActive   = errors.New("can't use getUpdates while webhook is active")
	errWebhookURL      = errors.New("invalid webhook url")
	botWaitMu          sync.Mutex
	botWait            = map[string]chan struct{}{}
)

func wakeBot(botID string) {
	botWaitMu.Lock()
	ch := botWait[botID]
	botWaitMu.Unlock()
	if ch == nil {
		return
	}
	select {
	case ch <- struct{}{}:
	default:
	}
}

func botWaitCh(botID string) chan struct{} {
	botWaitMu.Lock()
	defer botWaitMu.Unlock()
	if ch, ok := botWait[botID]; ok {
		return ch
	}
	ch := make(chan struct{}, 1)
	botWait[botID] = ch
	return ch
}

type botRow struct {
	UserID, OwnerID, TokenHash string
	APIID                      int64
	WebhookURL, WebhookSecret  string
	Handle, Name               string
}

func (a *App) botManageRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/bots", a.auth(a.listBots))
	mux.HandleFunc("POST /v1/bots", a.auth(a.createBot))
	mux.HandleFunc("POST /v1/bots/{id}/revoke", a.auth(a.revokeBotToken))
	mux.HandleFunc("DELETE /v1/bots/{id}", a.auth(a.deleteBot))
}

func validBotHandle(s string) bool {
	s = strings.ToLower(s)
	if !validHandle(s) {
		return false
	}
	return strings.HasSuffix(s, "bot")
}

func newBotToken(apiID int64) (plain, hashed string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", err
	}
	plain = fmt.Sprintf("%d:%s", apiID, strings.TrimRight(base64.RawURLEncoding.EncodeToString(b), "="))
	return plain, hash(plain), nil
}

func allocAPIID(tx *sql.Tx, kind, id string) (int64, error) {
	var existing int64
	e := tx.QueryRow("SELECT api_id FROM api_ids WHERE kind=? AND id=?", kind, id).Scan(&existing)
	if e == nil {
		return existing, nil
	}
	if !errors.Is(e, sql.ErrNoRows) {
		return 0, e
	}
	var max int64
	if e = tx.QueryRow("SELECT COALESCE(MAX(ABS(api_id)),100000) FROM api_ids").Scan(&max); e != nil {
		return 0, e
	}
	next := max + 1
	if kind == "chat" {
		var typ string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", id).Scan(&typ); e != nil && !errors.Is(e, sql.ErrNoRows) {
			return 0, e
		}
		if typ == "group" || typ == "channel" {
			next = -next
		}
	}
	if _, e = tx.Exec("INSERT INTO api_ids(kind,id,api_id) VALUES(?,?,?)", kind, id, next); e != nil {
		return 0, e
	}
	return next, nil
}

func lookupAPIID(tx *sql.Tx, kind string, apiID int64) (string, error) {
	var id string
	e := tx.QueryRow("SELECT id FROM api_ids WHERE kind=? AND api_id=?", kind, apiID).Scan(&id)
	return id, e
}

func (a *App) ensureUserAPIID(uid string) (int64, error) {
	var apiID int64
	e := a.transaction(func(tx *sql.Tx) error {
		var err error
		apiID, err = allocAPIID(tx, "user", uid)
		return err
	})
	return apiID, e
}

func (a *App) createBot(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Username string `json:"username"`
		Name     string `json:"display_name"`
	}
	if !decode(w, r, &b) {
		return
	}
	handle := strings.ToLower(strings.TrimSpace(b.Username))
	name := strings.TrimSpace(b.Name)
	if !validBotHandle(handle) || name == "" || len(name) > 120 {
		fail(w, ErrInvalid)
		return
	}
	var count int
	if e := a.DB.QueryRow("SELECT count(*) FROM bots WHERE owner_id=?", p.UserID).Scan(&count); e != nil {
		fail(w, e)
		return
	}
	if count >= maxBotsPerOwner {
		fail(w, ErrInvalid)
		return
	}
	var isBot int
	if e := a.DB.QueryRow("SELECT IFNULL(is_bot,0) FROM users WHERE id=?", p.UserID).Scan(&isBot); e != nil || isBot == 1 {
		fail(w, ErrForbidden)
		return
	}
	pwd := id() + id()
	hashedPwd, e := bcrypt.GenerateFromPassword([]byte(pwd), bcrypt.DefaultCost)
	if e != nil {
		fail(w, e)
		return
	}
	uid := id()
	var token string
	var apiID int64
	e = a.transaction(func(tx *sql.Tx) error {
		if _, err := tx.Exec("INSERT INTO users(id,handle,name,password,admin,last_seen,is_bot) VALUES(?,?,?,?,0,?,1)", uid, handle, name, string(hashedPwd), now()); err != nil {
			return ErrConflict
		}
		var err error
		apiID, err = allocAPIID(tx, "user", uid)
		if err != nil {
			return err
		}
		var hashed string
		token, hashed, err = newBotToken(apiID)
		if err != nil {
			return err
		}
		_, err = tx.Exec("INSERT INTO bots(user_id,owner_id,token_hash,api_id,created) VALUES(?,?,?,?,?)", uid, p.UserID, hashed, apiID, now())
		return err
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, map[string]any{
		"id":           uid,
		"api_id":       apiID,
		"username":     handle,
		"display_name": name,
		"token":        token,
	})
}

func (a *App) listBots(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT b.user_id,b.api_id,u.handle,u.name,b.created FROM bots b JOIN users u ON u.id=b.user_id WHERE b.owner_id=? ORDER BY b.created", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, handle, name, created string
		var apiID int64
		if e = rows.Scan(&id, &apiID, &handle, &name, &created); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"id": id, "api_id": apiID, "username": handle, "display_name": name, "created_at": created})
	}
	respond(w, 200, map[string]any{"bots": out})
}

func (a *App) ownerBot(p Principal, botID string) (botRow, error) {
	var b botRow
	e := a.DB.QueryRow("SELECT b.user_id,b.owner_id,b.token_hash,b.api_id,b.webhook_url,b.webhook_secret,u.handle,u.name FROM bots b JOIN users u ON u.id=b.user_id WHERE b.user_id=? AND b.owner_id=?", botID, p.UserID).
		Scan(&b.UserID, &b.OwnerID, &b.TokenHash, &b.APIID, &b.WebhookURL, &b.WebhookSecret, &b.Handle, &b.Name)
	if e != nil {
		return b, ErrForbidden
	}
	return b, nil
}

func (a *App) revokeBotToken(w http.ResponseWriter, r *http.Request, p Principal) {
	b, e := a.ownerBot(p, r.PathValue("id"))
	if e != nil {
		fail(w, e)
		return
	}
	token, hashed, e := newBotToken(b.APIID)
	if e != nil {
		fail(w, e)
		return
	}
	if _, e = a.DB.Exec("UPDATE bots SET token_hash=? WHERE user_id=?", hashed, b.UserID); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"token": token})
}

func (a *App) deleteBot(w http.ResponseWriter, r *http.Request, p Principal) {
	b, e := a.ownerBot(p, r.PathValue("id"))
	if e != nil {
		fail(w, e)
		return
	}
	e = a.transaction(func(tx *sql.Tx) error {
		if _, err := tx.Exec("DELETE FROM bot_updates WHERE bot_id=?", b.UserID); err != nil {
			return err
		}
		if _, err := tx.Exec("DELETE FROM bot_callbacks WHERE bot_id=?", b.UserID); err != nil {
			return err
		}
		if _, err := tx.Exec("DELETE FROM bots WHERE user_id=?", b.UserID); err != nil {
			return err
		}
		_, err := tx.Exec("UPDATE users SET handle=?,name=?,deleted=1,is_bot=1,password=?,last_seen=? WHERE id=?",
			"deleted_"+b.UserID, "已注销", hash(id()), now(), b.UserID)
		return err
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func authenticateBotToken(tx interface {
	QueryRow(string, ...any) *sql.Row
}, token string) (botRow, error) {
	var b botRow
	e := tx.QueryRow("SELECT b.user_id,b.owner_id,b.token_hash,b.api_id,b.webhook_url,b.webhook_secret,u.handle,u.name FROM bots b JOIN users u ON u.id=b.user_id WHERE b.token_hash=? AND IFNULL(u.deleted,0)=0", hash(token)).
		Scan(&b.UserID, &b.OwnerID, &b.TokenHash, &b.APIID, &b.WebhookURL, &b.WebhookSecret, &b.Handle, &b.Name)
	if e != nil {
		return b, errBotUnauthorized
	}
	return b, nil
}

func (a *App) loadBotByToken(token string) (botRow, error) {
	var b botRow
	e := a.DB.QueryRow("SELECT b.user_id,b.owner_id,b.token_hash,b.api_id,b.webhook_url,b.webhook_secret,u.handle,u.name FROM bots b JOIN users u ON u.id=b.user_id WHERE b.token_hash=? AND IFNULL(u.deleted,0)=0", hash(token)).
		Scan(&b.UserID, &b.OwnerID, &b.TokenHash, &b.APIID, &b.WebhookURL, &b.WebhookSecret, &b.Handle, &b.Name)
	if e != nil {
		return b, errBotUnauthorized
	}
	return b, nil
}

func enqueueBotUpdates(tx *sql.Tx, users []string, typ, chat string, raw []byte) error {
	switch typ {
	case "message.created", "message.edited", "message.deleted":
	default:
		return nil
	}
	var m Message
	if e := json.Unmarshal(raw, &m); e != nil {
		return nil
	}
	if m.ChatID == "" {
		m.ChatID = chat
	}
	for _, u := range users {
		var apiID int64
		e := tx.QueryRow("SELECT api_id FROM bots WHERE user_id=?", u).Scan(&apiID)
		if e != nil {
			continue
		}
		if m.Sender == u {
			continue
		}
		payload, err := buildBotUpdatePayload(tx, typ, u, m)
		if err != nil || payload == nil {
			if err != nil {
				return err
			}
			continue
		}
		var updateID int64
		if e = tx.QueryRow("SELECT COALESCE(MAX(update_id),0)+1 FROM bot_updates WHERE bot_id=?", u).Scan(&updateID); e != nil {
			return e
		}
		envelope, _ := json.Marshal(map[string]any{"update_id": updateID, "payload": json.RawMessage(payload)})
		// payload already is a full Update minus update_id; rebuild:
		var body map[string]any
		if e = json.Unmarshal(payload, &body); e != nil {
			return e
		}
		body["update_id"] = updateID
		envelope, _ = json.Marshal(body)
		if _, e = tx.Exec("INSERT INTO bot_updates(bot_id,update_id,payload,delivered,created) VALUES(?,?,?,0,?)", u, updateID, string(envelope), now()); e != nil {
			return e
		}
		go wakeBot(u)
	}
	_ = typ
	return nil
}

func buildBotUpdatePayload(tx *sql.Tx, typ, botID string, m Message) ([]byte, error) {
	msg, e := telegramMessage(tx, botID, m)
	if e != nil {
		return nil, e
	}
	key := "message"
	switch typ {
	case "message.edited":
		key = "edited_message"
	case "message.deleted":
		return json.Marshal(map[string]any{
			"message": map[string]any{
				"message_id":          m.Seq,
				"date":                unixTime(m.Created),
				"chat":                msg["chat"],
				"delete_chat_message": true,
			},
		})
	}
	return json.Marshal(map[string]any{key: msg})
}

func unixTime(s string) int64 {
	t, e := time.Parse(time.RFC3339Nano, s)
	if e != nil {
		t, e = time.Parse(time.RFC3339, s)
		if e != nil {
			return time.Now().Unix()
		}
	}
	return t.Unix()
}

func telegramUser(tx *sql.Tx, uid string) (map[string]any, error) {
	var handle, name string
	var isBot int
	if e := tx.QueryRow("SELECT handle,name,IFNULL(is_bot,0) FROM users WHERE id=?", uid).Scan(&handle, &name, &isBot); e != nil {
		return nil, e
	}
	apiID, e := allocAPIID(tx, "user", uid)
	if e != nil {
		return nil, e
	}
	first, last := name, ""
	if i := strings.Index(name, " "); i > 0 {
		first, last = name[:i], name[i+1:]
	}
	u := map[string]any{"id": apiID, "is_bot": isBot == 1, "first_name": first}
	if last != "" {
		u["last_name"] = last
	}
	if handle != "" {
		u["username"] = handle
	}
	return u, nil
}

func telegramChat(tx *sql.Tx, botID, cid string, peer string) (map[string]any, error) {
	var kind, title string
	if e := tx.QueryRow("SELECT kind,title FROM chats WHERE id=?", cid).Scan(&kind, &title); e != nil {
		return nil, e
	}
	if kind == "direct" {
		other := peer
		if other == "" || other == botID {
			rows, e := tx.Query("SELECT user_id FROM members WHERE chat_id=?", cid)
			if e != nil {
				return nil, e
			}
			for rows.Next() {
				var u string
				if e = rows.Scan(&u); e != nil {
					rows.Close()
					return nil, e
				}
				if u != botID {
					other = u
				}
			}
			rows.Close()
		}
		u, e := telegramUser(tx, other)
		if e != nil {
			return nil, e
		}
		return map[string]any{"id": u["id"], "type": "private", "username": u["username"], "first_name": u["first_name"], "last_name": u["last_name"]}, nil
	}
	apiID, e := allocAPIID(tx, "chat", cid)
	if e != nil {
		return nil, e
	}
	typ := "group"
	if kind == "channel" {
		typ = "channel"
	}
	return map[string]any{"id": apiID, "type": typ, "title": title}, nil
}

func telegramMessage(tx *sql.Tx, botID string, m Message) (map[string]any, error) {
	from, e := telegramUser(tx, m.Sender)
	if e != nil {
		return nil, e
	}
	chat, e := telegramChat(tx, botID, m.ChatID, m.Sender)
	if e != nil {
		return nil, e
	}
	out := map[string]any{
		"message_id": m.Seq,
		"from":       from,
		"chat":       chat,
		"date":       unixTime(m.Created),
	}
	if m.Text != "" && !m.Deleted {
		if m.MediaID != "" {
			out["caption"] = m.Text
		} else {
			out["text"] = m.Text
		}
	}
	if m.Deleted {
		out["text"] = ""
	}
	if m.Edited != "" {
		out["edit_date"] = unixTime(m.Edited)
	}
	if m.ReplyToSeq > 0 {
		out["reply_to_message"] = map[string]any{"message_id": m.ReplyToSeq}
	} else if m.ReplyTo != "" {
		var seq int64
		if e = tx.QueryRow("SELECT seq FROM messages WHERE id=?", m.ReplyTo).Scan(&seq); e == nil && seq > 0 {
			out["reply_to_message"] = map[string]any{"message_id": seq}
		}
	}
	if m.ReplyMarkup != nil {
		out["reply_markup"] = m.ReplyMarkup
	}
	if m.MediaID != "" && !m.Deleted {
		file := map[string]any{"file_id": m.MediaID, "file_unique_id": m.MediaID}
		if m.Media != nil {
			file["file_size"] = m.Media.Bytes
			if m.Media.FileName != "" {
				file["file_name"] = m.Media.FileName
			}
			if m.Media.MIME != "" {
				file["mime_type"] = m.Media.MIME
			}
			if m.Media.Width > 0 {
				file["width"] = m.Media.Width
			}
			if m.Media.Height > 0 {
				file["height"] = m.Media.Height
			}
			if m.Media.DurationMs > 0 {
				file["duration"] = m.Media.DurationMs / 1000
			}
			if m.Media.ThumbnailID != "" {
				file["thumbnail"] = map[string]any{"file_id": m.Media.ThumbnailID, "file_unique_id": m.Media.ThumbnailID}
			}
		}
		switch m.Kind {
		case "image":
			out["photo"] = []any{file}
		case "video":
			out["video"] = file
		case "animation":
			out["animation"] = file
		case "video_note":
			out["video_note"] = file
		case "voice":
			out["voice"] = file
		default:
			if m.Media != nil && strings.HasPrefix(m.Media.MIME, "audio/") {
				out["audio"] = file
			} else {
				out["document"] = file
			}
		}
	}
	return out, nil
}

func (a *App) dispatchCallbackQuery(p Principal, m Message, data string) error {
	// The bot that owns the message is the sender if it is a bot; otherwise any
	// bot member of the chat whose keyboard this is.
	botID := m.Sender
	var isBot int
	if e := a.DB.QueryRow("SELECT IFNULL(is_bot,0) FROM users WHERE id=?", botID).Scan(&isBot); e != nil || isBot != 1 {
		// Prefer the message sender; fall back to via_bot or first bot member.
		botID = m.ViaBotID
		if botID == "" {
			_ = a.DB.QueryRow("SELECT b.user_id FROM bots b JOIN members mb ON mb.user_id=b.user_id WHERE mb.chat_id=? LIMIT 1", m.ChatID).Scan(&botID)
		}
	}
	if botID == "" {
		return ErrInvalid
	}
	qid := id()
	return a.transaction(func(tx *sql.Tx) error {
		if _, e := tx.Exec("INSERT INTO bot_callbacks(id,bot_id,chat_id,message_id,from_user,data,created) VALUES(?,?,?,?,?,?,?)", qid, botID, m.ChatID, m.ID, p.UserID, data, now()); e != nil {
			return e
		}
		from, e := telegramUser(tx, p.UserID)
		if e != nil {
			return e
		}
		msg, e := telegramMessage(tx, botID, m)
		if e != nil {
			return e
		}
		var updateID int64
		if e = tx.QueryRow("SELECT COALESCE(MAX(update_id),0)+1 FROM bot_updates WHERE bot_id=?", botID).Scan(&updateID); e != nil {
			return e
		}
		body, _ := json.Marshal(map[string]any{
			"update_id": updateID,
			"callback_query": map[string]any{
				"id":            qid,
				"from":          from,
				"message":       msg,
				"data":          data,
				"chat_instance": m.ChatID,
			},
		})
		if _, e = tx.Exec("INSERT INTO bot_updates(bot_id,update_id,payload,delivered,created) VALUES(?,?,?,0,?)", botID, updateID, string(body), now()); e != nil {
			return e
		}
		go wakeBot(botID)
		return nil
	})
}
