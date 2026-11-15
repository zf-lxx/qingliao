package chat

import (
	"database/sql"
	"net/http"
	"time"
)

func (a *App) pin(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	var b struct {
		MessageID string `json:"message_id"`
		Remove    bool   `json:"remove"`
	}
	if !decode(w, r, &b) {
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		role, joined, e := member(tx, cid, p.UserID)
		if e != nil {
			return e
		}
		var kind string
		if e = tx.QueryRow("SELECT kind FROM chats WHERE id=?", cid).Scan(&kind); e != nil {
			return e
		}
		if kind == "channel" && role != "owner" && role != "admin" {
			return ErrForbidden
		}
		if kind == "group" && role != "owner" && role != "admin" {
			ok, err := memberCan(tx, cid, role, "can_pin_messages")
			if err != nil {
				return err
			}
			if !ok {
				return ErrForbidden
			}
		}
		var n int
		if e = tx.QueryRow("SELECT count(*) FROM messages WHERE id=? AND chat_id=? AND seq>? AND deleted=0", b.MessageID, cid, joined).Scan(&n); e != nil {
			return e
		}
		if n != 1 {
			return ErrForbidden
		}
		typ := "message.pinned"
		if b.Remove {
			_, e = tx.Exec("DELETE FROM pins WHERE chat_id=? AND message_id=?", cid, b.MessageID)
			typ = "message.unpinned"
		} else {
			tx.QueryRow("SELECT count(*) FROM pins WHERE chat_id=?", cid).Scan(&n)
			if n >= 50 {
				return ErrInvalid
			}
			_, e = tx.Exec("INSERT OR IGNORE INTO pins(chat_id,message_id,pinned_by,created) VALUES(?,?,?,?)", cid, b.MessageID, p.UserID, now())
		}
		if e != nil {
			return e
		}
		if e = audit(tx, cid, p.UserID, typ, b.MessageID, nil); e != nil {
			return e
		}
		users, e := members(tx, cid)
		if e != nil {
			return e
		}
		return emit(tx, users, typ, cid, map[string]string{"message_id": b.MessageID, "actor_id": p.UserID})
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
func (a *App) pins(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query("SELECT "+prefixColumns("m", msgColumns)+" FROM pins p JOIN messages m ON m.id=p.message_id JOIN members b ON b.chat_id=p.chat_id WHERE p.chat_id=? AND b.user_id=? AND m.seq>b.joined_seq AND m.deleted=0 ORDER BY p.created DESC", cid, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		m, e := scanMessage(rows)
		if e != nil {
			fail(w, e)
			return
		}
		out = append(out, m)
	}
	respond(w, 200, map[string]any{"messages": out})
}

type PollSpec struct {
	Question      string   `json:"question"`
	Options       []string `json:"options"`
	Multiple      bool     `json:"multiple_choice"`
	Anonymous     bool     `json:"anonymous"`
	Quiz          bool     `json:"quiz"`
	CorrectOption *int     `json:"correct_option"`
	ClosesAt      string   `json:"closes_at,omitempty"`
	ClientID      string   `json:"client_msg_id"`
}

func validatePoll(p PollSpec) error {
	if len(p.Question) < 1 || len(p.Question) > 1000 || len(p.Options) < 2 || len(p.Options) > 10 || len(p.ClientID) < 1 || len(p.ClientID) > 128 {
		return ErrInvalid
	}
	for _, s := range p.Options {
		if len(s) < 1 || len(s) > 300 {
			return ErrInvalid
		}
	}
	if p.Quiz {
		if p.Multiple || p.CorrectOption == nil || *p.CorrectOption < 0 || *p.CorrectOption >= len(p.Options) {
			return ErrInvalid
		}
	} else if p.CorrectOption != nil {
		return ErrInvalid
	}
	if p.ClosesAt != "" {
		t, e := time.Parse(time.RFC3339, p.ClosesAt)
		if e != nil || !t.After(time.Now()) || t.After(time.Now().Add(365*24*time.Hour)) {
			return ErrInvalid
		}
	}
	return nil
}
func (a *App) pollStub(w http.ResponseWriter, r *http.Request, p Principal) {
	cid := r.PathValue("id")
	if !a.isMember(cid, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	if r.Method == "POST" && r.PathValue("poll_id") == "" {
		var b PollSpec
		if !decode(w, r, &b) {
			return
		}
		if e := validatePoll(b); e != nil {
			fail(w, e)
			return
		}
	}
	respond(w, 501, map[string]string{"error": "polls_phase2", "status": "schema_and_validation_only"})
}
func (a *App) callbackStub(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Data string `json:"callback_data"`
	}
	if !decode(w, r, &b) {
		return
	}
	if len(b.Data) < 1 || len(b.Data) > 64 {
		fail(w, ErrInvalid)
		return
	}
	mid := r.PathValue("id")
	m, e := scanMessage(a.DB.QueryRow("SELECT "+msgColumns+" FROM messages WHERE id=?", mid))
	if e != nil || m.Deleted || !a.isMember(m.ChatID, p.UserID) {
		fail(w, ErrForbidden)
		return
	}
	var joined int64
	a.DB.QueryRow("SELECT joined_seq FROM members WHERE chat_id=? AND user_id=?", m.ChatID, p.UserID).Scan(&joined)
	if m.Seq <= joined {
		fail(w, ErrForbidden)
		return
	}
	found := false
	if m.ReplyMarkup != nil {
		for _, row := range m.ReplyMarkup.InlineKeyboard {
			for _, bt := range row {
				if bt.CallbackData == b.Data {
					found = true
				}
			}
		}
	}
	if !found {
		fail(w, ErrInvalid)
		return
	}
	if e := a.dispatchCallbackQuery(p, m, b.Data); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
