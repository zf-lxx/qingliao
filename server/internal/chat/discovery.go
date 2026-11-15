package chat

import (
	"database/sql"
	"database/sql/driver"
	"fmt"
	"modernc.org/sqlite"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// FTS5 unicode61 cannot segment unspaced Chinese. Index each Han rune as an
// ASCII token, retaining Latin words; phrase MATCH gives contiguous Chinese
// substring search (including 1/2-character queries), without a dictionary.
func searchTokens(s string) string {
	var out []string
	var word strings.Builder
	flush := func() {
		if word.Len() > 0 {
			out = append(out, "word"+word.String())
			word.Reset()
		}
	}
	for _, r := range strings.ToLower(s) {
		if unicode.Is(unicode.Han, r) {
			flush()
			out = append(out, fmt.Sprintf("han%x", r))
		} else if unicode.IsLetter(r) || unicode.IsDigit(r) {
			word.WriteRune(r)
		} else {
			flush()
		}
	}
	flush()
	return strings.Join(out, " ")
}
func init() {
	sqlite.MustRegisterDeterministicScalarFunction("qing_tokens", 1, func(_ *sqlite.FunctionContext, v []driver.Value) (driver.Value, error) {
		s, _ := v[0].(string)
		return searchTokens(s), nil
	})
}

const discoverySchema = `
CREATE TABLE IF NOT EXISTS user_blocks(owner TEXT NOT NULL REFERENCES users(id),target TEXT NOT NULL REFERENCES users(id),created TEXT NOT NULL,PRIMARY KEY(owner,target),CHECK(owner<>target));
CREATE TABLE IF NOT EXISTS reports(id TEXT PRIMARY KEY,reporter TEXT NOT NULL REFERENCES users(id),chat_id TEXT NOT NULL REFERENCES chats(id),message_id TEXT NOT NULL,reason TEXT NOT NULL,created TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS reports_time ON reports(created,id);
CREATE VIRTUAL TABLE IF NOT EXISTS message_fts USING fts5(message_id UNINDEXED,tokens,tokenize='unicode61');
CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages WHEN new.deleted=0 BEGIN INSERT INTO message_fts(rowid,message_id,tokens) VALUES(new.rowid,new.id,qing_tokens(new.text)); END;
CREATE TRIGGER IF NOT EXISTS messages_fts_update AFTER UPDATE OF text,deleted ON messages BEGIN DELETE FROM message_fts WHERE rowid=old.rowid; INSERT INTO message_fts(rowid,message_id,tokens) SELECT new.rowid,new.id,qing_tokens(new.text) WHERE new.deleted=0; END;
CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN DELETE FROM message_fts WHERE rowid=old.rowid; END;
INSERT INTO message_fts(rowid,message_id,tokens) SELECT rowid,id,qing_tokens(text) FROM messages WHERE deleted=0 AND rowid NOT IN(SELECT rowid FROM message_fts);
CREATE INDEX IF NOT EXISTS messages_media_timeline ON messages(chat_id,kind,seq DESC) WHERE deleted=0;
PRAGMA user_version=4;
`

func (a *App) checkBlocked(tx *sql.Tx, cid string) error {
	var n int
	e := tx.QueryRow(`SELECT count(*) FROM user_blocks x JOIN members a ON a.user_id=x.owner JOIN members b ON b.user_id=x.target AND a.chat_id=b.chat_id JOIN chats c ON c.id=a.chat_id WHERE c.id=? AND c.kind='direct'`, cid).Scan(&n)
	if e != nil {
		return e
	}
	if n > 0 {
		return ErrForbidden
	}
	return nil
}
func (a *App) Block(p Principal, target string, blocked bool) error {
	if target == p.UserID || target == "" {
		return ErrInvalid
	}
	return a.transaction(func(tx *sql.Tx) error {
		var n int
		if e := tx.QueryRow("SELECT count(*) FROM users WHERE id=?", target).Scan(&n); e != nil {
			return e
		}
		if n != 1 {
			return ErrForbidden
		}
		var e error
		if blocked {
			_, e = tx.Exec("INSERT INTO user_blocks(owner,target,created) VALUES(?,?,?) ON CONFLICT(owner,target) DO NOTHING", p.UserID, target, now())
		} else {
			_, e = tx.Exec("DELETE FROM user_blocks WHERE owner=? AND target=?", p.UserID, target)
		}
		if e != nil {
			return e
		}
		return emit(tx, []string{p.UserID}, "block.updated", "", map[string]any{"user_id": target, "blocked": blocked})
	})
}
func (a *App) ClearHistory(p Principal, cid string, both bool) error {
	return a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var kind string
		var high int64
		if e = tx.QueryRow("SELECT kind,last_seq FROM chats WHERE id=?", cid).Scan(&kind, &high); e != nil {
			return e
		}
		if both && kind != "direct" && role != "owner" && role != "admin" {
			return ErrForbidden
		}
		users := []string{p.UserID}
		if both {
			users, e = members(tx, cid)
			if e != nil {
				return e
			}
			if _, e = tx.Exec("UPDATE messages SET deleted=1,text='',media_id='',media_meta_json='',entities_json='[]',preview_json='',reply_markup_json='' WHERE chat_id=? AND seq<=?", cid, high); e != nil {
				return e
			}
			if _, e = tx.Exec("DELETE FROM pins WHERE chat_id=?", cid); e != nil {
				return e
			}
		}
		for _, u := range users {
			if _, e = tx.Exec("UPDATE members SET joined_seq=max(joined_seq,?),read_seq=max(read_seq,?),manual_unread=0,draft_json='' WHERE chat_id=? AND user_id=?", high, high, cid, u); e != nil {
				return e
			}
		}
		if _, e = tx.Exec("UPDATE push_jobs SET done=1 WHERE chat_id=? AND user_id IN(SELECT user_id FROM members WHERE chat_id=? AND joined_seq>=?)", cid, cid, high); e != nil {
			return e
		}
		if e = emit(tx, users, "conversation.cleared", cid, map[string]any{"through_seq": high, "both": both}); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, cid)
	})
}
func (a *App) Search(p Principal, cid, q string, before int64, limit int) ([]Message, error) {
	tokens := searchTokens(q)
	if len(q) > 512 || !utf8.ValidString(q) || tokens == "" {
		return nil, ErrInvalid
	}
	if !a.isMember(cid, p.UserID) {
		return nil, ErrForbidden
	}
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	if before <= 0 {
		before = 1 << 62
	}
	rows, e := a.DB.Query("SELECT "+prefixColumns("m", msgColumns)+` FROM message_fts f JOIN messages m ON m.rowid=f.rowid JOIN members b ON b.chat_id=m.chat_id WHERE message_fts MATCH ? AND m.chat_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0 AND m.seq<? ORDER BY m.seq DESC LIMIT ?`, `"`+tokens+`"`, cid, p.UserID, before, limit)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	items, e := scanMessages(rows)
	if e != nil {
		return nil, e
	}
	attachReplySeqs(a.DB, items)
	a.attachPolls(items, p.UserID)
	a.attachChecklists(items)
	return items, nil
}
func scanMessages(rows *sql.Rows) ([]Message, error) {
	out := []Message{}
	for rows.Next() {
		m, e := scanMessage(rows)
		if e != nil {
			return nil, e
		}
		out = append(out, m)
	}
	return out, rows.Err()
}
func (a *App) SharedMedia(p Principal, cid, kind string, before int64, date string, limit int) (map[string]any, error) {
	if !a.isMember(cid, p.UserID) {
		return nil, ErrForbidden
	}
	if limit <= 0 || limit > 100 {
		limit = 60
	}
	if before <= 0 {
		before = 1 << 62
	}
	filter := ""
	switch kind {
	case "", "all":
		filter = " AND (m.media_id<>'' OR m.preview_json<>'')"
	case "image", "video", "file", "voice", "animation", "video_note", "poll":
		filter = " AND m.kind='" + kind + "'"
	case "link":
		filter = " AND m.preview_json<>''"
	case "audio":
		filter, _ = globalMediaFilter("audio")
	default:
		return nil, ErrInvalid
	}
	base := ` FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.chat_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0`
	// Stats are over the complete visible history, not the paginated page.
	counts := map[string]int64{"image": 0, "video": 0, "file": 0, "voice": 0, "link": 0, "audio": 0}
	rows, e := a.DB.Query("SELECT m.kind,count(*)"+base+" AND m.media_id<>'' GROUP BY m.kind", cid, p.UserID)
	if e != nil {
		return nil, e
	}
	for rows.Next() {
		var k string
		var n int64
		if e = rows.Scan(&k, &n); e != nil {
			rows.Close()
			return nil, e
		}
		counts[k] = n
	}
	if e = rows.Err(); e != nil {
		rows.Close()
		return nil, e
	}
	rows.Close()
	if e = a.DB.QueryRow("SELECT count(*)"+base+" AND m.preview_json<>''", cid, p.UserID).Scan(newCount(counts, "link")); e != nil {
		return nil, e
	}
	if e = a.DB.QueryRow("SELECT count(*)"+base+" AND m.kind='file' AND EXISTS (SELECT 1 FROM media md WHERE md.id=m.media_id AND (md.mime LIKE 'audio/%' OR lower(md.file_name) LIKE '%.mp3' OR lower(md.file_name) LIKE '%.m4a' OR lower(md.file_name) LIKE '%.flac' OR lower(md.file_name) LIKE '%.ogg' OR lower(md.file_name) LIKE '%.wav' OR lower(md.file_name) LIKE '%.aac'))", cid, p.UserID).Scan(newCount(counts, "audio")); e != nil {
		return nil, e
	}
	buckets := []map[string]any{}
	rows, e = a.DB.Query("SELECT strftime('%Y-%m',m.created,'+8 hours'),count(*),max(m.seq),min(m.seq)"+base+filter+" GROUP BY 1 ORDER BY 1 DESC", cid, p.UserID)
	if e != nil {
		return nil, e
	}
	for rows.Next() {
		var month string
		var n, hi, lo int64
		if e = rows.Scan(&month, &n, &hi, &lo); e != nil {
			rows.Close()
			return nil, e
		}
		buckets = append(buckets, map[string]any{"month": month, "count": n, "first_seq": hi, "last_seq": lo})
	}
	if e = rows.Err(); e != nil {
		rows.Close()
		return nil, e
	}
	rows.Close()
	where := base + filter + " AND m.seq<?"
	args := []any{cid, p.UserID, before}
	if date != "" {
		if !validDate(date) {
			return nil, ErrInvalid
		}
		where += " AND julianday(m.created)<=julianday(?)"
		args = append(args, date)
	}
	args = append(args, limit+1)
	rows, e = a.DB.Query("SELECT "+prefixColumns("m", msgColumns)+where+" ORDER BY m.seq DESC LIMIT ?", args...)
	if e != nil {
		return nil, e
	}
	items, e := scanMessages(rows)
	rows.Close()
	if e != nil {
		return nil, e
	}
	attachReplySeqs(a.DB, items)
	a.attachPolls(items, p.UserID)
	a.attachChecklists(items)
	more := len(items) > limit
	if more {
		items = items[:limit]
	}
	var next int64
	if len(items) > 0 {
		next = items[len(items)-1].Seq
	}
	return map[string]any{"messages": items, "counts": counts, "months": buckets, "timezone": "Asia/Shanghai", "next_before": next, "has_more": more}, nil
}

