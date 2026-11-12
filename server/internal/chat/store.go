package chat

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"golang.org/x/crypto/bcrypt"
	_ "modernc.org/sqlite"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

type Config struct {
	Addr, DataDir, AllowedOrigin, AdminHandle, AdminPassword string
	StorageDriver                                            string
	ReadReceiptsEnabled                                      bool
	FCMServiceAccount                                        string
	PushProviders                                            map[string]PushProvider
	MediaQuota, MaxFile                                      int64
	SessionTTL                                               time.Duration
	XiaomiSecret, XiaomiPackage, XiaomiURL                   string
	AllowHTTPWebhook                                         bool
}

func DefaultConfig() Config {
	return Config{ReadReceiptsEnabled: true, StorageDriver: "local", Addr: "127.0.0.1:8088", DataDir: "./data", MediaQuota: 512 << 20, MaxFile: 20 << 20, SessionTTL: 30 * 24 * time.Hour, XiaomiURL: "https://api.xmpush.xiaomi.com/v3/message/regid"}
}

type App struct {
	ctx       context.Context
	cancel    context.CancelFunc
	providers map[string]PushProvider
	DB        *sql.DB
	C         Config
	mu        sync.Mutex
	mediaMu   sync.Mutex
	hub       *Hub
	storage   Storage
	limiter   *limiter
	ticketsMu sync.Mutex
	tickets   map[string]ticket
	stop      chan struct{}
	done      chan struct{}
}
type Principal struct {
	UserID, DeviceID, SessionID string
	Admin                       bool
}
type User struct {
	ID       string `json:"id"`
	Handle   string `json:"handle"`
	Name     string `json:"display_name"`
	Avatar     string `json:"avatar_media_id"`
	AvatarMIME string `json:"avatar_mime,omitempty"`
	LastSeen   string `json:"last_seen"`
	Online     bool   `json:"online"`
}
type MediaInfo struct {
	ID          string `json:"id"`
	MIME        string `json:"mime,omitempty"`
	Bytes       int64  `json:"bytes,omitempty"`
	Width       int    `json:"width,omitempty"`
	Height      int    `json:"height,omitempty"`
	DurationMs  int    `json:"duration_ms,omitempty"`
	Waveform    string `json:"waveform,omitempty"`
	FileName    string `json:"file_name,omitempty"`
	ThumbnailID string `json:"thumbnail_id,omitempty"`
}
type Message struct {
	Entities      []Entity        `json:"entities"`
	LinkPreview   *LinkPreview    `json:"link_preview,omitempty"`
	ReplyMarkup   *ReplyMarkup    `json:"reply_markup,omitempty"`
	ViaBotID      string          `json:"via_bot_id,omitempty"`
	ForwardOrigin json.RawMessage `json:"forward_origin,omitempty"`
	Media         *MediaInfo      `json:"media,omitempty"`
	Poll          any             `json:"poll,omitempty"`
	Checklist     any             `json:"checklist,omitempty"`
	ID            string          `json:"id"`
	ChatID        string          `json:"conversation_id"`
	Seq           int64           `json:"conversation_seq"`
	Sender        string          `json:"sender_id"`
	ClientID      string          `json:"client_msg_id"`
	Kind          string          `json:"kind"`
	Text          string          `json:"text"`
	MediaID       string          `json:"media_id,omitempty"`
	AlbumID       string          `json:"album_id,omitempty"`
	ReplyTo       string          `json:"reply_to,omitempty"`
	ReplyToSeq    int64           `json:"reply_to_seq,omitempty"`
	Created       string          `json:"created_at"`
	Edited        string          `json:"edited_at,omitempty"`
	Deleted       bool            `json:"deleted"`
}
type Send struct {
	Entities      []Entity     `json:"entities,omitempty"`
	LinkPreviewID string       `json:"link_preview_id,omitempty"`
	ReplyMarkup   *ReplyMarkup `json:"reply_markup,omitempty"`
	ViaBotID      string       `json:"via_bot_id,omitempty"`
	ClientID      string       `json:"client_msg_id"`
	Kind          string       `json:"kind"`
	Text          string       `json:"text"`
	MediaID       string       `json:"media_id"`
	AlbumID       string       `json:"album_id,omitempty"`
	ReplyTo       string       `json:"reply_to"`
	StickerID     string       `json:"sticker_id,omitempty"`
}
type Event struct {
	V      int             `json:"v"`
	Op     string          `json:"op"`
	Seq    int64           `json:"event_seq"`
	Type   string          `json:"type"`
	ChatID string          `json:"conversation_id"`
	Data   json.RawMessage `json:"data"`
}

