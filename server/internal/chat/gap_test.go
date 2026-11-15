package chat

import "testing"

func TestProfileBioUsernameAndConversationMeta(t *testing.T) {
	f := setup(t)
	me := req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"bio": "你好", "username": "Admin_New"}, 200)
	if me["bio"] != "你好" || me["handle"] != "admin_new" {
		t.Fatal(me)
	}
	req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"username": "bob"}, 409)
	long := ""
	for i := 0; i < 71; i++ {
		long += "字"
	}
	req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"bio": long}, 400)
	got := req(t, f.s, "GET", "/v1/me", f.at, nil, 200)
	if got["bio"] != "你好" || got["handle"] != "admin_new" {
		t.Fatal(got)
	}

	gid, e := f.a.CreateChat(f.admin, "group", "meta", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+gid, f.bt, map[string]any{"description": "nope"}, 403)
	perms := map[string]any{"@type": "chatPermissions", "can_send_polls": false}
	req(t, f.s, "PATCH", "/v1/conversations/"+gid, f.at, map[string]any{
		"description": "关于这个群", "slow_mode_seconds": 3600, "permissions": perms,
	}, 200)
	info := req(t, f.s, "GET", "/v1/conversations/"+gid, f.bt, nil, 200)
	if info["description"] != "关于这个群" || int(info["slow_mode_seconds"].(float64)) != 3600 {
		t.Fatal(info)
	}
	if info["permissions"].(map[string]any)["can_send_polls"] != false {
		t.Fatal(info)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages", f.bt, map[string]any{"client_msg_id": "slow1", "kind": "text", "text": "first"}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages", f.bt, map[string]any{"client_msg_id": "slow2", "kind": "text", "text": "second"}, 429)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages", f.at, map[string]any{"client_msg_id": "slow-owner", "kind": "text", "text": "owner"}, 200)

	found := req(t, f.s, "GET", "/v1/conversations/"+gid+"/members?q=bob", f.at, nil, 200)
	members := found["members"].([]any)
	if len(members) != 1 || members[0].(map[string]any)["user_id"] != f.bob.UserID {
		t.Fatal(found)
	}
	none := req(t, f.s, "GET", "/v1/conversations/"+gid+"/members?q=zzzz", f.at, nil, 200)
	if len(none["members"].([]any)) != 0 {
		t.Fatal(none)
	}
}

func TestDirectDeleteReopenHidesOldHistory(t *testing.T) {
	f := setup(t)
	cid := direct(t, f)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/messages", f.at, map[string]any{"client_msg_id": "keep", "kind": "text", "text": "still there"}, 200)
	req(t, f.s, "DELETE", "/v1/conversations/"+cid, f.at, nil, 200)
	req(t, f.s, "GET", "/v1/conversations/"+cid+"/messages", f.at, nil, 403)
	bob := req(t, f.s, "GET", "/v1/conversations/"+cid+"/messages", f.bt, nil, 200)
	if len(bob["messages"].([]any)) != 1 {
		t.Fatal(bob)
	}
	again, e := f.a.CreateChat(f.admin, "direct", "", []string{f.bob.UserID})
	if e != nil || again != cid {
		t.Fatalf("reopen %s %v", again, e)
	}
	mine := req(t, f.s, "GET", "/v1/conversations/"+cid+"/messages", f.at, nil, 200)
	if len(mine["messages"].([]any)) != 0 {
		t.Fatal(mine)
	}
	bob = req(t, f.s, "GET", "/v1/conversations/"+cid+"/messages", f.bt, nil, 200)
	if len(bob["messages"].([]any)) != 1 {
		t.Fatal(bob)
	}
}

func TestOwnerDeletesGroupForEveryone(t *testing.T) {
	f := setup(t)
	gid, e := f.a.CreateChat(f.admin, "group", "gone", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "DELETE", "/v1/conversations/"+gid, f.bt, nil, 403)
	req(t, f.s, "DELETE", "/v1/conversations/"+gid, f.at, nil, 200)
	req(t, f.s, "GET", "/v1/conversations/"+gid, f.bt, nil, 403)
	req(t, f.s, "GET", "/v1/conversations/"+gid, f.at, nil, 403)
}