// database/sql Scan needs an address; assign through a scanner to a map.
type countScanner struct {
	m map[string]int64
	k string
}

func (s countScanner) Scan(v any) error {
	switch n := v.(type) {
	case int64:
		s.m[s.k] = n
	case int:
		s.m[s.k] = int64(n)
	case int32:
		s.m[s.k] = int64(n)
	default:
		return ErrInvalid
	}
	return nil
}
func newCount(m map[string]int64, k string) countScanner { return countScanner{m, k} }
func validDate(s string) bool {
	if _, e := time.Parse(time.RFC3339, s); e == nil {
		return true
	}
	_, e := time.Parse("2006-01-02", s)
	return e == nil
}
func (a *App) discoveryRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/conversations/{id}/search", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		before, _ := strconv.ParseInt(r.URL.Query().Get("before"), 10, 64)
		items, e := a.Search(p, r.PathValue("id"), r.URL.Query().Get("q"), before, num(r, "limit"))
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]any{"messages": items})
	}))
	mux.HandleFunc("GET /v1/conversations/{id}/media", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		before, _ := strconv.ParseInt(r.URL.Query().Get("before"), 10, 64)
		v, e := a.SharedMedia(p, r.PathValue("id"), r.URL.Query().Get("kind"), before, r.URL.Query().Get("before_date"), num(r, "limit"))
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, v)
	}))
	mux.HandleFunc("GET /v1/me/media", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		v, e := a.GlobalMedia(p, r.URL.Query().Get("kind"), r.URL.Query().Get("q"), r.URL.Query().Get("offset"), num(r, "limit"))
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, v)
	}))
	mux.HandleFunc("POST /v1/conversations/{id}/clear", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b struct {
			Both bool `json:"both"`
		}
		if !decode(w, r, &b) {
			return
		}
		if e := a.ClearHistory(p, r.PathValue("id"), b.Both); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("PUT /v1/users/{id}/block", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		var b struct {
			Blocked bool `json:"blocked"`
		}
		if !decode(w, r, &b) {
			return
		}
		if e := a.Block(p, r.PathValue("id"), b.Blocked); e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"ok": true})
	}))
	mux.HandleFunc("GET /v1/me/blocks", a.auth(func(w http.ResponseWriter, r *http.Request, p Principal) {
		rows, e := a.DB.Query("SELECT target FROM user_blocks WHERE owner=? ORDER BY target", p.UserID)
		if e != nil {
			fail(w, e)
			return
		}
		defer rows.Close()
		out := []string{}
		for rows.Next() {
			var u string
			if e = rows.Scan(&u); e != nil {
				fail(w, e)
				return
			}
			out = append(out, u)
		}
		respond(w, 200, map[string]any{"user_ids": out})
	}))
	mux.HandleFunc("POST /v1/conversations/{id}/report", a.auth(a.report))
	mux.HandleFunc("GET /v1/admin/reports", a.auth(a.reports))
}
func (a *App) report(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		MessageID string `json:"message_id"`
		Reason    string `json:"reason"`
	}
	if !decode(w, r, &b) {
		return
	}
	cid := r.PathValue("id")
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	if strings.TrimSpace(b.Reason) == "" || len(b.Reason) > 2000 {
		fail(w, ErrInvalid)
		return
	}
	rid := id()
	e := a.transaction(func(tx *sql.Tx) error {
		_, joined, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		if b.MessageID != "" {
			var n int
			if e = tx.QueryRow("SELECT count(*) FROM messages WHERE id=? AND chat_id=? AND seq>?", b.MessageID, cid, joined).Scan(&n); e != nil {
				return e
			}
			if n != 1 {
				return ErrForbidden
			}
		}
		_, e = tx.Exec("INSERT INTO reports(id,reporter,chat_id,message_id,reason,created) VALUES(?,?,?,?,?,?)", rid, p.UserID, cid, b.MessageID, b.Reason, now())
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, map[string]string{"id": rid, "status": "submitted"})
}
func (a *App) reports(w http.ResponseWriter, r *http.Request, p Principal) {
	if !p.Admin {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT id,reporter,chat_id,message_id,reason,created FROM reports ORDER BY created DESC,id DESC LIMIT 100")
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]string{}
	for rows.Next() {
		var id, u, c, m, reason, t string
		if e = rows.Scan(&id, &u, &c, &m, &reason, &t); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]string{"id": id, "reporter": u, "conversation_id": c, "message_id": m, "reason": reason, "created_at": t})
	}
	respond(w, 200, map[string]any{"reports": out})
}

