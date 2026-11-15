package chat

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"github.com/gorilla/websocket"
	"image"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

type fixture struct {
	a               *App
	s               *httptest.Server
	admin, bob, eve Principal
	at, bt, et      string
	config          Config
}

func req(t *testing.T, s *httptest.Server, method, path, token string, body any, want int) map[string]any {
	t.Helper()
	var data io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		data = bytes.NewReader(b)
	}
	r, _ := http.NewRequest(method, s.URL+path, data)
	if token != "" {
		r.Header.Set("Authorization", "Bearer "+token)
	}
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	if res.StatusCode != want {
		t.Fatalf("%s %s got %d wanted %d: %s", method, path, res.StatusCode, want, b)
	}
	out := map[string]any{}
	json.Unmarshal(b, &out)
	return out
}
func setup(t *testing.T) *fixture { return setupConfig(t, nil) }
func setupConfig(t *testing.T, configure func(*Config)) *fixture {
	t.Helper()
	c := DefaultConfig()
	c.DataDir = t.TempDir()
	c.AdminHandle = "admin"
	c.AdminPassword = "test-password-long"
	if configure != nil {
		configure(&c)
	}
	a, e := Open(c)
	if e != nil {
		t.Fatal(e)
	}
	s := httptest.NewServer(a.Handler())
	f := &fixture{a: a, s: s, config: c}
	t.Cleanup(func() { s.Close(); a.Close() })
	v := req(t, s, "POST", "/v1/auth/login", "", map[string]any{"handle": "admin", "password": c.AdminPassword, "platform": "test"}, 200)
	f.at = v["access_token"].(string)
	f.admin, _ = a.authenticate(f.at)
	v = req(t, s, "POST", "/v1/invites", f.at, map[string]any{"uses": 2, "expires_hours": 24}, 201)
	code := v["invite_code"].(string)
	for i, name := range []string{"bob", "eve"} {
		v = req(t, s, "POST", "/v1/auth/register", "", map[string]any{"handle": name, "password": "test-password-long", "invite_code": code, "platform": "test"}, 201)
		tok := v["access_token"].(string)
		p, _ := a.authenticate(tok)
		if i == 0 {
			f.bt = tok
			f.bob = p
		} else {
			f.et = tok
			f.eve = p
		}
	}
	return f
}
func direct(t *testing.T, f *fixture) string {
	t.Helper()
	c, e := f.a.CreateChat(f.admin, "direct", "", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	return c
}
func TestInviteAuthAndRevocation(t *testing.T) {
	f := setup(t)
	req(t, f.s, "POST", "/v1/auth/register", "", map[string]any{"handle": "bad", "password": "test-password-long", "invite_code": "bad"}, 403)
	req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "admin", "password": "bad"}, 401)
	req(t, f.s, "POST", "/v1/invites", f.bt, map[string]any{"uses": 1, "expires_hours": 1}, 403)
	req(t, f.s, "PUT", "/v1/devices/current/push", f.bt, map[string]any{"provider": "mipush", "token": "fake-device-id"}, 200)
	req(t, f.s, "DELETE", "/v1/devices/"+f.bob.DeviceID, f.at, nil, 403)
	req(t, f.s, "DELETE", "/v1/devices/"+f.bob.DeviceID, f.bt, nil, 200)
	req(t, f.s, "GET", "/v1/me", f.bt, nil, 401)
	req(t, f.s, "POST", "/v1/auth/logout", f.at, nil, 200)
	req(t, f.s, "GET", "/v1/me", f.at, nil, 401)
}
func TestMessageIdempotencyAndConflict(t *testing.T) {
	f := setup(t)
	c := direct(t, f)
	s := Send{ClientID: "client1", Kind: "text", Text: "你好"}
	m, e := f.a.SendMessage(f.admin, c, s)
	if e != nil {
		t.Fatal(e)
	}
	n, e := f.a.SendMessage(f.admin, c, s)
	if e != nil || m.ID != n.ID || m.Seq != 1 {
		t.Fatalf("not idempotent: %+v %v", n, e)
	}
	s.Text = "different"
	if _, e = f.a.SendMessage(f.admin, c, s); e != ErrConflict {
		t.Fatal(e)
	}
	h, e := f.a.History(f.bob, c, 0, 10)
	if e != nil || len(h) != 1 {
		t.Fatal(h, e)
	}
	if _, e = f.a.SendMessage(f.eve, c, Send{ClientID: "notmember", Text: "no"}); e != ErrForbidden {
		t.Fatal(e)
	}
	other, _ := f.a.CreateChat(f.admin, "direct", "", []string{f.eve.UserID})
	if _, e = f.a.SendMessage(f.admin, other, Send{ClientID: "replycross", Text: "no", ReplyTo: m.ID}); e != ErrInvalid {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/conversations/"+c+"/messages", f.et, nil, 403)
}
func TestConcurrentSeq(t *testing.T) {
	f := setup(t)
	c := direct(t, f)
	var wg sync.WaitGroup
	errs := make(chan error, 40)
	for i := 0; i < 40; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, e := f.a.SendMessage(f.admin, c, Send{ClientID: fmt.Sprint(i), Text: "concurrent"})
			errs <- e
		}(i)
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		if e != nil {
			t.Fatal(e)
		}
	}
	h, e := f.a.History(f.bob, c, 0, 100)
	if e != nil || len(h) != 40 {
		t.Fatal(len(h), e)
	}
	for i, m := range h {
		if m.Seq != int64(40-i) {
			t.Fatal("sequence gap")
		}
	}
}
func TestEditDeleteReplyReactionsRead(t *testing.T) {
	f := setup(t)
	c := direct(t, f)
	m, e := f.a.SendMessage(f.admin, c, Send{ClientID: "a", Text: "hello"})
	if e != nil {
		t.Fatal(e)
	}
	if e = f.a.AlterMessage(f.bob, m.ID, "edit", "attack"); e != ErrForbidden {
		t.Fatal(e)
	}
	if e = f.a.AlterMessage(f.admin, m.ID, "edit", "edited"); e != nil {
		t.Fatal(e)
	}
	if e = f.a.React(f.bob, m.ID, "👍", false); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/messages/"+m.ID+"/reactions", f.bt, nil, 200)
	if e = f.a.React(f.bob, m.ID, "👍", true); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/conversations", f.bt, nil, 200)
	if e = f.a.Read(f.bob, c, 1); e != nil {
		t.Fatal(e)
	}
	f.a.Read(f.bob, c, 0)
	var read int64
	f.a.DB.QueryRow("SELECT read_seq FROM members WHERE chat_id=? AND user_id=?", c, f.bob.UserID).Scan(&read)
	if read != 1 {
		t.Fatal(read)
	}
	if e = f.a.Read(f.bob, c, 2); e != ErrInvalid {
		t.Fatal(e)
	}
	if e = f.a.AlterMessage(f.admin, m.ID, "delete", ""); e != nil {
		t.Fatal(e)
	}
	h, _ := f.a.History(f.bob, c, 0, 10)
	if !h[0].Deleted || h[0].Text != "" {
		t.Fatal(h)
	}
	d, _ := f.a.Difference(f.bob.UserID, 0, 200)
	if len(d["events"].([]Event)) < 6 {
		t.Fatal(d)
	}
}
func TestGroupPermissionsHistoryBoundary(t *testing.T) {
	f := setup(t)
	c, e := f.a.CreateChat(f.admin, "group", "小群", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+c, f.at, map[string]any{"permissions": map[string]any{"can_invite_users": false}}, 200)
	old, _ := f.a.SendMessage(f.admin, c, Send{ClientID: "old", Text: "before"})
	if e = f.a.ChangeMember(f.bob, c, f.eve.UserID, "add", ""); e != ErrForbidden {
		t.Fatal(e)
	}
	if e = f.a.ChangeMember(f.admin, c, f.eve.UserID, "add", ""); e != nil {
		t.Fatal(e)
	}
	h, _ := f.a.History(f.eve, c, 0, 100)
	if len(h) != 0 {
		t.Fatal("history leaked")
	}
	if e = f.a.React(f.eve, old.ID, "x", false); e != ErrForbidden {
		t.Fatal(e)
	}
	f.a.SendMessage(f.admin, c, Send{ClientID: "new", Text: "after"})
	h, _ = f.a.History(f.eve, c, 0, 100)
	if len(h) != 1 {
		t.Fatal(h)
	}
	if e = f.a.ChangeMember(f.admin, c, f.bob.UserID, "role", "admin"); e != nil {
		t.Fatal(e)
	}
	if e = f.a.ChangeMember(f.bob, c, f.admin.UserID, "remove", ""); e != ErrForbidden {
		t.Fatal(e)
	}
	if e = f.a.ChangeMember(f.admin, c, f.eve.UserID, "remove", ""); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/conversations/"+c+"/members", f.et, nil, 403)
	if _, e = f.a.SendMessage(f.eve, c, Send{ClientID: "gone", Text: "x"}); e != ErrForbidden {
		t.Fatal(e)
	}
}
func uploadReq(t *testing.T, f *fixture, tok, cid string, data []byte, want int) map[string]any {
	t.Helper()
	r, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(data))
	r.Header.Set("Authorization", "Bearer "+tok)
	r.Header.Set("X-Conversation-ID", cid)
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	if res.StatusCode != want {
		t.Fatalf("upload got %d want %d %s", res.StatusCode, want, b)
	}
	m := map[string]any{}
	json.Unmarshal(b, &m)
	return m
}
func TestMediaAuthQuotaAndTombstone(t *testing.T) {
	f := setup(t)
	c := direct(t, f)
	var b bytes.Buffer
	png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 2, 2)))
	v := uploadReq(t, f, f.at, c, b.Bytes(), 201)
	mid := v["id"].(string)
	req(t, f.s, "GET", "/v1/media/"+mid, f.bt, nil, 403)
	req(t, f.s, "GET", "/v1/media/"+mid, f.et, nil, 403)
	m, e := f.a.SendMessage(f.admin, c, Send{ClientID: "pic", Kind: "image", MediaID: mid})
	if e != nil {
		t.Fatal(e)
	}
	r, _ := http.NewRequest("GET", f.s.URL+"/v1/media/"+mid, nil)
	r.Header.Set("Authorization", "Bearer "+f.bt)
	r.Header.Set("Range", "bytes=0-9")
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	io.Copy(io.Discard, res.Body)
	res.Body.Close()
	if res.StatusCode != 206 {
		t.Fatal(res.StatusCode)
	}
	req(t, f.s, "DELETE", "/v1/media/"+mid, f.at, nil, 409)
	f.a.AlterMessage(f.admin, m.ID, "delete", "")
	req(t, f.s, "GET", "/v1/media/"+mid, f.bt, nil, 403)
	req(t, f.s, "DELETE", "/v1/media/"+mid, f.at, nil, 200)
	f.a.C.MaxFile = 16
	uploadReq(t, f, f.at, c, bytes.Repeat([]byte{0}, 30), 413)
	f.a.C.MaxFile = 1024
	f.a.C.MediaQuota = 20
	uploadReq(t, f, f.at, c, bytes.Repeat([]byte{0}, 30), 413)
	uploadReq(t, f, f.et, c, []byte("x"), 403)
	uploadReq(t, f, f.at, c, []byte("<html>bad</html>"), 400)
}
func TestAvatarProfileAndSearch(t *testing.T) {
	f := setup(t)
	var b bytes.Buffer
	png.Encode(&b, image.NewRGBA(image.Rect(0, 0, 1, 1)))
	v := uploadReq(t, f, f.at, "", b.Bytes(), 201)
	mid := v["id"].(string)
	req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"display_name": "管理员", "avatar_media_id": mid}, 200)
	req(t, f.s, "GET", "/v1/users?q=ad", f.bt, nil, 200)
	req(t, f.s, "GET", "/v1/media/"+mid, f.bt, nil, 200)
	req(t, f.s, "PATCH", "/v1/me", f.bt, map[string]any{"display_name": "bad", "avatar_media_id": mid}, 403)
}
func TestProfileAvatarVideoMIME(t *testing.T) {
	f := setup(t)
	mp4 := []byte{0, 0, 0, 24, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm', 0, 0, 0, 0, 'i', 's', 'o', 'm', 'm', 'p', '4', '2'}
	v := uploadReq(t, f, f.at, "", mp4, 201)
	if v["mime"] != "video/mp4" {
		t.Fatalf("upload mime %v", v["mime"])
	}
	mid := v["id"].(string)
	me := req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"display_name": "管理员", "avatar_media_id": mid}, 200)
	if me["avatar_media_id"] != mid {
		t.Fatalf("avatar id %v", me["avatar_media_id"])
	}
	if me["avatar_mime"] != "video/mp4" {
		t.Fatalf("avatar mime %v", me["avatar_mime"])
	}
	got := req(t, f.s, "GET", "/v1/users/"+f.admin.UserID, f.bt, nil, 200)
	if got["avatar_mime"] != "video/mp4" {
		t.Fatalf("peer mime %v", got["avatar_mime"])
	}
	webm := []byte{0x1A, 0x45, 0xDF, 0xA3, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1F, 0x42, 0x86, 0x81, 0x01}
	wv := uploadReq(t, f, f.at, "", webm, 201)
	if wv["mime"] != "video/webm" {
		t.Fatalf("webm mime %v", wv["mime"])
	}
	req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"display_name": "管理员", "avatar_media_id": wv["id"]}, 200)
	doc := append([]byte("%PDF-1.4\n"), bytes.Repeat([]byte{1}, 32)...)
	dv := uploadReq(t, f, f.at, "", doc, 201)
	req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"display_name": "管理员", "avatar_media_id": dv["id"]}, 403)
}

