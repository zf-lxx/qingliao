package chat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
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
	payload, _ := json.Marshal(map[string]string{"conversation_id": cid, "chat_id": cid, "message_id": mid})
	v := url.Values{"registration_id": {regid}, "restricted_package_name": {x.Package}, "title": {"轻聊"}, "description": {"你有一条新消息"}, "payload": {string(payload)}, "pass_through": {"0"}, "notify_type": {"-1"}, "extra.notify_effect": {"1"}, "extra.jobkey": {hash(mid)[:20]}, "notify_id": {chatNotifyID(cid)}}
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
	if result.Code == 66007 {
		return ErrInvalidPushToken
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
			a.releaseScheduled()
			a.expireMessages()
			if time.Now().Unix()%30 == 0 {
				a.gcOrphanMedia()
			}
			a.processPush()
			a.processBotWebhooks()
		}
	}
}
func chatNotifyID(cid string) string {
	n, _ := strconv.ParseUint(hash(cid)[:7], 16, 32)
	return strconv.FormatUint(n, 10)
}
func (a *App) processPush() {
	type job struct {
		id, user, chat, msg string
		attempts            int
	}
	rows, e := a.DB.Query(`SELECT j.id,j.user_id,j.chat_id,j.msg_id,j.attempts FROM push_jobs j WHERE j.done=0 AND j.next_at<=? AND NOT EXISTS(SELECT 1 FROM push_jobs newer WHERE newer.done=0 AND newer.user_id=j.user_id AND newer.chat_id=j.chat_id AND newer.rowid>j.rowid) ORDER BY j.rowid LIMIT 16`, time.Now().Unix())
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
		a.DB.Exec("UPDATE push_jobs SET done=1,last_error='coalesced' WHERE done=0 AND user_id=? AND chat_id=? AND rowid<(SELECT rowid FROM push_jobs WHERE id=?)", j.user, j.chat, j.id)
		if !a.isMember(j.chat, j.user) {
			a.DB.Exec("UPDATE push_jobs SET done=1,last_error='not_member' WHERE id=?", j.id)
			continue
		}
		var unread int
		a.DB.QueryRow("SELECT count(*) FROM messages m JOIN members b ON b.chat_id=m.chat_id WHERE m.id=? AND b.user_id=? AND m.seq>b.read_seq AND m.seq>b.joined_seq AND m.deleted=0 AND b.notification_mute_until<=unixepoch()", j.msg, j.user).Scan(&unread)
		if unread == 0 {
			a.DB.Exec("UPDATE push_jobs SET done=1 WHERE id=?", j.id)
			continue
		}
		type device struct{ id, provider, token string }
		rows, e = a.DB.Query("SELECT id,push_provider,push_token FROM devices WHERE user_id=? AND revoked=0 AND push_provider<>'none' AND push_token<>''", j.user)
		if e != nil {
			continue
		}
		devices := []device{}
		for rows.Next() {
			var d device
			if rows.Scan(&d.id, &d.provider, &d.token) == nil {
				devices = append(devices, d)
			}
		}
		rows.Close()
		if len(devices) == 0 {
			a.DB.Exec("UPDATE push_jobs SET done=1,last_error='no_primary_channel' WHERE id=?", j.id)
			continue
		}
		var sendError error
		disabled := ""
		for _, d := range devices {
			if a.hub.deviceOnline(d.id) {
				continue
			}
			provider := a.providers[d.provider]
			if provider == nil {
				disabled = d.provider + "_not_configured"
				continue
			}
			ctx, cancel := context.WithTimeout(a.ctx, 8*time.Second)
			err := provider.Send(ctx, d.token, j.chat, j.msg)
			cancel()
			if errors.Is(err, ErrInvalidPushToken) {
				a.DB.Exec("UPDATE devices SET push_provider='none',push_token='' WHERE id=? AND push_provider=? AND push_token=?", d.id, d.provider, d.token)
				continue
			}
			if err != nil {
				sendError = err
			}
		}
		if sendError == nil && disabled == "" {
			a.DB.Exec("UPDATE push_jobs SET done=1,last_error='' WHERE id=?", j.id)
		} else if sendError == nil {
			a.DB.Exec("UPDATE push_jobs SET next_at=?,last_error=? WHERE id=?", time.Now().Add(5*time.Minute).Unix(), disabled, j.id)
		} else {
			state := 0
			if j.attempts >= 5 {
				state = -1
			}
			delay := time.Duration(1<<j.attempts) * time.Minute
			a.DB.Exec("UPDATE push_jobs SET attempts=attempts+1,next_at=?,done=?,last_error=? WHERE id=?", time.Now().Add(delay).Unix(), state, sendError.Error(), j.id)
		}
	}
}
