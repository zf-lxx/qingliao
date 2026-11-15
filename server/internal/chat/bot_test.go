package chat

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func botCall(t *testing.T, s *httptest.Server, token, method string, body any, want int) map[string]any {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req, _ := http.NewRequest("POST", s.URL+"/bot"+token+"/"+method, rdr)
	req.Header.Set("Content-Type", "application/json")
	res, e := http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	if res.StatusCode != want {
		t.Fatalf("%s got %d wanted %d: %s", method, res.StatusCode, want, b)
	}
	if token != "" && strings.Contains(string(b), token) {
		t.Fatalf("token leaked in response: %s", b)
	}
	out := map[string]any{}
	json.Unmarshal(b, &out)
	return out
}

func TestBotAPILifecycleAndMessaging(t *testing.T) {
	f := setup(t)
	created := req(t, f.s, "POST", "/v1/bots", f.at, map[string]any{"username": "echo_bot", "display_name": "Echo Bot"}, 201)
	token, _ := created["token"].(string)
	if token == "" || !strings.Contains(token, ":") {
		t.Fatalf("missing token: %v", created)
	}
	var stored int
	f.a.DB.QueryRow("SELECT count(*) FROM bots WHERE token_hash=?", hash(token)).Scan(&stored)
	if stored != 1 {
		t.Fatal("token was not stored hashed")
	}
	var raw int
	f.a.DB.QueryRow("SELECT count(*) FROM bots WHERE token_hash=?", token).Scan(&raw)
	if raw != 0 {
		t.Fatal("plaintext token stored")
	}
	me := botCall(t, f.s, token, "getMe", map[string]any{}, 200)
	result := me["result"].(map[string]any)
	if result["is_bot"] != true || result["username"] != "echo_bot" {
		t.Fatalf("getMe: %v", me)
	}
	botCall(t, f.s, "0:notarealtokenvalueatallxxxx", "getMe", nil, 401)
	req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "echo_bot", "password": "test-password-long"}, 401)

	botID, _ := created["id"].(string)
	cid, e := f.a.CreateChat(f.admin, "direct", "", []string{botID})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: "hello-bot", Kind: "text", Text: "你好机器人"}); e != nil {
		t.Fatal(e)
	}
	updates := botCall(t, f.s, token, "getUpdates", map[string]any{"timeout": 1}, 200)
	arr, _ := updates["result"].([]any)
	if len(arr) < 1 {
		t.Fatalf("expected updates, got %v", updates)
	}
	first := arr[0].(map[string]any)
	msg := first["message"].(map[string]any)
	if msg["text"] != "你好机器人" {
		t.Fatalf("incoming text: %v", msg)
	}
	chat := msg["chat"].(map[string]any)
	chatID := chat["id"]

	sent := botCall(t, f.s, token, "sendMessage", map[string]any{
		"chat_id":      chatID,
		"text":         "收到了",
		"reply_markup": map[string]any{"inline_keyboard": []any{[]any{map[string]any{"text": "确定", "callback_data": "ok"}}}},
	}, 200)
	out := sent["result"].(map[string]any)
	mid := int64(out["message_id"].(float64))
	if out["text"] != "收到了" {
		t.Fatalf("sendMessage: %v", sent)
	}
	edited := botCall(t, f.s, token, "editMessageText", map[string]any{"chat_id": chatID, "message_id": mid, "text": "已修改"}, 200)
	if edited["result"].(map[string]any)["text"] != "已修改" {
		t.Fatalf("edit: %v", edited)
	}
	botCall(t, f.s, token, "deleteMessage", map[string]any{"chat_id": chatID, "message_id": mid}, 200)

	// recieve callback on a fresh message
	sent = botCall(t, f.s, token, "sendMessage", map[string]any{
		"chat_id":      chatID,
		"text":         "请选择",
		"reply_markup": map[string]any{"inline_keyboard": []any{[]any{map[string]any{"text": "确定", "callback_data": "ok"}}}},
	}, 200)
	mid = int64(sent["result"].(map[string]any)["message_id"].(float64))
	var midStr string
	if e := f.a.DB.QueryRow("SELECT id FROM messages WHERE chat_id=? AND seq=?", cid, mid).Scan(&midStr); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/messages/"+midStr+"/callback", f.at, map[string]any{"callback_data": "ok"}, 200)
	cb := botCall(t, f.s, token, "getUpdates", map[string]any{"timeout": 1}, 200)
	found := false
	var qid string
	for _, item := range cb["result"].([]any) {
		u := item.(map[string]any)
		if q, ok := u["callback_query"].(map[string]any); ok && q["data"] == "ok" {
			found = true
			qid, _ = q["id"].(string)
		}
	}
	if !found || qid == "" {
		t.Fatalf("missing callback_query: %v", cb)
	}
	botCall(t, f.s, token, "answerCallbackQuery", map[string]any{"callback_query_id": qid}, 200)

	list := req(t, f.s, "GET", "/v1/bots", f.at, nil, 200)
	if len(list["bots"].([]any)) != 1 {
		t.Fatalf("list: %v", list)
	}
	revoked := req(t, f.s, "POST", "/v1/bots/"+botID+"/revoke", f.at, nil, 200)
	newTok := revoked["token"].(string)
	if newTok == token {
		t.Fatal("revoke reused token")
	}
	botCall(t, f.s, token, "getMe", nil, 401)
	botCall(t, f.s, newTok, "getMe", nil, 200)
	req(t, f.s, "DELETE", "/v1/bots/"+botID, f.at, nil, 200)
	botCall(t, f.s, newTok, "getMe", nil, 401)
}

