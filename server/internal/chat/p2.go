package chat

import (
	"database/sql"
	"errors"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

var albumIDRE = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

func (a *App) p2Routes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/messages/{id}/forward", a.auth(a.forward))
}

func (a *App) hideBlockedPresence(viewer string, u *User) {
	if u == nil || u.ID == "" || u.ID == viewer {
		return
	}
	var n int
	a.DB.QueryRow("SELECT count(*) FROM user_blocks WHERE (owner=? AND target=?) OR (owner=? AND target=?)", viewer, u.ID, u.ID, viewer).Scan(&n)
	if n > 0 {
		u.Online = false
		u.LastSeen = ""
	}
}

func mediaSnapshot(tx *sql.Tx, mid string) (*MediaInfo, error) {
	var info MediaInfo
	e := tx.QueryRow("SELECT id,mime,bytes,width,height,duration_ms,waveform,file_name,thumbnail_id FROM media WHERE id=?", mid).Scan(&info.ID, &info.MIME, &info.Bytes, &info.Width, &info.Height, &info.DurationMs, &info.Waveform, &info.FileName, &info.ThumbnailID)
	if e != nil {
		return nil, e
	}
	return &info, nil
}

func attachReplySeqs(db *sql.DB, items []Message) {
	ids := make([]string, 0, len(items))
	for _, m := range items {
		if m.ReplyTo != "" && m.ReplyToSeq == 0 {
			ids = append(ids, m.ReplyTo)
		}
	}
	if len(ids) == 0 {
		return
	}
	args := make([]any, len(ids))
	ph := make([]string, len(ids))
	for i, id := range ids {
		args[i] = id
		ph[i] = "?"
	}
	rows, e := db.Query("SELECT id,seq FROM messages WHERE id IN("+strings.Join(ph, ",")+")", args...)
	if e != nil {
		return
	}
	defer rows.Close()
	seq := map[string]int64{}
	for rows.Next() {
		var id string
		var n int64
		if rows.Scan(&id, &n) == nil {
			seq[id] = n
		}
	}
	for i := range items {
		if n := seq[items[i].ReplyTo]; n != 0 {
			items[i].ReplyToSeq = n
		}
	}
}

func (a *App) patchConversation(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Title  *string `json:"title"`
		Avatar *string `json:"avatar_media_id"`
	}
	if !decode(w, r, &b) {
		return
	}
	if e := a.UpdateConversation(p, cid, b.Title, b.Avatar); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) UpdateConversation(p Principal, cid string, title, avatar *string) error {
	if title == nil && avatar == nil {
		return ErrInvalid
	}
	if title != nil && (strings.TrimSpace(*title) == "" || len(*title) > 200) {
		return ErrInvalid
	}
	if avatar != nil && *avatar != "" {
		var n int
		if e := a.DB.QueryRow("SELECT count(*) FROM media WHERE id=? AND owner=? AND mime IN ('image/png','image/jpeg','image/webp','image/gif')", *avatar, p.UserID).Scan(&n); e != nil || n != 1 {
			return ErrForbidden
		}
	}
	return a.transaction(func(tx *sql.Tx) error {
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
			return ErrForbidden
		}
		if title != nil {
			if _, e = tx.Exec("UPDATE chats SET title=? WHERE id=?", *title, cid); e != nil {
				return e
			}
		}
		if avatar != nil {
			if _, e = tx.Exec("UPDATE chats SET avatar=? WHERE id=?", *avatar, cid); e != nil {
				return e
			}
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		data := map[string]any{"id": cid, "kind": kind}
		if title != nil {
			data["title"] = *title
		}
		if avatar != nil {
			data["avatar_media_id"] = *avatar
		}
		if e = audit(tx, cid, p.UserID, "conversation.updated", cid, data); e != nil {
			return e
		}
		if e = emit(tx, users, "conversation.updated", cid, data); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, cid)
	})
}

func (a *App) forward(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		ConversationID string `json:"conversation_id"`
		ClientID       string `json:"client_msg_id"`
	}
	if !decode(w, r, &b) {
		return
	}
	m, e := a.ForwardMessage(p, r.PathValue("id"), b.ConversationID, b.ClientID)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, m)
}

