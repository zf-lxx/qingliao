package chat

import (
	"bytes"
	"image"
	"image/png"
	"strconv"
	"testing"
	"time"
)

func TestPasswordChangeAndTwoFactor(t *testing.T) {
	f := setup(t)
	sec := req(t, f.s, "GET", "/v1/me/security", f.bt, nil, 200)
	if sec["has_password"] != true || sec["two_factor_enabled"] != false {
		t.Fatal(sec)
	}
	req(t, f.s, "POST", "/v1/me/password", f.bt, map[string]any{"old_password": "test-password-long", "new_password": "short"}, 400)
	req(t, f.s, "POST", "/v1/me/password", f.bt, map[string]any{"old_password": "wrong-password-long", "new_password": "new-password-long", "hint": "pets"}, 401)
	changed := req(t, f.s, "POST", "/v1/me/password", f.bt, map[string]any{"old_password": "test-password-long", "new_password": "new-password-long", "hint": "pets"}, 200)
	if changed["password_hint"] != "pets" {
		t.Fatal(changed)
	}
	req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "test-password-long", "platform": "test"}, 401)
	started := req(t, f.s, "POST", "/v1/me/totp/start", f.bt, map[string]any{}, 200)
	secret, _ := started["secret"].(string)
	if secret == "" || started["otpauth_url"] == nil {
		t.Fatal(started)
	}
	req(t, f.s, "POST", "/v1/me/totp/confirm", f.bt, map[string]any{"code": "000000"}, 400)
	ok := req(t, f.s, "POST", "/v1/me/totp/confirm", f.bt, map[string]any{"code": totpAt(secret, time.Now().Unix()/30)}, 200)
	codes, _ := ok["recovery_codes"].([]any)
	if len(codes) != 8 {
		t.Fatal(ok)
	}
	sec = req(t, f.s, "GET", "/v1/me/security", f.bt, nil, 200)
	if sec["two_factor_enabled"] != true {
		t.Fatal(sec)
	}
	first := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "new-password-long", "platform": "test"}, 200)
	if first["two_factor_required"] != true || first["pending_token"] == nil {
		t.Fatal(first)
	}
	req(t, f.s, "POST", "/v1/auth/login/totp", "", map[string]any{"pending_token": first["pending_token"], "totp_code": "000000"}, 401)
	done := req(t, f.s, "POST", "/v1/auth/login/totp", "", map[string]any{"pending_token": first["pending_token"], "totp_code": totpAt(secret, time.Now().Unix()/30)}, 200)
	if done["access_token"] == nil {
		t.Fatal(done)
	}
	direct := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "new-password-long", "platform": "ios", "totp_code": totpAt(secret, time.Now().Unix()/30), "app_name": "轻聊", "device_model": "iPhone"}, 200)
	if direct["access_token"] == nil {
		t.Fatal(direct)
	}
	recovery := codes[0].(string)
	recovered := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "new-password-long", "recovery_code": recovery, "platform": "test"}, 200)
	if recovered["access_token"] == nil {
		t.Fatal(recovered)
	}
	req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "new-password-long", "recovery_code": recovery, "platform": "test"}, 401)
	req(t, f.s, "POST", "/v1/me/totp/disable", direct["access_token"].(string), map[string]any{"password": "new-password-long", "code": totpAt(secret, time.Now().Unix()/30)}, 200)
	again := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "new-password-long", "platform": "test"}, 200)
	if again["access_token"] == nil || again["two_factor_required"] == true {
		t.Fatal(again)
	}
}