func TestBotWebhookAndLongPoll(t *testing.T) {
	f := setupConfig(t, func(c *Config) { c.AllowHTTPWebhook = true })
	created := req(t, f.s, "POST", "/v1/bots", f.at, map[string]any{"username": "hook_bot", "display_name": "Hook"}, 201)
	token := created["token"].(string)
	botID := created["id"].(string)
	got := make(chan map[string]any, 4)
	hook := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Bot-Api-Secret-Token") != "s3cret" {
			w.WriteHeader(403)
			return
		}
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		got <- body
		w.WriteHeader(200)
	}))
	defer hook.Close()
	botCall(t, f.s, token, "setWebhook", map[string]any{"url": hook.URL, "secret_token": "s3cret"}, 200)
	botCall(t, f.s, token, "getUpdates", map[string]any{"timeout": 0}, 409)
	cid, e := f.a.CreateChat(f.admin, "direct", "", []string{botID})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.admin, cid, Send{ClientID: "hook-hi", Text: "webhook please"}); e != nil {
		t.Fatal(e)
	}
	f.a.processBotWebhooks()
	select {
	case body := <-got:
		msg := body["message"].(map[string]any)
		if msg["text"] != "webhook please" {
			t.Fatalf("hook payload: %v", body)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("webhook not delivered")
	}
	botCall(t, f.s, token, "deleteWebhook", map[string]any{}, 200)
	info := botCall(t, f.s, token, "getWebhookInfo", nil, 200)
	if info["result"].(map[string]any)["url"] != "" {
		t.Fatalf("webhook not cleared: %v", info)
	}

	// SSRF: private / metadata rejected when loopback allowance is off
	g := setup(t)
	created = req(t, g.s, "POST", "/v1/bots", g.at, map[string]any{"username": "safe_bot", "display_name": "Safe"}, 201)
	tok := created["token"].(string)
	botCall(t, g.s, tok, "setWebhook", map[string]any{"url": "http://127.0.0.1:9/x"}, 400)
	botCall(t, g.s, tok, "setWebhook", map[string]any{"url": "https://169.254.169.254/latest"}, 400)
}

func TestBotSendExistingMediaAndLongPollWake(t *testing.T) {
	f := setup(t)
	created := req(t, f.s, "POST", "/v1/bots", f.bt, map[string]any{"username": "media_bot", "display_name": "Media"}, 201)
	token := created["token"].(string)
	botID := created["id"].(string)
	cid, e := f.a.CreateChat(f.bob, "direct", "", []string{botID})
	if e != nil {
		t.Fatal(e)
	}
	// Upload a tiny PNG as bob, then have the bot send it by file_id (existing media).
	png := []byte{137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 8, 153, 99, 96, 96, 96, 96, 0, 0, 0, 5, 0, 1, 138, 51, 230, 223, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130}
	// actually use a real generated png via existing helpers if any — send as raw upload
	reqUp, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(png))
	reqUp.Header.Set("Authorization", "Bearer "+f.bt)
	reqUp.Header.Set("Content-Type", "image/png")
	reqUp.Header.Set("X-Conversation-ID", cid)
	res, e := http.DefaultClient.Do(reqUp)
	if e != nil {
		t.Fatal(e)
	}
	b, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != 201 {
		t.Fatalf("upload %d %s", res.StatusCode, b)
	}
	var up map[string]any
	json.Unmarshal(b, &up)
	fileID, _ := up["id"].(string)
	if fileID == "" {
		t.Fatalf("upload: %s", b)
	}
	sent := botCall(t, f.s, token, "sendPhoto", map[string]any{"chat_id": "@bob", "photo": fileID, "caption": "图"}, 200)
	photo, _ := sent["result"].(map[string]any)["photo"]
	if photo == nil {
		t.Fatalf("sendPhoto: %v", sent)
	}
	file := botCall(t, f.s, token, "getFile", map[string]any{"file_id": fileID}, 200)
	path, _ := file["result"].(map[string]any)["file_path"].(string)
	if !strings.Contains(path, fileID) {
		t.Fatalf("getFile: %v", file)
	}
	dl, e := http.Get(f.s.URL + "/file/bot" + token + "/" + path)
	if e != nil {
		t.Fatal(e)
	}
	body, _ := io.ReadAll(dl.Body)
	dl.Body.Close()
	if dl.StatusCode != 200 || len(body) == 0 {
		t.Fatalf("download %d %d", dl.StatusCode, len(body))
	}

	// Long-poll wakes when a message arrives mid-wait.
	done := make(chan map[string]any, 1)
	go func() {
		done <- botCall(t, f.s, token, "getUpdates", map[string]any{"timeout": 8}, 200)
	}()
	time.Sleep(200 * time.Millisecond)
	if _, e = f.a.SendMessage(f.bob, cid, Send{ClientID: "wake-up", Text: "wake"}); e != nil {
		t.Fatal(e)
	}
	select {
	case upd := <-done:
		found := false
		for _, item := range upd["result"].([]any) {
			u := item.(map[string]any)
			if m, ok := u["message"].(map[string]any); ok && m["text"] == "wake" {
				found = true
			}
		}
		if !found {
			t.Fatalf("long poll missed wake: %v", upd)
		}
	case <-time.After(9 * time.Second):
		t.Fatal("getUpdates did not wake")
	}
}

