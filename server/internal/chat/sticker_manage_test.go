package chat

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"testing"
)

// The sticker management UI calls TDLib methods that had no HTTP route, so
// every rename/delete/reorder silently failed. These tests pin the endpoints
// that back them.

func pngBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	for x := 0; x < 8; x++ {
		for y := 0; y < 8; y++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 30), G: uint8(y * 30), B: 200, A: 255})
		}
	}
	var buf bytes.Buffer
	if e := png.Encode(&buf, img); e != nil {
		t.Fatal(e)
	}
	return buf.Bytes()
}

// newPack creates a pack owned by tok and returns its id.
func newPack(t *testing.T, f *fixture, tok, title string) string {
	t.Helper()
	out := req(t, f.s, "POST", "/v1/sticker-packs", tok, map[string]any{"title": title}, 201)
	return out["id"].(string)
}

// addStickerTo uploads an image and appends it to the pack.
func addStickerTo(t *testing.T, f *fixture, tok, pid, emoji string) string {
	t.Helper()
	m := uploadReq(t, f, tok, "", pngBytes(t), 201)
	out := req(t, f.s, "POST", "/v1/sticker-packs/"+pid+"/stickers", tok, map[string]any{
		"emoji":    emoji,
		"media_id": m["id"],
	}, 201)
	return out["id"].(string)
}

func packStickerIDs(t *testing.T, f *fixture, tok, pid string) []string {
	t.Helper()
	pack := req(t, f.s, "GET", "/v1/sticker-packs/"+pid, tok, nil, 200)
	ids := []string{}
	for _, raw := range pack["stickers"].([]any) {
		ids = append(ids, raw.(map[string]any)["id"].(string))
	}
	return ids
}

func TestStickerPackRename(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "旧名字")

	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid, f.at, map[string]any{"title": "新名字"}, 200)
	pack := req(t, f.s, "GET", "/v1/sticker-packs/"+pid, f.at, nil, 200)
	if pack["title"] != "新名字" {
		t.Fatalf("title %v", pack["title"])
	}

	// Blank titles are refused.
	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid, f.at, map[string]any{"title": "  "}, 400)
}

func TestStickerPackRenameRequiresOwnership(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "admin 的包")

	// bob does not own it.
	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid, f.bt, map[string]any{"title": "偷改"}, 403)
	// The deployment's default pack cannot be renamed by anyone.
	req(t, f.s, "PATCH", "/v1/sticker-packs/qingliao-basic", f.at, map[string]any{"title": "改名"}, 403)
}

func TestStickerPackDelete(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "待删")
	sid := addStickerTo(t, f, f.at, pid, "👍")

	req(t, f.s, "DELETE", "/v1/sticker-packs/"+pid, f.at, nil, 200)

	// The pack is gone for its owner.
	req(t, f.s, "GET", "/v1/sticker-packs/"+pid, f.at, nil, 403)

	// No orphaned rows are left behind.
	var stickers, favorites int
	f.a.DB.QueryRow("SELECT count(*) FROM stickers WHERE pack_id=?", pid).Scan(&stickers)
	f.a.DB.QueryRow("SELECT count(*) FROM sticker_favorites WHERE sticker_id=?", sid).Scan(&favorites)
	if stickers != 0 || favorites != 0 {
		t.Fatalf("leftovers: stickers=%d favorites=%d", stickers, favorites)
	}
}

func TestStickerPackDeleteRequiresOwnership(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "admin 的包")

	req(t, f.s, "DELETE", "/v1/sticker-packs/"+pid, f.bt, nil, 403)
	req(t, f.s, "DELETE", "/v1/sticker-packs/qingliao-basic", f.at, nil, 403)
	// The pack survives the refused attempts.
	req(t, f.s, "GET", "/v1/sticker-packs/"+pid, f.at, nil, 200)
}

func TestStickerDelete(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "包")
	keep := addStickerTo(t, f, f.at, pid, "👍")
	drop := addStickerTo(t, f, f.at, pid, "❤️")

	req(t, f.s, "DELETE", "/v1/sticker-packs/"+pid+"/stickers/"+drop, f.at, nil, 200)

	ids := packStickerIDs(t, f, f.at, pid)
	if len(ids) != 1 || ids[0] != keep {
		t.Fatalf("remaining %v", ids)
	}
	// Deleting it again is a forbidden no-op rather than a 500.
	req(t, f.s, "DELETE", "/v1/sticker-packs/"+pid+"/stickers/"+drop, f.at, nil, 403)
}

func TestStickerReorder(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "包")
	a := addStickerTo(t, f, f.at, pid, "1️⃣")
	b := addStickerTo(t, f, f.at, pid, "2️⃣")
	c := addStickerTo(t, f, f.at, pid, "3️⃣")

	// Move the last sticker to the front.
	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid+"/stickers/"+c, f.at,
		map[string]any{"position": 0}, 200)
	ids := packStickerIDs(t, f, f.at, pid)
	want := []string{c, a, b}
	for i := range want {
		if ids[i] != want[i] {
			t.Fatalf("order %v want %v", ids, want)
		}
	}

	// Positions past the end clamp instead of erroring.
	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid+"/stickers/"+c, f.at,
		map[string]any{"position": 999}, 200)
	ids = packStickerIDs(t, f, f.at, pid)
	if ids[len(ids)-1] != c {
		t.Fatalf("clamped order %v", ids)
	}
}

func TestStickerEmojiEdit(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "包")
	sid := addStickerTo(t, f, f.at, pid, "👍")

	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid+"/stickers/"+sid, f.at,
		map[string]any{"emoji": "🎉"}, 200)

	pack := req(t, f.s, "GET", "/v1/sticker-packs/"+pid, f.at, nil, 200)
	sealed := pack["stickers"].([]any)[0].(map[string]any)
	if sealed["emoji"] != "🎉" {
		t.Fatalf("emoji %v", sealed["emoji"])
	}

	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid+"/stickers/"+sid, f.at,
		map[string]any{"emoji": ""}, 400)
}

func TestStickerEditRequiresOwnership(t *testing.T) {
	f := setup(t)
	pid := newPack(t, f, f.at, "admin 的包")
	sid := addStickerTo(t, f, f.at, pid, "👍")

	req(t, f.s, "PATCH", "/v1/sticker-packs/"+pid+"/stickers/"+sid, f.bt,
		map[string]any{"emoji": "🔥"}, 403)
	req(t, f.s, "DELETE", "/v1/sticker-packs/"+pid+"/stickers/"+sid, f.bt, nil, 403)
}