// GlobalMedia lists media (and link / voice / audio) messages across every
// conversation the caller can still see. Used by the drawer-level 「文件」
// browser. The cursor is an opaque "created|message-id" string so the page
// can stride across chats; the per-chat seq cursor used by SharedMedia would
// collide between conversations.
func (a *App) GlobalMedia(p Principal, kind, q, offset string, limit int) (map[string]any, error) {
	if limit <= 0 || limit > 100 {
		limit = 40
	}
	if kind == "" {
		kind = "all"
	}
	filter, err := globalMediaFilter(kind)
	if err != nil {
		return nil, err
	}
	base := ` FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0`
	where := base + filter
	args := []any{p.UserID}
	if needle := strings.TrimSpace(q); needle != "" {
		like := "%" + strings.ToLower(needle) + "%"
		where += " AND (lower(ifnull(m.text,'')) LIKE ? OR EXISTS (SELECT 1 FROM media md WHERE md.id=m.media_id AND (lower(ifnull(md.file_name,'')) LIKE ? OR lower(ifnull(md.mime,'')) LIKE ?)))"
		args = append(args, like, like, like)
	}
	if offCreated, offID, ok := parseGlobalMediaOffset(offset); ok {
		where += " AND (m.created < ? OR (m.created = ? AND m.id < ?))"
		args = append(args, offCreated, offCreated, offID)
	}
	query := "SELECT " + prefixColumns("m", msgColumns) + where + " ORDER BY m.created DESC, m.id DESC LIMIT ?"
	args = append(args, limit+1)
	rows, e := a.DB.Query(query, args...)
	if e != nil {
		return nil, e
	}
	items, e := scanMessages(rows)
	rows.Close()
	if e != nil {
		return nil, e
	}
	attachReplySeqs(a.DB, items)
	a.attachPolls(items, p.UserID)
	a.attachChecklists(items)
	more := len(items) > limit
	if more {
		items = items[:limit]
	}
	next := ""
	if more && len(items) > 0 {
		last := items[len(items)-1]
		next = formatGlobalMediaOffset(last.Created, last.ID)
	}
	counts, e := a.globalMediaCounts(p.UserID)
	if e != nil {
		return nil, e
	}
	return map[string]any{"messages": items, "has_more": more, "next_offset": next, "counts": counts}, nil
}

