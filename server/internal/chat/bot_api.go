package chat

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

type botAPIError struct {
	Code int
	Desc string
}

func (e botAPIError) Error() string { return e.Desc }

func botOK(w http.ResponseWriter, result any) {
	respond(w, 200, map[string]any{"ok": true, "result": result})
}

func botFail(w http.ResponseWriter, e error) {
	code, desc := 400, "Bad Request"
	switch {
	case errors.Is(e, errBotUnauthorized):
		code, desc = 401, "Unauthorized"
	case errors.Is(e, errWebhookActive):
		code, desc = 409, e.Error()
	case errors.Is(e, errWebhookURL):
		code, desc = 400, "Invalid webhook URL"
	case errors.Is(e, ErrForbidden), errors.Is(e, sql.ErrNoRows), errors.Is(e, errBotNotFound):
		code, desc = 403, "Forbidden"
	case errors.Is(e, ErrConflict):
		code, desc = 409, "Conflict"
	case errors.Is(e, ErrRateLimited):
		code, desc = 429, "Too Many Requests"
	default:
		var be botAPIError
		if errors.As(e, &be) {
			code, desc = be.Code, be.Desc
		} else if errors.Is(e, errFileTooLarge) || errors.Is(e, errUploadFailed) {
			code, desc = 413, "file is too big"
		} else if errors.Is(e, errMediaQuota) {
			code, desc = 507, "media quota exceeded"
		} else if errors.Is(e, errUnsupportedMedia) {
			code, desc = 400, "unsupported media type"
		} else if errors.Is(e, ErrInvalid) {
			code, desc = 400, "Bad Request"
		} else if e != nil {
			code, desc = 400, "Bad Request"
		}
	}
	respond(w, code, map[string]any{"ok": false, "error_code": code, "description": desc})
}

func parseBotRequest(r *http.Request) (token, method, filePath string, ok bool) {
	path := r.URL.Path
	if strings.HasPrefix(path, "/file/bot") {
		rest := strings.TrimPrefix(path, "/file/bot")
		i := strings.IndexByte(rest, '/')
		if i <= 0 {
			return "", "", "", false
		}
		return rest[:i], "", rest[i+1:], true
	}
	if !strings.HasPrefix(path, "/bot") {
		return "", "", "", false
	}
	rest := strings.TrimPrefix(path, "/bot")
	i := strings.IndexByte(rest, '/')
	if i <= 0 {
		// /bot<token> with method in query ? or POST root is invalid
		return "", "", "", false
	}
	return rest[:i], rest[i+1:], "", true
}

