package chat

import (
	"context"
	"database/sql"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestEntitiesUTF16OverlapAndURL(t *testing.T) {
	text := "a😀hello"
	good := []Entity{{Type: "bold", Offset: 1, Length: 7}, {Type: "italic", Offset: 3, Length: 5}}
	if _, e := validateEntities(text, good); e != nil {
		t.Fatal(e)
	}
	bad := [][]Entity{{{Type: "bold", Offset: 2, Length: 1}}, {{Type: "bold", Offset: 0, Length: 99}}, {{Type: "bold", Offset: 0, Length: 4}, {Type: "italic", Offset: 3, Length: 5}}, {{Type: "code", Offset: 3, Length: 5}, {Type: "bold", Offset: 3, Length: 5}}, {{Type: "text_link", Offset: 3, Length: 5, URL: "javascript:alert(1)"}}, {{Type: "custom_emoji", Offset: 1, Length: 2}}, {{Type: "madeup", Offset: 0, Length: 1}}}
	for i, v := range bad {
		if _, e := validateEntities(text, v); e == nil {
			t.Fatal("accepted bad entities", i)
		}
	}
	if _, e := validateEntities("https://example.com", []Entity{{Type: "url", Offset: 0, Length: 19}}); e != nil {
		t.Fatal(e)
	}
}
func TestRichTextMarkupPersistenceAndCallbackStub(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	s := Send{ClientID: "rich", Text: "hello 😀", Entities: []Entity{{Type: "bold", Offset: 0, Length: 5}, {Type: "custom_emoji", Offset: 6, Length: 2, CustomEmojiID: "reserved"}}, ReplyMarkup: &ReplyMarkup{[][]InlineButton{{{Text: "网页", URL: "https://example.com"}, {Text: "回调", CallbackData: "go"}}}}}
	m, e := f.a.SendMessage(f.admin, cid, s)
	if e != nil {
		t.Fatal(e)
	}
	h, e := f.a.History(f.bob, cid, 0, 10)
	if e != nil || len(h[0].Entities) != 2 || h[0].ReplyMarkup == nil {
		t.Fatal(h, e)
	}
	req(t, f.s, "POST", "/v1/messages/"+m.ID+"/callback", f.bt, map[string]any{"callback_data": "go"}, 501)
	req(t, f.s, "POST", "/v1/messages/"+m.ID+"/callback", f.et, map[string]any{"callback_data": "go"}, 403)
	bad := &ReplyMarkup{[][]InlineButton{{{Text: "both", URL: "https://example.com", CallbackData: "x"}}}}
	if validateMarkup(bad) == nil {
		t.Fatal("button two actions accepted")
	}
	bad = &ReplyMarkup{[][]InlineButton{{{Text: "too long", CallbackData: strings.Repeat("字", 22)}}}}
	if validateMarkup(bad) == nil {
		t.Fatal("callback byte limit")
	}
	s.ClientID = "impersonate"
	s.ViaBotID = f.bob.UserID
	if _, e = f.a.SendMessage(f.admin, cid, s); e != ErrForbidden {
		t.Fatal(e)
	}
}
func TestPreviewSSRFAndMetadata(t *testing.T) {
	for _, raw := range []string{"http://127.0.0.1/", "http://[::1]/", "http://169.254.169.254/", "http://10.0.0.1/", "http://192.168.1.1/", "http://[::ffff:127.0.0.1]/", "http://localhost/", "http://100.64.0.1/", "http://8.8.8.8:8080/", "file:///etc/passwd", "https://user:pass@example.com/"} {
		if _, e := previewURL(raw); e == nil {
			t.Fatal("URL accepted", raw)
		}
	}
	for _, ip := range []string{"127.0.0.1", "10.2.2.2", "169.254.1.1", "::1", "fc00::1", "2001:db8::1", "198.18.0.1", "240.0.0.1"} {
		if publicIP(net.ParseIP(ip)) {
			t.Fatal(ip)
		}
	}
	if !publicIP(net.ParseIP("8.8.8.8")) {
		t.Fatal("public blocked")
	}
	client := previewClient()
	if e := client.CheckRedirect(&http.Request{URL: mustURL(t, "http://127.0.0.1/")}, []*http.Request{{}}); e == nil {
		t.Fatal("redirect private")
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if _, e := client.Transport.(*http.Transport).DialContext(ctx, "tcp", "127.0.0.1:80"); e == nil {
		t.Fatal("dial private")
	}
	p, e := parsePreview("https://example.com/page", strings.NewReader(`<html><title>fallback</title><meta property="og:title" content="Test &amp; title"><meta property="og:description" content="description"><meta property="og:image" content="/a.jpg"></html>`))
	if e != nil || p.Title != "Test & title" || p.Image != "https://example.com/a.jpg" {
		t.Fatal(p, e)
	}
}
func mustURL(t *testing.T, s string) *url.URL {
	t.Helper()
	u, e := url.Parse(s)
	if e != nil {
		t.Fatal(e)
	}
	return u
}
func TestPreviewCacheAndAttachment(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	pid := id()
	f.a.DB.Exec("INSERT INTO link_previews(id,url,title,description,image,site_name,fetched_at) VALUES(?,?,?,?,?,?,?)", pid, "https://example.com/", "Example", "desc", "", "site", time.Now().Unix())
	v := req(t, f.s, "POST", "/v1/link-previews", f.bt, map[string]any{"url": "https://example.com/"}, 200)
	if v["id"] != pid {
		t.Fatal(v)
	}
	m, e := f.a.SendMessage(f.admin, cid, Send{ClientID: "preview", Text: "https://example.com/", LinkPreviewID: pid})
	if e != nil || m.LinkPreview == nil {
		t.Fatal(m, e)
	}
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: "wrongpreview", Text: "unrelated", LinkPreviewID: pid}); e != ErrInvalid {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/link-previews", f.bt, map[string]any{"url": "http://127.0.0.1/"}, 403)
}
func TestMultiplePinsAndPollStubs(t *testing.T) {
	f := setup(t)
	cid, _ := f.a.CreateChat(f.admin, "group", "pins", []string{f.bob.UserID})
	for i := 0; i < 2; i++ {
		m, e := f.a.SendMessage(f.admin, cid, Send{ClientID: fmt.Sprint("pin", i), Text: "pinned"})
		if e != nil {
			t.Fatal(e)
		}
		req(t, f.s, "PUT", "/v1/conversations/"+cid+"/pins", f.bt, map[string]any{"message_id": m.ID}, 403)
		req(t, f.s, "PUT", "/v1/conversations/"+cid+"/pins", f.at, map[string]any{"message_id": m.ID}, 200)
	}
	v := req(t, f.s, "GET", "/v1/conversations/"+cid+"/pins", f.bt, nil, 200)
	if len(v["messages"].([]any)) != 2 {
		t.Fatal(v)
	}
	mid := v["messages"].([]any)[0].(map[string]any)["id"].(string)
	req(t, f.s, "PUT", "/v1/conversations/"+cid+"/pins", f.at, map[string]any{"message_id": mid, "remove": true}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/polls", f.bt, map[string]any{"question": "Which?", "options": []string{"A", "B"}, "anonymous": true, "client_msg_id": "poll1"}, 501)
	correct := 0
	if validatePoll(PollSpec{Question: "Quiz", Options: []string{"A", "B"}, Quiz: true, Multiple: true, CorrectOption: &correct, ClientID: "x"}) == nil {
		t.Fatal("multi quiz accepted")
	}
	var n int
	f.a.DB.QueryRow("SELECT count(*) FROM polls").Scan(&n)
	if n != 0 {
		t.Fatal("stub created fake poll")
	}
}
func TestModerationRestrictionsMuteBanAndAudit(t *testing.T) {
	f := setup(t)
	cid, _ := f.a.CreateChat(f.admin, "group", "moderation", []string{f.bob.UserID})
	cfg := map[string]any{"new_member_hours": 24, "user_rate_per_min": 120, "chat_rate_per_min": 300, "keywords": []string{"spamword"}}
	req(t, f.s, "PUT", "/v1/conversations/"+cid+"/settings", f.bt, cfg, 403)
	req(t, f.s, "PUT", "/v1/conversations/"+cid+"/settings", f.at, cfg, 200)
	for i, s := range []Send{{Text: "https://example.com"}, {Text: "spamword"}, {Text: "button", ReplyMarkup: &ReplyMarkup{[][]InlineButton{{{Text: "x", URL: "https://example.com"}}}}}} {
		s.ClientID = fmt.Sprint(i)
		if _, e := f.a.SendMessage(f.bob, cid, s); e != ErrForbidden {
			t.Fatal(s, e)
		}
	}
	uploadReq(t, f, f.bt, cid, []byte("blocked media"), 403)
	m, e := f.a.SendMessage(f.bob, cid, Send{ClientID: "safe", Text: "normal text"})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/moderation", f.at, map[string]any{"action": "mute", "user_id": f.bob.UserID, "duration_minutes": 5}, 200)
	if _, e = f.a.SendMessage(f.bob, cid, Send{ClientID: "muted", Text: "no"}); e != ErrForbidden {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/moderation", f.at, map[string]any{"action": "unmute", "user_id": f.bob.UserID}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/moderation", f.at, map[string]any{"action": "delete_all", "user_id": f.bob.UserID}, 200)
	h, _ := f.a.History(f.admin, cid, 0, 20)
	if h[0].ID != m.ID || !h[0].Deleted {
		t.Fatal(h)
	}
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/moderation", f.at, map[string]any{"action": "ban", "user_id": f.bob.UserID}, 200)
	if e = f.a.ChangeMember(f.admin, cid, f.bob.UserID, "add", ""); e != ErrForbidden {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/moderation", f.at, map[string]any{"action": "unban", "user_id": f.bob.UserID}, 200)
	if e = f.a.ChangeMember(f.admin, cid, f.bob.UserID, "add", ""); e != nil {
		t.Fatal(e)
	}
	v := req(t, f.s, "GET", "/v1/conversations/"+cid+"/audit", f.at, nil, 200)
	if len(v["audit"].([]any)) < 6 {
		t.Fatal(v)
	}
	req(t, f.s, "GET", "/v1/conversations/"+cid+"/audit", f.bt, nil, 403)
}
func TestPerMemberAndChatRateLimit(t *testing.T) {
	f := setup(t)
	cid, _ := f.a.CreateChat(f.admin, "group", "rates", []string{f.bob.UserID})
	req(t, f.s, "PUT", "/v1/conversations/"+cid+"/settings", f.at, map[string]any{"new_member_hours": 0, "user_rate_per_min": 2, "chat_rate_per_min": 3, "keywords": []string{}}, 200)
	s := Send{ClientID: "one", Text: "one"}
	if _, e := f.a.SendMessage(f.bob, cid, s); e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 5; i++ {
		if _, e := f.a.SendMessage(f.bob, cid, s); e != nil {
			t.Fatal("idempotent consumed rate", e)
		}
	}
	f.a.SendMessage(f.bob, cid, Send{ClientID: "two", Text: "two"})
	if _, e := f.a.SendMessage(f.bob, cid, Send{ClientID: "three", Text: "three"}); e != ErrRateLimited {
		t.Fatal(e)
	}
	f.a.SendMessage(f.admin, cid, Send{ClientID: "admin1", Text: "admin"})
	if _, e := f.a.SendMessage(f.admin, cid, Send{ClientID: "admin2", Text: "over chat limit"}); e != ErrRateLimited {
		t.Fatal(e)
	}
}
func dialog(t *testing.T, f *fixture, token, cid string) map[string]any {
	t.Helper()
	v := req(t, f.s, "GET", "/v1/conversations?archived=all", token, nil, 200)
	for _, raw := range v["conversations"].([]any) {
		d := raw.(map[string]any)
		if d["id"] == cid {
			return d
		}
	}
	t.Fatal("dialog missing", cid)
	return nil
}
func TestDialogsFoldersMuteDraftAndMentions(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	other, _ := f.a.CreateChat(f.bob, "direct", "", []string{f.eve.UserID})
	f.a.SendMessage(f.admin, cid, Send{ClientID: "mention", Text: "hello @bob"})
	d := dialog(t, f, f.bt, cid)
	if d["unread_count"].(float64) != 1 || d["unread_mention_count"].(float64) != 1 {
		t.Fatal(d)
	}
	v := req(t, f.s, "POST", "/v1/folders", f.bt, map[string]any{"name": "unread", "filter": map[string]any{"types": []string{"direct"}, "unread_only": true}}, 200)
	fid := v["id"].(string)
	v = req(t, f.s, "GET", "/v1/folders", f.bt, nil, 200)
	if v["folders"].([]any)[0].(map[string]any)["unread_count"].(float64) != 1 {
		t.Fatal(v)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+cid+"/state", f.bt, map[string]any{"mute_until": "forever", "archived": true, "pinned_order": 1, "draft": map[string]any{"text": "draft", "entities": []Entity{{Type: "bold", Offset: 0, Length: 5}}}}, 200)
	v = req(t, f.s, "GET", "/v1/conversations", f.bt, nil, 200)
	if v["total_unread_badge"].(float64) != 0 {
		t.Fatal(v)
	}
	d = dialog(t, f, f.bt, cid)
	if d["draft"].(map[string]any)["text"] != "draft" || d["pinned_order"].(float64) != 1 {
		t.Fatal(d)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+cid+"/state", f.bt, map[string]any{"mute_until": "", "mark_unread": false}, 200)
	d = dialog(t, f, f.bt, cid)
	if d["unread_count"].(float64) != 0 {
		t.Fatal(d)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+cid+"/state", f.bt, map[string]any{"mark_unread": true}, 200)
	v = req(t, f.s, "GET", "/v1/conversations?archived=all&limit=1", f.bt, nil, 200)
	if v["total_unread_badge"].(float64) != 1 || v["conversations"].([]any)[0].(map[string]any)["id"] != cid || !v["has_more"].(bool) {
		t.Fatal(v)
	}
	cursor := v["next_cursor"].(string)
	v = req(t, f.s, "GET", "/v1/conversations?archived=all&limit=1&cursor="+cursor, f.bt, nil, 200)
	if v["conversations"].([]any)[0].(map[string]any)["id"] != other {
		t.Fatal(v)
	}
	req(t, f.s, "GET", "/v1/conversations?folder_id="+fid, f.at, nil, 200)
	req(t, f.s, "PATCH", "/v1/folders/"+fid, f.at, map[string]any{"name": "steal", "filter": map[string]any{}}, 403)
	req(t, f.s, "DELETE", "/v1/folders/"+fid, f.bt, nil, 200)
}
func lastSeq(t *testing.T, a *App, u string) int64 {
	t.Helper()
	var n int64
	a.DB.QueryRow("SELECT COALESCE((SELECT seq FROM event_counters WHERE user_id=?),0)", u).Scan(&n)
	return n
}
func hasReadEvent(t *testing.T, a *App, u string, after int64) bool {
	t.Helper()
	d, e := a.Difference(u, after, 200)
	if e != nil {
		t.Fatal(e)
	}
	for _, ev := range d["events"].([]Event) {
		if ev.Type == "read.updated" {
			return true
		}
	}
	return false
}
func TestReadReceiptPrivacyGlobalAndReciprocal(t *testing.T) {
	for _, mode := range []string{"on", "global_off", "reader_off", "sender_off"} {
		t.Run(mode, func(t *testing.T) {
			f := setup(t)
			cid := direct(t, f)
			if mode == "global_off" {
				f.a.C.ReadReceiptsEnabled = false
			}
			if mode == "reader_off" {
				req(t, f.s, "PUT", "/v1/me/privacy", f.bt, map[string]any{"read_receipts_enabled": false}, 200)
			}
			if mode == "sender_off" {
				req(t, f.s, "PUT", "/v1/me/privacy", f.at, map[string]any{"read_receipts_enabled": false}, 200)
			}
			f.a.SendMessage(f.admin, cid, Send{ClientID: "privacy", Text: "read me"})
			cursor := lastSeq(t, f.a, f.admin.UserID)
			if e := f.a.Read(f.bob, cid, 1); e != nil {
				t.Fatal(e)
			}
			visible := mode == "on"
			if hasReadEvent(t, f.a, f.admin.UserID, cursor) != visible {
				t.Fatal("privacy event leaked", mode)
			}
			d := dialog(t, f, f.at, cid)
			if visible {
				if d["last_message_read_count"].(float64) != 1 {
					t.Fatal(d)
				}
			} else if mode == "reader_off" {
				if d["last_message_read_count"].(float64) != 0 {
					t.Fatal(d)
				}
			} else if d["last_message_read_count"] != nil {
				t.Fatal(d)
			}
			if dialog(t, f, f.bt, cid)["last_read_seq"].(float64) != 1 {
				t.Fatal("own read position lost")
			}
			v := req(t, f.s, "GET", "/v1/conversations/"+cid+"/members", f.at, nil, 200)
			for _, m := range v["members"].([]any) {
				x := m.(map[string]any)
				if x["user_id"] == f.bob.UserID && !visible && x["last_read_seq"] != nil {
					t.Fatal("member read leaked")
				}
			}
		})
	}
}
func TestGroupReadByCountAndMutedPush(t *testing.T) {
	f := setup(t)
	cid, _ := f.a.CreateChat(f.admin, "group", "reads", []string{f.bob.UserID, f.eve.UserID})
	f.a.SendMessage(f.admin, cid, Send{ClientID: "readgroup", Text: "group"})
	f.a.Read(f.bob, cid, 1)
	f.a.Read(f.eve, cid, 1)
	d := dialog(t, f, f.at, cid)
	if d["last_message_read_count"].(float64) != 2 {
		t.Fatal(d)
	}
	req(t, f.s, "PUT", "/v1/me/privacy", f.et, map[string]any{"read_receipts_enabled": false}, 200)
	d = dialog(t, f, f.at, cid)
	if d["last_message_read_count"].(float64) != 1 {
		t.Fatal(d)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+cid+"/state", f.bt, map[string]any{"mute_until": "forever"}, 200)
	f.a.SendMessage(f.admin, cid, Send{ClientID: "mutedpush", Text: "do not notify bob"})
	f.a.processPush()
	var pending int
	f.a.DB.QueryRow("SELECT count(*) FROM push_jobs WHERE user_id=? AND done=0", f.bob.UserID).Scan(&pending)
	if pending != 0 {
		t.Fatal("muted push pending", pending)
	}
}
func TestStateMigrationFromV1(t *testing.T) {
	c := DefaultConfig()
	c.DataDir = t.TempDir()
	db, e := sql.Open("sqlite", c.DataDir+"/chat.db")
	if e != nil {
		t.Fatal(e)
	}
	if _, e = db.Exec(schema); e != nil {
		t.Fatal(e)
	}
	db.Close()
	a, e := Open(c)
	if e != nil {
		t.Fatal(e)
	}
	defer a.Close()
	var version int
	a.DB.QueryRow("PRAGMA user_version").Scan(&version)
	if version != 3 {
		t.Fatal(version)
	}
}

func TestNotificationMuteExpiryAndPrivateDraftEvents(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	f.a.SendMessage(f.admin, cid, Send{ClientID: "expiry", Text: "unread"})
	before := lastSeq(t, f.a, f.admin.UserID)
	req(t, f.s, "PATCH", "/v1/conversations/"+cid+"/state", f.bt, map[string]any{"draft": map[string]any{"text": "private draft"}}, 200)
	if lastSeq(t, f.a, f.admin.UserID) != before {
		t.Fatal("private draft produced other member event")
	}
	f.a.DB.Exec("UPDATE members SET notification_mute_until=unixepoch()-1 WHERE chat_id=? AND user_id=?", cid, f.bob.UserID)
	f.a.expireNotificationMutes()
	var muted int64
	f.a.DB.QueryRow("SELECT notification_mute_until FROM members WHERE chat_id=? AND user_id=?", cid, f.bob.UserID).Scan(&muted)
	if muted != 0 {
		t.Fatal(muted)
	}
	v := req(t, f.s, "GET", "/v1/conversations", f.bt, nil, 200)
	if v["total_unread_badge"].(float64) != 1 {
		t.Fatal(v)
	}
}
