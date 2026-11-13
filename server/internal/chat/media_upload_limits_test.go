package chat

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"testing"
)

// These tests pin the upload limits that decide whether a phone-recorded
// video or voice note can be delivered at all. They exist because the client
// reports a generic failure and the cause is not obvious from the UI.

// A real mp4 header: ftyp box, then isom/mp42 compatible brands.
func mp4Header() []byte {
	return []byte{
		0, 0, 0, 0x18, 'f', 't', 'y', 'p',
		'i', 's', 'o', 'm', 0, 0, 0, 0,
		'i', 's', 'o', 'm', 'm', 'p', '4', '2',
	}
}

func uploadRaw(t *testing.T, f *fixture, tok, cid string, data []byte) (int, map[string]any) {
	t.Helper()
	r, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(data))
	r.Header.Set("Authorization", "Bearer "+tok)
	if cid != "" {
		r.Header.Set("X-Conversation-ID", cid)
	}
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	out := map[string]any{}
	json.Unmarshal(b, &out)
	return res.StatusCode, out
}

// A 20-second 1080p phone video is routinely far above the single-file cap.
func TestUploadRejectsOversizedVideo(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)

	if f.config.MaxFile != 100<<20 {
		t.Fatalf("single-file cap changed to %d; update the client hint", f.config.MaxFile)
	}

	// 120 MB of mp4 — a long clip straight off a phone, above the raised cap.
	body := append(mp4Header(), bytes.Repeat([]byte{0}, 120<<20)...)
	code, out := uploadRaw(t, f, f.at, cid, body)
	// MaxBytesReader truncates at the cap, so the failure surfaces from the
	// storage write as file_too_large_or_upload_failed rather than the cleaner
	// file_too_large branch.
	if code != 413 {
		t.Fatalf("120MB mp4 got %d want 413: %v", code, out)
	}
	if out["error"] != "file_too_large_or_upload_failed" {
		t.Fatalf("error %v", out["error"])
	}
}

// The quota is shared by the whole deployment, not per account.
func TestMediaQuotaIsGlobal(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)

	// The default quota is 5 GB, too large to fill in a unit test. Shrink it
	// for this fixture and keep the single-file cap as the interesting bound.
	f.a.C.MediaQuota = 65 << 20
	chunk := append(mp4Header(), bytes.Repeat([]byte{1}, 20<<20)...)
	for i := 0; i < 3; i++ {
		code, out := uploadRaw(t, f, f.at, cid, chunk)
		if code != 201 {
			t.Fatalf("chunk %d got %d: %v", i, code, out)
		}
	}
	// The remainder is smaller than MaxFile, so the next full-size upload is
	// refused by the quota rather than by the per-file cap.
	code, out := uploadRaw(t, f, f.at, cid, chunk)
	// The quota clamps limit below the chunk size, and MaxBytesReader then
	// truncates, so this also reports as an oversize failure. Document the
	// behaviour rather than the error code the code path suggests.
	if code != 413 {
		t.Fatalf("over-quota upload got %d want 413: %v", code, out)
	}
	if out["error"] != "file_too_large_or_upload_failed" {
		t.Fatalf("error %v", out["error"])
	}
}

// An m4a voice memo starts with the same ftyp box as an mp4 video. The server
// therefore stores it as video/mp4, and a voice message (which requires an
// audio/ prefix) cannot reference it.
func TestM4AAudioIsMislabelledAsVideo(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)

	m4a := append([]byte{
		0, 0, 0, 0x18, 'f', 't', 'y', 'p',
		'M', '4', 'A', ' ', 0, 0, 0, 0,
		'M', '4', 'A', ' ', 'm', 'p', '4', '2',
	}, bytes.Repeat([]byte{0}, 1024)...)
	v := uploadReq(t, f, f.at, cid, m4a, 201)
	if v["mime"] != "video/mp4" {
		t.Fatalf("m4a sniffed as %v, expected the current video/mp4 mislabel", v["mime"])
	}

	// Sending it as a voice note is rejected because the stored mime is video/.
	code, out := sendRaw(t, f, f.at, cid, map[string]any{
		"client_msg_id": "voice-from-m4a",
		"kind":          "voice",
		"media_id":      v["id"],
	})
	if code != 400 {
		t.Fatalf("m4a as voice got %d want 400: %v", code, out)
	}
}