func (a *App) serveBotAPI(w http.ResponseWriter, r *http.Request) {
	token, method, filePath, ok := parseBotRequest(r)
	if !ok {
		botFail(w, botAPIError{404, "Not Found"})
		return
	}
	bot, e := a.loadBotByToken(token)
	if e != nil {
		botFail(w, errBotUnauthorized)
		return
	}
	if filePath != "" {
		a.botDownloadFile(w, r, bot, filePath)
		return
	}
	if r.Body != nil && (r.Method == http.MethodPost || r.Method == http.MethodPut || r.Method == http.MethodPatch) {
		limit := a.C.MaxFile + (2 << 20)
		if limit < (2 << 20) {
			limit = 2 << 20
		}
		r.Body = http.MaxBytesReader(w, r.Body, limit)
	}
	params, files, e := readBotParams(r)
	if e != nil {
		var mb *http.MaxBytesError
		if errors.As(e, &mb) || errors.Is(e, errFileTooLarge) || errors.Is(e, errUploadFailed) {
			botFail(w, botAPIError{413, "file is too big"})
			return
		}
		botFail(w, ErrInvalid)
		return
	}
	method = strings.TrimSuffix(method, "/")
	switch method {
	case "getMe":
		botOK(w, a.botUserObject(bot))
	case "getUpdates":
		result, err := a.botGetUpdates(r.Context(), bot, params)
		if err != nil {
			botFail(w, err)
			return
		}
		botOK(w, result)
	case "setWebhook":
		info, err := a.botSetWebhook(bot, params)
		if err != nil {
			botFail(w, err)
			return
		}
		botOK(w, info)
	case "deleteWebhook":
		if _, err := a.botSetWebhook(bot, map[string]any{"url": ""}); err != nil {
			botFail(w, err)
			return
		}
		botOK(w, true)
	case "getWebhookInfo":
		botOK(w, a.botWebhookInfo(bot))
	case "sendMessage":
		msg, err := a.botSend(bot, params, files, "text", "")
		if err != nil {
			botFail(w, err)
			return
		}
		botOK(w, msg)
	case "editMessageText":
		msg, err := a.botEdit(bot, params)
		if err != nil {
			botFail(w, err)
			return
		}
		botOK(w, msg)
	case "deleteMessage":
		if err := a.botDelete(bot, params); err != nil {
			botFail(w, err)
			return
		}
		botOK(w, true)
	case "sendPhoto", "sendDocument", "sendAudio", "sendVideo", "sendVoice":
		kind := map[string]string{"sendPhoto": "image", "sendDocument": "file", "sendAudio": "file", "sendVideo": "video", "sendVoice": "voice"}[method]
		field := map[string]string{"sendPhoto": "photo", "sendDocument": "document", "sendAudio": "audio", "sendVideo": "video", "sendVoice": "voice"}[method]
		msg, err := a.botSend(bot, params, files, kind, field)
		if err != nil {
			botFail(w, err)
			return
		}
		botOK(w, msg)
	case "answerCallbackQuery":
		if err := a.botAnswerCallback(bot, params); err != nil {
			botFail(w, err)
			return
		}
		botOK(w, true)
	case "getFile":
		result, err := a.botGetFile(bot, params)
		if err != nil {
			botFail(w, err)
			return
		}
		botOK(w, result)
	default:
		botFail(w, botAPIError{404, "Not Found"})
	}
}

func readBotParams(r *http.Request) (map[string]any, map[string]*multipart.FileHeader, error) {
	out := map[string]any{}
	files := map[string]*multipart.FileHeader{}
	for k, vs := range r.URL.Query() {
		if len(vs) > 0 {
			out[k] = vs[0]
		}
	}
	ct := r.Header.Get("Content-Type")
	if r.Method == http.MethodGet || r.Body == nil {
		return out, files, nil
	}
	if strings.HasPrefix(ct, "multipart/form-data") {
		if e := r.ParseMultipartForm(aBotMaxMultipart); e != nil {
			return nil, nil, e
		}
		if r.MultipartForm != nil {
			for k, vs := range r.MultipartForm.Value {
				if len(vs) > 0 {
					out[k] = vs[0]
				}
			}
			for k, fhs := range r.MultipartForm.File {
				if len(fhs) > 0 && fhs[0] != nil {
					files[k] = fhs[0]
				}
			}
		}
		return out, files, nil
	}
	if strings.HasPrefix(ct, "application/x-www-form-urlencoded") {
		if e := r.ParseForm(); e != nil {
			return nil, nil, e
		}
		for k, vs := range r.PostForm {
			if len(vs) > 0 {
				out[k] = vs[0]
			}
		}
		return out, files, nil
	}
	defer r.Body.Close()
	body, e := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if e != nil {
		return nil, nil, e
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return out, files, nil
	}
	var parsed map[string]any
	if e = json.Unmarshal(body, &parsed); e != nil {
		return nil, nil, e
	}
	for k, v := range parsed {
		out[k] = v
	}
	return out, files, nil
}

const aBotMaxMultipart = 21 << 20

func paramString(p map[string]any, key string) string {
	v, ok := p[key]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return strconv.FormatFloat(t, 'f', -1, 64)
	case json.Number:
		return t.String()
	case bool:
		if t {
			return "true"
		}
		return "false"
	default:
		b, _ := json.Marshal(t)
		return string(b)
	}
}

