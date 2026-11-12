package chat

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"database/sql"
	"encoding/base32"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
)

func (a *App) securityRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/auth/login/totp", a.loginTotp)
	mux.HandleFunc("GET /v1/me/security", a.auth(a.getSecurity))
	mux.HandleFunc("POST /v1/me/password", a.auth(a.changePassword))
	mux.HandleFunc("POST /v1/me/totp/start", a.auth(a.startTotp))
	mux.HandleFunc("POST /v1/me/totp/confirm", a.auth(a.confirmTotp))
	mux.HandleFunc("POST /v1/me/totp/disable", a.auth(a.disableTotp))
	mux.HandleFunc("POST /v1/me/delete", a.auth(a.deleteAccount))
	mux.HandleFunc("POST /v1/devices/revoke-others", a.auth(a.revokeOtherDevices))
}

type deviceMeta struct {
	Platform    string
	AppName     string
	AppVersion  string
	DeviceModel string
	LastIP      string
}

func clipMeta(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) > n {
		return s[:n]
	}
	return s
}

func requestIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return clipMeta(r.RemoteAddr, 64)
	}
	return clipMeta(host, 64)
}

func (a *App) newSessionMeta(tx *sql.Tx, user string, meta deviceMeta) (map[string]any, error) {
	token := id() + id()
	device, sid := id(), id()
	expires := time.Now().Add(a.C.SessionTTL).Unix()
	nows := now()
	platform := clipMeta(meta.Platform, 32)
	if _, e := tx.Exec("INSERT INTO devices(id,user_id,platform,push_provider,created,last_seen,app_name,app_version,device_model,last_ip) VALUES(?,?,?,'none',?,?,?,?,?,?)",
		device, user, platform, nows, nows, clipMeta(meta.AppName, 64), clipMeta(meta.AppVersion, 32), clipMeta(meta.DeviceModel, 64), clipMeta(meta.LastIP, 64)); e != nil {
		return nil, e
	}
	if _, e := tx.Exec("INSERT INTO sessions(id,user_id,device_id,token_hash,expires) VALUES(?,?,?,?,?)", sid, user, device, hash(token), expires); e != nil {
		return nil, e
	}
	return map[string]any{"access_token": token, "token_type": "Bearer", "expires_at": time.Unix(expires, 0).UTC().Format(time.RFC3339), "device_id": device, "user_id": user}, nil
}

func (a *App) touchDevice(deviceID string) {
	if deviceID == "" {
		return
	}
	_, _ = a.DB.Exec("UPDATE devices SET last_seen=? WHERE id=? AND revoked=0", now(), deviceID)
}

func (a *App) userLoginRow(handle string) (uid, pass, totp string, deleted int, err error) {
	err = a.DB.QueryRow("SELECT id,password,IFNULL(totp_secret,''),IFNULL(deleted,0) FROM users WHERE handle=?", strings.ToLower(handle)).Scan(&uid, &pass, &totp, &deleted)
	return
}