var ErrForbidden = errors.New("forbidden")
var ErrConflict = errors.New("conflict")
var ErrInvalid = errors.New("invalid request")

func now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
func id() string {
	b := make([]byte, 16)
	if _, e := rand.Read(b); e != nil {
		panic(e)
	}
	return hex.EncodeToString(b)
}
func hash(s string) string { b := sha256.Sum256([]byte(s)); return hex.EncodeToString(b[:]) }
func Open(c Config) (*App, error) {
	if c.StorageDriver != "" && c.StorageDriver != "local" {
		return nil, fmt.Errorf("storage driver %q: %w (R2 adapter pending)", c.StorageDriver, ErrNotSupported)
	}
	if c.SessionTTL <= 0 {
		c.SessionTTL = 30 * 24 * time.Hour
	}
	if c.MediaQuota <= 0 || c.MaxFile <= 0 {
		return nil, ErrInvalid
	}
	if e := os.MkdirAll(c.DataDir, 0700); e != nil {
		return nil, e
	}
	dsn := filepath.Join(c.DataDir, "chat.db")
	db, e := sql.Open("sqlite", dsn)
	if e != nil {
		return nil, e
	}
	db.SetMaxOpenConns(1)
	a := &App{DB: db, C: c, hub: newHub(), limiter: newLimiter(), tickets: map[string]ticket{}, stop: make(chan struct{}), done: make(chan struct{})}
	if _, e = db.Exec(schema); e != nil {
		db.Close()
		return nil, e
	}
	if e = a.migrateExtensions(); e != nil {
		db.Close()
		return nil, e
	}
	a.storage, e = NewLocalStorage(filepath.Join(c.DataDir, "media"))
	if e != nil {
		db.Close()
		return nil, e
	}
	a.ctx, a.cancel = context.WithCancel(context.Background())
	a.providers = map[string]PushProvider{}
	if c.XiaomiSecret != "" && c.XiaomiPackage != "" {
		a.providers["mipush"] = &XiaomiPush{Secret: c.XiaomiSecret, Package: c.XiaomiPackage, Endpoint: c.XiaomiURL, Client: &http.Client{Timeout: 8 * time.Second}}
	}
	if c.FCMServiceAccount != "" {
		provider, err := loadFCM(a.ctx, c.FCMServiceAccount, &http.Client{Timeout: 8 * time.Second})
		if err != nil {
			a.cancel()
			db.Close()
			return nil, fmt.Errorf("invalid FCM service account configuration")
		}
		a.providers["fcm"] = provider
	}
	for name, provider := range c.PushProviders {
		a.providers[name] = provider
	}
	if c.AdminHandle != "" && c.AdminPassword != "" {
		if e = a.Bootstrap(c.AdminHandle, c.AdminPassword); e != nil {
			db.Close()
			return nil, e
		}
	}
	go a.pushWorker()
	return a, nil
}
func (a *App) Close() error {
	a.cancel()
	close(a.stop)
	a.hub.closeAll()
	<-a.done
	return a.DB.Close()
}
func (a *App) Bootstrap(handle, password string) error {
	if !validHandle(handle) || len(password) < 12 || len(password) > 72 {
		return fmt.Errorf("admin handle invalid or password not 12..72 bytes")
	}
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM users WHERE admin=1").Scan(&n); e != nil {
		return e
	}
	if n > 0 {
		return nil
	}
	b, e := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if e != nil {
		return e
	}
	_, e = a.DB.Exec("INSERT INTO users(id,handle,name,password,admin,last_seen) VALUES(?,?,?,?,1,?)", id(), handle, handle, string(b), now())
	return e
}
func (a *App) transaction(fn func(*sql.Tx) error) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	tx, e := a.DB.Begin()
	if e != nil {
		return e
	}
	defer tx.Rollback()
	if e = fn(tx); e != nil {
		return e
	}
	if e = tx.Commit(); e != nil {
		return e
	}
	a.hub.signal()
	return nil
}
func member(tx *sql.Tx, chat, user string) (string, int64, error) {
	var role string
	var joined int64
	e := tx.QueryRow("SELECT role,joined_seq FROM members WHERE chat_id=? AND user_id=?", chat, user).Scan(&role, &joined)
	if errors.Is(e, sql.ErrNoRows) {
		e = ErrForbidden
	}
	return role, joined, e
}
func members(tx *sql.Tx, chat string) ([]string, error) {
	rows, e := tx.Query("SELECT user_id FROM members WHERE chat_id=? ORDER BY user_id", chat)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var u string
		if e = rows.Scan(&u); e != nil {
			return nil, e
		}
		out = append(out, u)
	}
	return out, rows.Err()
}
func emit(tx *sql.Tx, users []string, typ, chat string, data any) error {
	b, e := json.Marshal(data)
	if e != nil {
		return e
	}
	for _, u := range users {
		var seq int64
		e = tx.QueryRow("INSERT INTO event_counters(user_id,seq) VALUES(?,1) ON CONFLICT(user_id) DO UPDATE SET seq=seq+1 RETURNING seq", u).Scan(&seq)
		if e != nil {
			return e
		}
		_, e = tx.Exec("INSERT INTO events(user_id,seq,type,chat_id,data,created) VALUES(?,?,?,?,?,?)", u, seq, typ, chat, string(b), now())
		if e != nil {
			return e
		}
	}
	return enqueueBotUpdates(tx, users, typ, chat, b)
}
func (a *App) Difference(user string, after int64, limit int) (map[string]any, error) {
	if after < 0 {
		return nil, ErrInvalid
	}
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	var high int64
	e := a.DB.QueryRow("SELECT COALESCE((SELECT seq FROM event_counters WHERE user_id=?),0)", user).Scan(&high)
	if e != nil {
		return nil, e
	}
	if after > high {
		return nil, ErrInvalid
	}
	rows, e := a.DB.Query("SELECT seq,type,chat_id,data FROM events WHERE user_id=? AND seq>? AND seq<=? ORDER BY seq LIMIT ?", user, after, high, limit)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []Event{}
	next := after
	for rows.Next() {
		ev := Event{V: 1, Op: "event"}
		var b string
		if e = rows.Scan(&ev.Seq, &ev.Type, &ev.ChatID, &b); e != nil {
			return nil, e
		}
		ev.Data = json.RawMessage(b)
		out = append(out, ev)
		next = ev.Seq
	}
	rowErr := rows.Err()
	rows.Close()
	a.redactEvents(user, out)
	return map[string]any{"events": out, "next_cursor": next, "high_watermark": high, "has_more": next < high}, rowErr
}
func (a *App) authenticate(token string) (Principal, error) {
	var p Principal
	var admin int
	var deleted int
	e := a.DB.QueryRow(`SELECT s.user_id,s.device_id,s.id,u.admin,IFNULL(u.deleted,0) FROM sessions s JOIN users u ON u.id=s.user_id JOIN devices d ON d.id=s.device_id WHERE s.token_hash=? AND s.expires>? AND s.revoked=0 AND d.revoked=0`, hash(token), time.Now().Unix()).Scan(&p.UserID, &p.DeviceID, &p.SessionID, &admin, &deleted)
	if e != nil {
		return Principal{}, e
	}
	if deleted == 1 {
		return Principal{}, ErrForbidden
	}
	p.Admin = admin == 1
	return p, nil
}
func (a *App) validSession(p Principal) bool {
	var n int
	e := a.DB.QueryRow("SELECT count(*) FROM sessions s JOIN devices d ON d.id=s.device_id WHERE s.id=? AND s.revoked=0 AND s.expires>? AND d.revoked=0", p.SessionID, time.Now().Unix()).Scan(&n)
	return e == nil && n == 1
}
func (a *App) online(user string) bool        { return a.hub.online(user) }
func (a *App) Ping(ctx context.Context) error { return a.DB.PingContext(ctx) }

