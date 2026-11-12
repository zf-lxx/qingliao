package chat

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"
)

func (a *App) receiptsOn(user string) bool {
	if !a.C.ReadReceiptsEnabled {
		return false
	}
	var on int
	e := a.DB.QueryRow("SELECT read_receipts_enabled FROM users WHERE id=?", user).Scan(&on)
	return e == nil && on == 1
}
func (a *App) readRecipients(tx *sql.Tx, reader, cid string) ([]string, error) {
	if !a.C.ReadReceiptsEnabled {
		return []string{reader}, nil
	}
	var on int
	if e := tx.QueryRow("SELECT read_receipts_enabled FROM users WHERE id=?", reader).Scan(&on); e != nil {
		return nil, e
	}
	if on != 1 {
		return []string{reader}, nil
	}
	rows, e := tx.Query("SELECT b.user_id FROM members b JOIN users u ON u.id=b.user_id WHERE b.chat_id=? AND u.read_receipts_enabled=1", cid)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	users := []string{}
	for rows.Next() {
		var id string
		if e = rows.Scan(&id); e != nil {
			return nil, e
		}
		users = append(users, id)
	}
	return users, rows.Err()
}
func (a *App) privacy(w http.ResponseWriter, r *http.Request, p Principal) {
	if r.Method == "GET" {
		var on int
		e := a.DB.QueryRow("SELECT read_receipts_enabled FROM users WHERE id=?", p.UserID).Scan(&on)
		if e != nil {
			fail(w, e)
			return
		}
		respond(w, 200, map[string]bool{"read_receipts_enabled": on == 1, "global_read_receipts_enabled": a.C.ReadReceiptsEnabled, "effective": a.C.ReadReceiptsEnabled && on == 1})
		return
	}
	var b struct {
		On bool `json:"read_receipts_enabled"`
	}
	if !decode(w, r, &b) {
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		if _, e := tx.Exec("UPDATE users SET read_receipts_enabled=? WHERE id=?", b.On, p.UserID); e != nil {
			return e
		}
		if e := emit(tx, []string{p.UserID}, "privacy.updated", "", map[string]bool{"read_receipts_enabled": b.On, "effective": a.C.ReadReceiptsEnabled && b.On}); e != nil {
			return e
		}
		rows, e := tx.Query("SELECT chat_id FROM members WHERE user_id=?", p.UserID)
		if e != nil {
			return e
		}
		chats := []string{}
		for rows.Next() {
			var cid string
			rows.Scan(&cid)
			chats = append(chats, cid)
		}
		rows.Close()
		for _, cid := range chats {
			users, e := members(tx, cid)
			if e != nil {
				return e
			}
			if e = a.emitDialogStates(tx, users, cid); e != nil {
				return e
			}
		}
		return nil
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
func (a *App) redactEvents(user string, events []Event) {
	if len(events) == 0 {
		return
	}
	canSee := a.receiptsOn(user)
	for i := range events {
		ev := &events[i]
		if strings.HasPrefix(ev.Type, "message.") {
			var m Message
			if json.Unmarshal(ev.Data, &m) == nil && m.ID != "" {
				var visible int
				a.DB.QueryRow("SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.id=? AND b.user_id=? AND m.seq>b.joined_seq AND (m.deleted=0 OR ?)", m.ID, user, m.Deleted).Scan(&visible)
				if visible == 0 {
					ev.Type = "privacy.redacted"
					ev.Data = json.RawMessage(`{}`)
				}
			}
		}
		if ev.Type == "dialog.updated" {
			var d map[string]any
			if json.Unmarshal(ev.Data, &d) == nil {
				if m, ok := d["last_message"].(map[string]any); ok {
					var cutoff int64
					a.DB.QueryRow("SELECT joined_seq FROM members WHERE chat_id=? AND user_id=?", ev.ChatID, user).Scan(&cutoff)
					if seq, ok := m["conversation_seq"].(float64); ok && int64(seq) <= cutoff {
						d["last_message"] = nil
						ev.Data, _ = json.Marshal(d)
					}
				}
			}
		}
		if ev.Type == "read.updated" {
			var b struct {
				UserID string `json:"user_id"`
			}
			if json.Unmarshal(ev.Data, &b) == nil && b.UserID != user && (!canSee || !a.receiptsOn(b.UserID)) {
				ev.Type = "privacy.redacted"
				ev.Data = json.RawMessage(`{}`)
			}
		}
		if ev.Type == "dialog.updated" && !canSee {
			var d map[string]any
			if json.Unmarshal(ev.Data, &d) == nil {
				d["last_message_read_count"] = nil
				d["read_receipts_visible"] = false
				ev.Data, _ = json.Marshal(d)
			}
		}
	}
}
