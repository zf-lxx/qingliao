package chat

import (
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

func allowedMessageKind(kind string) bool {
	switch kind {
	case "text", "image", "voice", "file", "video", "sticker", "poll", "checklist", "location", "contact", "dice", "video_note", "animation":
		return true
	default:
		return false
	}
}

func permForKind(kind string) string {
	switch kind {
	case "text":
		return "can_send_basic_messages"
	case "image":
		return "can_send_photos"
	case "voice":
		return "can_send_voice_notes"
	case "video":
		return "can_send_videos"
	case "video_note":
		return "can_send_video_notes"
	case "file":
		return "can_send_documents"
	case "poll", "checklist":
		return "can_send_polls"
	default:
		return "can_send_other_messages"
	}
}

func memberCan(tx *sql.Tx, cid, role, key string) (bool, error) {
	if role == "owner" || role == "admin" || key == "" {
		return true, nil
	}
	var raw string
	if e := tx.QueryRow("SELECT IFNULL(permissions_json,'') FROM chats WHERE id=?", cid).Scan(&raw); e != nil {
		return false, e
	}
	if strings.TrimSpace(raw) == "" {
		return true, nil
	}
	var m map[string]any
	if json.Unmarshal([]byte(raw), &m) != nil {
		return true, nil
	}
	v, ok := m[key]
	if !ok {
		return true, nil
	}
	b, ok := v.(bool)
	if !ok {
		return true, nil
	}
	return b, nil
}

func prepareSend(s *Send) error {
	if !allowedMessageKind(s.Kind) {
		return ErrInvalid
	}
	if s.TTL < -1 || s.TTL > 366*24*3600 {
		return ErrInvalid
	}
	if s.SendAt < 0 || s.SendAt > time.Now().Unix()+366*24*3600 {
		return ErrInvalid
	}
	switch s.Kind {
	case "location":
		return normalizeLocation(s)
	case "contact":
		return normalizeContact(s)
	case "dice":
		return normalizeDice(s)
	default:
		if len(s.Extra) > 4000 {
			return ErrInvalid
		}
		if len(s.Extra) > 0 && !json.Valid(s.Extra) {
			return ErrInvalid
		}
		return nil
	}
}

func asFloat(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case json.Number:
		f, e := n.Float64()
		return f, e == nil
	default:
		return 0, false
	}
}

func normalizeLocation(s *Send) error {
	if s.MediaID != "" || s.StickerID != "" || len(s.Extra) == 0 || len(s.Extra) > 4000 {
		return ErrInvalid
	}
	var raw map[string]any
	if json.Unmarshal(s.Extra, &raw) != nil {
		return ErrInvalid
	}
	lat, ok1 := asFloat(raw["latitude"])
	lon, ok2 := asFloat(raw["longitude"])
	if !ok1 || !ok2 || lat < -90 || lat > 90 || lon < -180 || lon > 180 {
		return ErrInvalid
	}
	out := map[string]any{"latitude": lat, "longitude": lon}
	if title, _ := raw["title"].(string); title != "" {
		if len(title) > 128 {
			return ErrInvalid
		}
		out["title"] = title
	}
	if address, _ := raw["address"].(string); address != "" {
		if len(address) > 256 {
			return ErrInvalid
		}
		out["address"] = address
	}
	b, e := json.Marshal(out)
	if e != nil {
		return e
	}
	s.Extra = b
	return nil
}

func normalizeContact(s *Send) error {
	if s.MediaID != "" || s.StickerID != "" || len(s.Extra) == 0 || len(s.Extra) > 4000 {
		return ErrInvalid
	}
	var raw map[string]any
	if json.Unmarshal(s.Extra, &raw) != nil {
		return ErrInvalid
	}
	phone, _ := raw["phone_number"].(string)
	first, _ := raw["first_name"].(string)
	phone = strings.TrimSpace(phone)
	first = strings.TrimSpace(first)
	if phone == "" || len(phone) > 32 || first == "" || len(first) > 64 {
		return ErrInvalid
	}
	out := map[string]any{"phone_number": phone, "first_name": first}
	if last, _ := raw["last_name"].(string); last != "" {
		if len(last) > 64 {
			return ErrInvalid
		}
		out["last_name"] = last
	}
	if vcard, _ := raw["vcard"].(string); vcard != "" {
		if len(vcard) > 2048 {
			return ErrInvalid
		}
		out["vcard"] = vcard
	}
	switch id := raw["user_id"].(type) {
	case string:
		if id != "" && len(id) <= 64 {
			out["user_id"] = id
		}
	case float64:
		if id > 0 {
			out["user_id"] = int64(id)
		}
	}
	b, e := json.Marshal(out)
	if e != nil {
		return e
	}
	s.Extra = b
	if s.Text == "" {
		s.Text = first
	}
	return nil
}

