package chat

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func pngHead() []byte {
	return []byte{0x89, 'P', 'N', 'G', 13, 10, 26, 10, 0, 0, 0, 13, 'I', 'H', 'D', 'R'}
}

func uploadMedia(t *testing.T, f *fixture, token, cid string, body []byte, headers map[string]string) map[string]any {
	t.Helper()
	req, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	if cid != "" {
		req.Header.Set("X-Conversation-ID", cid)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	res, e := http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	raw, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != 201 {
		t.Fatalf("upload %d %s", res.StatusCode, raw)
	}
	var v map[string]any
	json.Unmarshal(raw, &v)
	return v
}

func TestMediaMetaVideoAlbumAndForward(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	wave := base64.StdEncoding.EncodeToString([]byte{1, 2, 3, 4, 5, 6, 7, 8})
	thumb := uploadMedia(t, f, f.at, cid, pngHead(), map[string]string{"X-Media-Width": "80", "X-Media-Height": "80", "X-Media-Filename": "thumb.png"})
	img := uploadMedia(t, f, f.at, cid, pngHead(), map[string]string{"X-Media-Width": "1920", "X-Media-Height": "1080", "X-Media-Filename": "shot.png", "X-Thumbnail-ID": thumb["id"].(string)})
	if img["width"].(float64) != 1920 || img["thumbnail_id"] != thumb["id"] {
		t.Fatal(img)
	}
	m, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "image", MediaID: img["id"].(string), AlbumID: "album-1"})
	if e != nil || m.Media == nil || m.Media.Width != 1920 || m.AlbumID != "album-1" || m.Media.ThumbnailID != thumb["id"] {
		t.Fatal(m, e)
	}
	hist, e := f.a.History(f.bob, cid, 0, 10)
	if e != nil || len(hist) != 1 || hist[0].Media == nil || hist[0].Media.FileName != "shot.png" {
		t.Fatal(hist, e)
	}
	// video: craft a tiny ftyp box
	ftyp := make([]byte, 32)
	copy(ftyp[4:8], "ftyp")
	copy(ftyp[8:12], "isom")
	vid := uploadMedia(t, f, f.at, cid, ftyp, map[string]string{"X-Media-Duration-Ms": "1500", "X-Media-Width": "640", "X-Media-Height": "360", "X-Media-Filename": "clip.mp4"})
	if !strings.HasPrefix(vid["mime"].(string), "video/") {
		t.Fatal(vid["mime"])
	}
	vm, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: "video", MediaID: vid["id"].(string)})
	if e != nil || vm.Kind != "video" || vm.Media.DurationMs != 1500 {
		t.Fatal(vm, e)
	}
	voiceBody := append([]byte("OggS"), bytes.Repeat([]byte{0}, 32)...)
	// DetectContentType may not call this ogg; send as file if needed
	voice := uploadMedia(t, f, f.at, cid, voiceBody, map[string]string{"X-Media-Duration-Ms": "800", "X-Media-Waveform": wave, "X-Media-Filename": "note.ogg"})
	kind := "file"
	if strings.HasPrefix(voice["mime"].(string), "audio/") {
		kind = "voice"
	}
	vo, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Kind: kind, MediaID: voice["id"].(string)})
	if e != nil || vo.Media == nil || vo.Media.Waveform == "" {
		t.Fatal(vo, e, voice["mime"])
	}
	page, e := f.a.SharedMedia(f.bob, cid, "all", 0, "", 20)
	if e != nil || page["counts"].(map[string]int64)["image"] < 1 || page["counts"].(map[string]int64)["video"] < 1 {
		t.Fatal(page, e)
	}
	other, e := f.a.CreateChat(f.admin, "direct", "", []string{f.eve.UserID})
	if e != nil {
		t.Fatal(e)
	}
	fwd, e := f.a.ForwardMessage(f.admin, m.ID, other, id())
	if e != nil || fwd.MediaID != m.MediaID || len(fwd.ForwardOrigin) == 0 || fwd.Sender != f.admin.UserID {
		t.Fatal(fwd, e)
	}
	// Eve can download forwarded image
	req, _ := http.NewRequest("GET", f.s.URL+"/v1/media/"+m.MediaID, nil)
	req.Header.Set("Authorization", "Bearer "+f.et)
	res, e := http.DefaultClient.Do(req)
	if e != nil {
		t.Fatal(e)
	}
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatal(res.StatusCode)
	}
	if _, e = f.a.ForwardMessage(f.bob, m.ID, other, id()); e != ErrForbidden {
		t.Fatal(e)
	}
}

func TestChannelAndGroupProfile(t *testing.T) {
	f := setup(t)
	cid, e := f.a.CreateChat(f.admin, "channel", "公告", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.SendMessage(f.bob, cid, Send{ClientID: id(), Text: "subscriber cannot post"}); e != ErrForbidden {
		t.Fatal(e)
	}
	m, e := f.a.SendMessage(f.admin, cid, Send{ClientID: id(), Text: "频道消息"})
	if e != nil {
		t.Fatal(e)
	}
	hist, e := f.a.History(f.bob, cid, 0, 10)
	if e != nil || len(hist) != 1 || hist[0].ID != m.ID {
		t.Fatal(hist, e)
	}
	title := "新公告"
	if e = f.a.UpdateConversation(f.admin, cid, &title, nil, nil, nil, nil); e != nil {
		t.Fatal(e)
	}
	if e = f.a.UpdateConversation(f.bob, cid, &title, nil, nil, nil, nil); e != ErrForbidden {
		t.Fatal(e)
	}
	g, e := f.a.CreateChat(f.admin, "group", "小组", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	img := uploadMedia(t, f, f.at, "", pngHead(), map[string]string{"X-Media-Filename": "g.png"})
	av := img["id"].(string)
	if e = f.a.UpdateConversation(f.admin, g, nil, &av, nil, nil, nil); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+g, f.at, map[string]any{"title": "新组名"}, 200)
	if _, e = f.a.CreateChat(f.admin, "channel", "", nil); e != ErrInvalid {
		t.Fatal(e)
	}
}
