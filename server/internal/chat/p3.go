package chat

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func (a *App) p3Routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/me/contacts", a.auth(a.listContacts))
	mux.HandleFunc("PUT /v1/me/contacts/{id}", a.auth(a.putContact))
	mux.HandleFunc("DELETE /v1/me/contacts/{id}", a.auth(a.deleteContact))
	mux.HandleFunc("GET /v1/me/notification-scopes", a.auth(a.notificationScopes))
	mux.HandleFunc("PUT /v1/me/notification-scopes/{scope}", a.auth(a.putNotificationScope))
	mux.HandleFunc("GET /v1/me/privacy/rules", a.auth(a.privacyRules))
	mux.HandleFunc("PUT /v1/me/privacy/rules", a.auth(a.putPrivacyRules))
	mux.HandleFunc("GET /v1/sticker-packs", a.auth(a.listStickerPacks))
	mux.HandleFunc("GET /v1/sticker-packs/{id}", a.auth(a.getStickerPack))
	mux.HandleFunc("POST /v1/sticker-packs", a.auth(a.createStickerPack))
	mux.HandleFunc("POST /v1/sticker-packs/{id}/stickers", a.auth(a.addSticker))
	mux.HandleFunc("GET /v1/sticker-files/{id}", a.auth(a.stickerFile))
	mux.HandleFunc("GET /v1/stickers", a.auth(a.searchStickers))
	mux.HandleFunc("GET /v1/me/sticker-favorites", a.auth(a.listFavoriteStickers))
	mux.HandleFunc("PUT /v1/me/sticker-favorites/{id}", a.auth(a.putFavoriteSticker))
	mux.HandleFunc("POST /v1/conversations/{id}/checklists", a.auth(a.createChecklist))
	mux.HandleFunc("GET /v1/messages/{id}/checklist", a.auth(a.getChecklist))
	mux.HandleFunc("POST /v1/messages/{id}/checklist/tasks", a.auth(a.addChecklistTasks))
	mux.HandleFunc("POST /v1/messages/{id}/checklist/done", a.auth(a.markChecklistTasks))
	mux.HandleFunc("PATCH /v1/messages/{id}/checklist", a.auth(a.editChecklist))
}

// MARK: Polls

func (a *App) createPoll(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b PollSpec
	if !decode(w, r, &b) {
		return
	}
	if e := validatePoll(b); e != nil {
		fail(w, e)
		return
	}
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		if e := a.checkSend(tx, p, cid, Send{ClientID: b.ClientID, Kind: "poll", Text: b.Question}); e != nil {
			return e
		}
		digest := hash("poll:" + cid + ":" + b.ClientID + ":" + b.Question)
		var old string
		e := tx.QueryRow("SELECT payload_hash FROM messages WHERE sender=? AND client_id=?", p.UserID, b.ClientID).Scan(&old)
		if e == nil {
			if old != digest {
				return ErrConflict
			}
			out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE sender=? AND client_id=?", p.UserID, b.ClientID))
			return e
		}
		if e != nil && e != sql.ErrNoRows {
			return e
		}
		var seq int64
		if e = tx.QueryRow("UPDATE chats SET last_seq=last_seq+1,last_activity=? WHERE id=? RETURNING last_seq", time.Now().UnixMicro(), cid).Scan(&seq); e != nil {
			return e
		}
		mid := id()
		pid := id()
		var closes *int64
		if b.ClosesAt != "" {
			t, _ := time.Parse(time.RFC3339, b.ClosesAt)
			u := t.Unix()
			closes = &u
		}
		correct := sql.NullInt64{}
		if b.CorrectOption != nil {
			correct = sql.NullInt64{Int64: int64(*b.CorrectOption), Valid: true}
		}
		if _, e = tx.Exec("INSERT INTO messages(id,chat_id,seq,sender,client_id,kind,text,media_id,reply_to,payload_hash,created,entities_json,preview_json,reply_markup_json,via_bot_id,forward_origin_json,media_meta_json,album_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", mid, cid, seq, p.UserID, b.ClientID, "poll", b.Question, "", "", digest, now(), "[]", "", "", "", "", "", ""); e != nil {
			return e
		}
		if _, e = tx.Exec("INSERT INTO polls(id,chat_id,message_id,creator_id,question,multiple_choice,anonymous,is_quiz,correct_option,closes_at,closed,created) VALUES(?,?,?,?,?,?,?,?,?,?,0,?)", pid, cid, mid, p.UserID, b.Question, boolInt(b.Multiple), boolInt(b.Anonymous), boolInt(b.Quiz), correct, closes, now()); e != nil {
			return e
		}
		for i, opt := range b.Options {
			if _, e = tx.Exec("INSERT INTO poll_options(poll_id,option_id,text) VALUES(?,?,?)", pid, i, opt); e != nil {
				return e
			}
		}
		out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil {
			return e
		}
		if e = a.attachPoll(tx, p.UserID, &out); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message.created", cid, out); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, cid)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, out)
}