func normalizeDice(s *Send) error {
	if s.MediaID != "" || s.StickerID != "" {
		return ErrInvalid
	}
	emoji := strings.TrimSpace(s.Text)
	if emoji == "" && len(s.Extra) > 0 {
		var raw map[string]any
		if json.Unmarshal(s.Extra, &raw) == nil {
			emoji, _ = raw["emoji"].(string)
		}
	}
	if _, ok := diceFaces[emoji]; !ok {
		return ErrInvalid
	}
	s.Text = emoji
	b, e := json.Marshal(map[string]any{"emoji": emoji})
	if e != nil {
		return e
	}
	s.Extra = b
	return nil
}

var diceFaces = map[string]int{"🎲": 6, "🎯": 6, "🎳": 6, "🏀": 5, "⚽": 5, "🎰": 64}

func rollDice(emoji string) (int, bool) {
	n, ok := diceFaces[emoji]
	if !ok || n < 1 {
		return 0, false
	}
	var b [1]byte
	if _, e := rand.Read(b[:]); e != nil {
		return 0, false
	}
	return int(b[0])%n + 1, true
}

func saveScheduled(tx *sql.Tx, p Principal, cid string, s Send, digest string, sendAt int64, whenOnline bool) (Message, error) {
	var oldID, oldHash string
	e := tx.QueryRow("SELECT id,payload_hash FROM scheduled_messages WHERE sender=? AND client_id=?", p.UserID, s.ClientID).Scan(&oldID, &oldHash)
	if e == nil {
		if oldHash != digest {
			return Message{}, ErrConflict
		}
		return loadScheduled(tx, oldID)
	}
	if e != nil && e != sql.ErrNoRows {
		return Message{}, e
	}
	sid := id()
	extra := ""
	if len(s.Extra) > 0 {
		extra = string(s.Extra)
	}
	online := 0
	if whenOnline {
		online = 1
	}
	_, e = tx.Exec("INSERT INTO scheduled_messages(id,chat_id,sender,client_id,kind,text,media_id,reply_to,extra_json,ttl,send_at,when_online,payload_hash,created) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)", sid, cid, p.UserID, s.ClientID, s.Kind, s.Text, s.MediaID, s.ReplyTo, extra, s.TTL, sendAt, online, digest, now())
	if e != nil {
		return Message{}, e
	}
	return loadScheduled(tx, sid)
}

func loadScheduled(tx *sql.Tx, sid string) (Message, error) {
	var m Message
	var extra string
	var online int
	e := tx.QueryRow("SELECT id,chat_id,sender,client_id,kind,text,media_id,reply_to,extra_json,ttl,send_at,when_online,created FROM scheduled_messages WHERE id=?", sid).Scan(&m.ID, &m.ChatID, &m.Sender, &m.ClientID, &m.Kind, &m.Text, &m.MediaID, &m.ReplyTo, &extra, &m.TTL, &m.SendAt, &online, &m.Created)
	if e != nil {
		return Message{}, e
	}
	m.WhenOnline = online == 1
	m.Scheduled = true
	m.Entities = []Entity{}
	if extra != "" {
		m.Extra = json.RawMessage(extra)
	}
	return m, nil
}