func paramInt(p map[string]any, key string) (int64, bool) {
	s := paramString(p, key)
	if s == "" {
		return 0, false
	}
	n, e := strconv.ParseInt(s, 10, 64)
	return n, e == nil
}

func (a *App) botUserObject(b botRow) map[string]any {
	first, last := b.Name, ""
	if i := strings.Index(b.Name, " "); i > 0 {
		first, last = b.Name[:i], b.Name[i+1:]
	}
	out := map[string]any{"id": b.APIID, "is_bot": true, "first_name": first, "username": b.Handle, "can_join_groups": true, "can_read_all_group_messages": false, "supports_inline_queries": false}
	if last != "" {
		out["last_name"] = last
	}
	return out
}

func (a *App) botGetUpdates(ctx context.Context, b botRow, p map[string]any) (any, error) {
	if b.WebhookURL != "" {
		return nil, errWebhookActive
	}
	offset, _ := paramInt(p, "offset")
	limit, ok := paramInt(p, "limit")
	if !ok || limit <= 0 {
		limit = 100
	}
	if limit > 100 {
		limit = 100
	}
	timeout, _ := paramInt(p, "timeout")
	if timeout < 0 {
		timeout = 0
	}
	if timeout > 30 {
		timeout = 30
	}
	if offset > 0 {
		if _, e := a.DB.Exec("DELETE FROM bot_updates WHERE bot_id=? AND update_id<?", b.UserID, offset); e != nil {
			return nil, e
		}
	}
	fetch := func() ([]json.RawMessage, error) {
		rows, e := a.DB.Query("SELECT payload FROM bot_updates WHERE bot_id=? AND delivered=0 ORDER BY update_id LIMIT ?", b.UserID, limit)
		if e != nil {
			return nil, e
		}
		defer rows.Close()
		out := []json.RawMessage{}
		for rows.Next() {
			var s string
			if e = rows.Scan(&s); e != nil {
				return nil, e
			}
			out = append(out, json.RawMessage(s))
		}
		return out, rows.Err()
	}
	out, e := fetch()
	if e != nil {
		return nil, e
	}
	if len(out) > 0 || timeout == 0 {
		if out == nil {
			out = []json.RawMessage{}
		}
		return out, nil
	}
	ch := botWaitCh(b.UserID)
	timer := time.NewTimer(time.Duration(timeout) * time.Second)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	case <-ch:
	}
	out, e = fetch()
	if e != nil {
		return nil, e
	}
	if out == nil {
		out = []json.RawMessage{}
	}
	return out, nil
}

func (a *App) botSetWebhook(b botRow, p map[string]any) (bool, error) {
	u := strings.TrimSpace(paramString(p, "url"))
	secret := paramString(p, "secret_token")
	if len(secret) > 256 {
		return false, ErrInvalid
	}
	if u == "" {
		_, e := a.DB.Exec("UPDATE bots SET webhook_url='',webhook_secret='' WHERE user_id=?", b.UserID)
		return true, e
	}
	if e := a.validateWebhookURL(u); e != nil {
		return false, e
	}
	_, e := a.DB.Exec("UPDATE bots SET webhook_url=?,webhook_secret=? WHERE user_id=?", u, secret, b.UserID)
	return true, e
}

func (a *App) botWebhookInfo(b botRow) map[string]any {
	var url, secret string
	var pending int
	a.DB.QueryRow("SELECT webhook_url,webhook_secret FROM bots WHERE user_id=?", b.UserID).Scan(&url, &secret)
	a.DB.QueryRow("SELECT count(*) FROM bot_updates WHERE bot_id=? AND delivered=0", b.UserID).Scan(&pending)
	return map[string]any{"url": url, "has_custom_certificate": false, "pending_update_count": pending, "ip_address": "", "max_connections": 40}
}