func TestDevicesRemoteLogoutAndAccountDeletion(t *testing.T) {
	f := setup(t)
	second := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "test-password-long", "platform": "android", "app_name": "轻聊", "app_version": "0.4.2", "device_model": "Pixel"}, 200)
	st := second["access_token"].(string)
	listed := req(t, f.s, "GET", "/v1/devices", st, nil, 200)
	devs := listed["devices"].([]any)
	if len(devs) < 2 {
		t.Fatal(listed)
	}
	var other string
	current := 0
	for _, raw := range devs {
		d := raw.(map[string]any)
		if d["current"] == true {
			current++
			if d["app_name"] != "轻聊" || d["device_model"] != "Pixel" {
				t.Fatal(d)
			}
		} else {
			other = d["id"].(string)
		}
	}
	if current != 1 || other == "" {
		t.Fatal(listed)
	}
	req(t, f.s, "DELETE", "/v1/devices/"+other, st, nil, 200)
	req(t, f.s, "GET", "/v1/me", f.bt, nil, 401)
	third := req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "test-password-long", "platform": "desktop"}, 200)
	tt := third["access_token"].(string)
	req(t, f.s, "GET", "/v1/me", st, nil, 200)
	req(t, f.s, "POST", "/v1/devices/revoke-others", tt, map[string]any{}, 200)
	req(t, f.s, "GET", "/v1/me", st, nil, 401)
	listed = req(t, f.s, "GET", "/v1/devices", tt, nil, 200)
	if len(listed["devices"].([]any)) != 1 {
		t.Fatal(listed)
	}
	req(t, f.s, "POST", "/v1/me/delete", tt, map[string]any{"password": "wrong-password-long"}, 401)
	uid := third["user_id"].(string)
	req(t, f.s, "POST", "/v1/me/delete", tt, map[string]any{"password": "test-password-long", "reason": "leaving"}, 200)
	req(t, f.s, "POST", "/v1/auth/login", "", map[string]any{"handle": "bob", "password": "test-password-long", "platform": "test"}, 401)
	req(t, f.s, "GET", "/v1/me", tt, nil, 401)
	gone := req(t, f.s, "GET", "/v1/users/"+uid, f.at, nil, 200)
	if gone["display_name"] != "已注销" {
		t.Fatal(gone)
	}
}

func TestStoryAlbumsPersistAfterExpiry(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	media := uploadTinyPNG(t, f, f.at, cid)
	created := req(t, f.s, "POST", "/v1/stories", f.at, map[string]any{
		"media_id": media, "kind": "photo", "caption": "keep", "privacy": map[string]any{"type": "everyone"},
	}, 201)
	no := int(created["story_no"].(float64))
	album := req(t, f.s, "POST", "/v1/story-albums", f.at, map[string]any{"title": "精选", "story_nos": []int{no}}, 201)
	aid := album["id"].(string)
	if aid == "" {
		t.Fatal(album)
	}
	_, e := f.a.DB.Exec("UPDATE stories SET expires=? WHERE author_id=? AND story_no=?", time.Now().Unix()-10, f.admin.UserID, no)
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/stories/"+f.admin.UserID+"/"+strconv.Itoa(no), f.bt, nil, 200)
	listed := req(t, f.s, "GET", "/v1/story-albums?owner="+f.admin.UserID, f.bt, nil, 200)
	if len(listed["albums"].([]any)) != 1 {
		t.Fatal(listed)
	}
	detail := req(t, f.s, "GET", "/v1/story-albums/"+aid, f.bt, nil, 200)
	if len(detail["stories"].([]any)) != 1 {
		t.Fatal(detail)
	}
	req(t, f.s, "PATCH", "/v1/story-albums/"+aid, f.at, map[string]any{"title": "旅途"}, 200)
	req(t, f.s, "PUT", "/v1/story-albums/"+aid+"/stories", f.at, map[string]any{"op": "remove", "story_nos": []int{no}}, 200)
	req(t, f.s, "GET", "/v1/stories/"+f.admin.UserID+"/"+strconv.Itoa(no), f.bt, nil, 403)
	req(t, f.s, "DELETE", "/v1/story-albums/"+aid, f.at, nil, 200)
	req(t, f.s, "GET", "/v1/story-albums/"+aid, f.at, nil, 403)
}

func uploadTinyPNG(t *testing.T, f *fixture, token, cid string) string {
	t.Helper()
	var buf bytes.Buffer
	if e := png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 2, 2))); e != nil {
		t.Fatal(e)
	}
	media := uploadReq(t, f, token, cid, buf.Bytes(), 201)
	id, _ := media["id"].(string)
	if id == "" {
		t.Fatal(media)
	}
	return id
}