func (a *App) releaseScheduled() {
	nowUnix := time.Now().Unix()
	rows, e := a.DB.Query("SELECT id,chat_id,sender,client_id,kind,text,media_id,reply_to,extra_json,ttl,send_at,when_online FROM scheduled_messages WHERE (when_online=0 AND send_at>0 AND send_at<=?) OR when_online=1 ORDER BY created LIMIT 32", nowUnix)
	if e != nil {
		return
	}
	type row struct {
		id, chat, sender, client, kind, text, media, reply, extra string
		ttl, online                                               int
		sendAt                                                    int64
	}
	list := []row{}
	for rows.Next() {
		var r row
		if rows.Scan(&r.id, &r.chat, &r.sender, &r.client, &r.kind, &r.text, &r.media, &r.reply, &r.extra, &r.ttl, &r.sendAt, &r.online) == nil {
			list = append(list, r)
		}
	}
	rows.Close()
	for _, r := range list {
		if r.online == 1 && !a.someoneElseOnline(r.chat, r.sender) {
			continue
		}
		s := Send{ClientID: r.client, Kind: r.kind, Text: r.text, MediaID: r.media, ReplyTo: r.reply, TTL: r.ttl}
		if r.extra != "" {
			s.Extra = json.RawMessage(r.extra)
		}
		_, err := a.SendMessage(Principal{UserID: r.sender}, r.chat, s)
		if err != nil && err != ErrConflict {
			continue
		}
		_, _ = a.DB.Exec("DELETE FROM scheduled_messages WHERE id=?", r.id)
	}
}