func (a *App) validateWebhookURL(raw string) error {
	u, e := url.Parse(raw)
	if e != nil || u.Host == "" || u.User != nil {
		return errWebhookURL
	}
	scheme := strings.ToLower(u.Scheme)
	host := u.Hostname()
	if scheme != "https" {
		if !(a.C.AllowHTTPWebhook && scheme == "http" && isLoopbackHost(host)) {
			return errWebhookURL
		}
	}
	ips, e := net.LookupIP(host)
	if e != nil || len(ips) == 0 {
		// Allow unresolved loopback hostnames only in tests (httptest uses IPs).
		if a.C.AllowHTTPWebhook && isLoopbackHost(host) {
			return nil
		}
		return errWebhookURL
	}
	for _, ip := range ips {
		if !a.C.AllowHTTPWebhook || !ip.IsLoopback() {
			if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsUnspecified() || isMetadataIP(ip) {
				return errWebhookURL
			}
		}
	}
	return nil
}

func isLoopbackHost(host string) bool {
	h := strings.ToLower(host)
	if h == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func isMetadataIP(ip net.IP) bool {
	v4 := ip.To4()
	if v4 == nil {
		return false
	}
	return v4[0] == 169 && v4[1] == 254 && v4[2] == 169 && v4[3] == 254
}

func (a *App) processBotWebhooks() {
	rows, e := a.DB.Query("SELECT user_id,webhook_url,webhook_secret FROM bots WHERE webhook_url<>''")
	if e != nil {
		return
	}
	type hook struct{ id, url, secret string }
	list := []hook{}
	for rows.Next() {
		var h hook
		if rows.Scan(&h.id, &h.url, &h.secret) == nil {
			list = append(list, h)
		}
	}
	rows.Close()
	for _, h := range list {
		a.flushBotWebhook(h.id, h.url, h.secret)
	}
}

func (a *App) flushBotWebhook(botID, hookURL, secret string) {
	rows, e := a.DB.Query("SELECT update_id,payload FROM bot_updates WHERE bot_id=? AND delivered=0 ORDER BY update_id LIMIT 16", botID)
	if e != nil {
		return
	}
	type item struct {
		id      int64
		payload string
	}
	items := []item{}
	for rows.Next() {
		var it item
		if rows.Scan(&it.id, &it.payload) == nil {
			items = append(items, it)
		}
	}
	rows.Close()
	client := &http.Client{Timeout: 8 * time.Second}
	for _, it := range items {
		req, e := http.NewRequest(http.MethodPost, hookURL, strings.NewReader(it.payload))
		if e != nil {
			return
		}
		req.Header.Set("Content-Type", "application/json")
		if secret != "" {
			req.Header.Set("X-Bot-Api-Secret-Token", secret)
		}
		resp, e := client.Do(req)
		if e != nil {
			return
		}
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return
		}
		a.DB.Exec("UPDATE bot_updates SET delivered=1 WHERE bot_id=? AND update_id=?", botID, it.id)
	}
}

func (a *App) resolveBotChat(bot botRow, chatID string) (string, error) {
	chatID = strings.TrimSpace(chatID)
	if chatID == "" {
		return "", ErrInvalid
	}
	if strings.HasPrefix(chatID, "@") {
		chatID = chatID[1:]
	}
	var cid string
	// Existing conversation id?
	if e := a.DB.QueryRow("SELECT id FROM chats WHERE id=?", chatID).Scan(&cid); e == nil {
		if !a.isMember(cid, bot.UserID) {
			return "", ErrForbidden
		}
		return cid, nil
	}
	// Numeric api_id
	if n, err := strconv.ParseInt(chatID, 10, 64); err == nil {
		var kind, id string
		e := a.DB.QueryRow("SELECT kind,id FROM api_ids WHERE api_id=?", n).Scan(&kind, &id)
		if e != nil {
			return "", ErrInvalid
		}
		if kind == "chat" {
			if !a.isMember(id, bot.UserID) {
				return "", ErrForbidden
			}
			return id, nil
		}
		// user: get or create direct chat
		p := Principal{UserID: bot.UserID}
		return a.CreateChat(p, "direct", "", []string{id})
	}
	// handle
	var uid string
	if e := a.DB.QueryRow("SELECT id FROM users WHERE handle=? AND IFNULL(deleted,0)=0", strings.ToLower(chatID)).Scan(&uid); e != nil {
		return "", ErrInvalid
	}
	return a.CreateChat(Principal{UserID: bot.UserID}, "direct", "", []string{uid})
}