func dial(t *testing.T, f *fixture, token string) *websocket.Conn {
	t.Helper()
	h := http.Header{}
	h.Set("Authorization", "Bearer "+token)
	c, _, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(f.s.URL, "http")+"/v1/ws", h)
	if e != nil {
		t.Fatal(e)
	}
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	var v map[string]any
	if e = c.ReadJSON(&v); e != nil || v["op"] != "hello" {
		t.Fatal(v, e)
	}
	return c
}
func until(t *testing.T, c *websocket.Conn, op string) map[string]any {
	t.Helper()
	for i := 0; i < 30; i++ {
		var v map[string]any
		if e := c.ReadJSON(&v); e != nil {
			t.Fatal(e)
		}
		if v["op"] == op {
			return v
		}
	}
	t.Fatal("op not seen", op)
	return nil
}
func TestWSResumeAckAndRealtime(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	c := dial(t, f, f.bt)
	defer c.Close()
	c.WriteJSON(map[string]any{"v": 1, "op": "sync.resume", "req_id": "resume", "after_event_seq": 0})
	until(t, c, "result")
	f.a.SendMessage(f.admin, cid, Send{ClientID: "ws1", Text: "live"})
	var last int64
	for i := 0; i < 2; i++ {
		v := until(t, c, "event")
		last = int64(v["event_seq"].(float64))
	}
	c.WriteJSON(map[string]any{"v": 1, "op": "event.ack", "last_persisted_event_seq": last})
	until(t, c, "result")
	var ack int64
	f.a.DB.QueryRow("SELECT ack FROM devices WHERE id=?", f.bob.DeviceID).Scan(&ack)
	if ack != last {
		t.Fatal(ack, last)
	}
	c.WriteJSON(map[string]any{"v": 1, "op": "event.ack", "last_persisted_event_seq": last + 100})
	until(t, c, "error")
	c.WriteJSON(map[string]any{"v": 1, "op": "message.send", "req_id": "send", "conversation_id": cid, "client_msg_id": "clientWS", "payload": map[string]any{"kind": "text", "text": "reply"}})
	v := until(t, c, "message.ack")
	if v["data"].(map[string]any)["conversation_seq"].(float64) != 2 {
		t.Fatal(v)
	}
	c.Close()
	d, e := f.a.Difference(f.bob.UserID, last, 100)
	if e != nil {
		t.Fatal(e)
	}
	messageEvents := 0
	for _, ev := range d["events"].([]Event) {
		if ev.Type == "message.created" {
			messageEvents++
		}
	}
	if messageEvents != 1 {
		t.Fatal(d)
	}
}
func TestWSTicketsOriginAndRevocation(t *testing.T) {
	f := setup(t)
	v := req(t, f.s, "POST", "/v1/ws-ticket", f.at, nil, 200)
	url := "ws" + strings.TrimPrefix(f.s.URL, "http") + "/v1/ws?ticket=" + v["ticket"].(string)
	c, _, e := websocket.DefaultDialer.Dial(url, nil)
	if e != nil {
		t.Fatal(e)
	}
	defer c.Close()
	c.SetReadDeadline(time.Now().Add(2 * time.Second))
	var hello map[string]any
	c.ReadJSON(&hello)
	if _, res, e := websocket.DefaultDialer.Dial(url, nil); e == nil || res.StatusCode != 401 {
		t.Fatal("ticket reused")
	}
	h := http.Header{"Origin": []string{"https://evil.example"}, "Authorization": []string{"Bearer " + f.at}}
	if _, res, e := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(f.s.URL, "http")+"/v1/ws", h); e == nil || res.StatusCode != 403 {
		t.Fatal("origin accepted")
	}
	req(t, f.s, "DELETE", "/v1/devices/"+f.admin.DeviceID, f.at, nil, 200)
	if e = c.ReadJSON(&hello); e == nil {
		t.Fatal("revoked socket stayed open")
	}
}
func TestRestartPersistence(t *testing.T) {
	c := DefaultConfig()
	c.DataDir = t.TempDir()
	c.AdminHandle = "admin"
	c.AdminPassword = "test-password-long"
	a, e := Open(c)
	if e != nil {
		t.Fatal(e)
	}
	var uid string
	a.DB.QueryRow("SELECT id FROM users WHERE handle='admin'").Scan(&uid)
	e = a.transaction(func(tx *sql.Tx) error {
		return emit(tx, []string{uid}, "test", "", map[string]string{"text": "persistent"})
	})
	if e != nil {
		t.Fatal(e)
	}
	a.Close()
	a, e = Open(c)
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	d, e := a.Difference(uid, 0, 100)
	if e != nil || len(d["events"].([]Event)) != 1 {
		t.Fatal(d, e)
	}
}
func TestXiaomiHTTPContract(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		r.ParseForm()
		if r.Header.Get("Authorization") != "key=fake" || r.Form.Get("registration_id") != "reg" || r.Form.Get("restricted_package_name") != "pkg" {
			t.Error("push contract mismatch")
		}
		io.WriteString(w, `{"code":0,"result":"ok"}`)
	}))
	defer server.Close()
	x := XiaomiPush{Secret: "fake", Package: "pkg", Endpoint: server.URL}
	if e := x.Send(context.Background(), "reg", "chat", "01234567890123456789012345678901"); e != nil {
		t.Fatal(e)
	}
	x.Secret = ""
	if e := x.Send(context.Background(), "reg", "chat", "message"); e == nil {
		t.Fatal("missing credentials not rejected")
	}
}
func TestInviteSingleUseConcurrent(t *testing.T) {
	f := setup(t)
	v := req(t, f.s, "POST", "/v1/invites", f.at, map[string]any{"uses": 1, "expires_hours": 1}, 201)
	var wg sync.WaitGroup
	status := make(chan int, 2)
	for _, name := range []string{"one", "two"} {
		wg.Add(1)
		go func(name string) {
			defer wg.Done()
			b, _ := json.Marshal(map[string]any{"handle": name, "password": "test-password-long", "invite_code": v["invite_code"]})
			res, e := http.Post(f.s.URL+"/v1/auth/register", "application/json", bytes.NewReader(b))
			if e != nil {
				status <- 0
				return
			}
			io.Copy(io.Discard, res.Body)
			res.Body.Close()
			status <- res.StatusCode
		}(name)
	}
	wg.Wait()
	close(status)
	success := 0
	for s := range status {
		if s == 201 {
			success++
		} else if s != 403 {
			t.Fatalf("unexpected %d", s)
		}
	}
	if success != 1 {
		t.Fatal(success)
	}
}

