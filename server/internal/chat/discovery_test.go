package chat

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
)

func TestSearchClearBlockReport(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	send := func(text string) Message {
		m, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Text: text})
		if e != nil {
			t.Fatal(e)
		}
		return m
	}
	m := send("你好中国，北京 Hello WORLD")
	for _, q := range []string{"中国", "北京", "你", "Hello world"} {
		items, e := f.a.Search(f.bob, cid, q, 0, 10)
		if e != nil || len(items) != 1 {
			t.Fatalf("search %q %v %v", q, items, e)
		}
	}
	items, e := f.a.Search(f.bob, cid, "国你", 0, 10)
	if e != nil || len(items) != 0 {
		t.Fatal(items, e)
	}
	if _, e = f.a.Search(f.eve, cid, "中国", 0, 10); e != ErrForbidden {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/conversations/"+cid+"/search?q=%E4%B8%AD%E5%9B%BD", f.bt, nil, 200)
	if e = f.a.EditMessage(f.admin, m.ID, Send{Text: "上海新词"}); e != nil {
		t.Fatal(e)
	}
	items, e = f.a.Search(f.bob, cid, "中国", 0, 10)
	if e != nil || len(items) != 0 {
		t.Fatal(items, e)
	}
	items, e = f.a.Search(f.bob, cid, "上海", 0, 10)
	if e != nil || len(items) != 1 {
		t.Fatal(items, e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/report", f.bt, map[string]any{"message_id": m.ID, "reason": "测试举报，不自动处罚"}, 201)
	req(t, f.s, "GET", "/v1/admin/reports", f.bt, nil, 403)
	r := req(t, f.s, "GET", "/v1/admin/reports", f.at, nil, 200)
	if len(r["reports"].([]any)) != 1 {
		t.Fatal(r)
	}
	req(t, f.s, "PUT", "/v1/users/"+f.admin.UserID+"/block", f.bt, map[string]bool{"blocked": true}, 200)
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Text: "blocked"}); e != ErrForbidden {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.bob, cid, Send{ClientID: id(), Text: "blocked reverse"}); e != ErrForbidden {
		t.Fatal(e)
	}
	if e = f.a.Block(f.bob, f.admin.UserID, false); e != nil {
		t.Fatal(e)
	}
	send("解锁后发送")
	if e = f.a.ClearHistory(f.bob, cid, false); e != nil {
		t.Fatal(e)
	}
	hist, e := f.a.History(f.bob, cid, 0, 100)
	if e != nil || len(hist) != 0 {
		t.Fatal(hist, e)
	}
	hist, e = f.a.History(f.admin, cid, 0, 100)
	if e != nil || len(hist) != 2 {
		t.Fatal(hist, e)
	}
	items, e = f.a.Search(f.bob, cid, "上海", 0, 100)
	if e != nil || len(items) != 0 {
		t.Fatal(items, e)
	}
	diff, e := f.a.Difference(f.bob.UserID, 0, 200)
	if e != nil {
		t.Fatal(e)
	}
	b, _ := json.Marshal(diff)
	if bytes.Contains(b, []byte("上海新词")) {
		t.Fatalf("clear leaked old sync: %s", b)
	}
	send("清空后新消息")
	hist, e = f.a.History(f.bob, cid, 0, 100)
	if e != nil || len(hist) != 1 {
		t.Fatal(hist, e)
	}
	if e = f.a.ClearHistory(f.bob, cid, true); e != nil {
		t.Fatal(e)
	}
	hist, e = f.a.History(f.admin, cid, 0, 100)
	if e != nil || len(hist) != 0 {
		t.Fatal(hist, e)
	}
	diff, _ = f.a.Difference(f.admin.UserID, 0, 200)
	b, _ = json.Marshal(diff)
	if bytes.Contains(b, []byte("清空后新消息")) {
		t.Fatal("both clear leaked sync")
	}
}
func TestSharedMediaVisibilityAndDateCursor(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	// Upload a valid tiny image through the actual quota/storage/auth path.
	data := []byte{0x89, 'P', 'N', 'G', 13, 10, 26, 10, 0, 0, 0, 13, 'I', 'H', 'D', 'R'}
	request, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(data))
	request.Header.Set("Authorization", "Bearer "+f.at)
	request.Header.Set("X-Conversation-ID", cid)
	res, e := http.DefaultClient.Do(request)
	if e != nil {
		t.Fatal(e)
	}
	raw, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != 201 {
		t.Fatalf("upload %s", raw)
	}
	var v map[string]any
	json.Unmarshal(raw, &v)
	for i := 0; i < 4; i++ {
		m, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "image", MediaID: v["id"].(string)})
		if e != nil {
			t.Fatal(e)
		}
		date := fmt.Sprintf("2026-%02d-01T01:00:00Z", i+1)
		if _, e = f.a.DB.Exec("UPDATE messages SET created=? WHERE id=?", date, m.ID); e != nil {
			t.Fatal(e)
		}
	}
	page, e := f.a.SharedMedia(f.bob, cid, "image", 0, "", 2)
	if e != nil {
		t.Fatal(e)
	}
	if len(page["messages"].([]Message)) != 2 || !page["has_more"].(bool) || page["counts"].(map[string]int64)["image"] != 4 || len(page["months"].([]map[string]any)) != 4 {
		t.Fatal(page)
	}
	page2, e := f.a.SharedMedia(f.bob, cid, "image", page["next_before"].(int64), "", 2)
	if e != nil || len(page2["messages"].([]Message)) != 2 || page2["has_more"].(bool) {
		t.Fatal(page2, e)
	}
	page, e = f.a.SharedMedia(f.bob, cid, "image", 0, "2026-02-15T00:00:00+08:00", 10)
	if e != nil || len(page["messages"].([]Message)) != 2 {
		t.Fatal(page, e)
	}
	if _, e = f.a.SharedMedia(f.eve, cid, "image", 0, "", 10); e != ErrForbidden {
		t.Fatal(e)
	}
	if e = f.a.ClearHistory(f.bob, cid, false); e != nil {
		t.Fatal(e)
	}
	page, e = f.a.SharedMedia(f.bob, cid, "all", 0, "", 10)
	if e != nil || page["counts"].(map[string]int64)["image"] != 0 {
		t.Fatal(page, e)
	}
	g, e := f.a.CreateChat(f.admin, "group", "group", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	if e = f.a.ClearHistory(f.bob, g, true); e != ErrForbidden {
		t.Fatal(e)
	}
}
