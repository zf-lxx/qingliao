package chat

import (
	"testing"
	"time"
)

func TestRound3LinksJoinsPollsAndSchedule(t *testing.T) {
	f := setup(t)
	gid, e := f.a.CreateChat(f.admin, "group", "round3", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/upgrade", f.at, map[string]any{}, 200)
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/username", f.bt, map[string]any{"username": "roundthree"}, 403)
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/username", f.at, map[string]any{"username": "bob"}, 409)
	named := req(t, f.s, "PUT", "/v1/conversations/"+gid+"/username", f.at, map[string]any{"username": "RoundThree"}, 200)
	if named["username"] != "roundthree" {
		t.Fatal(named)
	}
	pub := req(t, f.s, "GET", "/v1/public/roundthree", f.et, nil, 200)
	chat, _ := pub["chat"].(map[string]any)
	if pub["kind"] != "chat" || chat["id"] != gid {
		t.Fatal(pub)
	}
	joined := req(t, f.s, "POST", "/v1/public/roundthree/join", f.et, map[string]any{}, 200)
	if joined["status"] != "joined" || joined["conversation_id"] != gid {
		t.Fatal(joined)
	}
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/protected", f.at, map[string]any{"enabled": true}, 200)
	msg, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "secret", Text: "不要转发"})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = f.a.ForwardMessage(f.bob, msg.ID, direct(t, f), "fwd-secret"); e == nil {
		t.Fatal("protected forward succeeded")
	}
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/protected", f.at, map[string]any{"enabled": false}, 200)

	past := req(t, f.s, "GET", "/v1/conversations/"+gid+"/by-date?at=1", f.bt, nil, 404)
	if past["error"] != "not_found" {
		t.Fatal(past)
	}
	found := req(t, f.s, "GET", "/v1/conversations/"+gid+"/by-date?at="+itoa(time.Now().Unix()+30), f.bt, nil, 200)
	if found["id"] != msg.ID {
		t.Fatal(found)
	}

	poll := req(t, f.s, "POST", "/v1/conversations/"+gid+"/polls", f.at, map[string]any{
		"question": "去哪", "options": []string{"左", "右"}, "client_msg_id": "poll-r3",
	}, 201)
	pollBody, _ := poll["poll"].(map[string]any)
	pid, _ := pollBody["id"].(string)
	if pid == "" {
		t.Fatal(poll)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/polls/"+pid+"/vote", f.bt, map[string]any{"option_ids": []int{0}, "client_vote_id": "v"}, 200)
	voters := req(t, f.s, "GET", "/v1/conversations/"+gid+"/polls/"+pid+"/voters?option_id=0", f.at, nil, 200)
	list, _ := voters["voters"].([]any)
	if voters["total_count"] != float64(1) || len(list) != 1 {
		t.Fatal(voters)
	}
	anon := req(t, f.s, "POST", "/v1/conversations/"+gid+"/polls", f.at, map[string]any{
		"question": "匿名", "options": []string{"a", "b"}, "anonymous": true, "client_msg_id": "poll-anon",
	}, 201)
	anonBody, _ := anon["poll"].(map[string]any)
	req(t, f.s, "GET", "/v1/conversations/"+gid+"/polls/"+anonBody["id"].(string)+"/voters?option_id=0", f.at, nil, 403)

	inv := req(t, f.s, "POST", "/v1/conversations/"+gid+"/invites", f.at, map[string]any{"name": "审", "creates_join_request": true}, 201)
	code := inv["code"].(string)
	other := req(t, f.s, "POST", "/v1/auth/register", "", map[string]any{"handle": "nina", "password": "test-password-long", "invite_code": mustAccountInvite(t, f), "platform": "test"}, 201)
	nt := other["access_token"].(string)
	asked := req(t, f.s, "POST", "/v1/invites/"+code+"/join", nt, map[string]any{}, 200)
	if asked["status"] != "requested" {
		t.Fatal(asked)
	}
	var n int
	f.a.DB.QueryRow("SELECT count(*) FROM members WHERE chat_id=? AND user_id=(SELECT id FROM users WHERE handle='nina')", gid).Scan(&n)
	if n != 0 {
		t.Fatal("request joined immediately")
	}
	pending := req(t, f.s, "GET", "/v1/conversations/"+gid+"/join-requests", f.at, nil, 200)
	reqs, _ := pending["requests"].([]any)
	if len(reqs) != 1 {
		t.Fatal(pending)
	}
	nina := reqs[0].(map[string]any)["user_id"].(string)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/join-requests/"+nina, f.bt, map[string]any{"approve": true}, 403)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/join-requests/"+nina, f.at, map[string]any{"approve": true}, 200)
	f.a.DB.QueryRow("SELECT count(*) FROM members WHERE chat_id=? AND user_id=?", gid, nina).Scan(&n)
	if n != 1 {
		t.Fatal("approve did not add member")
	}

	when := time.Now().Unix() + 7200
	sched, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "later-r3", Text: "稍后", SendAt: when})
	if e != nil || !sched.Scheduled {
		t.Fatal(sched, e)
	}
	req(t, f.s, "PATCH", "/v1/scheduled/"+sched.ID, f.at, map[string]any{"send_at": when + 60}, 200)
	req(t, f.s, "POST", "/v1/scheduled/"+sched.ID+"/send", f.at, nil, 200)
	hist, e := f.a.History(f.bob, gid, 0, 50)
	if e != nil {
		t.Fatal(e)
	}
	seen := false
	for _, m := range hist {
		if m.Text == "稍后" {
			seen = true
		}
	}
	if !seen {
		t.Fatal("scheduled send did not land")
	}

	media := id()
	if _, e = f.a.DB.Exec("INSERT INTO media(id,owner,chat_id,mime,bytes,sha256,created,file_name) VALUES(?,?,?,?,?,?,?,?)", media, f.admin.UserID, gid, "image/png", 4, "abc", now(), "a.png"); e != nil {
		t.Fatal(e)
	}
	photo, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "pic", Kind: "image", Text: "图", MediaID: media})
	if e != nil {
		t.Fatal(e)
	}
	media2 := id()
	if _, e = f.a.DB.Exec("INSERT INTO media(id,owner,chat_id,mime,bytes,sha256,created,file_name) VALUES(?,?,?,?,?,?,?,?)", media2, f.admin.UserID, gid, "image/gif", 4, "def", now(), "a.gif"); e != nil {
		t.Fatal(e)
	}
	edited := req(t, f.s, "PATCH", "/v1/messages/"+photo.ID+"/media", f.at, map[string]any{"kind": "animation", "text": "动图", "media_id": media2}, 200)
	if edited["kind"] != "animation" || edited["text"] != "动图" {
		t.Fatal(edited)
	}
	page := req(t, f.s, "GET", "/v1/conversations/"+gid+"/media?kind=animation&limit=5", f.bt, nil, 200)
	items, _ := page["messages"].([]any)
	if len(items) != 1 {
		t.Fatal(page)
	}

	dialogs := req(t, f.s, "GET", "/v1/conversations?limit=100&archived=all", f.at, nil, 200)
	var row map[string]any
	for _, item := range dialogs["conversations"].([]any) {
		d := item.(map[string]any)
		if d["id"] == gid {
			row = d
		}
	}
	if row == nil || row["upgraded"] != true || row["username"] != "roundthree" || row["protected"] != false {
		t.Fatal(row)
	}
}

func mustAccountInvite(t *testing.T, f *fixture) string {
	t.Helper()
	v := req(t, f.s, "POST", "/v1/invites", f.at, map[string]any{"uses": 1, "expires_hours": 1}, 201)
	return v["invite_code"].(string)
}