func globalMediaFilter(kind string) (string, error) {
	switch kind {
	case "all":
		return " AND (m.media_id<>'' OR m.preview_json<>'')", nil
	case "image", "video", "file", "voice", "animation", "video_note", "poll":
		return " AND m.kind='" + kind + "'", nil
	case "link":
		return " AND m.preview_json<>''", nil
	case "audio":
		return " AND m.kind='file' AND EXISTS (SELECT 1 FROM media md WHERE md.id=m.media_id AND (md.mime LIKE 'audio/%' OR lower(md.file_name) LIKE '%.mp3' OR lower(md.file_name) LIKE '%.m4a' OR lower(md.file_name) LIKE '%.flac' OR lower(md.file_name) LIKE '%.ogg' OR lower(md.file_name) LIKE '%.wav' OR lower(md.file_name) LIKE '%.aac'))", nil
	default:
		return "", ErrInvalid
	}
}

func formatGlobalMediaOffset(created, id string) string {
	return created + "|" + id
}

func parseGlobalMediaOffset(offset string) (string, string, bool) {
	if offset == "" {
		return "", "", false
	}
	i := strings.IndexByte(offset, '|')
	if i <= 0 || i == len(offset)-1 {
		return "", "", false
	}
	return offset[:i], offset[i+1:], true
}