func TestOfflinePaginationAndMessageRestart(t *testing.T) {
	c := DefaultConfig()
	c.DataDir = t.TempDir()
	c.AdminHandle = "admin"
	c.AdminPassword = "test-password-long"
	a, e := Open(c)
	if e != nil {
		t.Fatal(e)
	}
	var uid string
	a.DB.QueryRow("SELECT id FROM users WHERE handle='admin'").Scan(&uid)
	bob := id()
	_, e = a.DB.Exec("INSERT INTO users(id,handle,name,password,last_seen) VALUES(?,?,?,?,?)", bob, "reader", "reader", "not-a-login-hash", now())
	if e != nil {
		t.Fatal(e)
	}
	p := Principal{UserID: uid}
	cid, e := a.CreateChat(p, "direct", "", []string{bob})
	if e != nil {
		t.Fatal(e)
	}
	first, e := a.SendMessage(p, cid, Send{ClientID: "persisted", Text: "first"})
	if e != nil {
		t.Fatal(e)
	}
	reply, e := a.SendMessage(Principal{UserID: bob}, cid, Send{ClientID: "reply", Text: "reply", ReplyTo: first.ID})
	if e != nil || reply.ReplyTo != first.ID {
		t.Fatal(reply, e)
	}
	d, e := a.Difference(bob, 0, 2)
	if e != nil || !d["has_more"].(bool) || d["next_cursor"].(int64) != 2 {
		t.Fatal(d, e)
	}
	if e = a.Close(); e != nil {
		t.Fatal(e)
	}
	a, e = Open(c)
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	retry, e := a.SendMessage(p, cid, Send{ClientID: "persisted", Text: "first"})
	if e != nil || retry.ID != first.ID || retry.Seq != 1 {
		t.Fatal(retry, e)
	}
	h, e := a.History(Principal{UserID: bob}, cid, 0, 10)
	if e != nil || len(h) != 2 {
		t.Fatal(h, e)
	}
	d, e = a.Difference(bob, 2, 200)
	if e != nil || d["has_more"].(bool) || len(d["events"].([]Event)) != 3 {
		t.Fatal(d, e)
	}
	if _, e = a.Difference(bob, 10000, 2); e != ErrInvalid {
		t.Fatal(e)
	}
}