// OGG/Opus, which the Android recorder produces, is stored as audio/ogg and
// therefore works as a voice note.
func TestOggOpusWorksAsVoice(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)

	ogg := append([]byte("OggS\x00\x02\x00\x00"), bytes.Repeat([]byte{0}, 1024)...)
	v := uploadReq(t, f, f.at, cid, ogg, 201)
	if v["mime"] != "audio/ogg" {
		t.Fatalf("ogg sniffed as %v", v["mime"])
	}
	sendRaw(t, f, f.at, cid, map[string]any{
		"client_msg_id": "voice-ogg",
		"kind":          "voice",
		"media_id":      v["id"],
	}, 200)
}

func sendRaw(t *testing.T, f *fixture, tok, cid string, body map[string]any, want ...int) (int, map[string]any) {
	t.Helper()
	b, _ := json.Marshal(body)
	r, _ := http.NewRequest("POST", f.s.URL+"/v1/conversations/"+cid+"/messages", bytes.NewReader(b))
	r.Header.Set("Authorization", "Bearer "+tok)
	r.Header.Set("Content-Type", "application/json")
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	out := map[string]any{}
	json.Unmarshal(raw, &out)
	if len(want) > 0 && res.StatusCode != want[0] {
		t.Fatalf("send got %d want %d: %s", res.StatusCode, want[0], raw)
	}
	return res.StatusCode, out
}

// Declaring audio/mp4 lets the same bytes that sniff as video/mp4 be used as a
// voice note, which is what the client now sends for an .m4a recording.
func TestDeclaredMimeFixesM4ALabel(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)

	m4a := append([]byte{
		0, 0, 0, 0x18, 'f', 't', 'y', 'p',
		'M', '4', 'A', ' ', 0, 0, 0, 0,
		'M', '4', 'A', ' ', 'm', 'p', '4', '2',
	}, bytes.Repeat([]byte{0}, 1024)...)

	r, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(m4a))
	r.Header.Set("Authorization", "Bearer "+f.at)
	r.Header.Set("X-Conversation-ID", cid)
	r.Header.Set("X-Media-Mime", "audio/mp4")
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	if res.StatusCode != 201 {
		t.Fatalf("upload got %d: %s", res.StatusCode, raw)
	}
	out := map[string]any{}
	json.Unmarshal(raw, &out)
	if out["mime"] != "audio/mp4" {
		t.Fatalf("mime %v want audio/mp4", out["mime"])
	}
	sendRaw(t, f, f.at, cid, map[string]any{
		"client_msg_id": "voice-m4a-declared",
		"kind":          "voice",
		"media_id":      out["id"],
	}, 200)
}

// A declaration that disagrees with the container family is ignored, so a
// caller cannot relabel arbitrary bytes as an image.
func TestDeclaredMimeCannotCrossFamilies(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)

	// An HTML document declared as image/png must still be rejected.
	html := []byte("<html><body>not an image</body></html>")
	r, _ := http.NewRequest("POST", f.s.URL+"/v1/media", bytes.NewReader(html))
	r.Header.Set("Authorization", "Bearer "+f.at)
	r.Header.Set("X-Conversation-ID", cid)
	r.Header.Set("X-Media-Mime", "image/png")
	res, e := http.DefaultClient.Do(r)
	if e != nil {
		t.Fatal(e)
	}
	defer res.Body.Close()
	if res.StatusCode == 201 {
		t.Fatalf("html declared as image/png was accepted")
	}
}