func (a *App) issueLogin(w http.ResponseWriter, r *http.Request, uid string, meta deviceMeta, status int) {
	var result map[string]any
	e := a.transaction(func(tx *sql.Tx) error {
		var err error
		result, err = a.newSessionMeta(tx, uid, meta)
		return err
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, status, result)
}

func (a *App) beginTotpChallenge(uid string, meta deviceMeta) (map[string]any, error) {
	plain := id() + id()
	exp := time.Now().Add(5 * time.Minute).Unix()
	if _, e := a.DB.Exec("DELETE FROM login_challenges WHERE user_id=? OR expires<?", uid, time.Now().Unix()); e != nil {
		return nil, e
	}
	if _, e := a.DB.Exec("INSERT INTO login_challenges(token_hash,user_id,platform,app_name,app_version,device_model,last_ip,expires) VALUES(?,?,?,?,?,?,?,?)",
		hash(plain), uid, clipMeta(meta.Platform, 32), clipMeta(meta.AppName, 64), clipMeta(meta.AppVersion, 32), clipMeta(meta.DeviceModel, 64), clipMeta(meta.LastIP, 64), exp); e != nil {
		return nil, e
	}
	return map[string]any{
		"two_factor_required": true,
		"pending_token":       plain,
		"expires_at":          time.Unix(exp, 0).UTC().Format(time.RFC3339),
	}, nil
}

type loginBody struct {
	Handle      string `json:"handle"`
	Password    string `json:"password"`
	Platform    string `json:"platform"`
	TotpCode    string `json:"totp_code"`
	Recovery    string `json:"recovery_code"`
	AppName     string `json:"app_name"`
	AppVersion  string `json:"app_version"`
	DeviceModel string `json:"device_model"`
}

func loginMeta(b loginBody, r *http.Request) deviceMeta {
	return deviceMeta{
		Platform:    b.Platform,
		AppName:     b.AppName,
		AppVersion:  b.AppVersion,
		DeviceModel: b.DeviceModel,
		LastIP:      requestIP(r),
	}
}

func (a *App) completeLogin(w http.ResponseWriter, r *http.Request, uid, totpSecret, totpCode, recovery string, meta deviceMeta, status int) {
	if totpSecret != "" {
		if !a.verifyTotpOrRecovery(uid, totpSecret, totpCode, recovery) {
			respond(w, 401, map[string]string{"error": "invalid_totp"})
			return
		}
	}
	a.issueLogin(w, r, uid, meta, status)
}

func (a *App) login(w http.ResponseWriter, r *http.Request) {
	var b loginBody
	if !decode(w, r, &b) {
		return
	}
	if len(b.Password) > 72 || len(b.Platform) > 32 {
		fail(w, ErrInvalid)
		return
	}
	uid, pass, totp, deleted, e := a.userLoginRow(b.Handle)
	dummy := "$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy"
	if e != nil {
		pass = dummy
	}
	check := bcrypt.CompareHashAndPassword([]byte(pass), []byte(b.Password))
	if e != nil || check != nil || deleted == 1 {
		respond(w, 401, map[string]string{"error": "invalid_credentials"})
		return
	}
	meta := loginMeta(b, r)
	if totp != "" && strings.TrimSpace(b.TotpCode) == "" && strings.TrimSpace(b.Recovery) == "" {
		ch, err := a.beginTotpChallenge(uid, meta)
		if err != nil {
			fail(w, err)
			return
		}
		respond(w, 200, ch)
		return
	}
	a.completeLogin(w, r, uid, totp, b.TotpCode, b.Recovery, meta, 200)
}

func (a *App) loginTotp(w http.ResponseWriter, r *http.Request) {
	var b struct {
		PendingToken string `json:"pending_token"`
		TotpCode     string `json:"totp_code"`
		Recovery     string `json:"recovery_code"`
	}
	if !decode(w, r, &b) {
		return
	}
	if b.PendingToken == "" {
		fail(w, ErrInvalid)
		return
	}
	var uid, platform, appName, appVersion, model, ip string
	var expires int64
	e := a.DB.QueryRow("SELECT user_id,platform,app_name,app_version,device_model,last_ip,expires FROM login_challenges WHERE token_hash=?", hash(b.PendingToken)).Scan(&uid, &platform, &appName, &appVersion, &model, &ip, &expires)
	if e != nil || expires <= time.Now().Unix() {
		respond(w, 401, map[string]string{"error": "invalid_totp"})
		return
	}
	var totp string
	var deleted int
	if e = a.DB.QueryRow("SELECT IFNULL(totp_secret,''),IFNULL(deleted,0) FROM users WHERE id=?", uid).Scan(&totp, &deleted); e != nil || deleted == 1 || totp == "" {
		respond(w, 401, map[string]string{"error": "invalid_totp"})
		return
	}
	if !a.verifyTotpOrRecovery(uid, totp, b.TotpCode, b.Recovery) {
		respond(w, 401, map[string]string{"error": "invalid_totp"})
		return
	}
	_, _ = a.DB.Exec("DELETE FROM login_challenges WHERE token_hash=?", hash(b.PendingToken))
	a.issueLogin(w, r, uid, deviceMeta{Platform: platform, AppName: appName, AppVersion: appVersion, DeviceModel: model, LastIP: ip}, 200)
}

func (a *App) getSecurity(w http.ResponseWriter, r *http.Request, p Principal) {
	var hint, totp, pending string
	if e := a.DB.QueryRow("SELECT IFNULL(password_hint,''),IFNULL(totp_secret,''),IFNULL(totp_pending,'') FROM users WHERE id=?", p.UserID).Scan(&hint, &totp, &pending); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{
		"has_password":        true,
		"password_hint":       hint,
		"two_factor_enabled":  totp != "",
		"two_factor_pending":  totp == "" && pending != "",
		"has_recovery_email":  false,
	})
}