func TestRESTMessageLifecycleAndGroupRoles(t *testing.T) {
	f := setup(t)
	v := req(t, f.s, "POST", "/v1/conversations", f.at, map[string]any{"kind": "group", "title": "API group", "member_ids": []string{f.bob.UserID}}, 201)
	cid := v["id"].(string)
	v = req(t, f.s, "POST", "/v1/conversations/"+cid+"/messages", f.bt, map[string]any{"client_msg_id": "api", "kind": "text", "text": "from API"}, 200)
	mid := v["id"].(string)
	req(t, f.s, "PATCH", "/v1/messages/"+mid, f.bt, map[string]any{"text": "updated"}, 200)
	req(t, f.s, "PUT", "/v1/messages/"+mid+"/reactions", f.at, map[string]any{"emoji": "🔥", "remove": false}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/read", f.at, map[string]any{"last_read_seq": 1}, 200)
	req(t, f.s, "GET", "/v1/sync?after=0&limit=2", f.bt, nil, 200)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/members", f.at, map[string]any{"user_id": f.eve.UserID, "action": "add"}, 200)
	req(t, f.s, "GET", "/v1/conversations/"+cid+"/members", f.et, nil, 200)
	req(t, f.s, "DELETE", "/v1/messages/"+mid, f.et, nil, 403)
	req(t, f.s, "DELETE", "/v1/messages/"+mid, f.at, nil, 200)
	req(t, f.s, "GET", "/v1/devices", f.bt, nil, 200)
	req(t, f.s, "GET", "/v1/users/"+f.admin.UserID, f.bt, nil, 200)
}

func TestVoiceFileAndPushJobDurability(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	// OggS signature is enough for MIME detection; this is not a codec/decode test.
	b := append([]byte("OggS\x00"), bytes.Repeat([]byte{0}, 80)...)
	media := uploadReq(t, f, f.at, cid, b, 201)
	if _, e := f.a.SendMessage(f.admin, cid, Send{ClientID: "voice", Kind: "voice", MediaID: media["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	media = uploadReq(t, f, f.at, cid, []byte("plain file content"), 201)
	if _, e := f.a.SendMessage(f.admin, cid, Send{ClientID: "file", Kind: "file", MediaID: media["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	f.a.DB.Exec("UPDATE devices SET push_provider='mipush',push_token='test-regid' WHERE id=?", f.bob.DeviceID)
	f.a.processPush()
	var n int
	if e := f.a.DB.QueryRow("SELECT count(*) FROM push_jobs WHERE user_id=? AND done=0 AND last_error='mipush_not_configured'", f.bob.UserID).Scan(&n); e != nil || n != 1 {
		t.Fatal(n, e)
	}
}
