package chat

import (
	"database/sql"
	"errors"
	"github.com/gorilla/websocket"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

type ticket struct {
	P       Principal
	Expires time.Time
}
type Hub struct {
	mu      sync.Mutex
	clients map[*connection]bool
}
type connection struct {
	ws     *websocket.Conn
	p      Principal
	out    chan any
	wake   chan struct{}
	sent   atomic.Int64
	cursor atomic.Int64
	active atomic.Bool
}

func newHub() *Hub { return &Hub{clients: map[*connection]bool{}} }
func (h *Hub) online(user string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.p.UserID == user {
			return true
		}
	}
	return false
}
func (h *Hub) deviceOnline(id string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.p.DeviceID == id {
			return true
		}
	}
	return false
}
func (h *Hub) add(c *connection) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if len(h.clients) >= 512 {
		return false
	}
	n := 0
	for x := range h.clients {
		if x.p.UserID == c.p.UserID {
			n++
		}
	}
	if n >= 256 {
		return false
	}
	h.clients[c] = true
	return true
}
func (h *Hub) signal() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		select {
		case c.wake <- struct{}{}:
		default:
		}
	}
}
func (h *Hub) remove(c *connection) { h.mu.Lock(); delete(h.clients, c); h.mu.Unlock() }
func (h *Hub) closeAll() {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		c.ws.Close()
	}
}
func (h *Hub) closeDevice(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.p.DeviceID == id {
			c.ws.Close()
		}
	}
}
func (h *Hub) closeSession(id string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.p.SessionID == id {
			c.ws.Close()
		}
	}
}
func (c *connection) enqueue(v any) {
	select {
	case c.out <- v:
	default:
		c.ws.Close()
	}
}
func (h *Hub) broadcast(users []string, except string, data any) {
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.clients {
		if c.p.UserID == except {
			continue
		}
		for _, u := range users {
			if c.p.UserID == u {
				c.enqueue(data)
				break
			}
		}
	}
}
func (a *App) wsTicket(w http.ResponseWriter, r *http.Request, p Principal) {
	a.ticketsMu.Lock()
	defer a.ticketsMu.Unlock()
	for k, t := range a.tickets {
		if time.Now().After(t.Expires) {
			delete(a.tickets, k)
		}
	}
	if len(a.tickets) > 1000 {
		respond(w, 429, map[string]string{"error": "too_many_tickets"})
		return
	}
	s := id() + id()
	a.tickets[hash(s)] = ticket{p, time.Now().Add(30 * time.Second)}
	respond(w, 200, map[string]any{"ticket": s, "expires_in": 30})
}
func (a *App) websocket(w http.ResponseWriter, r *http.Request) {
	var p Principal
	var e error
	if s := r.URL.Query().Get("ticket"); s != "" {
		a.ticketsMu.Lock()
		t, ok := a.tickets[hash(s)]
		delete(a.tickets, hash(s))
		a.ticketsMu.Unlock()
		if !ok || time.Now().After(t.Expires) || !a.validSession(t.P) {
			respond(w, 401, map[string]string{"error": "invalid_ticket"})
			return
		}
		p = t.P
	} else {
		p, e = a.authenticate(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		if e != nil {
			respond(w, 401, map[string]string{"error": "unauthorized"})
			return
		}
	}
	up := websocket.Upgrader{ReadBufferSize: 1024, WriteBufferSize: 1024, CheckOrigin: func(r *http.Request) bool {
		return r.Header.Get("Origin") == "" || r.Header.Get("Origin") == a.C.AllowedOrigin
	}}
	ws, e := up.Upgrade(w, r, nil)
	if e != nil {
		return
	}
	c := &connection{ws: ws, p: p, out: make(chan any, 32), wake: make(chan struct{}, 1)}
	if !a.hub.add(c) {
		ws.Close()
		return
	}
	defer func() {
		ws.Close()
		a.hub.remove(c)
		a.DB.Exec("UPDATE users SET last_seen=? WHERE id=?", now(), p.UserID)
		a.presence(p.UserID)
	}()
	a.presence(p.UserID)
	done := make(chan struct{})
	go func() { defer close(done); a.wsRead(c) }()
	defer func() { ws.Close(); <-done }()
	tick := time.NewTicker(300 * time.Millisecond)
	defer tick.Stop()
	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()
	check := time.NewTicker(5 * time.Second)
	defer check.Stop()
	write := func(v any) bool { ws.SetWriteDeadline(time.Now().Add(5 * time.Second)); return ws.WriteJSON(v) == nil }
	if !write(map[string]any{"v": 1, "op": "hello", "device_id": p.DeviceID, "resume_required": true}) {
		return
	}
	drain := func() bool {
		if !c.active.Load() {
			return true
		}
		d, e := a.Difference(p.UserID, c.cursor.Load(), 100)
		if e != nil {
			return false
		}
		for _, ev := range d["events"].([]Event) {
			c.sent.Store(ev.Seq)
			if !write(ev) {
				return false
			}
			c.cursor.Store(ev.Seq)
			c.sent.Store(ev.Seq)
		}
		return true
	}
	for {
		select {
		case <-done:
			return
		case <-a.stop:
			return
		case v := <-c.out:
			if !write(v) {
				return
			}
		case <-heartbeat.C:
			if e := ws.WriteControl(websocket.PingMessage, nil, time.Now().Add(5*time.Second)); e != nil {
				return
			}
		case <-check.C:
			if !a.validSession(p) {
				return
			}
		case <-tick.C:
			if !drain() {
				return
			}
		case <-c.wake:
			if !drain() {
				return
			}
		}
	}
}

type frame struct {
	V        int    `json:"v"`
	Op       string `json:"op"`
	ReqID    string `json:"req_id"`
	ChatID   string `json:"conversation_id"`
	Payload  Send   `json:"payload"`
	ClientID string `json:"client_msg_id"`
	After    int64  `json:"after_event_seq"`
	Ack      int64  `json:"last_persisted_event_seq"`
	Read     int64  `json:"last_read_seq"`
	Typing   bool   `json:"typing"`
}

func (a *App) wsRead(c *connection) {
	c.ws.SetReadLimit(64 << 10)
	c.ws.SetReadDeadline(time.Now().Add(70 * time.Second))
	c.ws.SetPongHandler(func(string) error { return c.ws.SetReadDeadline(time.Now().Add(70 * time.Second)) })
	for {
		var f frame
		if e := c.ws.ReadJSON(&f); e != nil {
			return
		}
		if !a.validSession(c.p) {
			return
		}
		if !a.limiter.allow("ws:"+c.p.UserID, 120, time.Second) {
			return
		}
		if f.V != 1 || len(f.ReqID) > 128 {
			c.enqueue(map[string]any{"v": 1, "op": "error", "req_id": f.ReqID, "error": "invalid_frame"})
			continue
		}
		var e error
		var data any = map[string]bool{"ok": true}
		op := "result"
		switch f.Op {
		case "sync.resume":
			// Resume is permitted once per connection, avoiding cursor/write races.
			if c.active.Load() {
				e = ErrConflict
				break
			}
			var high int64
			e = a.DB.QueryRow("SELECT COALESCE((SELECT seq FROM event_counters WHERE user_id=?),0)", c.p.UserID).Scan(&high)
			if e == nil && (f.After < 0 || f.After > high) {
				e = ErrInvalid
			}
			if e == nil {
				c.cursor.Store(f.After)
				c.sent.Store(f.After)
				c.active.Store(true)
				data = map[string]any{"high_watermark": high, "after_event_seq": f.After}
			}
		case "event.ack":
			if f.Ack < 0 || f.Ack > c.sent.Load() {
				e = ErrInvalid
				break
			}
			_, e = a.DB.Exec("UPDATE devices SET ack=max(ack,?) WHERE id=?", f.Ack, c.p.DeviceID)
		case "message.send":
			if f.ClientID != "" {
				f.Payload.ClientID = f.ClientID
			}
			data, e = a.SendMessage(c.p, f.ChatID, f.Payload)
			op = "message.ack"
		case "read.update":
			e = a.Read(c.p, f.ChatID, f.Read)
		case "typing":
			if !a.isMember(f.ChatID, c.p.UserID) {
				e = ErrForbidden
				break
			}
			if a.limiter.allow("typing:"+c.p.UserID+":"+f.ChatID, 1, 2*time.Second) {
				var users []string
				e = a.transaction(func(tx *sql.Tx) error {
					if e := a.checkBlocked(tx, f.ChatID); e != nil {
						return e
					}
					var e error
					users, e = members(tx, f.ChatID)
					return e
				})
				if e == nil {
					a.hub.broadcast(users, c.p.UserID, map[string]any{"v": 1, "op": "typing", "conversation_id": f.ChatID, "user_id": c.p.UserID, "typing": f.Typing, "expires_in": 5})
				}
			}
		case "ping":
			op = "pong"
		default:
			e = ErrInvalid
		}
		if e != nil {
			code := "invalid_request"
			if errors.Is(e, ErrRateLimited) {
				code = "rate_limited"
			}
			if errors.Is(e, ErrForbidden) {
				code = "forbidden"
			} else if errors.Is(e, ErrConflict) {
				code = "conflict"
			}
			c.enqueue(map[string]any{"v": 1, "op": "error", "req_id": f.ReqID, "error": code})
			continue
		}
		c.enqueue(map[string]any{"v": 1, "op": op, "req_id": f.ReqID, "data": data})
	}
}
func (a *App) presence(uid string) {
	rows, e := a.DB.Query("SELECT DISTINCT b.user_id FROM members a JOIN members b ON b.chat_id=a.chat_id WHERE a.user_id=? AND b.user_id<>? AND NOT EXISTS(SELECT 1 FROM user_blocks x WHERE (x.owner=a.user_id AND x.target=b.user_id) OR (x.owner=b.user_id AND x.target=a.user_id))", uid, uid)
	if e != nil {
		return
	}
	users := []string{}
	for rows.Next() {
		var u string
		if rows.Scan(&u) == nil {
			users = append(users, u)
		}
	}
	rows.Close()
	a.hub.broadcast(users, uid, map[string]any{"v": 1, "op": "presence", "user_id": uid, "online": a.online(uid), "last_seen": now()})
}