func (a *App) changePassword(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Old  string `json:"old_password"`
		New  string `json:"new_password"`
		Hint string `json:"hint"`
	}
	if !decode(w, r, &b) {
		return
	}
	if len(b.New) < 12 || len(b.New) > 72 || len(b.Hint) > 64 {
		fail(w, ErrInvalid)
		return
	}
	var pass string
	if e := a.DB.QueryRow("SELECT password FROM users WHERE id=?", p.UserID).Scan(&pass); e != nil {
		fail(w, e)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(pass), []byte(b.Old)) != nil {
		respond(w, 401, map[string]string{"error": "invalid_credentials"})
		return
	}
	hashPass, e := bcrypt.GenerateFromPassword([]byte(b.New), bcrypt.DefaultCost)
	if e != nil {
		fail(w, e)
		return
	}
	if _, e = a.DB.Exec("UPDATE users SET password=?,password_hint=? WHERE id=?", string(hashPass), strings.TrimSpace(b.Hint), p.UserID); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"ok": true, "has_password": true, "password_hint": strings.TrimSpace(b.Hint)})
}

func (a *App) startTotp(w http.ResponseWriter, r *http.Request, p Principal) {
	var secret, pending string
	if e := a.DB.QueryRow("SELECT IFNULL(totp_secret,''),IFNULL(totp_pending,'') FROM users WHERE id=?", p.UserID).Scan(&secret, &pending); e != nil {
		fail(w, e)
		return
	}
	if secret != "" {
		fail(w, ErrConflict)
		return
	}
	raw := make([]byte, 20)
	if _, e := rand.Read(raw); e != nil {
		fail(w, e)
		return
	}
	encoded := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(raw)
	u, e := a.getUser(p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	if _, e = a.DB.Exec("UPDATE users SET totp_pending=? WHERE id=?", encoded, p.UserID); e != nil {
		fail(w, e)
		return
	}
	issuer := "轻聊"
	otpauth := fmt.Sprintf("otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30",
		url.PathEscape(issuer), url.PathEscape(u.Handle), encoded, url.QueryEscape(issuer))
	respond(w, 200, map[string]any{"secret": encoded, "otpauth_url": otpauth})
}

func (a *App) confirmTotp(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Code string `json:"code"`
	}
	if !decode(w, r, &b) {
		return
	}
	var pending, current string
	if e := a.DB.QueryRow("SELECT IFNULL(totp_pending,''),IFNULL(totp_secret,'') FROM users WHERE id=?", p.UserID).Scan(&pending, &current); e != nil {
		fail(w, e)
		return
	}
	if current != "" || pending == "" || !totpValid(pending, b.Code, time.Now()) {
		fail(w, ErrInvalid)
		return
	}
	codes, hashes, e := newRecoveryCodes(8)
	if e != nil {
		fail(w, e)
		return
	}
	blob, _ := json.Marshal(hashes)
	if _, e = a.DB.Exec("UPDATE users SET totp_secret=?,totp_pending='',totp_recovery=? WHERE id=?", pending, string(blob), p.UserID); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"ok": true, "recovery_codes": codes})
}

