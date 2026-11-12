package chat

import (
	"bytes"
	"image"
	"image/png"
	"strconv"
	"testing"
)

func TestStoriesPostViewAndPrivacy(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	var buf bytes.Buffer
	png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 2, 2)))
	media := uploadReq(t, f, f.at, cid, buf.Bytes(), 201)
	mid := media["id"].(string)
	created := req(t, f.s, "POST", "/v1/stories", f.at, map[string]any{
		"media_id": mid, "kind": "photo", "caption": "hello", "privacy": map[string]any{"type": "everyone"},
	}, 201)
	no := int(created["story_no"].(float64))
	if no < 1 {
		t.Fatal(created)
	}
	author := f.admin.UserID
	path := "/v1/stories/" + author + "/" + strconv.Itoa(no)
	got := req(t, f.s, "GET", path, f.bt, nil, 200)
	if got["caption"] != "hello" {
		t.Fatal(got)
	}
	req(t, f.s, "POST", path+"/open", f.bt, map[string]any{}, 200)
	req(t, f.s, "PUT", path+"/reaction", f.bt, map[string]any{"emoji": "👍"}, 200)
	inter := req(t, f.s, "GET", path+"/interactions", f.at, nil, 200)
	if len(inter["interactions"].([]any)) != 1 {
		t.Fatal(inter)
	}
	active := req(t, f.s, "GET", "/v1/stories/active", f.bt, nil, 200)
	if len(active["chats"].([]any)) < 1 {
		t.Fatal(active)
	}
	req(t, f.s, "POST", path+"/report", f.bt, map[string]any{"reason": "spam"}, 200)
	req(t, f.s, "DELETE", path, f.at, nil, 200)
	req(t, f.s, "GET", path, f.bt, nil, 403)
}