const schema = `PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA cache_size=-2048; PRAGMA synchronous=FULL;
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY,handle TEXT NOT NULL UNIQUE,name TEXT NOT NULL,password TEXT NOT NULL,avatar TEXT NOT NULL DEFAULT '',admin INTEGER NOT NULL DEFAULT 0,last_seen TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS invites(code_hash TEXT PRIMARY KEY,uses INTEGER NOT NULL,expires INTEGER NOT NULL,created_by TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),platform TEXT NOT NULL,push_provider TEXT NOT NULL DEFAULT '',push_token TEXT NOT NULL DEFAULT '',ack INTEGER NOT NULL DEFAULT 0,revoked INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS sessions(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),device_id TEXT NOT NULL REFERENCES devices(id),token_hash TEXT NOT NULL UNIQUE,expires INTEGER NOT NULL,revoked INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS chats(id TEXT PRIMARY KEY,kind TEXT NOT NULL,title TEXT NOT NULL,last_seq INTEGER NOT NULL DEFAULT 0,pair TEXT UNIQUE,created_by TEXT NOT NULL REFERENCES users(id));
CREATE TABLE IF NOT EXISTS members(chat_id TEXT NOT NULL REFERENCES chats(id),user_id TEXT NOT NULL REFERENCES users(id),role TEXT NOT NULL,joined_seq INTEGER NOT NULL DEFAULT 0,read_seq INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(chat_id,user_id));
CREATE INDEX IF NOT EXISTS members_user ON members(user_id);
CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY,chat_id TEXT NOT NULL REFERENCES chats(id),seq INTEGER NOT NULL,sender TEXT NOT NULL REFERENCES users(id),client_id TEXT NOT NULL,kind TEXT NOT NULL,text TEXT NOT NULL,media_id TEXT NOT NULL DEFAULT '',reply_to TEXT NOT NULL DEFAULT '',payload_hash TEXT NOT NULL,created TEXT NOT NULL,edited TEXT NOT NULL DEFAULT '',deleted INTEGER NOT NULL DEFAULT 0,UNIQUE(chat_id,seq),UNIQUE(sender,client_id));
CREATE TABLE IF NOT EXISTS reactions(message_id TEXT NOT NULL REFERENCES messages(id),user_id TEXT NOT NULL REFERENCES users(id),emoji TEXT NOT NULL,PRIMARY KEY(message_id,user_id,emoji));
CREATE TABLE IF NOT EXISTS event_counters(user_id TEXT PRIMARY KEY REFERENCES users(id),seq INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS events(user_id TEXT NOT NULL REFERENCES users(id),seq INTEGER NOT NULL,type TEXT NOT NULL,chat_id TEXT NOT NULL,data TEXT NOT NULL,created TEXT NOT NULL,PRIMARY KEY(user_id,seq));
CREATE TABLE IF NOT EXISTS media(id TEXT PRIMARY KEY,owner TEXT NOT NULL REFERENCES users(id),chat_id TEXT NOT NULL,mime TEXT NOT NULL,bytes INTEGER NOT NULL,sha256 TEXT NOT NULL,created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS push_jobs(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),chat_id TEXT NOT NULL,msg_id TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,next_at INTEGER NOT NULL,done INTEGER NOT NULL DEFAULT 0,last_error TEXT NOT NULL DEFAULT '');
CREATE INDEX IF NOT EXISTS push_due ON push_jobs(done,next_at);
PRAGMA user_version=1;`