func (a *App) disableTotp(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Password string `json:"password"`
		Code     string `json:"code"`
		Recovery string `json:"recovery_code"`
	}
	if !decode(w, r, &b) {
		return
	}
	var pass, secret string
	if e := a.DB.QueryRow("SELECT password,IFNULL(totp_secret,'') FROM users WHERE id=?", p.UserID).Scan(&pass, &secret); e != nil {
		fail(w, e)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(pass), []byte(b.Password)) != nil {
		respond(w, 401, map[string]string{"error": "invalid_credentials"})
		return
	}
	if secret == "" {
		respond(w, 200, map[string]bool{"ok": true})
		return
	}
	if !a.verifyTotpOrRecovery(p.UserID, secret, b.Code, b.Recovery) {
		respond(w, 401, map[string]string{"error": "invalid_totp"})
		return
	}
	if _, e := a.DB.Exec("UPDATE users SET totp_secret='',totp_pending='',totp_recovery='' WHERE id=?", p.UserID); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) deleteAccount(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Password string `json:"password"`
		Reason   string `json:"reason"`
		Code     string `json:"totp_code"`
		Recovery string `json:"recovery_code"`
	}
	if !decode(w, r, &b) {
		return
	}
	if len(b.Reason) > 200 {
		fail(w, ErrInvalid)
		return
	}
	var pass, secret string
	if e := a.DB.QueryRow("SELECT password,IFNULL(totp_secret,'') FROM users WHERE id=?", p.UserID).Scan(&pass, &secret); e != nil {
		fail(w, e)
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(pass), []byte(b.Password)) != nil {
		respond(w, 401, map[string]string{"error": "invalid_credentials"})
		return
	}
	if secret != "" && !a.verifyTotpOrRecovery(p.UserID, secret, b.Code, b.Recovery) {
		respond(w, 401, map[string]string{"error": "invalid_totp"})
		return
	}
	goneHash, e := bcrypt.GenerateFromPassword([]byte(id()+id()), bcrypt.DefaultCost)
	if e != nil {
		fail(w, e)
		return
	}
	handle := "deleted_" + p.UserID
	if len(handle) > 32 {
		handle = handle[:32]
	}
	e = a.transaction(func(tx *sql.Tx) error {
		if _, e := tx.Exec("UPDATE users SET handle=?,name=?,avatar='',password=?,password_hint='',totp_secret='',totp_pending='',totp_recovery='',deleted=1,last_seen=? WHERE id=?", handle, "已注销", string(goneHash), now(), p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("UPDATE sessions SET revoked=1 WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("UPDATE devices SET revoked=1,push_token='',push_provider='none' WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM login_challenges WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM contacts WHERE owner=? OR user_id=?", p.UserID, p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM folders WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM privacy_rules WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM notification_scopes WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM sticker_favorites WHERE user_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM story_album_items WHERE album_id IN (SELECT id FROM story_albums WHERE owner=?)", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("DELETE FROM story_albums WHERE owner=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("UPDATE stories SET deleted=1 WHERE author_id=?", p.UserID); e != nil {
			return e
		}
		if _, e := tx.Exec("UPDATE messages SET deleted=1,text='',media_id='',entities_json='[]',preview_json='',reply_markup_json='' WHERE sender=? AND deleted=0", p.UserID); e != nil {
			return e
		}
		return nil
	})
	if e != nil {
		fail(w, e)
		return
	}
	a.hub.closeUser(p.UserID)
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) revokeOtherDevices(w http.ResponseWriter, r *http.Request, p Principal) {
	rows, e := a.DB.Query("SELECT id FROM devices WHERE user_id=? AND id<>? AND revoked=0", p.UserID, p.DeviceID)
	if e != nil {
		fail(w, e)
		return
	}
	ids := []string{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	if _, e = a.DB.Exec("UPDATE devices SET revoked=1,push_token='',push_provider='none' WHERE user_id=? AND id<>? AND revoked=0", p.UserID, p.DeviceID); e != nil {
		fail(w, e)
		return
	}
	if _, e = a.DB.Exec("UPDATE sessions SET revoked=1 WHERE user_id=? AND device_id<>?", p.UserID, p.DeviceID); e != nil {
		fail(w, e)
		return
	}
	for _, id := range ids {
		a.hub.closeDevice(id)
	}
	respond(w, 200, map[string]any{"ok": true, "revoked": len(ids)})
}

func (a *App) listDevices(w http.ResponseWriter, r *http.Request, p Principal) {
	a.touchDevice(p.DeviceID)
	rows, e := a.DB.Query("SELECT id,platform,revoked,ack,IFNULL(created,''),IFNULL(last_seen,''),IFNULL(app_name,''),IFNULL(app_version,''),IFNULL(device_model,''),IFNULL(last_ip,'') FROM devices WHERE user_id=? AND revoked=0 ORDER BY (id=? ) DESC, last_seen DESC, id", p.UserID, p.DeviceID)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, platform, created, lastSeen, appName, appVersion, model, ip string
		var revoked int
		var ack int64
		if e = rows.Scan(&id, &platform, &revoked, &ack, &created, &lastSeen, &appName, &appVersion, &model, &ip); e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{
			"id":                       id,
			"platform":                 platform,
			"revoked":                  revoked == 1,
			"last_persisted_event_seq": ack,
			"current":                  id == p.DeviceID,
			"created_at":               created,
			"last_seen":                lastSeen,
			"app_name":                 appName,
			"app_version":              appVersion,
			"device_model":             model,
			"last_ip":                  ip,
		})
	}
	respond(w, 200, map[string]any{"devices": out})
}