func TestInvitesWallpapersSenderAndPollOption(t *testing.T) {
	f := setup(t)
	gid, e := f.a.CreateChat(f.admin, "group", "links", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+gid, f.at, map[string]any{"permissions": map[string]any{"can_invite_users": false}}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/invites", f.bt, map[string]any{"name": "no"}, 403)
	created := req(t, f.s, "POST", "/v1/conversations/"+gid+"/invites", f.at, map[string]any{"name": "door", "member_limit": 5}, 201)
	code := created["code"].(string)
	if created["invite_link"] != "ql://join/"+code {
		t.Fatal(created)
	}
	preview := req(t, f.s, "GET", "/v1/invites/"+code, f.et, nil, 200)
	if preview["title"] != "links" || int(preview["member_count"].(float64)) != 2 {
		t.Fatal(preview)
	}
	joined := req(t, f.s, "POST", "/v1/invites/"+code+"/join", f.et, nil, 200)
	if joined["conversation_id"] != gid {
		t.Fatal(joined)
	}
	req(t, f.s, "PATCH", "/v1/invites/"+code, f.at, map[string]any{"name": "renamed"}, 200)
	req(t, f.s, "DELETE", "/v1/invites/"+code, f.at, nil, 200)
	req(t, f.s, "POST", "/v1/invites/"+code+"/join", f.bt, nil, 403)
	revoked := req(t, f.s, "GET", "/v1/conversations/"+gid+"/invites?revoked=1", f.at, nil, 200)
	if len(revoked["invites"].([]any)) != 1 {
		t.Fatal(revoked)
	}

	req(t, f.s, "PUT", "/v1/me/wallpapers", f.at, map[string]any{"chat_id": gid, "background": map[string]any{"@type": "chatBackground"}}, 200)
	req(t, f.s, "PUT", "/v1/me/wallpapers", f.at, map[string]any{"chat_id": "@default", "background": map[string]any{"@type": "background", "id": 1}}, 200)
	req(t, f.s, "PUT", "/v1/me/wallpapers", f.bt, map[string]any{"chat_id": "not-a-chat", "background": map[string]any{"a": 1}}, 403)
	papers := req(t, f.s, "GET", "/v1/me/wallpapers", f.at, nil, 200)
	if len(papers["wallpapers"].([]any)) != 2 {
		t.Fatal(papers)
	}
	req(t, f.s, "DELETE", "/v1/me/wallpapers?chat_id="+gid, f.at, nil, 200)
	papers = req(t, f.s, "GET", "/v1/me/wallpapers", f.at, nil, 200)
	if len(papers["wallpapers"].([]any)) != 1 {
		t.Fatal(papers)
	}

	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages", f.bt, map[string]any{"client_msg_id": "bob1", "kind": "text", "text": "from bob"}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages/by-sender", f.bt, map[string]any{"user_id": f.admin.UserID}, 403)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages/by-sender", f.at, map[string]any{"user_id": f.bob.UserID}, 200)
	hist := req(t, f.s, "GET", "/v1/conversations/"+gid+"/messages", f.at, nil, 200)
	var saw bool
	for _, raw := range hist["messages"].([]any) {
		m := raw.(map[string]any)
		if m["sender_id"] == f.bob.UserID {
			saw = true
			if m["deleted"] != true {
				t.Fatal(m)
			}
		}
	}
	if !saw {
		t.Fatal(hist)
	}

	poll := req(t, f.s, "POST", "/v1/conversations/"+gid+"/polls", f.at, map[string]any{
		"question": "Pick", "options": []string{"A", "B"}, "client_msg_id": "optpoll",
	}, 201)
	pid := poll["poll"].(map[string]any)["id"].(string)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/polls/"+pid+"/options", f.bt, map[string]any{"text": "no"}, 403)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/polls/"+pid+"/options", f.at, map[string]any{"text": "C"}, 200)
	got := req(t, f.s, "GET", "/v1/conversations/"+gid+"/polls/"+pid, f.at, nil, 200)
	if len(got["options"].([]any)) != 3 {
		t.Fatal(got)
	}
}