func (a *App) botSend(bot botRow, p map[string]any, files map[string]*multipart.FileHeader, kind, mediaField string) (map[string]any, error) {
	cid, e := a.resolveBotChat(bot, paramString(p, "chat_id"))
	if e != nil {
		return nil, e
	}
	text := paramString(p, "text")
	if text == "" {
		text = paramString(p, "caption")
	}
	if !utf8.ValidString(text) || len(text) > 16384 {
		return nil, ErrInvalid
	}
	s := Send{ClientID: "bot-" + id(), Kind: kind, Text: text}
	if mediaField != "" {
		mediaID, e := a.resolveBotInputFile(bot, cid, p, files, mediaField, kind)
		if e != nil {
			return nil, e
		}
		s.MediaID = mediaID
		if kind == "text" {
			s.Kind = "file"
		}
	} else if strings.TrimSpace(text) == "" {
		return nil, ErrInvalid
	}
	if reply, ok := paramInt(p, "reply_to_message_id"); ok && reply > 0 {
		var mid string
		if e := a.DB.QueryRow("SELECT id FROM messages WHERE chat_id=? AND seq=?", cid, reply).Scan(&mid); e != nil {
			return nil, ErrInvalid
		}
		s.ReplyTo = mid
	}
	if raw := p["reply_markup"]; raw != nil {
		var markup ReplyMarkup
		b, _ := json.Marshal(raw)
		if e := json.Unmarshal(b, &markup); e != nil {
			return nil, ErrInvalid
		}
		s.ReplyMarkup = &markup
	}
	msg, e := a.SendMessage(Principal{UserID: bot.UserID}, cid, s)
	if e != nil {
		return nil, e
	}
	var out map[string]any
	e = a.transaction(func(tx *sql.Tx) error {
		var err error
		out, err = telegramMessage(tx, bot.UserID, msg)
		return err
	})
	return out, e
}

