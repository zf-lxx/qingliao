package chat

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"regexp"
	"strings"
	"time"
)

type Draft struct {
	Text     string   `json:"text"`
	Entities []Entity `json:"entities"`
	ReplyTo  string   `json:"reply_to,omitempty"`
}
type FolderFilter struct {
	Include    []string `json:"include_chat_ids"`
	Exclude    []string `json:"exclude_chat_ids"`
	Types      []string `json:"types"`
	UnreadOnly bool     `json:"unread_only"`
}

var mentionPattern = regexp.MustCompile(`(?:^|[^A-Za-z0-9_])@([A-Za-z0-9_]{3,32})\b`)

func (a *App) recordMentions(tx *sql.Tx, cid string, m Message) error {
	handles := mentionPattern.FindAllStringSubmatch(m.Text, -1)
	seen := map[string]bool{}
	for _, match := range handles {
		h := strings.ToLower(match[1])
		if seen[h] {
			continue
		}
		seen[h] = true
		_, e := tx.Exec("INSERT OR IGNORE INTO message_mentions(message_id,user_id) SELECT ?,u.id FROM users u JOIN members b ON b.user_id=u.id WHERE b.chat_id=? AND u.handle=? AND u.id<>?", m.ID, cid, h, m.Sender)
		if e != nil {
			return e
		}
	}
	return nil
}

const dialogStatsCTE = `WITH counts AS(SELECT b.chat_id,COALESCE(SUM(CASE WHEN m.seq>b.read_seq AND m.sender<>b.user_id AND m.deleted=0 THEN 1 ELSE 0 END),0) AS unread_count,COALESCE(SUM(CASE WHEN m.seq>b.read_seq AND m.sender<>b.user_id AND m.deleted=0 AND EXISTS(SELECT 1 FROM message_mentions mm WHERE mm.message_id=m.id AND mm.user_id=b.user_id) THEN 1 ELSE 0 END),0) AS mentions FROM members b LEFT JOIN messages m ON m.chat_id=b.chat_id AND m.seq>max(b.joined_seq,b.read_seq) WHERE b.user_id=? GROUP BY b.chat_id), badge AS(SELECT COALESCE(SUM(CASE WHEN b.notification_mute_until<=unixepoch() THEN max(x.unread_count,b.manual_unread) ELSE 0 END),0) AS total FROM members b JOIN counts x ON x.chat_id=b.chat_id WHERE b.user_id=?) `