func (a *App) someoneElseOnline(cid, sender string) bool {
	rows, e := a.DB.Query("SELECT user_id FROM members WHERE chat_id=?", cid)
	if e != nil {
		return false
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	for _, id := range ids {
		if id != sender && a.online(id) {
			return true
		}
	}
	return false
}

func (a *App) expireMessages() {
	_ = a.transaction(func(tx *sql.Tx) error {
		rows, e := tx.Query("SELECT id FROM messages WHERE ttl>0 AND deleted=0 AND unixepoch(substr(created,1,19))+ttl<=unixepoch() LIMIT 32")
		if e != nil {
			return e
		}
		ids := []string{}
		for rows.Next() {
			var id string
			if rows.Scan(&id) == nil {
				ids = append(ids, id)
			}
		}
		e = rows.Err()
		rows.Close()
		if e != nil {
			return e
		}
		for _, id := range ids {
			if e = tombstone(tx, id); e != nil {
				return e
			}
		}
		return nil
	})
}

func burnViewOnce(tx *sql.Tx, cid, reader string, from, to int64) error {
	rows, e := tx.Query("SELECT id FROM messages WHERE chat_id=? AND sender!=? AND ttl=-1 AND deleted=0 AND seq>? AND seq<=?", cid, reader, from, to)
	if e != nil {
		return e
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	e = rows.Err()
	rows.Close()
	if e != nil {
		return e
	}
	for _, id := range ids {
		if e = tombstone(tx, id); e != nil {
			return e
		}
	}
	return nil
}

func tombstone(tx *sql.Tx, mid string) error {
	m, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=? AND deleted=0", mid))
	if e != nil {
		if errorsIsNoRows(e) {
			return nil
		}
		return e
	}
	m.Deleted = true
	m.Text = ""
	m.MediaID = ""
	m.Entities = []Entity{}
	m.LinkPreview = nil
	m.ReplyMarkup = nil
	m.Extra = nil
	m.TTL = 0
	if _, e = tx.Exec("DELETE FROM pins WHERE message_id=?", mid); e != nil {
		return e
	}
	if _, e = tx.Exec("UPDATE messages SET text='',media_id='',media_meta_json='',album_id='',entities_json='[]',preview_json='',reply_markup_json='',extra_json='',ttl=0,deleted=1 WHERE id=?", mid); e != nil {
		return e
	}
	users, e := members(tx, m.ChatID)
	if e != nil {
		return e
	}
	return emit(tx, users, "message.deleted", m.ChatID, m)
}

func errorsIsNoRows(e error) bool { return e == sql.ErrNoRows }

func (a *App) gcOrphanMedia() {
	rows, e := a.DB.Query(`SELECT id FROM media WHERE unixepoch(substr(created,1,19)) < unixepoch()-3600
		AND id NOT IN (
			SELECT media_id FROM messages WHERE media_id<>'' AND deleted=0
			UNION SELECT avatar FROM users WHERE avatar<>''
			UNION SELECT avatar FROM chats WHERE avatar<>''
			UNION SELECT thumbnail_id FROM media WHERE thumbnail_id<>''
			UNION SELECT media_id FROM stickers WHERE media_id<>''
			UNION SELECT media_id FROM stories WHERE media_id<>''
			UNION SELECT media_id FROM scheduled_messages WHERE media_id<>''
		) LIMIT 32`)
	if e != nil {
		return
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	for _, id := range ids {
		_ = a.storage.Delete(a.ctx, id)
		_, _ = a.DB.Exec("DELETE FROM media WHERE id=?", id)
	}
}

func (a *App) round2Routes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/conversations/{id}/transfer", a.auth(a.transferOwnership))
	mux.HandleFunc("POST /v1/conversations/{id}/upgrade", a.auth(a.upgradeGroup))
	mux.HandleFunc("POST /v1/conversations/{id}/delivered", a.auth(a.markDelivered))
	mux.HandleFunc("GET /v1/conversations/{id}/scheduled", a.auth(a.listScheduled))
	mux.HandleFunc("PUT /v1/conversations/{id}/history", a.auth(a.setHistoryForNew))
	mux.HandleFunc("PUT /v1/conversations/{id}/auto-delete", a.auth(a.setAutoDelete))
	mux.HandleFunc("GET /v1/conversations/{id}/messages/{seq}/viewers", a.auth(a.messageViewers))
	mux.HandleFunc("GET /v1/conversations/{id}/messages/{seq}/read-date", a.auth(a.messageReadDate))
	mux.HandleFunc("GET /v1/link-previews/{id}/image", a.auth(a.previewImage))
	mux.HandleFunc("GET /v1/custom-emoji", a.auth(a.customEmoji))
}

func (a *App) transferOwnership(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		UserID   string `json:"user_id"`
		Password string `json:"password"`
	}
	if !decode(w, r, &b) || b.UserID == "" || b.Password == "" || b.UserID == p.UserID {
		if w.Header().Get("Content-Type") == "" {
			fail(w, ErrInvalid)
		}
		return
	}
	cid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error {
		var pass string
		if e := tx.QueryRow("SELECT password FROM users WHERE id=?", p.UserID).Scan(&pass); e != nil {
			return e
		}
		if bcrypt.CompareHashAndPassword([]byte(pass), []byte(b.Password)) != nil {
			return ErrForbidden
		}
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || role != "owner" {
			return ErrForbidden
		}
		target, _, e := member(tx, cid, b.UserID)
		if e != nil || target == "" {
			return ErrForbidden
		}
		if _, e = tx.Exec("UPDATE members SET role='owner' WHERE chat_id=? AND user_id=?", cid, b.UserID); e != nil {
			return e
		}
		if _, e = tx.Exec("UPDATE members SET role='admin' WHERE chat_id=? AND user_id=?", cid, p.UserID); e != nil {
			return e
		}
		if e = audit(tx, cid, p.UserID, "ownership.transfer", b.UserID, nil); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "membership.changed", cid, map[string]any{"user_id": b.UserID, "action": "role", "role": "owner"}); e != nil {
			return e
		}
		return emit(tx, users, "membership.changed", cid, map[string]any{"user_id": p.UserID, "action": "role", "role": "admin"})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) upgradeGroup(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || role != "owner" {
			return ErrForbidden
		}
		var kind string
		var upgraded int
		if e = tx.QueryRow("SELECT kind,IFNULL(upgraded,0) FROM chats WHERE id=?", cid).Scan(&kind, &upgraded); e != nil {
			return e
		}
		if kind != "group" || upgraded == 1 {
			return ErrInvalid
		}
		var n int
		if e = tx.QueryRow("SELECT count(*) FROM members WHERE chat_id=?", cid).Scan(&n); e != nil {
			return e
		}
		if n < 2 {
			return ErrInvalid
		}
		if _, e = tx.Exec("UPDATE chats SET upgraded=1 WHERE id=?", cid); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "kind": kind, "upgraded": true})
	})
	if e != nil {
		fail(w, e)
		return
	}
	a.getConversation(w, r, p)
}