func (a *App) botEdit(bot botRow, p map[string]any) (map[string]any, error) {
	cid, e := a.resolveBotChat(bot, paramString(p, "chat_id"))
	if e != nil {
		return nil, e
	}
	seq, ok := paramInt(p, "message_id")
	if !ok || seq <= 0 {
		return nil, ErrInvalid
	}
	var mid string
	var m Message
	m, e = scanMessage(a.DB.QueryRow("SELECT "+msgColumns+" FROM messages WHERE chat_id=? AND seq=?", cid, seq))
	if e != nil {
		return nil, e
	}
	mid = m.ID
	text := paramString(p, "text")
	if strings.TrimSpace(text) == "" || !utf8.ValidString(text) {
		return nil, ErrInvalid
	}
	s := Send{Text: text, Kind: "text"}
	if raw := p["reply_markup"]; raw != nil {
		var markup ReplyMarkup
		b, _ := json.Marshal(raw)
		if e := json.Unmarshal(b, &markup); e != nil {
			return nil, ErrInvalid
		}
		s.ReplyMarkup = &markup
	}
	if e = a.EditMessage(Principal{UserID: bot.UserID}, mid, s); e != nil {
		return nil, e
	}
	m, e = scanMessage(a.DB.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
	if e != nil {
		return nil, e
	}
	var out map[string]any
	e = a.transaction(func(tx *sql.Tx) error {
		var err error
		out, err = telegramMessage(tx, bot.UserID, m)
		return err
	})
	return out, e
}

func (a *App) botDelete(bot botRow, p map[string]any) error {
	cid, e := a.resolveBotChat(bot, paramString(p, "chat_id"))
	if e != nil {
		return e
	}
	seq, ok := paramInt(p, "message_id")
	if !ok || seq <= 0 {
		return ErrInvalid
	}
	var mid string
	if e = a.DB.QueryRow("SELECT id FROM messages WHERE chat_id=? AND seq=?", cid, seq).Scan(&mid); e != nil {
		return e
	}
	return a.AlterMessage(Principal{UserID: bot.UserID}, mid, "delete", "")
}

func (a *App) botAnswerCallback(bot botRow, p map[string]any) error {
	qid := paramString(p, "callback_query_id")
	if qid == "" {
		return ErrInvalid
	}
	res, e := a.DB.Exec("UPDATE bot_callbacks SET answered=1 WHERE id=? AND bot_id=?", qid, bot.UserID)
	if e != nil {
		return e
	}
	n, _ := res.RowsAffected()
	if n != 1 {
		return ErrInvalid
	}
	return nil
}

func botMediaRequire(kind, field string) string {
	switch field {
	case "photo":
		return "image/"
	case "video":
		return "video/"
	case "voice", "audio":
		return "audio/"
	}
	switch kind {
	case "image":
		return "image/"
	case "video":
		return "video/"
	case "voice":
		return "audio/"
	}
	return ""
}

func botThumbField(p map[string]any, files map[string]*multipart.FileHeader) string {
	for _, name := range []string{"thumbnail", "thumb"} {
		if _, ok := files[name]; ok {
			return name
		}
		if paramString(p, name) != "" {
			return name
		}
	}
	return ""
}

func (a *App) resolveBotInputFile(bot botRow, cid string, p map[string]any, files map[string]*multipart.FileHeader, field, kind string) (string, error) {
	if files == nil {
		files = map[string]*multipart.FileHeader{}
	}
	var thumbID string
	var thumbNew bool
	if field == "document" || field == "audio" || field == "video" {
		if tf := botThumbField(p, files); tf != "" {
			id, created, e := a.lookupOrStoreBotFile(bot, cid, p, files, tf, "image/", "", false)
			if e != nil {
				return "", e
			}
			thumbID, thumbNew = id, created
		}
	}
	mid, _, e := a.lookupOrStoreBotFile(bot, cid, p, files, field, botMediaRequire(kind, field), thumbID, true)
	if e != nil {
		if thumbNew && thumbID != "" {
			a.removeOrphanMedia(thumbID)
		}
		return "", e
	}
	return mid, nil
}

func (a *App) lookupOrStoreBotFile(bot botRow, cid string, p map[string]any, files map[string]*multipart.FileHeader, field, require, thumbID string, applyMeta bool) (string, bool, error) {
	if fh, ok := files[field]; ok {
		mid, e := a.storeBotUpload(bot, cid, fh, p, require, thumbID, applyMeta)
		return mid, true, e
	}
	raw := strings.TrimSpace(paramString(p, field))
	if raw == "" {
		return "", false, botAPIError{400, "media is required"}
	}
	if strings.HasPrefix(raw, "attach://") {
		name := strings.TrimPrefix(raw, "attach://")
		if name == "" || strings.ContainsAny(name, "/\\") || strings.Contains(name, "..") {
			return "", false, botAPIError{400, "attached file not found"}
		}
		fh, ok := files[name]
		if !ok {
			return "", false, botAPIError{400, "attached file not found"}
		}
		mid, e := a.storeBotUpload(bot, cid, fh, p, require, thumbID, applyMeta)
		return mid, true, e
	}
	var mime string
	if e := a.DB.QueryRow("SELECT mime FROM media WHERE id=?", raw).Scan(&mime); e != nil {
		return "", false, botAPIError{400, "unknown file_id"}
	}
	if require != "" && !strings.HasPrefix(mime, require) {
		return "", false, errUnsupportedMedia
	}
	return raw, false, nil
}

func (a *App) storeBotUpload(bot botRow, cid string, fh *multipart.FileHeader, p map[string]any, require, thumbID string, applyMeta bool) (string, error) {
	if fh == nil {
		return "", ErrInvalid
	}
	if e := a.uploadPermission(Principal{UserID: bot.UserID}, cid); e != nil {
		return "", e
	}
	src, e := fh.Open()
	if e != nil {
		return "", ErrInvalid
	}
	defer src.Close()
	opts := mediaStoreOpts{
		Owner: bot.UserID, ChatID: cid, FileName: fh.Filename, Require: require, ThumbnailID: thumbID,
	}
	if applyMeta {
		if w, ok := paramInt(p, "width"); ok && w >= 0 && w <= 65535 {
			opts.Width = int(w)
		}
		if h, ok := paramInt(p, "height"); ok && h >= 0 && h <= 65535 {
			opts.Height = int(h)
		}
		if d, ok := paramInt(p, "duration_ms"); ok && d >= 0 && d <= 86_400_000 {
			opts.DurationMs = int(d)
		} else if d, ok := paramInt(p, "duration"); ok && d >= 0 && d <= 86_400 {
			opts.DurationMs = int(d) * 1000
		}
	}
	info, e := a.storeMedia(context.Background(), src, opts)
	if e != nil {
		return "", e
	}
	return info.ID, nil
}

func (a *App) removeOrphanMedia(mid string) {
	if mid == "" || !keyRE.MatchString(mid) {
		return
	}
	var refs int
	_ = a.DB.QueryRow("SELECT (SELECT count(*) FROM messages WHERE media_id=? AND deleted=0)+(SELECT count(*) FROM media WHERE thumbnail_id=?)", mid, mid).Scan(&refs)
	if refs > 0 {
		return
	}
	_ = a.storage.Delete(context.Background(), mid)
	_, _ = a.DB.Exec("DELETE FROM media WHERE id=?", mid)
}

func (a *App) botGetFile(bot botRow, p map[string]any) (map[string]any, error) {
	fid := paramString(p, "file_id")
	if fid == "" {
		return nil, ErrInvalid
	}
	var bytes int64
	var mime string
	e := a.DB.QueryRow("SELECT bytes,mime FROM media WHERE id=?", fid).Scan(&bytes, &mime)
	if e != nil {
		return nil, ErrInvalid
	}
	// Authorize: bot owns it or it appears in a shared chat.
	var allowed int
	a.DB.QueryRow(`SELECT (SELECT count(*) FROM media WHERE id=? AND owner=?)+(SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.media_id=? AND b.user_id=? AND m.deleted=0)`, fid, bot.UserID, fid, bot.UserID).Scan(&allowed)
	if allowed == 0 {
		return nil, ErrForbidden
	}
	return map[string]any{"file_id": fid, "file_unique_id": fid, "file_size": bytes, "file_path": "media/" + fid}, nil
}

func (a *App) botDownloadFile(w http.ResponseWriter, r *http.Request, bot botRow, path string) {
	fid := strings.TrimPrefix(path, "media/")
	fid = strings.TrimPrefix(fid, "/")
	var mime string
	var bytes int64
	e := a.DB.QueryRow("SELECT mime,bytes FROM media WHERE id=?", fid).Scan(&mime, &bytes)
	if e != nil {
		botFail(w, ErrForbidden)
		return
	}
	var allowed int
	a.DB.QueryRow(`SELECT (SELECT count(*) FROM media WHERE id=? AND owner=?)+(SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.media_id=? AND b.user_id=? AND m.deleted=0)`, fid, bot.UserID, fid, bot.UserID).Scan(&allowed)
	if allowed == 0 {
		botFail(w, ErrForbidden)
		return
	}
	f, e := a.storage.Open(r.Context(), fid)
	if e != nil {
		botFail(w, e)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Content-Length", fmt.Sprint(bytes))
	io.Copy(w, f)
}