func botMultipart(t *testing.T, s *httptest.Server, token, method string, fields map[string]string, files map[string][]byte, filenames map[string]string, want int) map[string]any {
	t.Helper()
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	for k, v := range fields {
		if e := w.WriteField(k, v); e != nil {
			t.Fatal(e)
		}
	}
	for k, data := range files {
		name := k + ".bin"
		if filenames != nil && filenames[k] != "" {
			name = filenames[k]
		}
		part, e := w.CreateFormFile(k, name)
		if e != nil {
			t.Fatal(e)
		}
		if _, e = part.Write(data); e != nil {
			t.Fatal(e)
		}
	}
	if e := w.Close(); e != nil {
		t.Fatal(e)
	}
	req, _ := http.NewRequest("POST", s.URL+"/bot"+token+"/"+method, &buf)
	req.Header.Set("Content-Type", w.FormDataContentType())
	res, e := http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	if res.StatusCode != want {
		t.Fatalf("%s got %d wanted %d: %s", method, res.StatusCode, want, b)
	}
	if token != "" && strings.Contains(string(b), token) {
		t.Fatalf("token leaked in response: %s", b)
	}
	out := map[string]any{}
	json.Unmarshal(b, &out)
	return out
}

func botFileID(t *testing.T, result map[string]any, field string) string {
	t.Helper()
	if field == "photo" {
		arr, _ := result["photo"].([]any)
		if len(arr) == 0 {
			t.Fatalf("missing photo: %v", result)
		}
		file, _ := arr[0].(map[string]any)
		id, _ := file["file_id"].(string)
		if id == "" {
			t.Fatalf("missing photo file_id: %v", result)
		}
		return id
	}
	file, _ := result[field].(map[string]any)
	id, _ := file["file_id"].(string)
	if id == "" {
		t.Fatalf("missing %s file_id: %v", field, result)
	}
	return id
}

