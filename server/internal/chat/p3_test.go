package chat

import (
	"testing"
)

func TestPollCreateVoteAndClose(t *testing.T) {
	f := setup(t)
	cid, _ := f.a.CreateChat(f.admin, "group", "polls", []string{f.bob.UserID})
	created := req(t, f.s, "POST", "/v1/conversations/"+cid+"/polls", f.at, map[string]any{
		"question": "Tea or coffee?", "options": []string{"Tea", "Coffee"}, "anonymous": false, "client_msg_id": "p3poll",
	}, 201)
	if created["kind"] != "poll" {
		t.Fatal(created)
	}
	poll := created["poll"].(map[string]any)
	pid := poll["id"].(string)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/polls/"+pid+"/vote", f.bt, map[string]any{"option_ids": []int{0}}, 200)
	got := req(t, f.s, "GET", "/v1/conversations/"+cid+"/polls/"+pid, f.at, nil, 200)
	if int(got["total_voter_count"].(float64)) != 1 {
		t.Fatal(got)
	}
	opts := got["options"].([]any)
	if int(opts[0].(map[string]any)["voter_count"].(float64)) != 1 {
		t.Fatal(got)
	}
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/polls/"+pid+"/close", f.at, nil, 200)
	req(t, f.s, "POST", "/v1/conversations/"+cid+"/polls/"+pid+"/vote", f.bt, map[string]any{"option_ids": []int{1}}, 403)
	hist := req(t, f.s, "GET", "/v1/conversations/"+cid+"/messages", f.bt, nil, 200)
	msgs := hist["messages"].([]any)
	if len(msgs) == 0 || msgs[0].(map[string]any)["poll"] == nil {
		t.Fatal(hist)
	}
}

func TestChecklistAndContacts(t *testing.T) {
	f := setup(t)
	cid, _ := f.a.CreateChat(f.admin, "group", "lists", []string{f.bob.UserID})
	created := req(t, f.s, "POST", "/v1/conversations/"+cid+"/checklists", f.at, map[string]any{
		"title": "Picnic", "tasks": []string{"Bread", "Fruit"}, "others_can_add": true, "others_can_mark": true, "client_msg_id": "cl1",
	}, 201)
	if created["kind"] != "checklist" {
		t.Fatal(created)
	}
	mid := created["id"].(string)
	req(t, f.s, "POST", "/v1/messages/"+mid+"/checklist/done", f.bt, map[string]any{"done_task_ids": []int{1}}, 200)
	got := req(t, f.s, "GET", "/v1/messages/"+mid+"/checklist", f.at, nil, 200)
	tasks := got["checklist"].(map[string]any)["tasks"].([]any)
	if tasks[0].(map[string]any)["completed_by"] == "" {
		t.Fatal(got)
	}
	req(t, f.s, "POST", "/v1/messages/"+mid+"/checklist/tasks", f.bt, map[string]any{"tasks": []string{"Juice"}}, 200)
	req(t, f.s, "PUT", "/v1/me/contacts/"+f.bob.UserID, f.at, map[string]any{"first_name": "Bob", "last_name": ""}, 200)
	list := req(t, f.s, "GET", "/v1/me/contacts", f.at, nil, 200)
	if len(list["contacts"].([]any)) != 1 {
		t.Fatal(list)
	}
	req(t, f.s, "DELETE", "/v1/me/contacts/"+f.bob.UserID, f.at, nil, 200)
	list = req(t, f.s, "GET", "/v1/me/contacts", f.at, nil, 200)
	if len(list["contacts"].([]any)) != 0 {
		t.Fatal(list)
	}
}

func TestStickersNotificationsAndPrivacy(t *testing.T) {
	f := setup(t)
	packs := req(t, f.s, "GET", "/v1/sticker-packs", f.at, nil, 200)
	if len(packs["packs"].([]any)) < 1 {
		t.Fatal(packs)
	}
	pack := req(t, f.s, "GET", "/v1/sticker-packs/qingliao-basic", f.at, nil, 200)
	stickers := pack["stickers"].([]any)
	if len(stickers) < 8 {
		t.Fatal(pack)
	}
	sid := stickers[0].(map[string]any)["id"].(string)
	fid := stickers[0].(map[string]any)["file_id"].(string)
	req(t, f.s, "GET", "/v1/sticker-files/"+fid, f.at, nil, 200)
	req(t, f.s, "PUT", "/v1/me/sticker-favorites/"+sid, f.at, map[string]any{"favorite": true}, 200)
	fav := req(t, f.s, "GET", "/v1/me/sticker-favorites", f.at, nil, 200)
	if len(fav["stickers"].([]any)) != 1 {
		t.Fatal(fav)
	}
	cid := direct(t, f)
	sent := req(t, f.s, "POST", "/v1/conversations/"+cid+"/messages", f.at, map[string]any{
		"client_msg_id": "stk1", "kind": "sticker", "sticker_id": sid, "text": "",
	}, 200)
	if sent["kind"] != "sticker" {
		t.Fatal(sent)
	}
	req(t, f.s, "PUT", "/v1/me/notification-scopes/private", f.at, map[string]any{"mute_until": 0, "show_preview": false}, 200)
	scopes := req(t, f.s, "GET", "/v1/me/notification-scopes", f.at, nil, 200)
	if len(scopes["scopes"].([]any)) != 1 {
		t.Fatal(scopes)
	}
	req(t, f.s, "PUT", "/v1/me/privacy/rules", f.at, map[string]any{
		"setting": "userPrivacySettingShowStatus",
		"rules":   []any{map[string]any{"@type": "userPrivacySettingRuleAllowContacts"}},
	}, 200)
	rules := req(t, f.s, "GET", "/v1/me/privacy/rules?setting=userPrivacySettingShowStatus", f.at, nil, 200)
	if rules["rules"] == nil {
		t.Fatal(rules)
	}
	search := req(t, f.s, "GET", "/v1/stickers?q=👍", f.at, nil, 200)
	if len(search["stickers"].([]any)) < 1 {
		t.Fatal(search)
	}
}
