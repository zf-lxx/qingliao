package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// PushProvider is intentionally independent from delivery/read receipts.
type PushProvider interface {
	Send(context.Context, string, string, string) error
}
type XiaomiPush struct {
	Secret, Package, Endpoint string
	Client                    *http.Client
}

func (x *XiaomiPush) Send(ctx context.Context, regid, cid, mid string) error {
	if x.Secret == "" || x.Package == "" {
		return fmt.Errorf("xiaomi_not_configured")
	}
	payload, _ := json.Marshal(map[string]string{"conversation_id": cid, "message_id": mid})
	v := url.Values{"registration_id": {regid}, "restricted_package_name": {x.Package}, "title": {"轻聊"}, "description": {"你有一条新消息"}, "payload": {string(payload)}, "pass_through": {"0"}, "notify_type": {"-1"}, "extra.notify_effect": {"1"}, "extra.jobkey": {hash(mid)[:20]}}
	req, e := http.NewRequestWithContext(ctx, "POST", x.Endpoint, strings.NewReader(v.Encode()))
	if e != nil {
		return e
	}
	req.Header.Set("Authorization", "key="+x.Secret)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	client := x.Client
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}
	resp, e := client.Do(req)
	if e != nil {
		return fmt.Errorf("xiaomi_transport_error")
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("xiaomi_http_%d", resp.StatusCode)
	}
	var result struct {
		Code   int    `json:"code"`
		Result string `json:"result"`
	}
	if e = json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&result); e != nil {
		return fmt.Errorf("xiaomi_bad_response")
	}
	if result.Code != 0 || result.Result != "ok" {
		return fmt.Errorf("xiaomi_rejected_%d", result.Code)
	}
	return nil
}

// Transactional jobs survive restart; retry 6 times, then done=-1 (dead letter).
func (a *App) pushWorker() {
	defer close(a.done)
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	for {
		select {
		case <-a.stop:
			return
		case <-tick.C:
			a.expireNotificationMutes()
			a.processPush()
		}
	}
}
func (a *App) processPush() {
	type job struct {
		id, user, chat, msg string
		attempts            int
	}
	rows, e := a.DB.Query("SELECT id,user_id,chat_id,msg_id,attempts FROM push_jobs WHERE done=0 AND next_at<=? ORDER BY rowid LIMIT 16", time.Now().Unix())
	if e != nil {
		return
	}
	jobs := []job{}
	for rows.Next() {
		var j job
		if rows.Scan(&j.id, &j.user, &j.chat, &j.msg, &j.attempts) == nil {
			jobs = append(jobs, j)
		}
	}
	rows.Close()
	for _, j := range jobs {
		select {
		case <-a.stop:
			return
		default:
		}
		if !a.isMember(j.chat, j.user) || a.online(j.user) {
			a.DB.Exec("UPDATE push_jobs SET done=1,last_error='online_or_not_member' WHERE id=?", j.id)
			continue
		}
		var unread int
		a.DB.QueryRow("SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.id=? AND b.user_id=? AND m.seq>b.read_seq AND m.seq>b.joined_seq AND m.deleted=0 AND b.notification_mute_until<=unixepoch()", j.msg, j.user).Scan(&unread)
		if unread == 0 {
			a.DB.Exec("UPDATE push_jobs SET done=1 WHERE id=?", j.id)
			continue
		}
		if a.C.XiaomiSecret == "" || a.C.XiaomiPackage == "" {
			a.DB.Exec("UPDATE push_jobs SET next_at=?,last_error='xiaomi_not_configured' WHERE id=?", time.Now().Add(5*time.Minute).Unix(), j.id)
			continue
		}
		rows, e = a.DB.Query("SELECT push_token FROM devices WHERE user_id=? AND revoked=0 AND push_provider='xiaomi' AND push_token<>''", j.user)
		if e != nil {
			continue
		}
		tokens := []string{}
		for rows.Next() {
			var t string
			if rows.Scan(&t) == nil {
				tokens = append(tokens, t)
			}
		}
		rows.Close()
		if len(tokens) == 0 {
			a.DB.Exec("UPDATE push_jobs SET done=1,last_error='no_push_token' WHERE id=?", j.id)
			continue
		}
		provider := &XiaomiPush{Secret: a.C.XiaomiSecret, Package: a.C.XiaomiPackage, Endpoint: a.C.XiaomiURL}
		var sendError error
		for _, token := range tokens {
			ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
			e = provider.Send(ctx, token, j.chat, j.msg)
			cancel()
			if e != nil {
				sendError = e
			}
		}
		if sendError == nil {
			a.DB.Exec("UPDATE push_jobs SET done=1,last_error='' WHERE id=?", j.id)
		} else {
			state := 0
			if j.attempts >= 5 {
				state = -1
			}
			a.DB.Exec("UPDATE push_jobs SET attempts=attempts+1,next_at=?,done=?,last_error=? WHERE id=?", time.Now().Add(time.Duration(1<<j.attempts)*10*time.Second).Unix(), state, sendError.Error(), j.id)
		}
	}
}