func TestBotMultipartUploadAndFileID(t *testing.T) {
	f := setup(t)
	created := req(t, f.s, "POST", "/v1/bots", f.bt, map[string]any{"username": "up_bot", "display_name": "Up"}, 201)
	token := created["token"].(string)
	botID := created["id"].(string)
	if _, e := f.a.CreateChat(f.bob, "direct", "", []string{botID}); e != nil {
		t.Fatal(e)
	}
	png := pngHead()
	sent := botMultipart(t, f.s, token, "sendPhoto", map[string]string{"chat_id": "@bob", "caption": "新图"}, map[string][]byte{"photo": png}, map[string]string{"photo": "shot.png"}, 200)
	result := sent["result"].(map[string]any)
	if result["caption"] != "新图" {
		t.Fatalf("caption: %v", sent)
	}
	fileID := botFileID(t, result, "photo")
	info := botCall(t, f.s, token, "getFile", map[string]any{"file_id": fileID}, 200)
	path, _ := info["result"].(map[string]any)["file_path"].(string)
	if !strings.Contains(path, fileID) {
		t.Fatalf("getFile: %v", info)
	}
	dl, e := http.Get(f.s.URL + "/file/bot" + token + "/" + path)
	if e != nil {
		t.Fatal(e)
	}
	body, _ := io.ReadAll(dl.Body)
	dl.Body.Close()
	if dl.StatusCode != 200 || !bytes.Equal(body, png) {
		t.Fatalf("download %d %d", dl.StatusCode, len(body))
	}
	// Existing file_id still works after a fresh upload.
	again := botCall(t, f.s, token, "sendPhoto", map[string]any{"chat_id": "@bob", "photo": fileID}, 200)
	if botFileID(t, again["result"].(map[string]any), "photo") != fileID {
		t.Fatalf("resend file_id: %v", again)
	}
	// Multipart form field (not a file part) can also pass an existing file_id.
	viaForm := botMultipart(t, f.s, token, "sendPhoto", map[string]string{"chat_id": "@bob", "photo": fileID}, nil, nil, 200)
	if botFileID(t, viaForm["result"].(map[string]any), "photo") != fileID {
		t.Fatalf("form file_id: %v", viaForm)
	}

	doc := []byte("%PDF-1.4 test document")
	docs := botMultipart(t, f.s, token, "sendDocument", map[string]string{"chat_id": "@bob", "document": "attach://filepart", "caption": "文档"}, map[string][]byte{"filepart": doc}, map[string]string{"filepart": "notes.pdf"}, 200)
	docID := botFileID(t, docs["result"].(map[string]any), "document")
	if docs["result"].(map[string]any)["document"].(map[string]any)["file_name"] != "notes.pdf" {
		t.Fatalf("document name: %v", docs)
	}
	_ = docID

	ftyp := make([]byte, 32)
	copy(ftyp[4:8], "ftyp")
	copy(ftyp[8:12], "isom")
	vid := botMultipart(t, f.s, token, "sendVideo",
		map[string]string{"chat_id": "@bob", "video": "attach://clip", "thumbnail": "attach://thumb", "duration": "2", "width": "640", "height": "360"},
		map[string][]byte{"clip": ftyp, "thumb": png},
		map[string]string{"clip": "clip.mp4", "thumb": "thumb.png"},
		200)
	video := vid["result"].(map[string]any)["video"].(map[string]any)
	if video["file_id"] == nil || video["thumbnail"] == nil {
		t.Fatalf("sendVideo: %v", vid)
	}

	voiceBody := append([]byte("OggS"), bytes.Repeat([]byte{0}, 32)...)
	voice := botMultipart(t, f.s, token, "sendVoice", map[string]string{"chat_id": "@bob"}, map[string][]byte{"voice": voiceBody}, map[string]string{"voice": "note.ogg"}, 200)
	_ = botFileID(t, voice["result"].(map[string]any), "voice")

	song := append([]byte("ID3"), bytes.Repeat([]byte{0}, 24)...)
	audio := botMultipart(t, f.s, token, "sendAudio", map[string]string{"chat_id": "@bob"}, map[string][]byte{"audio": song}, map[string]string{"audio": "song.mp3"}, 200)
	_ = botFileID(t, audio["result"].(map[string]any), "audio")

	gif := []byte("GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;")
	anim := botMultipart(t, f.s, token, "sendAnimation", map[string]string{"chat_id": "@bob"}, map[string][]byte{"animation": gif}, map[string]string{"animation": "a.gif"}, 200)
	if anim["result"].(map[string]any)["animation"] == nil {
		t.Fatalf("sendAnimation: %v", anim)
	}
	note := botMultipart(t, f.s, token, "sendVideoNote", map[string]string{"chat_id": "@bob"}, map[string][]byte{"video_note": ftyp}, map[string]string{"video_note": "note.mp4"}, 200)
	if note["result"].(map[string]any)["video_note"] == nil {
		t.Fatalf("sendVideoNote: %v", note)
	}

	// Auth failure: bad token, no leak.
	bad := "0:notarealtokenvalueatallxxxx"
	botMultipart(t, f.s, bad, "sendPhoto", map[string]string{"chat_id": "@bob"}, map[string][]byte{"photo": png}, map[string]string{"photo": "x.png"}, 401)

	// Unsupported types.
	botMultipart(t, f.s, token, "sendPhoto", map[string]string{"chat_id": "@bob"}, map[string][]byte{"photo": []byte("<html>bad</html>")}, map[string]string{"photo": "x.html"}, 400)
	botMultipart(t, f.s, token, "sendPhoto", map[string]string{"chat_id": "@bob"}, map[string][]byte{"photo": []byte("plain file content")}, map[string]string{"photo": "x.txt"}, 400)

	// Oversize uses the same MaxFile limit as user uploads.
	f.a.C.MaxFile = 32
	big := append(pngHead(), bytes.Repeat([]byte{0}, 64)...)
	botMultipart(t, f.s, token, "sendDocument", map[string]string{"chat_id": "@bob"}, map[string][]byte{"document": big}, map[string]string{"document": "big.bin"}, 413)
}