func (a *App) getPoll(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	pid := r.PathValue("poll_id")
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	var mid string
	if e := a.DB.QueryRow("SELECT message_id FROM polls WHERE id=? AND chat_id=?", pid, cid).Scan(&mid); e != nil {
		fail(w, ErrForbidden)
		return
	}
	m, e := scanMessage(a.DB.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
	if e != nil {
		fail(w, e)
		return
	}
	if e = a.attachPoll(a.DB, p.UserID, &m); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, m.Poll)
}

func (a *App) votePoll(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	pid := r.PathValue("poll_id")
	var b struct {
		Options  []int  `json:"option_ids"`
		ClientID string `json:"client_vote_id"`
	}
	if !decode(w, r, &b) {
		return
	}
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		if !isMemberTx(tx, cid, p.UserID) {
			return ErrForbidden
		}
		var mid string
		var multi, closed int
		var closes sql.NullInt64
		if e := tx.QueryRow("SELECT message_id,multiple_choice,closed,closes_at FROM polls WHERE id=? AND chat_id=?", pid, cid).Scan(&mid, &multi, &closed, &closes); e != nil {
			return ErrForbidden
		}
		if closed == 1 || (closes.Valid && closes.Int64 <= time.Now().Unix()) {
			if closed == 0 {
				tx.Exec("UPDATE polls SET closed=1 WHERE id=?", pid)
			}
			return ErrForbidden
		}
		if multi == 0 && len(b.Options) > 1 {
			return ErrInvalid
		}
		if _, e := tx.Exec("DELETE FROM poll_votes WHERE poll_id=? AND user_id=?", pid, p.UserID); e != nil {
			return e
		}
		for _, opt := range uniqueInts(b.Options) {
			if _, e := tx.Exec("INSERT INTO poll_votes(poll_id,user_id,option_id,created) VALUES(?,?,?,?)", pid, p.UserID, opt, now()); e != nil {
				return ErrInvalid
			}
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

func (a *App) closePoll(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	pid := r.PathValue("poll_id")
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		role, _, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var mid, creator string
		if e = tx.QueryRow("SELECT message_id,creator_id FROM polls WHERE id=? AND chat_id=?", pid, cid).Scan(&mid, &creator); e != nil {
			return ErrForbidden
		}
		if creator != p.UserID && role != "owner" && role != "admin" {
			return ErrForbidden
		}
		if _, e = tx.Exec("UPDATE polls SET closed=1 WHERE id=?", pid); e != nil {
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

func boolInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func uniqueInts(in []int) []int {
	seen := map[int]bool{}
	out := []int{}
	for _, n := range in {
		if n < 0 || seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}

func isMemberTx(tx *sql.Tx, cid, uid string) bool {
	var n int
	tx.QueryRow("SELECT count(*) FROM members WHERE chat_id=? AND user_id=?", cid, uid).Scan(&n)
	return n == 1
}

type queryer interface {
	Query(string, ...any) (*sql.Rows, error)
	QueryRow(string, ...any) *sql.Row
}

func (a *App) attachPoll(q queryer, viewer string, m *Message) error {
	if m == nil || m.Kind != "poll" {
		return nil
	}
	var pid, question string
	var multi, anon, quiz, closed int
	var correct sql.NullInt64
	var closes sql.NullInt64
	if e := q.QueryRow("SELECT id,question,multiple_choice,anonymous,is_quiz,correct_option,closes_at,closed FROM polls WHERE message_id=?", m.ID).Scan(&pid, &question, &multi, &anon, &quiz, &correct, &closes, &closed); e != nil {
		return e
	}
	if closes.Valid && closes.Int64 <= time.Now().Unix() {
		closed = 1
	}
	rows, e := q.Query("SELECT option_id,text FROM poll_options WHERE poll_id=? ORDER BY option_id", pid)
	if e != nil {
		return e
	}
	type opt struct {
		ID   int    `json:"id"`
		Text string `json:"text"`
		N    int    `json:"voter_count"`
		Mine bool   `json:"chosen,omitempty"`
	}
	options := []opt{}
	for rows.Next() {
		var o opt
		if e = rows.Scan(&o.ID, &o.Text); e != nil {
			rows.Close()
			return e
		}
		options = append(options, o)
	}
	rows.Close()
	if e = rows.Err(); e != nil {
		return e
	}
	counts := map[int]int{}
	rows, e = q.Query("SELECT option_id,count(*) FROM poll_votes WHERE poll_id=? GROUP BY option_id", pid)
	if e != nil {
		return e
	}
	for rows.Next() {
		var id, n int
		rows.Scan(&id, &n)
		counts[id] = n
	}
	rows.Close()
	chosen := map[int]bool{}
	rows, e = q.Query("SELECT option_id FROM poll_votes WHERE poll_id=? AND user_id=?", pid, viewer)
	if e != nil {
		return e
	}
	for rows.Next() {
		var id int
		rows.Scan(&id)
		chosen[id] = true
	}
	rows.Close()
	total := 0
	q.QueryRow("SELECT count(DISTINCT user_id) FROM poll_votes WHERE poll_id=?", pid).Scan(&total)
	for i := range options {
		options[i].N = counts[options[i].ID]
		options[i].Mine = chosen[options[i].ID]
	}
	poll := map[string]any{
		"id": pid, "question": question, "multiple_choice": multi == 1, "anonymous": anon == 1,
		"quiz": quiz == 1, "closed": closed == 1, "total_voter_count": total, "options": options,
	}
	if quiz == 1 && closed == 1 && correct.Valid {
		poll["correct_option"] = correct.Int64
	}
	if closes.Valid {
		poll["closes_at"] = closes.Int64
	}
	m.Poll = poll
	return nil
}

func (a *App) attachPolls(messages []Message, viewer string) {
	for i := range messages {
		_ = a.attachPoll(a.DB, viewer, &messages[i])
	}
}

// MARK: Checklists

type checklistSpec struct {
	Title        string   `json:"title"`
	Tasks        []string `json:"tasks"`
	OthersAdd    bool     `json:"others_can_add"`
	OthersMark   bool     `json:"others_can_mark"`
	ClientID     string   `json:"client_msg_id"`
}

func (a *App) createChecklist(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b checklistSpec
	if !decode(w, r, &b) {
		return
	}
	b.Title = strings.TrimSpace(b.Title)
	tasks := []string{}
	for _, t := range b.Tasks {
		t = strings.TrimSpace(t)
		if t != "" {
			tasks = append(tasks, t)
		}
	}
	if b.Title == "" || len(tasks) == 0 || len(tasks) > 30 || len(b.ClientID) < 1 || len(b.ClientID) > 128 || len(b.Title) > 300 {
		fail(w, ErrInvalid)
		return
	}
	for _, t := range tasks {
		if len(t) > 300 {
			fail(w, ErrInvalid)
			return
		}
	}
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		if e := a.checkSend(tx, p, cid, Send{ClientID: b.ClientID, Kind: "checklist", Text: b.Title}); e != nil {
			return e
		}
		digest := hash("checklist:" + cid + ":" + b.ClientID + ":" + b.Title)
		var old string
		e := tx.QueryRow("SELECT payload_hash FROM messages WHERE sender=? AND client_id=?", p.UserID, b.ClientID).Scan(&old)
		if e == nil {
			if old != digest {
				return ErrConflict
			}
			out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE sender=? AND client_id=?", p.UserID, b.ClientID))
			return e
		}
		if e != nil && e != sql.ErrNoRows {
			return e
		}
		var seq int64
		if e = tx.QueryRow("UPDATE chats SET last_seq=last_seq+1,last_activity=? WHERE id=? RETURNING last_seq", time.Now().UnixMicro(), cid).Scan(&seq); e != nil {
			return e
		}
		mid, hid := id(), id()
		if _, e = tx.Exec("INSERT INTO messages(id,chat_id,seq,sender,client_id,kind,text,media_id,reply_to,payload_hash,created,entities_json,preview_json,reply_markup_json,via_bot_id,forward_origin_json,media_meta_json,album_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", mid, cid, seq, p.UserID, b.ClientID, "checklist", b.Title, "", "", digest, now(), "[]", "", "", "", "", "", ""); e != nil {
			return e
		}
		if _, e = tx.Exec("INSERT INTO checklists(id,chat_id,message_id,creator_id,title,others_can_add,others_can_mark,created) VALUES(?,?,?,?,?,?,?,?)", hid, cid, mid, p.UserID, b.Title, boolInt(b.OthersAdd), boolInt(b.OthersMark), now()); e != nil {
			return e
		}
		for i, t := range tasks {
			if _, e = tx.Exec("INSERT INTO checklist_tasks(id,checklist_id,task_no,text,completed_by,completed_at) VALUES(?,?,?,?,?,?)", id(), hid, i+1, t, "", ""); e != nil {
				return e
			}
		}
		out, e = scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil {
			return e
		}
		if e = a.attachChecklist(tx, &out); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		if e = emit(tx, users, "message.created", cid, out); e != nil {
			return e
		}
		return a.emitDialogStates(tx, users, cid)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, out)
}

func (a *App) getChecklist(w http.ResponseWriter, r *http.Request, p Principal) {
	m, e := a.loadVisibleMessage(p, r.PathValue("id"))
	if e != nil {
		fail(w, e)
		return
	}
	if e = a.attachChecklist(a.DB, &m); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, m)
}

func (a *App) addChecklistTasks(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Tasks []string `json:"tasks"`
	}
	if !decode(w, r, &b) {
		return
	}
	a.mutateChecklist(w, r, p, func(tx *sql.Tx, hid, creator string, add, mark int) error {
		if p.UserID != creator && add == 0 {
			return ErrForbidden
		}
		var max int
		tx.QueryRow("SELECT COALESCE(max(task_no),0) FROM checklist_tasks WHERE checklist_id=?", hid).Scan(&max)
		n := 0
		tx.QueryRow("SELECT count(*) FROM checklist_tasks WHERE checklist_id=?", hid).Scan(&n)
		for _, t := range b.Tasks {
			t = strings.TrimSpace(t)
			if t == "" {
				continue
			}
			if len(t) > 300 || n >= 30 {
				return ErrInvalid
			}
			max++
			n++
			if _, e := tx.Exec("INSERT INTO checklist_tasks(id,checklist_id,task_no,text,completed_by,completed_at) VALUES(?,?,?,?,?,?)", id(), hid, max, t, "", ""); e != nil {
				return e
			}
		}
		return nil
	})
}

func (a *App) markChecklistTasks(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Done   []int `json:"done_task_ids"`
		Undone []int `json:"undone_task_ids"`
	}
	if !decode(w, r, &b) {
		return
	}
	a.mutateChecklist(w, r, p, func(tx *sql.Tx, hid, creator string, add, mark int) error {
		if p.UserID != creator && mark == 0 {
			return ErrForbidden
		}
		for _, n := range b.Done {
			if _, e := tx.Exec("UPDATE checklist_tasks SET completed_by=?,completed_at=? WHERE checklist_id=? AND task_no=? AND completed_by=''", p.UserID, now(), hid, n); e != nil {
				return e
			}
		}
		for _, n := range b.Undone {
			if _, e := tx.Exec("UPDATE checklist_tasks SET completed_by='',completed_at='' WHERE checklist_id=? AND task_no=?", hid, n); e != nil {
				return e
			}
		}
		return nil
	})
}

func (a *App) editChecklist(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Title      string         `json:"title"`
		Tasks      []map[string]any `json:"tasks"`
		OthersAdd  *bool          `json:"others_can_add"`
		OthersMark *bool          `json:"others_can_mark"`
	}
	if !decode(w, r, &b) {
		return
	}
	a.mutateChecklist(w, r, p, func(tx *sql.Tx, hid, creator string, add, mark int) error {
		if p.UserID != creator {
			return ErrForbidden
		}
		title := strings.TrimSpace(b.Title)
		if title != "" {
			if _, e := tx.Exec("UPDATE checklists SET title=? WHERE id=?", title, hid); e != nil {
				return e
			}
			if _, e := tx.Exec("UPDATE messages SET text=?,edited=? WHERE id=(SELECT message_id FROM checklists WHERE id=?)", title, now(), hid); e != nil {
				return e
			}
		}
		if b.OthersAdd != nil || b.OthersMark != nil {
			if b.OthersAdd != nil {
				add = boolInt(*b.OthersAdd)
			}
			if b.OthersMark != nil {
				mark = boolInt(*b.OthersMark)
			}
			if _, e := tx.Exec("UPDATE checklists SET others_can_add=?,others_can_mark=? WHERE id=?", add, mark, hid); e != nil {
				return e
			}
		}
		if b.Tasks == nil {
			return nil
		}
		keep := map[int]bool{}
		for _, raw := range b.Tasks {
			text := strings.TrimSpace(fmt.Sprint(raw["text"]))
			if text == "" {
				if inner, ok := raw["text"].(map[string]any); ok {
					text = strings.TrimSpace(fmt.Sprint(inner["text"]))
				}
			}
			no := 0
			switch v := raw["id"].(type) {
			case float64:
				no = int(v)
			case int:
				no = v
			}
			if no <= 0 || text == "" {
				continue
			}
			keep[no] = true
			if _, e := tx.Exec("INSERT INTO checklist_tasks(id,checklist_id,task_no,text) VALUES(?,?,?,?) ON CONFLICT(checklist_id,task_no) DO UPDATE SET text=excluded.text", id(), hid, no, text); e != nil {
				return e
			}
		}
		rows, e := tx.Query("SELECT task_no FROM checklist_tasks WHERE checklist_id=?", hid)
		if e != nil {
			return e
		}
		drop := []int{}
		for rows.Next() {
			var n int
			if rows.Scan(&n) == nil && !keep[n] {
				drop = append(drop, n)
			}
		}
		rows.Close()
		for _, n := range drop {
			if _, e := tx.Exec("DELETE FROM checklist_tasks WHERE checklist_id=? AND task_no=?", hid, n); e != nil {
				return e
			}
		}
		return nil
	})
}