func (a *App) emitDialogStates(tx *sql.Tx, users []string, cid string) error {
	for _, u := range users {
		var read, unread, mentions, total, mute, arch, pin, manual int64
		var draft string
		e := tx.QueryRow(dialogStatsCTE+`SELECT b.read_seq,x.unread_count,x.mentions,z.total,b.notification_mute_until,b.archived,b.pin_order,b.manual_unread,b.draft_json FROM members b JOIN counts x ON x.chat_id=b.chat_id CROSS JOIN badge z WHERE b.user_id=? AND b.chat_id=?`, u, u, u, cid).Scan(&read, &unread, &mentions, &total, &mute, &arch, &pin, &manual, &draft)
		if e == sql.ErrNoRows {
			if err := tx.QueryRow(dialogStatsCTE+"SELECT total FROM badge", u, u).Scan(&total); err != nil {
				return err
			}
			if e = emit(tx, []string{u}, "dialog.removed", cid, map[string]any{"id": cid, "total_unread_badge": total}); e != nil {
				return e
			}
			continue
		}
		if e != nil {
			return e
		}
		folderCounts, e := a.folderCounts(tx, u)
		if e != nil {
			return e
		}
		data := map[string]any{"folder_unread_counts": folderCounts, "id": cid, "last_read_seq": read, "unread_count": unread, "unread_mention_count": mentions, "total_unread_badge": total, "notification_mute_until": mute, "archived": arch == 1, "pinned_order": pin, "manual_unread": manual == 1}
		if draft != "" {
			data["draft"] = json.RawMessage(draft)
		} else {
			data["draft"] = nil
		}
		// Refresh this chat's last preview/read aggregation, without leaking another user's draft.
		var mid, kind, text, sender, edited string
		var seq, deleted, readers, recipients int64
		e = tx.QueryRow(`SELECT m.id,m.kind,substr(m.text,1,180),m.sender,m.edited,m.seq,m.deleted,(SELECT count(*) FROM members r JOIN users ru ON ru.id=r.user_id WHERE r.chat_id=m.chat_id AND r.user_id<>m.sender AND r.read_seq>=m.seq AND ru.read_receipts_enabled=1),(SELECT count(*) FROM members r WHERE r.chat_id=m.chat_id AND r.user_id<>m.sender) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE b.user_id=? AND m.chat_id=? AND m.seq>b.joined_seq ORDER BY m.seq DESC LIMIT 1`, u, cid).Scan(&mid, &kind, &text, &sender, &edited, &seq, &deleted, &readers, &recipients)
		if e != nil && e != sql.ErrNoRows {
			return e
		}
		if e == nil {
			var activity int64
			if err := tx.QueryRow("SELECT last_activity FROM chats WHERE id=?", cid).Scan(&activity); err != nil {
				return err
			}
			data["last_activity"] = activity
			data["last_message"] = map[string]any{"id": mid, "kind": kind, "text": text, "sender_id": sender, "conversation_seq": seq, "deleted": deleted == 1, "edited_at": edited}
			var ownPrivacy int
			if err := tx.QueryRow("SELECT read_receipts_enabled FROM users WHERE id=?", u).Scan(&ownPrivacy); err != nil {
				return err
			}
			data["read_receipts_visible"] = a.C.ReadReceiptsEnabled && ownPrivacy == 1
			if a.C.ReadReceiptsEnabled && ownPrivacy == 1 {
				data["last_message_read_count"] = readers
			} else {
				data["last_message_read_count"] = nil
			}
			data["last_message_recipient_count"] = recipients
		}
		if e = emit(tx, []string{u}, "dialog.updated", cid, data); e != nil {
			return e
		}
	}
	return nil
}
func (a *App) dialogState(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		Archived   *bool   `json:"archived"`
		PinOrder   *int    `json:"pinned_order"`
		Mute       *string `json:"mute_until"`
		Unread     *bool   `json:"mark_unread"`
		Draft      *Draft  `json:"draft"`
		ClearDraft bool    `json:"clear_draft"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.PinOrder != nil && (*b.PinOrder < 0 || *b.PinOrder > 1000) {
		fail(w, ErrInvalid)
		return
	}
	mute := int64(0)
	if b.Mute != nil && *b.Mute != "" {
		if *b.Mute == "forever" {
			mute = 253402300799
		} else {
			t, e := time.Parse(time.RFC3339, *b.Mute)
			if e != nil || t.Before(time.Now()) {
				fail(w, ErrInvalid)
				return
			}
			mute = t.Unix()
		}
	}
	if b.Draft != nil {
		if len(b.Draft.Text) > 16384 {
			fail(w, ErrInvalid)
			return
		}
		var e error
		b.Draft.Entities, e = validateEntities(b.Draft.Text, b.Draft.Entities)
		if e != nil {
			fail(w, e)
			return
		}
	}
	e := a.transaction(func(tx *sql.Tx) error {
		_, joined, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		if b.Archived != nil {
			if _, e = tx.Exec("UPDATE members SET archived=? WHERE chat_id=? AND user_id=?", *b.Archived, cid, p.UserID); e != nil {
				return e
			}
		}
		if b.PinOrder != nil {
			if _, e = tx.Exec("UPDATE members SET pin_order=? WHERE chat_id=? AND user_id=?", *b.PinOrder, cid, p.UserID); e != nil {
				return e
			}
		}
		if b.Mute != nil {
			if _, e = tx.Exec("UPDATE members SET notification_mute_until=? WHERE chat_id=? AND user_id=?", mute, cid, p.UserID); e != nil {
				return e
			}
		}
		if b.Draft != nil {
			if b.Draft.ReplyTo != "" {
				var n int
				if e = tx.QueryRow("SELECT count(*) FROM messages WHERE id=? AND chat_id=? AND seq>? AND deleted=0", b.Draft.ReplyTo, cid, joined).Scan(&n); e != nil || n != 1 {
					return ErrInvalid
				}
			}
			if _, e = tx.Exec("UPDATE members SET draft_json=? WHERE chat_id=? AND user_id=?", jsonText(b.Draft, ""), cid, p.UserID); e != nil {
				return e
			}
		}
		if b.ClearDraft {
			if _, e = tx.Exec("UPDATE members SET draft_json='' WHERE chat_id=? AND user_id=?", cid, p.UserID); e != nil {
				return e
			}
		}
		if b.Unread != nil {
			if *b.Unread {
				_, e = tx.Exec("UPDATE members SET manual_unread=1 WHERE chat_id=? AND user_id=?", cid, p.UserID)
			} else {
				_, e = tx.Exec("UPDATE members SET manual_unread=0,read_seq=(SELECT last_seq FROM chats WHERE id=?) WHERE chat_id=? AND user_id=?", cid, cid, p.UserID)
				if e == nil {
					var seq int64
					tx.QueryRow("SELECT last_seq FROM chats WHERE id=?", cid).Scan(&seq)
					users, err := a.readRecipients(tx, p.UserID, cid)
					if err != nil {
						return err
					}
					if e = emit(tx, users, "read.updated", cid, map[string]any{"user_id": p.UserID, "last_read_seq": seq}); e != nil {
						return e
					}
				}
			}
			if e != nil {
				return e
			}
		}
		users := []string{p.UserID}
		if b.Unread != nil && !*b.Unread {
			var err error
			users, err = a.readRecipients(tx, p.UserID, cid)
			if err != nil {
				return err
			}
		}
		return a.emitDialogStates(tx, users, cid)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

// SQL predicates use bound JSON, not interpolated IDs. Inclusion overrides type;
// exclusions always win; unread-only applies last. All owned folders are private.
const folderPredicate = `(NOT EXISTS(SELECT 1 FROM json_each(json_extract(f.filter_json,'$.exclude_chat_ids')) WHERE value=c.id)) AND ((json_array_length(json_extract(f.filter_json,'$.include_chat_ids'))=0 AND json_array_length(json_extract(f.filter_json,'$.types'))=0) OR EXISTS(SELECT 1 FROM json_each(json_extract(f.filter_json,'$.include_chat_ids')) WHERE value=c.id) OR EXISTS(SELECT 1 FROM json_each(json_extract(f.filter_json,'$.types')) WHERE value=c.kind)) AND (COALESCE(json_extract(f.filter_json,'$.unread_only'),0)=0 OR max(x.unread_count,b.manual_unread)>0)`

func (a *App) folderCounts(tx *sql.Tx, user string) (map[string]int64, error) {
	rows, e := tx.Query(dialogStatsCTE+`SELECT f.id,COALESCE((SELECT SUM(CASE WHEN b.notification_mute_until<=unixepoch() THEN max(x.unread_count,b.manual_unread) ELSE 0 END) FROM members b JOIN chats c ON c.id=b.chat_id JOIN counts x ON x.chat_id=c.id WHERE b.user_id=f.user_id AND `+folderPredicate+`),0) FROM folders f WHERE f.user_id=?`, user, user, user)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := map[string]int64{}
	for rows.Next() {
		var id string
		var n int64
		if e = rows.Scan(&id, &n); e != nil {
			return nil, e
		}
		out[id] = n
	}
	return out, rows.Err()
}
func validateFilter(f *FolderFilter) error {
	if len(f.Include) > 200 || len(f.Exclude) > 200 || len(f.Types) > 2 {
		return ErrInvalid
	}
	if f.Include == nil {
		f.Include = []string{}
	}
	if f.Exclude == nil {
		f.Exclude = []string{}
	}
	if f.Types == nil {
		f.Types = []string{}
	}
	for _, t := range f.Types {
		if t != "direct" && t != "group" {
			return ErrInvalid
		}
	}
	for _, list := range [][]string{f.Include, f.Exclude} {
		for _, id := range list {
			if !keyRE.MatchString(id) {
				return ErrInvalid
			}
		}
	}
	return nil
}
func (a *App) folders(w http.ResponseWriter, r *http.Request, p Principal) {
	if r.Method == "GET" {
		rows, e := a.DB.Query(dialogStatsCTE+`SELECT f.id,f.name,f.filter_json,f.sort_order,COALESCE((SELECT SUM(CASE WHEN b.notification_mute_until<=unixepoch() THEN max(x.unread_count,b.manual_unread) ELSE 0 END) FROM members b JOIN chats c ON c.id=b.chat_id JOIN counts x ON x.chat_id=c.id WHERE b.user_id=f.user_id AND `+folderPredicate+`),0) FROM folders f WHERE f.user_id=? ORDER BY sort_order,id`, p.UserID, p.UserID, p.UserID)
		if e != nil {
			fail(w, e)
			return
		}
		defer rows.Close()
		out := []map[string]any{}
		for rows.Next() {
			var id, name, filter string
			var order, unread int64
			if e = rows.Scan(&id, &name, &filter, &order, &unread); e != nil {
				fail(w, e)
				return
			}
			out = append(out, map[string]any{"id": id, "name": name, "filter": json.RawMessage(filter), "sort_order": order, "unread_count": unread})
		}
		respond(w, 200, map[string]any{"folders": out})
		return
	}
	var b struct {
		Name   string       `json:"name"`
		Filter FolderFilter `json:"filter"`
		Order  int          `json:"sort_order"`
	}
	if !decode(w, r, &b) {
		return
	}
	if len(b.Name) < 1 || len(b.Name) > 100 || validateFilter(&b.Filter) != nil {
		fail(w, ErrInvalid)
		return
	}
	fid := r.PathValue("id")
	if fid == "" {
		fid = id()
	}
	e := a.transaction(func(tx *sql.Tx) error {
		var count int
		if e := tx.QueryRow("SELECT count(*) FROM folders WHERE user_id=?", p.UserID).Scan(&count); e != nil {
			return e
		}
		if count >= 20 && r.Method == "POST" {
			return ErrInvalid
		}
		if r.Method == "PATCH" {
			var owned int
			tx.QueryRow("SELECT count(*) FROM folders WHERE id=? AND user_id=?", fid, p.UserID).Scan(&owned)
			if owned != 1 {
				return ErrForbidden
			}
		}
		_, e := tx.Exec("INSERT INTO folders(id,user_id,name,filter_json,sort_order) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,filter_json=excluded.filter_json,sort_order=excluded.sort_order", fid, p.UserID, b.Name, jsonText(b.Filter, "{}"), b.Order)
		if e != nil {
			return e
		}
		counts, e := a.folderCounts(tx, p.UserID)
		if e != nil {
			return e
		}
		return emit(tx, []string{p.UserID}, "folder.updated", "", map[string]any{"unread_count": counts[fid], "id": fid, "name": b.Name, "filter": b.Filter, "sort_order": b.Order})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]string{"id": fid})
}
func (a *App) deleteFolder(w http.ResponseWriter, r *http.Request, p Principal) {
	fid := r.PathValue("id")
	e := a.transaction(func(tx *sql.Tx) error {
		res, e := tx.Exec("DELETE FROM folders WHERE id=? AND user_id=?", fid, p.UserID)
		if e != nil {
			return e
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			return ErrForbidden
		}
		return emit(tx, []string{p.UserID}, "folder.deleted", "", map[string]string{"id": fid})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

type dialogCursor struct {
	Class    int    `json:"c"`
	Order    int64  `json:"o"`
	Activity int64  `json:"a"`
	ID       string `json:"i"`
}

func (a *App) dialogs(w http.ResponseWriter, r *http.Request, p Principal) {
	limit := num(r, "limit")
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	cur := dialogCursor{Class: -1}
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		b, e := base64.RawURLEncoding.DecodeString(raw)
		if e != nil || json.Unmarshal(b, &cur) != nil || !keyRE.MatchString(cur.ID) {
			fail(w, ErrInvalid)
			return
		}
	}
	arch := 0
	if r.URL.Query().Get("archived") == "true" {
		arch = 1
	} else if r.URL.Query().Get("archived") == "all" {
		arch = -1
	}
	folder := r.URL.Query().Get("folder_id")
	// One SELECT: indexed message ranges + last-message lookup + badge + keyset pagination.
	query := dialogStatsCTE + `SELECT c.id,c.kind,c.title,c.last_seq,c.last_activity,b.read_seq,b.role,(SELECT read_receipts_enabled FROM users WHERE id=b.user_id),b.archived,b.pin_order,b.notification_mute_until,b.manual_unread,b.draft_json,x.unread_count,x.mentions,z.total,COALESCE(m.id,''),COALESCE(m.seq,0),COALESCE(m.sender,''),COALESCE(m.kind,''),COALESCE(substr(m.text,1,180),''),COALESCE(m.deleted,0),COALESCE(m.edited,''),(SELECT count(*) FROM members r JOIN users ru ON ru.id=r.user_id WHERE r.chat_id=c.id AND r.user_id<>m.sender AND r.read_seq>=m.seq AND ru.read_receipts_enabled=1),(SELECT count(*) FROM members r WHERE r.chat_id=c.id AND r.user_id<>m.sender) FROM members b JOIN chats c ON c.id=b.chat_id JOIN counts x ON x.chat_id=c.id CROSS JOIN badge z LEFT JOIN messages m ON m.id=(SELECT mm.id FROM messages mm WHERE mm.chat_id=c.id AND mm.seq>b.joined_seq ORDER BY mm.seq DESC LIMIT 1) LEFT JOIN folders f ON f.id=? AND f.user_id=b.user_id WHERE b.user_id=? AND (?=-1 OR b.archived=?) AND (?='' OR (f.id IS NOT NULL AND ` + folderPredicate + `)) AND ((CASE WHEN b.pin_order>0 THEN 0 ELSE 1 END,CASE WHEN b.pin_order>0 THEN b.pin_order ELSE 0 END,-c.last_activity,c.id)>(?,?,?,?)) ORDER BY CASE WHEN b.pin_order>0 THEN 0 ELSE 1 END,CASE WHEN b.pin_order>0 THEN b.pin_order ELSE 0 END,-c.last_activity,c.id LIMIT ?`
	query = dialogStatsCTE + ",paged AS (" + strings.TrimPrefix(query, dialogStatsCTE) + ") SELECT * FROM paged UNION ALL SELECT '','','',0,0,0,'',0,0,0,0,0,'',0,0,z.total,'',0,'','','',0,'',0,0 FROM badge z"
	rows, e := a.DB.Query(query, p.UserID, p.UserID, folder, p.UserID, arch, arch, folder, cur.Class, cur.Order, cur.Activity, cur.ID, limit+1)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	var last dialogCursor
	var total int64
	hasMore := false
	for rows.Next() {

		var cid, kind, title, role, draft, mid, sender, mkind, text, edited string
		var ownPrivacy int64
		var seq, activity, read, archived, pin, mute, manual, unread, mentions, mseq, deleted, readers, recipients int64
		if e = rows.Scan(&cid, &kind, &title, &seq, &activity, &read, &role, &ownPrivacy, &archived, &pin, &mute, &manual, &draft, &unread, &mentions, &total, &mid, &mseq, &sender, &mkind, &text, &deleted, &edited, &readers, &recipients); e != nil {
			fail(w, e)
			return
		}
		if cid == "" {
			continue
		}
		if len(out) == limit {
			hasMore = true
			continue
		}
		d := map[string]any{"id": cid, "kind": kind, "title": title, "last_seq": seq, "last_activity": activity, "last_read_seq": read, "role": role, "archived": archived == 1, "pinned_order": pin, "notification_mute_until": mute, "manual_unread": manual == 1, "unread_count": unread, "unread_mention_count": mentions, "last_message_read_count": readers, "last_message_recipient_count": recipients, "draft": nil, "last_message": nil}
		d["read_receipts_visible"] = a.C.ReadReceiptsEnabled && ownPrivacy == 1
		if !a.C.ReadReceiptsEnabled || ownPrivacy != 1 {
			d["last_message_read_count"] = nil
		}
		if draft != "" {
			d["draft"] = json.RawMessage(draft)
		}
		if mid != "" {
			d["last_message"] = map[string]any{"id": mid, "conversation_seq": mseq, "sender_id": sender, "kind": mkind, "text": text, "deleted": deleted == 1, "edited_at": edited}
		}
		out = append(out, d)
		class := 1
		order := int64(0)
		if pin > 0 {
			class = 0
			order = pin
		}
		last = dialogCursor{class, order, -activity, cid}
	}
	cursor := ""
	if hasMore {
		b, _ := json.Marshal(last)
		cursor = base64.RawURLEncoding.EncodeToString(b)
	}
	respond(w, 200, map[string]any{"conversations": out, "total_unread_badge": total, "next_cursor": cursor, "has_more": hasMore})
}

// One bounded indexed scan/sec; finite notification mutes expire into durable
// private state events, so an idle second device's badge does not stay stale.
func (a *App) expireNotificationMutes() {
	type item struct{ chat, user string }
	rows, e := a.DB.Query("SELECT chat_id,user_id FROM members WHERE notification_mute_until>0 AND notification_mute_until<=unixepoch() LIMIT 32")
	if e != nil {
		return
	}
	items := []item{}
	for rows.Next() {
		var i item
		if rows.Scan(&i.chat, &i.user) == nil {
			items = append(items, i)
		}
	}
	rows.Close()
	if len(items) == 0 {
		return
	}
	_ = a.transaction(func(tx *sql.Tx) error {
		for _, i := range items {
			res, e := tx.Exec("UPDATE members SET notification_mute_until=0 WHERE chat_id=? AND user_id=? AND notification_mute_until>0 AND notification_mute_until<=unixepoch()", i.chat, i.user)
			if e != nil {
				return e
			}
			n, _ := res.RowsAffected()
			if n > 0 {
				if e = a.emitDialogStates(tx, []string{i.user}, i.chat); e != nil {
					return e
				}
			}
		}
		return nil
	})
}
