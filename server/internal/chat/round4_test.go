package chat

import "testing"

func TestRound4RestrictionsFlagsProfileAndFolders(t *testing.T) {
	f := setup(t)
	gid, e := f.a.CreateChat(f.admin, "group", "round4", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/members/"+f.bob.UserID+"/status", f.bt, map[string]any{"status": "banned"}, 403)
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/members/"+f.bob.UserID+"/status", f.at, map[string]any{
		"status": "restricted", "is_member": true, "until": 0,
		"permissions": map[string]any{"can_send_basic_messages": false, "can_react_to_messages": false},
	}, 200)
	if _, e = f.a.SendMessage(f.bob, gid, Send{ClientID: "blocked", Text: "不行"}); e == nil {
		t.Fatal("restricted member sent text")
	}
	if _, e = f.a.SendMessage(f.admin, gid, Send{ClientID: "admin-ok", Text: "可以"}); e != nil {
		t.Fatal(e)
	}
	msg, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "react-host", Text: "表情"})
	if e != nil {
		t.Fatal(e)
	}
	if e = f.a.React(f.bob, msg.ID, "👍", false); e == nil {
		t.Fatal("restricted reaction accepted")
	}
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/members/"+f.bob.UserID+"/status", f.at, map[string]any{"status": "member"}, 200)
	if _, e = f.a.SendMessage(f.bob, gid, Send{ClientID: "after-clear", Text: "恢复"}); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/flags", f.at, map[string]any{
		"reactions":     map[string]any{"@type": "chatAvailableReactionsSome", "reactions": []any{map[string]any{"emoji": "👍"}}},
		"sign_messages": true, "show_message_sender": true, "hidden_members": true, "join_to_send": true,
	}, 200)
	if e = f.a.React(f.bob, msg.ID, "❤️", false); e == nil {
		t.Fatal("reaction outside the allow list")
	}
	if e = f.a.React(f.bob, msg.ID, "👍", false); e != nil {
		t.Fatal(e)
	}
	conv := req(t, f.s, "GET", "/v1/conversations/"+gid, f.bt, nil, 200)
	if conv["sign_messages"] != true || conv["hidden_members"] != true || conv["join_to_send"] != true || conv["show_message_sender"] != true {
		t.Fatal(conv)
	}
	reactions, _ := conv["reactions"].(map[string]any)
	if reactions["@type"] != "chatAvailableReactionsSome" {
		t.Fatal(conv["reactions"])
	}

	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/members/"+f.bob.UserID+"/tag", f.at, map[string]any{"tag": "值日"}, 200)
	members := req(t, f.s, "GET", "/v1/conversations/"+gid+"/members", f.at, nil, 200)
	foundTag := false
	for _, item := range members["members"].([]any) {
		m := item.(map[string]any)
		if m["user_id"] == f.bob.UserID && m["tag"] == "值日" {
			foundTag = true
		}
	}
	if !foundTag {
		t.Fatal(members)
	}

	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/members/"+f.bob.UserID+"/status", f.at, map[string]any{"status": "banned"}, 200)
	bans := req(t, f.s, "GET", "/v1/conversations/"+gid+"/bans", f.at, nil, 200)
	list, _ := bans["bans"].([]any)
	if len(list) != 1 || list[0].(map[string]any)["user_id"] != f.bob.UserID {
		t.Fatal(bans)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/members", f.at, map[string]any{"user_id": f.bob.UserID, "action": "add"}, 403)
	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/members/"+f.bob.UserID+"/status", f.at, map[string]any{"status": "left"}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/members", f.at, map[string]any{"user_id": f.bob.UserID, "action": "add"}, 200)
	if _, e = f.a.SendMessage(f.bob, gid, Send{ClientID: "rejoined", Text: "回来了"}); e != nil {
		t.Fatal(e)
	}

	req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"birthdate": map[string]any{"day": 32, "month": 1, "year": 0}}, 400)
	me := req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{
		"birthdate": map[string]any{"day": 3, "month": 4, "year": 0}, "accent_color_id": 0, "profile_accent_color_id": -1,
	}, 200)
	born, _ := me["birthdate"].(map[string]any)
	if born["day"] != float64(3) || born["month"] != float64(4) || me["accent_color_id"] != float64(0) || me["profile_accent_color_id"] != float64(-1) {
		t.Fatal(me)
	}
	me = req(t, f.s, "PATCH", "/v1/me", f.at, map[string]any{"birthdate": nil}, 200)
	if _, ok := me["birthdate"]; ok {
		t.Fatal(me)
	}

	folder := req(t, f.s, "POST", "/v1/folders", f.at, map[string]any{
		"name": "分享", "filter": map[string]any{"include_chat_ids": []string{gid}, "exclude_chat_ids": []string{}, "types": []string{}, "unread_only": false},
	}, 200)
	inv := req(t, f.s, "POST", "/v1/folders/"+folder["id"].(string)+"/invites", f.at, map[string]any{"name": "一组", "chat_ids": []string{gid}}, 201)
	code := inv["code"].(string)
	if inv["invite_link"] != "ql://folder/"+code {
		t.Fatal(inv)
	}
	preview := req(t, f.s, "GET", "/v1/folder-invites/"+code, f.et, nil, 200)
	if preview["title"] != "分享" {
		t.Fatal(preview)
	}
	var before int
	f.a.DB.QueryRow("SELECT count(*) FROM members WHERE chat_id=?", gid).Scan(&before)
	joined := req(t, f.s, "POST", "/v1/folder-invites/"+code+"/join", f.et, map[string]any{}, 200)
	chats, _ := joined["chat_ids"].([]any)
	if len(chats) != 0 {
		t.Fatal("join added chats the user is not in", joined)
	}
	var after int
	f.a.DB.QueryRow("SELECT count(*) FROM members WHERE chat_id=?", gid).Scan(&after)
	if after != before {
		t.Fatal("folder join changed membership", before, after)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/members", f.at, map[string]any{"user_id": f.eve.UserID, "action": "add"}, 200)
	again := req(t, f.s, "POST", "/v1/folder-invites/"+code+"/join", f.et, map[string]any{}, 200)
	againChats, _ := again["chat_ids"].([]any)
	if len(againChats) != 1 || againChats[0] != gid {
		t.Fatal(again)
	}
	req(t, f.s, "DELETE", "/v1/folder-invites/"+code, f.at, nil, 200)
	req(t, f.s, "GET", "/v1/folder-invites/"+code, f.et, nil, 403)
}