func (a *App) mutateChecklist(w http.ResponseWriter, r *http.Request, p Principal, fn func(*sql.Tx, string, string, int, int) error) {
	mid := r.PathValue("id")
	var out Message
	e := a.transaction(func(tx *sql.Tx) error {
		var hid, creator, cid string
		var add, mark int
		if e := tx.QueryRow("SELECT c.id,c.creator_id,c.chat_id,c.others_can_add,c.others_can_mark FROM checklists c JOIN messages m ON m.id=c.message_id JOIN members b ON b.chat_id=c.chat_id WHERE c.message_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0", mid, p.UserID).Scan(&hid, &creator, &cid, &add, &mark); e != nil {
			return ErrForbidden
		}
		if e := fn(tx, hid, creator, add, mark); e != nil {
			return e
		}
		m, e := scanMessage(tx.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
		if e != nil {
			return e
		}
		if e = a.attachChecklist(tx, &m); e != nil {
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

func (a *App) loadVisibleMessage(p Principal, mid string) (Message, error) {
	var n int
	e := a.DB.QueryRow("SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0", mid, p.UserID).Scan(&n)
	if e != nil || n != 1 {
		return Message{}, ErrForbidden
	}
	return scanMessage(a.DB.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
}

func (a *App) attachChecklist(q queryer, m *Message) error {
	if m == nil || m.Kind != "checklist" {
		return nil
	}
	var hid, title, creator string
	var add, mark int
	if e := q.QueryRow("SELECT id,title,creator_id,others_can_add,others_can_mark FROM checklists WHERE message_id=?", m.ID).Scan(&hid, &title, &creator, &add, &mark); e != nil {
		return e
	}
	rows, e := q.Query("SELECT task_no,text,completed_by,completed_at FROM checklist_tasks WHERE checklist_id=? ORDER BY task_no", hid)
	if e != nil {
		return e
	}
	tasks := []map[string]any{}
	for rows.Next() {
		var no int
		var text, by, at string
		if e = rows.Scan(&no, &text, &by, &at); e != nil {
			rows.Close()
			return e
		}
		tasks = append(tasks, map[string]any{"id": no, "text": text, "completed_by": by, "completed_at": at})
	}
	rows.Close()
	m.Checklist = map[string]any{"id": hid, "title": title, "creator_id": creator, "others_can_add": add == 1, "others_can_mark": mark == 1, "tasks": tasks}
	return nil
}

func (a *App) attachChecklists(messages []Message) {
	for i := range messages {
		_ = a.attachChecklist(a.DB, &messages[i])
	}
}

// MARK: Contacts

func (a *App) listContacts(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT user_id,first_name,last_name FROM contacts WHERE owner=? ORDER BY first_name,user_id", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]string{}
	for rows.Next() {
		var id, first, last string
		if e = rows.Scan(&id, &first, &last); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]string{"user_id": id, "first_name": first, "last_name": last})
	}
	respond(w, 200, map[string]any{"contacts": out})
}

func (a *App) putContact(w http.ResponseWriter, r *http.Request, p Principal) {
	uid := r.PathValue("id")
	if uid == p.UserID || !keyRE.MatchString(uid) {
		fail(w, ErrInvalid)
		return
	}
	var b struct {
		First string `json:"first_name"`
		Last  string `json:"last_name"`
	}
	if !decode(w, r, &b) {
		return
	}
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM users WHERE id=?", uid).Scan(&n); e != nil || n != 1 {
		fail(w, ErrForbidden)
		return
	}
	if _, e := a.DB.Exec("INSERT INTO contacts(owner,user_id,first_name,last_name,created) VALUES(?,?,?,?,?) ON CONFLICT(owner,user_id) DO UPDATE SET first_name=excluded.first_name,last_name=excluded.last_name", p.UserID, uid, b.First, b.Last, now()); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) deleteContact(w http.ResponseWriter, r *http.Request, p Principal) {
	res, e := a.DB.Exec("DELETE FROM contacts WHERE owner=? AND user_id=?", p.UserID, r.PathValue("id"))
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

// MARK: Notification scopes & privacy rules

func (a *App) notificationScopes(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT scope,mute_until,show_preview,settings_json FROM notification_scopes WHERE user_id=?", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var scope, raw string
		var mute, preview int64
		if e = rows.Scan(&scope, &mute, &preview, &raw); e != nil {
			fail(w, e)
			return
		}
		item := map[string]any{"scope": scope, "mute_until": mute, "show_preview": preview == 1}
		if raw != "" && raw != "{}" {
			item["settings"] = json.RawMessage(raw)
		}
		out = append(out, item)
	}
	respond(w, 200, map[string]any{"scopes": out})
}

func (a *App) putNotificationScope(w http.ResponseWriter, r *http.Request, p Principal) {
	scope := r.PathValue("scope")
	if scope != "private" && scope != "group" && scope != "channel" {
		fail(w, ErrInvalid)
		return
	}
	var b struct {
		Mute    int64          `json:"mute_until"`
		Preview *bool          `json:"show_preview"`
		Extra   map[string]any `json:"settings"`
	}
	if !decode(w, r, &b) {
		return
	}
	preview := 1
	if b.Preview != nil && !*b.Preview {
		preview = 0
	}
	if _, e := a.DB.Exec("INSERT INTO notification_scopes(user_id,scope,mute_until,show_preview,settings_json) VALUES(?,?,?,?,?) ON CONFLICT(user_id,scope) DO UPDATE SET mute_until=excluded.mute_until,show_preview=excluded.show_preview,settings_json=excluded.settings_json", p.UserID, scope, b.Mute, preview, jsonText(b.Extra, "{}")); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

var privacySettings = map[string]bool{
	"userPrivacySettingShowStatus": true, "userPrivacySettingShowProfilePhoto": true,
	"userPrivacySettingShowPhoneNumber": true, "userPrivacySettingAllowChatInvites": true,
	"userPrivacySettingAllowCalls": true, "userPrivacySettingAllowFindingByUsername": true,
	"userPrivacySettingShowLinkInForwardedMessages": true, "userPrivacySettingShowBio": true,
	"userPrivacySettingAllowFindingByPhoneNumber": true, "userPrivacySettingAllowPeerToPeerCalls": true,
	"userPrivacySettingShowBirthdate": true, "userPrivacySettingAllowPrivateVoiceVideoNoteMessages": true,
}

func (a *App) privacyRules(w http.ResponseWriter, r *http.Request, p Principal) {
	setting := r.URL.Query().Get("setting")
	if setting != "" && !privacySettings[setting] {
		fail(w, ErrInvalid)
		return
	}
	rows, e := a.DB.Query("SELECT setting,rules_json FROM privacy_rules WHERE user_id=? AND (?='' OR setting=?)", p.UserID, setting, setting)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := map[string]json.RawMessage{}
	for rows.Next() {
		var s, raw string
		if e = rows.Scan(&s, &raw); e != nil {
			fail(w, e)
			return
		}
		out[s] = json.RawMessage(raw)
	}
	respond(w, 200, map[string]any{"rules": out})
}

func (a *App) putPrivacyRules(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Setting string          `json:"setting"`
		Rules   json.RawMessage `json:"rules"`
	}
	if !decode(w, r, &b) {
		return
	}
	if !privacySettings[b.Setting] || len(b.Rules) == 0 {
		fail(w, ErrInvalid)
		return
	}
	if _, e := a.DB.Exec("INSERT INTO privacy_rules(user_id,setting,rules_json) VALUES(?,?,?) ON CONFLICT(user_id,setting) DO UPDATE SET rules_json=excluded.rules_json", p.UserID, b.Setting, string(b.Rules)); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

// MARK: Stickers

func (a *App) ensureDefaultStickers() error {
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM sticker_packs WHERE id='qingliao-basic'").Scan(&n); e != nil {
		return e
	}
	if n > 0 {
		return nil
	}
	return a.transaction(func(tx *sql.Tx) error {
		if _, e := tx.Exec("INSERT OR IGNORE INTO sticker_packs(id,owner,title,is_emoji,created) VALUES('qingliao-basic','','轻聊',0,?)", now()); e != nil {
			return e
		}
		type item struct {
			id, emoji string
			c         color.RGBA
		}
		pack := []item{
			{"st-ok", "👍", color.RGBA{66, 133, 244, 255}},
			{"st-heart", "❤️", color.RGBA{234, 67, 53, 255}},
			{"st-fire", "🔥", color.RGBA{251, 140, 0, 255}},
			{"st-party", "🎉", color.RGBA{156, 39, 176, 255}},
			{"st-joy", "😂", color.RGBA{251, 188, 5, 255}},
			{"st-pray", "🙏", color.RGBA{15, 157, 88, 255}},
			{"st-clap", "👏", color.RGBA{3, 155, 229, 255}},
			{"st-spark", "✨", color.RGBA{255, 215, 64, 255}},
		}
		for i, it := range pack {
			png, sum, size, e := solidStickerPNG(it.c)
			if e != nil {
				return e
			}
			if _, e = tx.Exec("INSERT OR IGNORE INTO sticker_files(id,mime,bytes,sha256,data) VALUES(?,?,?,?,?)", it.id, "image/png", size, sum, png); e != nil {
				return e
			}
			if _, e = tx.Exec("INSERT OR IGNORE INTO stickers(id,pack_id,emoji,media_id,file_id,sort_order) VALUES(?,?,?,?,?,?)", it.id, "qingliao-basic", it.emoji, "", it.id, i); e != nil {
				return e
			}
		}
		return nil
	})
}

func solidStickerPNG(c color.RGBA) ([]byte, string, int, error) {
	const s = 96
	img := image.NewRGBA(image.Rect(0, 0, s, s))
	for y := 0; y < s; y++ {
		for x := 0; x < s; x++ {
			dx, dy := float64(x-s/2), float64(y-s/2)
			if dx*dx+dy*dy <= float64((s/2-2)*(s/2-2)) {
				img.SetRGBA(x, y, c)
			}
		}
	}
	var buf bytes.Buffer
	if e := png.Encode(&buf, img); e != nil {
		return nil, "", 0, e
	}
	sum := sha256.Sum256(buf.Bytes())
	return buf.Bytes(), hex.EncodeToString(sum[:]), buf.Len(), nil
}

func (a *App) listStickerPacks(w http.ResponseWriter, r *http.Request, p Principal) {
	if e := a.ensureDefaultStickers(); e != nil {
		fail(w, e)
		return
	}
	rows, e := a.DB.Query("SELECT id,owner,title,is_emoji FROM sticker_packs WHERE owner='' OR owner=? ORDER BY created,id", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, owner, title string
		var emoji int
		if e = rows.Scan(&id, &owner, &title, &emoji); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"id": id, "owner": owner, "title": title, "is_emoji": emoji == 1})
	}
	respond(w, 200, map[string]any{"packs": out})
}

func (a *App) getStickerPack(w http.ResponseWriter, r *http.Request, p Principal) {
	if e := a.ensureDefaultStickers(); e != nil {
		fail(w, e)
		return
	}
	pid := r.PathValue("id")
	var owner, title string
	var emoji int
	if e := a.DB.QueryRow("SELECT owner,title,is_emoji FROM sticker_packs WHERE id=? AND (owner='' OR owner=?)", pid, p.UserID).Scan(&owner, &title, &emoji); e != nil {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT id,emoji,media_id,file_id,sort_order FROM stickers WHERE pack_id=? ORDER BY sort_order,id", pid)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	items := []map[string]any{}
	for rows.Next() {
		var id, em, mid, fid string
		var sort int
		if e = rows.Scan(&id, &em, &mid, &fid, &sort); e != nil {
			fail(w, e)
			return
		}
		items = append(items, map[string]any{"id": id, "emoji": em, "media_id": mid, "file_id": fid, "sort_order": sort})
	}
	respond(w, 200, map[string]any{"id": pid, "owner": owner, "title": title, "is_emoji": emoji == 1, "stickers": items})
}

func (a *App) createStickerPack(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Title   string `json:"title"`
		IsEmoji bool   `json:"is_emoji"`
	}
	if !decode(w, r, &b) {
		return
	}
	title := strings.TrimSpace(b.Title)
	if title == "" || len(title) > 100 {
		fail(w, ErrInvalid)
		return
	}
	pid := id()
	if _, e := a.DB.Exec("INSERT INTO sticker_packs(id,owner,title,is_emoji,created) VALUES(?,?,?,?,?)", pid, p.UserID, title, boolInt(b.IsEmoji), now()); e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, map[string]string{"id": pid})
}

