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

func TestGlobalMediaAcrossChatsAndKinds(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	other, e := f.a.CreateChat(f.admin, "direct", "", []string{f.eve.UserID})
	if e != nil {
		t.Fatal(e)
	}
	img := uploadMedia(t, f, f.at, cid, pngHead(), map[string]string{"X-Media-Width": "32", "X-Media-Height": "32", "X-Media-Filename": "shot.png"})
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "image", MediaID: img["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	ftyp := make([]byte, 32)
	copy(ftyp[4:8], "ftyp")
	copy(ftyp[8:12], "isom")
	vid := uploadMedia(t, f, f.at, cid, ftyp, map[string]string{"X-Media-Duration-Ms": "1200", "X-Media-Width": "640", "X-Media-Height": "360", "X-Media-Filename": "clip.mp4"})
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "video", MediaID: vid["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	doc := uploadMedia(t, f, f.at, cid, []byte("%PDF-1.4 file"), map[string]string{"X-Media-Filename": "notes.pdf"})
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "file", MediaID: doc["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	song := uploadMedia(t, f, f.at, cid, append([]byte("ID3"), bytes.Repeat([]byte{0}, 24)...), map[string]string{"X-Media-Filename": "song.mp3"})
	if _, e = f.a.DB.Exec("UPDATE media SET mime='audio/mpeg' WHERE id=?", song["id"]); e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "file", MediaID: song["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	wave := "AQIDBAUGBwg="
	voiceBody := append([]byte("OggS"), bytes.Repeat([]byte{0}, 32)...)
	voice := uploadMedia(t, f, f.at, cid, voiceBody, map[string]string{"X-Media-Duration-Ms": "800", "X-Media-Waveform": wave, "X-Media-Filename": "note.ogg"})
	if _, e = f.a.DB.Exec("UPDATE media SET mime='audio/ogg' WHERE id=?", voice["id"]); e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "voice", MediaID: voice["id"].(string)}); e != nil {
		t.Fatal(e)
	}
	pid := id()
	if _, e = f.a.DB.Exec("INSERT INTO link_previews(id,url,title,description,image,site_name,fetched_at) VALUES(?,?,?,?,?,?,?)", pid, "https://example.com/", "Example", "desc", "", "site", 1); e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Text: "https://example.com/", LinkPreviewID: pid}); e != nil {
		t.Fatal(e)
	}
	img2 := uploadMedia(t, f, f.at, other, pngHead(), map[string]string{"X-Media-Width": "16", "X-Media-Height": "16", "X-Media-Filename": "eve.png"})
	hidden, e := f.a.SendMessage(f.admin, other, Send{ClientID: id(), Kind: "image", MediaID: img2["id"].(string)})
	if e != nil {
		t.Fatal(e)
	}

	page, e := f.a.GlobalMedia(f.bob, "image", "", "", 50)
	if e != nil {
		t.Fatal(e)
	}
	imgs := page["messages"].([]Message)
	if len(imgs) != 1 || imgs[0].Kind != "image" {
		t.Fatalf("bob should see the admin-bob image only, got %#v", page)
	}
	for _, m := range imgs {
		if m.ID == hidden.ID {
			t.Fatal("bob saw eve's chat image")
		}
	}
	counts := page["counts"].(map[string]int64)
	if counts["image"] != 1 || counts["video"] != 1 || counts["file"] != 2 || counts["voice"] != 1 || counts["link"] != 1 || counts["audio"] != 1 {
		t.Fatalf("counts %#v", counts)
	}

	// Empty query (the drawer「文件」path) must still return stored types.
	for _, kind := range []string{"image", "video", "file", "voice", "link", "audio"} {
		got, e := f.a.GlobalMedia(f.bob, kind, "", "", 50)
		if e != nil {
			t.Fatal(kind, e)
		}
		if len(got["messages"].([]Message)) == 0 {
			t.Fatalf("empty %s: %#v", kind, got)
		}
	}

	adminPage, e := f.a.GlobalMedia(f.admin, "image", "", "", 50)
	if e != nil || len(adminPage["messages"].([]Message)) != 2 {
		t.Fatal(adminPage, e)
	}

	// Filename search.
	q, e := f.a.GlobalMedia(f.bob, "file", "notes.pdf", "", 50)
	if e != nil || len(q["messages"].([]Message)) != 1 || q["messages"].([]Message)[0].Media == nil || q["messages"].([]Message)[0].Media.FileName != "notes.pdf" {
		t.Fatal(q, e)
	}

	// Pagination across the admin-bob chat (created timestamps are unique enough).
	first, e := f.a.GlobalMedia(f.admin, "all", "", "", 2)
	if e != nil || !first["has_more"].(bool) || first["next_offset"].(string) == "" || len(first["messages"].([]Message)) != 2 {
		t.Fatal(first, e)
	}
	second, e := f.a.GlobalMedia(f.admin, "all", "", first["next_offset"].(string), 20)
	if e != nil || len(second["messages"].([]Message)) == 0 {
		t.Fatal(second, e)
	}
	seen := map[string]bool{}
	for _, m := range first["messages"].([]Message) {
		seen[m.ID] = true
	}
	for _, m := range second["messages"].([]Message) {
		if seen[m.ID] {
			t.Fatalf("cursor repeated %s", m.ID)
		}
	}

	httpPage := req(t, f.s, "GET", "/v1/me/media?kind=image&limit=10", f.bt, nil, 200)
	raw, _ := json.Marshal(httpPage["messages"])
	var listed []Message
	if e := json.Unmarshal(raw, &listed); e != nil || len(listed) != 1 {
		t.Fatal(httpPage, e)
	}
}

func TestReplyToSeqOnTextAndImage(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	origText, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Text: "斑斑驳驳"})
	if e != nil {
		t.Fatal(e)
	}
	img := uploadMedia(t, f, f.at, cid, pngHead(), map[string]string{"X-Media-Width": "32", "X-Media-Height": "32", "X-Media-Filename": "shot.png"})
	origImg, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "image", MediaID: img["id"].(string)})
	if e != nil {
		t.Fatal(e)
	}
	textReply, e := f.a.SendMessage(f.bob, cid, Send{ClientID: id(), Text: "斑斑驳驳", ReplyTo: origText.ID})
	if e != nil || textReply.ReplyTo != origText.ID || textReply.ReplyToSeq != origText.Seq {
		t.Fatalf("text reply seq: %+v orig=%+v e=%v", textReply, origText, e)
	}
	imgReply, e := f.a.SendMessage(f.bob, cid, Send{ClientID: id(), Text: "急急急", ReplyTo: origImg.ID})
	if e != nil || imgReply.ReplyTo != origImg.ID || imgReply.ReplyToSeq != origImg.Seq {
		t.Fatalf("image reply seq: %+v orig=%+v e=%v", imgReply, origImg, e)
	}
	hist, e := f.a.History(f.bob, cid, 0, 20)
	if e != nil {
		t.Fatal(e)
	}
	byID := map[string]Message{}
	for _, m := range hist {
		byID[m.ID] = m
	}
	if byID[textReply.ID].ReplyToSeq != origText.Seq || byID[imgReply.ID].ReplyToSeq != origImg.Seq {
		t.Fatalf("history missing reply_to_seq: text=%+v image=%+v", byID[textReply.ID], byID[imgReply.ID])
	}
}