func (a *App) verifyTotpOrRecovery(uid, secret, code, recovery string) bool {
	if strings.TrimSpace(code) != "" && totpValid(secret, code, time.Now()) {
		return true
	}
	rec := normalizeRecovery(recovery)
	if rec == "" {
		return false
	}
	var raw string
	if e := a.DB.QueryRow("SELECT IFNULL(totp_recovery,'') FROM users WHERE id=?", uid).Scan(&raw); e != nil || raw == "" {
		return false
	}
	var hashes []string
	if json.Unmarshal([]byte(raw), &hashes) != nil {
		return false
	}
	want := hash(rec)
	kept := make([]string, 0, len(hashes))
	used := false
	for _, h := range hashes {
		if !used && h == want {
			used = true
			continue
		}
		kept = append(kept, h)
	}
	if !used {
		return false
	}
	blob, _ := json.Marshal(kept)
	_, _ = a.DB.Exec("UPDATE users SET totp_recovery=? WHERE id=?", string(blob), uid)
	return true
}

func totpValid(secret, code string, now time.Time) bool {
	code = strings.TrimSpace(code)
	if len(code) != 6 {
		return false
	}
	for _, step := range []int64{-1, 0, 1} {
		if hmac.Equal([]byte(totpAt(secret, now.Unix()/30+step)), []byte(code)) {
			return true
		}
	}
	return false
}

func totpAt(secret string, counter int64) string {
	sec := strings.ToUpper(strings.TrimSpace(secret))
	raw, err := base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(sec)
	if err != nil {
		padded := sec
		if m := len(padded) % 8; m != 0 {
			padded += strings.Repeat("=", 8-m)
		}
		raw, err = base32.StdEncoding.DecodeString(padded)
		if err != nil {
			return ""
		}
	}
	var buf [8]byte
	binary.BigEndian.PutUint64(buf[:], uint64(counter))
	mac := hmac.New(sha1.New, raw)
	mac.Write(buf[:])
	sum := mac.Sum(nil)
	off := sum[len(sum)-1] & 0x0f
	bin := binary.BigEndian.Uint32(sum[off:off+4]) & 0x7fffffff
	return fmt.Sprintf("%06d", bin%1000000)
}

func newRecoveryCodes(n int) (codes, hashes []string, err error) {
	const alphabet = "abcdefghijkmnpqrstuvwxyz23456789"
	for i := 0; i < n; i++ {
		b := make([]byte, 8)
		if _, err = rand.Read(b); err != nil {
			return nil, nil, err
		}
		var sb strings.Builder
		for j, v := range b {
			if j == 4 {
				sb.WriteByte('-')
			}
			sb.WriteByte(alphabet[int(v)%len(alphabet)])
		}
		code := sb.String()
		codes = append(codes, code)
		hashes = append(hashes, hash(normalizeRecovery(code)))
	}
	return codes, hashes, nil
}

func normalizeRecovery(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, "-", "")
	s = strings.ReplaceAll(s, " ", "")
	return s
}