func (a *App) addSticker(w http.ResponseWriter, r *http.Request, p Principal) {
	pid := r.PathValue("id")
	var b struct {
		Emoji   string `json:"emoji"`
		MediaID string `json:"media_id"`
	}
	if !decode(w, r, &b) {
		return
	}
	b.Emoji = strings.TrimSpace(b.Emoji)
	if b.Emoji == "" || len(b.Emoji) > 16 || b.MediaID == "" {
		fail(w, ErrInvalid)
		return
	}
	var owner string
	if e := a.DB.QueryRow("SELECT owner FROM sticker_packs WHERE id=?", pid).Scan(&owner); e != nil || owner != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM media WHERE id=? AND owner=?", b.MediaID, p.UserID).Scan(&n); e != nil || n != 1 {
		fail(w, ErrInvalid)
		return
	}
	sid := id()
	var sort int
	a.DB.QueryRow("SELECT COALESCE(max(sort_order)+1,0) FROM stickers WHERE pack_id=?", pid).Scan(&sort)
	if _, e := a.DB.Exec("INSERT INTO stickers(id,pack_id,emoji,media_id,file_id,sort_order) VALUES(?,?,?,?,?,?)", sid, pid, b.Emoji, b.MediaID, "", sort); e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, map[string]string{"id": sid})
}