func (a *App) globalMediaCounts(userID string) (map[string]int64, error) {
	counts := map[string]int64{"image": 0, "video": 0, "file": 0, "voice": 0, "link": 0, "audio": 0}
	base := ` FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0`
	rows, e := a.DB.Query("SELECT m.kind,count(*)"+base+" AND m.media_id<>'' GROUP BY m.kind", userID)
	if e != nil {
		return nil, e
	}
	for rows.Next() {
		var k string
		var n int64
		if e = rows.Scan(&k, &n); e != nil {
			rows.Close()
			return nil, e
		}
		counts[k] = n
	}
	if e = rows.Err(); e != nil {
		rows.Close()
		return nil, e
	}
	rows.Close()
	if e = a.DB.QueryRow("SELECT count(*)"+base+" AND m.preview_json<>''", userID).Scan(newCount(counts, "link")); e != nil {
		return nil, e
	}
	if e = a.DB.QueryRow("SELECT count(*)"+base+" AND m.kind='file' AND EXISTS (SELECT 1 FROM media md WHERE md.id=m.media_id AND (md.mime LIKE 'audio/%' OR lower(md.file_name) LIKE '%.mp3' OR lower(md.file_name) LIKE '%.m4a' OR lower(md.file_name) LIKE '%.flac' OR lower(md.file_name) LIKE '%.ogg' OR lower(md.file_name) LIKE '%.wav' OR lower(md.file_name) LIKE '%.aac'))", userID).Scan(newCount(counts, "audio")); e != nil {
		return nil, e
	}
	return counts, nil
}
