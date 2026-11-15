package chat

import (
	"encoding/json"
	"testing"
	"time"
)

func TestRound2PermissionsTransferUpgradeAndMessages(t *testing.T) {
	f := setup(t)
	gid, e := f.a.CreateChat(f.admin, "group", "round2", []string{f.bob.UserID})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+gid, f.at, map[string]any{"permissions": map[string]any{"can_send_basic_messages": false}}, 200)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages", f.bt, map[string]any{"client_msg_id": "denied", "kind": "text", "text": "no"}, 403)
	ok := req(t, f.s, "POST", "/v1/conversations/"+gid+"/messages", f.at, map[string]any{"client_msg_id": "owner", "kind": "text", "text": "yes"}, 200)
	if ok["kind"] != "text" {
		t.Fatal(ok)
	}
	req(t, f.s, "PATCH", "/v1/conversations/"+gid, f.at, map[string]any{"permissions": map[string]any{"can_send_basic_messages": true}}, 200)

	req(t, f.s, "POST", "/v1/conversations/"+gid+"/transfer", f.bt, map[string]any{"user_id": f.admin.UserID, "password": "test-password-long"}, 403)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/transfer", f.at, map[string]any{"user_id": f.bob.UserID, "password": "wrong-password"}, 403)
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/transfer", f.at, map[string]any{"user_id": f.bob.UserID, "password": "test-password-long"}, 200)
	var bobRole, adminRole string
	f.a.DB.QueryRow("SELECT role FROM members WHERE chat_id=? AND user_id=?", gid, f.bob.UserID).Scan(&bobRole)
	f.a.DB.QueryRow("SELECT role FROM members WHERE chat_id=? AND user_id=?", gid, f.admin.UserID).Scan(&adminRole)
	if bobRole != "owner" || adminRole != "admin" {
		t.Fatal(bobRole, adminRole)
	}

	up := req(t, f.s, "POST", "/v1/conversations/"+gid+"/upgrade", f.bt, map[string]any{}, 200)
	if up["upgraded"] != true || up["kind"] != "group" {
		t.Fatal(up)
	}
	if _, e = f.a.SendMessage(f.admin, gid, Send{ClientID: "after-upgrade", Text: "still a member"}); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/upgrade", f.bt, map[string]any{}, 400)

	dice, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "dice", Kind: "dice", Text: "🎲"})
	if e != nil {
		t.Fatal(e)
	}
	var rolled struct {
		Emoji string `json:"emoji"`
		Value int    `json:"value"`
	}
	if json.Unmarshal(dice.Extra, &rolled) != nil || rolled.Emoji != "🎲" || rolled.Value < 1 || rolled.Value > 6 {
		t.Fatalf("%s", dice.Extra)
	}
	again, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "dice", Kind: "dice", Text: "🎲"})
	if e != nil || again.ID != dice.ID {
		t.Fatal(again, e)
	}

	loc, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "loc", Kind: "location", Extra: json.RawMessage(`{"latitude":31.2,"longitude":121.5,"title":"外滩","address":"上海"}`)})
	if e != nil || loc.Kind != "location" || !json.Valid(loc.Extra) {
		t.Fatal(loc, e)
	}
	card, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "card", Kind: "contact", Extra: json.RawMessage(`{"phone_number":"+8613800138000","first_name":"李","last_name":"四"}`)})
	if e != nil || card.Kind != "contact" {
		t.Fatal(card, e)
	}

	future := time.Now().Unix() + 3600
	sched, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "later", Text: "定时", SendAt: future})
	if e != nil || !sched.Scheduled || sched.Seq != 0 {
		t.Fatalf("%+v %v", sched, e)
	}
	hist, e := f.a.History(f.bob, gid, 0, 50)
	if e != nil {
		t.Fatal(e)
	}
	for _, m := range hist {
		if m.ClientID == "later" {
			t.Fatal("scheduled leaked into history")
		}
	}
	if _, e = f.a.DB.Exec("UPDATE scheduled_messages SET send_at=? WHERE id=?", time.Now().Unix()-1, sched.ID); e != nil {
		t.Fatal(e)
	}
	f.a.releaseScheduled()
	found := false
	hist, _ = f.a.History(f.bob, gid, 0, 50)
	for _, m := range hist {
		if m.ClientID == "later" && m.Text == "定时" && !m.Scheduled {
			found = true
		}
	}
	if !found {
		t.Fatal("scheduled message was not released", hist)
	}

	secret, e := f.a.SendMessage(f.admin, gid, Send{ClientID: "once", Text: "阅后即焚", TTL: -1})
	if e != nil {
		t.Fatal(e)
	}
	if e = f.a.Read(f.bob, gid, secret.Seq); e != nil {
		t.Fatal(e)
	}
	var deleted int
	f.a.DB.QueryRow("SELECT deleted FROM messages WHERE id=?", secret.ID).Scan(&deleted)
	if deleted != 1 {
		t.Fatal("view-once survived a read")
	}

	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/auto-delete", f.bt, map[string]any{"seconds": 60}, 200)
	timed, e := f.a.SendMessage(f.bob, gid, Send{ClientID: "auto", Text: "会过期"})
	if e != nil || timed.TTL != 60 {
		t.Fatal(timed, e)
	}
	past := time.Now().Add(-2 * time.Hour).UTC().Format(time.RFC3339Nano)
	if _, e = f.a.DB.Exec("UPDATE messages SET created=? WHERE id=?", past, timed.ID); e != nil {
		t.Fatal(e)
	}
	f.a.expireMessages()
	f.a.DB.QueryRow("SELECT deleted FROM messages WHERE id=?", timed.ID).Scan(&deleted)
	if deleted != 1 {
		t.Fatal("ttl was not tombstoned")
	}

	req(t, f.s, "PUT", "/v1/conversations/"+gid+"/history", f.bt, map[string]any{"history_for_new": true}, 200)
	if e = f.a.ChangeMember(f.bob, gid, f.eve.UserID, "add", ""); e != nil {
		t.Fatal(e)
	}
	var joined int64
	f.a.DB.QueryRow("SELECT joined_seq FROM members WHERE chat_id=? AND user_id=?", gid, f.eve.UserID).Scan(&joined)
	if joined != 0 {
		t.Fatal(joined)
	}
	eveHist, e := f.a.History(f.eve, gid, 0, 50)
	if e != nil || len(eveHist) == 0 {
		t.Fatal(eveHist, e)
	}

	visible, e := f.a.SendMessage(f.bob, gid, Send{ClientID: "deliver-me", Text: "送到了吗"})
	if e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "POST", "/v1/conversations/"+gid+"/delivered", f.at, map[string]any{"seq": visible.Seq}, 200)
	viewers := req(t, f.s, "GET", "/v1/conversations/"+gid+"/messages/"+itoa(visible.Seq)+"/viewers", f.bt, nil, 200)
	rawViewers, _ := viewers["viewers"].([]any)
	if len(rawViewers) != 1 {
		t.Fatal(viewers)
	}
	unread := req(t, f.s, "GET", "/v1/conversations/"+gid+"/messages/"+itoa(visible.Seq)+"/read-date", f.bt, nil, 200)
	if unread["@type"] != "messageReadDateUnread" {
		t.Fatal(unread)
	}
	if e = f.a.Read(f.admin, gid, visible.Seq); e != nil {
		t.Fatal(e)
	}
	read := req(t, f.s, "GET", "/v1/conversations/"+gid+"/messages/"+itoa(visible.Seq)+"/read-date", f.bt, nil, 200)
	if read["@type"] != "messageReadDateRead" {
		t.Fatal(read)
	}

	pack := req(t, f.s, "POST", "/v1/sticker-packs", f.at, map[string]any{"title": "动图", "is_emoji": true}, 201)
	pid := pack["id"].(string)
	if _, e = f.a.DB.Exec("INSERT INTO media(id,owner,chat_id,mime,bytes,sha256,created,file_name) VALUES(?,?,?,?,?,?,?,?)", "webmmedia0000000000000000000001", f.admin.UserID, "", "video/webm", 8, "abc", now(), "pop.webm"); e != nil {
		t.Fatal(e)
	}
	added := req(t, f.s, "POST", "/v1/sticker-packs/"+pid+"/stickers", f.at, map[string]any{"emoji": "✨", "media_id": "webmmedia0000000000000000000001"}, 201)
	var format string
	f.a.DB.QueryRow("SELECT format FROM stickers WHERE id=?", added["id"]).Scan(&format)
	if format != "webm" {
		t.Fatal(format)
	}
	emoji := req(t, f.s, "GET", "/v1/custom-emoji", f.at, nil, 200)
	if len(emoji["stickers"].([]any)) != 1 {
		t.Fatal(emoji)
	}

	if _, e = f.a.DB.Exec("INSERT INTO link_previews(id,url,title,description,image,site_name,fetched_at) VALUES(?,?,?,?,?,?,?)", "prevprivate", "https://example.com/a", "t", "", "http://127.0.0.1/secret.png", "", time.Now().Unix()); e != nil {
		t.Fatal(e)
	}
	req(t, f.s, "GET", "/v1/link-previews/prevprivate/image", f.at, nil, 403)
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