func (a *App) ForwardMessage(p Principal, mid, dest, clientID string) (Message, error) {
	if dest == "" || len(clientID) < 1 || len(clientID) > 128 {
		return Message{}, ErrInvalid
	}
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		src, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil || src.Deleted {
			return ErrForbidden
		}
		_, joined, e := member(tx, src.ChatID, p.UserID)
		if e != nil || src.Seq <= joined {
			return ErrForbidden
		}
		if e = a.checkSend(tx, p, dest, Send{ClientID: clientID, Kind: src.Kind, Text: src.Text, MediaID: src.MediaID}); e != nil {
			return e
		}
		var oldHash string
		e = tx.QueryRow("SELECT payload_hash FROM messages WHERE sender=? AND client_id=?", p.UserID, clientID).Scan(&oldHash)
		digest := hash("forward:" + dest + ":" + mid + ":" + clientID)
		if e == nil {
			if oldHash != digest {
				return ErrConflict
			}
			out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE sender=? AND client_id=?", p.UserID, clientID))
			return e
		}
		if e != nil && !errors.Is(e, sql.ErrNoRows) {
			return e
		}
		origin := map[string]any{"message_id": src.ID, "conversation_id": src.ChatID, "conversation_seq": src.Seq, "sender_id": src.Sender, "created_at": src.Created, "kind": src.Kind}
		var srcKind, srcTitle, srcName string
		_ = tx.QueryRow("SELECT c.kind,c.title,u.name FROM chats c JOIN users u ON u.id=? WHERE c.id=?", src.Sender, src.ChatID).Scan(&srcKind, &srcTitle, &srcName)
		origin["sender_name"] = srcName
		if srcKind != "direct" {
			origin["chat_title"] = srcTitle
		}
		raw, _ := json.Marshal(origin)
		var seq int64
		if e = tx.QueryRow("UPDATE chats SET last_seq=last_seq+1,last_activity=? WHERE id=? RETURNING last_seq", time.Now().UnixMicro(), dest).Scan(&seq); e != nil {
			return e
		}
		out = Message{ID: id(), ChatID: dest, Seq: seq, Sender: p.UserID, ClientID: clientID, Kind: src.Kind, Text: src.Text, MediaID: src.MediaID, ReplyTo: "", Created: now(), Entities: src.Entities, Media: src.Media, ForwardOrigin: raw}
		if out.Entities == nil {
			out.Entities = []Entity{}
		}
		_, e = tx.Exec("INSERT INTO messages(id,chat_id,seq,sender,client_id,kind,text,media_id,reply_to,payload_hash,created,entities_json,preview_json,reply_markup_json,via_bot_id,forward_origin_json,media_meta_json,album_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", out.ID, dest, seq, p.UserID, clientID, out.Kind, out.Text, out.MediaID, "", digest, out.Created, jsonText(out.Entities, "[]"), "", "", "", string(raw), jsonText(out.Media, ""), "")
		if e != nil {
			return e
		}
		users, e := members(tx, dest)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message.created", dest, out); e != nil {
			return e
		}
		if e = a.emitDialogStates(tx, users, dest); e != nil {
			return e
		}
		for _, u := range users {
			if u != p.UserID {
				if _, e = tx.Exec("INSERT INTO push_jobs(id,user_id,chat_id,msg_id,next_at) VALUES(?,?,?,?,?)", id(), u, dest, out.ID, time.Now().Unix()); e != nil {
					return e
				}
			}
		}
		return nil
	})
	return out, e
}

// parseMediaHeaders reads optional descriptive metadata from an upload.
func parseMediaHeaders(r *http.Request) (MediaInfo, error) {
	var info MediaInfo
	intHeader := func(name string, max int) (int, error) {
		raw := strings.TrimSpace(r.Header.Get(name))
		if raw == "" {
			return 0, nil
		}
		n, e := strconv.Atoi(raw)
		if e != nil || n < 0 || n > max {
			return 0, ErrInvalid
		}
		return n, nil
	}
	var e error
	if info.Width, e = intHeader("X-Media-Width", 65535); e != nil {
		return info, e
	}
	if info.Height, e = intHeader("X-Media-Height", 65535); e != nil {
		return info, e
	}
	if info.DurationMs, e = intHeader("X-Media-Duration-Ms", 86_400_000); e != nil {
		return info, e
	}
	if wf := strings.TrimSpace(r.Header.Get("X-Media-Waveform")); wf != "" {
		raw, e := base64.StdEncoding.DecodeString(wf)
		if e != nil {
			raw, e = base64.RawStdEncoding.DecodeString(wf)
		}
		if e != nil || len(raw) == 0 || len(raw) > 256 {
			return info, ErrInvalid
		}
		info.Waveform = base64.StdEncoding.EncodeToString(raw)
	}
	if name := sanitizeFileName(r.Header.Get("X-Media-Filename")); name != "" {
		info.FileName = name
	}
	if thumb := strings.TrimSpace(r.Header.Get("X-Thumbnail-ID")); thumb != "" {
		if !keyRE.MatchString(thumb) {
			return info, ErrInvalid
		}
		info.ThumbnailID = thumb
	}
	return info, nil
}

func sanitizeFileName(raw string) string {
	name := path.Base(strings.ReplaceAll(strings.TrimSpace(raw), "\\", "/"))
	name = strings.TrimSpace(name)
	if name == "." || name == ".." {
		return ""
	}
	var b strings.Builder
	for _, r := range name {
		if r < 32 || r == 127 {
			continue
		}
		b.WriteRune(r)
	}
	name = b.String()
	if len(name) > 255 {
		name = string([]rune(name)[:255])
		for !utf8.ValidString(name) && len(name) > 0 {
			name = name[:len(name)-1]
		}
	}
	return name
}

func sniffMedia(head []byte, mime string) string {
	if mime == "application/ogg" {
		return "audio/ogg"
	}
	if len(head) >= 12 && string(head[4:8]) == "ftyp" && (mime == "application/octet-stream" || mime == "application/mp4") {
		return "video/mp4"
	}
	return mime
}