func (a *App) markDelivered(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Seq int64 `json:"seq"`
	}
	if !decode(w, r, &b) {
		return
	}
	cid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error {
		if _, _, e := member(tx, cid, p.UserID); e != nil {
			return e
		}
		var high, old int64
		if e := tx.QueryRow("SELECT c.last_seq,m.delivered_seq FROM chats c JOIN members m ON m.chat_id=c.id WHERE c.id=? AND m.user_id=?", cid, p.UserID).Scan(&high, &old); e != nil {
			return e
		}
		if b.Seq < 0 || b.Seq > high {
			return ErrInvalid
		}
		if b.Seq <= old {
			return nil
		}
		if _, e := tx.Exec("UPDATE members SET delivered_seq=?,delivered_at=unixepoch() WHERE chat_id=? AND user_id=?", b.Seq, cid, p.UserID); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "delivery.updated", cid, map[string]any{"user_id": p.UserID, "delivered_seq": b.Seq})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) listScheduled(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT id FROM scheduled_messages WHERE chat_id=? AND sender=? ORDER BY send_at,created", cid, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	out := []Message{}
	for _, id := range ids {
		var m Message
		e = a.transaction(func(tx *sql.Tx) error {
			var err error
			m, err = loadScheduled(tx, id)
			return err
		})
		if e == nil {
			out = append(out, m)
		}
	}
	respond(w, 200, map[string]any{"messages": out})
}

func (a *App) setHistoryForNew(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		HistoryForNew *bool `json:"history_for_new"`
	}
	if !decode(w, r, &b) || b.HistoryForNew == nil {
		if w.Header().Get("Content-Type") == "" {
			fail(w, ErrInvalid)
		}
		return
	}
	cid := r.PathValue("id")
	v := 0
	if *b.HistoryForNew {
		v = 1
	}
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || (role != "owner" && role != "admin") {
			return ErrForbidden
		}
		var kind string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil || (kind != "group" && kind != "channel") {
			return ErrForbidden
		}
		if _, e = tx.Exec("UPDATE chats SET history_for_new=? WHERE id=?", v, cid); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "history_for_new": v == 1})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"history_for_new": v == 1})
}

func (a *App) setAutoDelete(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Seconds int `json:"seconds"`
	}
	if !decode(w, r, &b) || b.Seconds < 0 || b.Seconds > 366*24*3600 {
		if w.Header().Get("Content-Type") == "" {
			fail(w, ErrInvalid)
		}
		return
	}
	cid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil || (role != "owner" && role != "admin") {
			return ErrForbidden
		}
		var kind string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
			return e
		}
		if kind != "group" && kind != "channel" {
			return ErrForbidden
		}
		if _, e = tx.Exec("UPDATE chats SET auto_delete=? WHERE id=?", b.Seconds, cid); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, "conversation.updated", cid, map[string]any{"id": cid, "auto_delete_seconds": b.Seconds})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"auto_delete_seconds": b.Seconds})
}

func (a *App) messageViewers(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var seq int64
	if _, e := parseSeq(r.PathValue("seq"), &seq); e != nil || seq <= 0 {
		fail(w, ErrInvalid)
		return
	}
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	var sender string
	if e := a.DB.QueryRow("SELECT sender FROM messages WHERE chat_id=? AND seq=? AND deleted=0", cid, seq).Scan(&sender); e != nil || sender != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT user_id,delivered_at,read_at,read_seq FROM members WHERE chat_id=? AND user_id!=? AND delivered_seq>=?", cid, p.UserID, seq)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var uid string
		var deliveredAt, readAt, readSeq int64
		if rows.Scan(&uid, &deliveredAt, &readAt, &readSeq) != nil {
			continue
		}
		view := deliveredAt
		if readSeq >= seq && readAt > view {
			view = readAt
		}
		out = append(out, map[string]any{"user_id": uid, "view_date": view})
	}
	respond(w, 200, map[string]any{"viewers": out})
}

func parseSeq(raw string, out *int64) (int64, error) {
	var n int64
	for _, c := range raw {
		if c < '0' || c > '9' {
			return 0, ErrInvalid
		}
		n = n*10 + int64(c-'0')
	}
	*out = n
	return n, nil
}