func (a *App) stickerFile(w http.ResponseWriter, r *http.Request, p Principal) {
	var mime string
	var data []byte
	if e := a.DB.QueryRow("SELECT mime,data FROM sticker_files WHERE id=?", r.PathValue("id")).Scan(&mime, &data); e != nil {
		fail(w, ErrForbidden)
		return
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Cache-Control", "private, max-age=86400")
	w.Write(data)
}

func (a *App) searchStickers(w http.ResponseWriter, r *http.Request, p Principal) {
	if e := a.ensureDefaultStickers(); e != nil {
		fail(w, e)
		return
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	rows, e := a.DB.Query("SELECT s.id,s.emoji,s.media_id,s.file_id,s.pack_id FROM stickers s JOIN sticker_packs p ON p.id=s.pack_id WHERE (p.owner='' OR p.owner=?) AND (?='' OR s.emoji LIKE ?) ORDER BY s.pack_id,s.sort_order LIMIT 100", p.UserID, q, q+"%")
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, em, mid, fid, pack string
		if e = rows.Scan(&id, &em, &mid, &fid, &pack); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"id": id, "emoji": em, "media_id": mid, "file_id": fid, "pack_id": pack})
	}
	respond(w, 200, map[string]any{"stickers": out})
}

func (a *App) listFavoriteStickers(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT s.id,s.emoji,s.media_id,s.file_id,s.pack_id FROM sticker_favorites f JOIN stickers s ON s.id=f.sticker_id WHERE f.user_id=? ORDER BY f.created", p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, em, mid, fid, pack string
		if e = rows.Scan(&id, &em, &mid, &fid, &pack); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"id": id, "emoji": em, "media_id": mid, "file_id": fid, "pack_id": pack})
	}
	respond(w, 200, map[string]any{"stickers": out})
}

func (a *App) putFavoriteSticker(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Favorite bool `json:"favorite"`
	}
	if !decode(w, r, &b) {
		return
	}
	sid := r.PathValue("id")
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM stickers WHERE id=?", sid).Scan(&n); e != nil || n != 1 {
		fail(w, ErrForbidden)
		return
	}
	var e error
	if b.Favorite {
		_, e = a.DB.Exec("INSERT OR IGNORE INTO sticker_favorites(user_id,sticker_id,created) VALUES(?,?,?)", p.UserID, sid, now())
	} else {
		_, e = a.DB.Exec("DELETE FROM sticker_favorites WHERE user_id=? AND sticker_id=?", p.UserID, sid)
	}
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func parseMuteUntil(v any) int64 {
	switch n := v.(type) {
	case float64:
		return int64(n)
	case int64:
		return n
	case string:
		x, _ := strconv.ParseInt(n, 10, 64)
		return x
	default:
		return 0
	}
}