func (a *App) messageReadDate(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var seq int64
	if _, e := parseSeq(r.PathValue("seq"), &seq); e != nil || seq <= 0 {
		fail(w, ErrInvalid)
		return
	}
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	var sender string
	if e := a.DB.QueryRow("SELECT sender FROM messages WHERE chat_id=? AND seq=? AND deleted=0", cid, seq).Scan(&sender); e != nil || sender != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT m.user_id,m.read_seq,m.read_at,IFNULL(u.read_receipts_enabled,1) FROM members m JOIN users u ON u.id=m.user_id WHERE m.chat_id=? AND m.user_id!=?", cid, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	var readAt int64
	unread := true
	hidden := false
	for rows.Next() {
		var uid string
		var readSeq, at int64
		var receipts int
		if rows.Scan(&uid, &readSeq, &at, &receipts) != nil {
			continue
		}
		if readSeq < seq {
			continue
		}
		unread = false
		if receipts != 1 || !a.C.ReadReceiptsEnabled {
			hidden = true
			continue
		}
		if at > readAt {
			readAt = at
		}
	}
	if unread {
		respond(w, 200, map[string]any{"@type": "messageReadDateUnread"})
		return
	}
	if hidden && readAt == 0 {
		respond(w, 200, map[string]any{"@type": "messageReadDateUserPrivacyRestricted"})
		return
	}
	respond(w, 200, map[string]any{"@type": "messageReadDateRead", "read_date": readAt})
}

func (a *App) previewImage(w http.ResponseWriter, r *http.Request, p Principal) {
	var imageURL string
	if e := a.DB.QueryRow("SELECT image FROM link_previews WHERE id=?", r.PathValue("id")).Scan(&imageURL); e != nil || imageURL == "" {
		fail(w, ErrForbidden)
		return
	}
	if _, e := previewURL(imageURL); e != nil {
		fail(w, ErrForbidden)
		return
	}
	ctx := r.Context()
	client := previewClient()
	defer client.CloseIdleConnections()
	req, e := http.NewRequestWithContext(ctx, "GET", imageURL, nil)
	if e != nil {
		fail(w, ErrForbidden)
		return
	}
	req.Header.Set("User-Agent", "QuietChat-LinkPreview/1.0")
	req.Header.Set("Accept", "image/*")
	res, e := client.Do(req)
	if e != nil {
		fail(w, ErrForbidden)
		return
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		fail(w, ErrInvalid)
		return
	}
	ct := res.Header.Get("Content-Type")
	if !strings.HasPrefix(strings.ToLower(ct), "image/") {
		fail(w, ErrInvalid)
		return
	}
	body, e := io.ReadAll(io.LimitReader(res.Body, (1<<20)+1))
	if e != nil || len(body) == 0 || len(body) > 1<<20 {
		fail(w, ErrInvalid)
		return
	}
	w.Header().Set("Content-Type", ct)
	w.Header().Set("Cache-Control", "private, max-age=3600")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(200)
	_, _ = w.Write(body)
}

func (a *App) customEmoji(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT s.id,s.emoji,s.media_id,s.file_id,s.pack_id,IFNULL(s.format,'') FROM stickers s JOIN sticker_packs p ON p.id=s.pack_id WHERE p.is_emoji=1 AND (p.owner='' OR p.owner=?) ORDER BY s.pack_id,s.sort_order LIMIT 200", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, em, mid, fid, pack, format string
		if rows.Scan(&id, &em, &mid, &fid, &pack, &format) != nil {
			continue
		}
		out = append(out, map[string]any{"id": id, "emoji": em, "media_id": mid, "file_id": fid, "pack_id": pack, "format": format, "is_emoji": true})
	}
	respond(w, 200, map[string]any{"stickers": out})
}

func stickerFormatOf(mime, name string) string {
	switch strings.ToLower(mime) {
	case "image/png", "image/jpeg":
		return "png"
	case "image/webp":
		return "webp"
	case "video/webm":
		return "webm"
	case "application/gzip", "application/x-gzip", "application/x-tgsticker":
		if mime == "application/x-tgsticker" || strings.HasSuffix(strings.ToLower(name), ".tgs") {
			return "tgs"
		}
	}
	return ""
}

func mediaMatches(require, mime string) bool {
	if require == "" {
		return true
	}
	if require == "animation" {
		return mime == "image/gif" || strings.HasPrefix(mime, "video/")
	}
	return strings.HasPrefix(mime, require)
}
