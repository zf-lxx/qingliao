package chat

import (
	"database/sql"
	"encoding/json"
	"fmt"
)

func (a *App) migrateExtensions() error {
	for table, columns := range map[string]map[string]string{
		"messages": {"media_meta_json": "TEXT NOT NULL DEFAULT ''", "album_id": "TEXT NOT NULL DEFAULT ''", "entities_json": "TEXT NOT NULL DEFAULT '[]'", "preview_json": "TEXT NOT NULL DEFAULT ''", "reply_markup_json": "TEXT NOT NULL DEFAULT ''", "via_bot_id": "TEXT NOT NULL DEFAULT ''", "forward_origin_json": "TEXT NOT NULL DEFAULT ''", "extra_json": "TEXT NOT NULL DEFAULT ''", "ttl": "INTEGER NOT NULL DEFAULT 0"},
		"media":    {"width": "INTEGER NOT NULL DEFAULT 0", "height": "INTEGER NOT NULL DEFAULT 0", "duration_ms": "INTEGER NOT NULL DEFAULT 0", "waveform": "TEXT NOT NULL DEFAULT ''", "file_name": "TEXT NOT NULL DEFAULT ''", "thumbnail_id": "TEXT NOT NULL DEFAULT ''"},
		"chats":    {"last_activity": "INTEGER NOT NULL DEFAULT 0", "avatar": "TEXT NOT NULL DEFAULT ''", "description": "TEXT NOT NULL DEFAULT ''", "slow_mode": "INTEGER NOT NULL DEFAULT 0", "permissions_json": "TEXT NOT NULL DEFAULT ''", "history_for_new": "INTEGER NOT NULL DEFAULT 0", "auto_delete": "INTEGER NOT NULL DEFAULT 0", "upgraded": "INTEGER NOT NULL DEFAULT 0"},
		"users":    {"read_receipts_enabled": "INTEGER NOT NULL DEFAULT 1", "password_hint": "TEXT NOT NULL DEFAULT ''", "totp_secret": "TEXT NOT NULL DEFAULT ''", "totp_pending": "TEXT NOT NULL DEFAULT ''", "totp_recovery": "TEXT NOT NULL DEFAULT ''", "deleted": "INTEGER NOT NULL DEFAULT 0", "is_bot": "INTEGER NOT NULL DEFAULT 0", "bio": "TEXT NOT NULL DEFAULT ''"},
		"devices":  {"created": "TEXT NOT NULL DEFAULT ''", "last_seen": "TEXT NOT NULL DEFAULT ''", "app_name": "TEXT NOT NULL DEFAULT ''", "app_version": "TEXT NOT NULL DEFAULT ''", "device_model": "TEXT NOT NULL DEFAULT ''", "last_ip": "TEXT NOT NULL DEFAULT ''"},
		"members":  {"manual_unread": "INTEGER NOT NULL DEFAULT 0", "archived": "INTEGER NOT NULL DEFAULT 0", "pin_order": "INTEGER NOT NULL DEFAULT 0", "notification_mute_until": "INTEGER NOT NULL DEFAULT 0", "draft_json": "TEXT NOT NULL DEFAULT ''", "joined_at": "INTEGER NOT NULL DEFAULT 0", "muted_until": "INTEGER NOT NULL DEFAULT 0", "delivered_seq": "INTEGER NOT NULL DEFAULT 0", "delivered_at": "INTEGER NOT NULL DEFAULT 0", "read_at": "INTEGER NOT NULL DEFAULT 0"},
	} {
		var exists int
		if e := a.DB.QueryRow("SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&exists); e != nil {
			return e
		}
		if exists == 0 {
			continue
		}
		rows, e := a.DB.Query("PRAGMA table_info(" + table + ")")
		if e != nil {
			return e
		}
		have := map[string]bool{}
		for rows.Next() {
			var cid, notnull, pk int
			var name, typ string
			var def any
			if e = rows.Scan(&cid, &name, &typ, &notnull, &def, &pk); e != nil {
				rows.Close()
				return e
			}
			have[name] = true
		}
		rows.Close()
		for name, typ := range columns {
			if !have[name] {
				if _, e = a.DB.Exec("ALTER TABLE " + table + " ADD COLUMN " + name + " " + typ); e != nil {
					return e
				}
			}
		}
	}
	_, e := a.DB.Exec(extensionSchema + discoverySchema + p2Schema + p3Schema + p4Schema + p5Schema + p6Schema + p7Schema + p8Schema)
	if e != nil {
		return e
	}
	return a.ensureColumn("stickers", "format", "TEXT NOT NULL DEFAULT ''")
}

func (a *App) ensureColumn(table, name, typ string) error {
	rows, e := a.DB.Query("PRAGMA table_info(" + table + ")")
	if e != nil {
		return e
	}
	found := false
	for rows.Next() {
		var cid, notnull, pk int
		var col, colType string
		var def any
		if e = rows.Scan(&cid, &col, &colType, &notnull, &def, &pk); e != nil {
			rows.Close()
			return e
		}
		if col == name {
			found = true
		}
	}
	e = rows.Err()
	rows.Close()
	if e != nil || found {
		return e
	}
	_, e = a.DB.Exec("ALTER TABLE " + table + " ADD COLUMN " + name + " " + typ)
	return e
}

const extensionSchema = `
CREATE TABLE IF NOT EXISTS link_previews(id TEXT PRIMARY KEY,url TEXT NOT NULL UNIQUE,title TEXT NOT NULL,description TEXT NOT NULL,image TEXT NOT NULL,site_name TEXT NOT NULL,fetched_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS pins(chat_id TEXT NOT NULL REFERENCES chats(id),message_id TEXT NOT NULL REFERENCES messages(id),pinned_by TEXT NOT NULL REFERENCES users(id),created TEXT NOT NULL,PRIMARY KEY(chat_id,message_id));
CREATE TABLE IF NOT EXISTS group_settings(chat_id TEXT PRIMARY KEY REFERENCES chats(id),new_member_hours INTEGER NOT NULL DEFAULT 0,user_rate INTEGER NOT NULL DEFAULT 120,chat_rate INTEGER NOT NULL DEFAULT 300,keywords_json TEXT NOT NULL DEFAULT '[]');
CREATE TABLE IF NOT EXISTS bans(chat_id TEXT NOT NULL REFERENCES chats(id),user_id TEXT NOT NULL REFERENCES users(id),actor_id TEXT NOT NULL REFERENCES users(id),reason TEXT NOT NULL,created TEXT NOT NULL,PRIMARY KEY(chat_id,user_id));
CREATE TABLE IF NOT EXISTS audit_log(id INTEGER PRIMARY KEY AUTOINCREMENT,chat_id TEXT NOT NULL REFERENCES chats(id),actor_id TEXT NOT NULL REFERENCES users(id),action TEXT NOT NULL,target_id TEXT NOT NULL,details_json TEXT NOT NULL,created TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS audit_chat ON audit_log(chat_id,id);
CREATE TABLE IF NOT EXISTS polls(id TEXT PRIMARY KEY,chat_id TEXT NOT NULL REFERENCES chats(id),message_id TEXT UNIQUE REFERENCES messages(id),creator_id TEXT NOT NULL REFERENCES users(id),question TEXT NOT NULL,multiple_choice INTEGER NOT NULL,anonymous INTEGER NOT NULL,is_quiz INTEGER NOT NULL,correct_option INTEGER,closes_at INTEGER,closed INTEGER NOT NULL DEFAULT 0,created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS poll_options(poll_id TEXT NOT NULL REFERENCES polls(id),option_id INTEGER NOT NULL,text TEXT NOT NULL,PRIMARY KEY(poll_id,option_id));
CREATE TABLE IF NOT EXISTS poll_votes(poll_id TEXT NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),option_id INTEGER NOT NULL,created TEXT NOT NULL,PRIMARY KEY(poll_id,user_id,option_id),FOREIGN KEY(poll_id,option_id) REFERENCES poll_options(poll_id,option_id));
CREATE TABLE IF NOT EXISTS message_mentions(message_id TEXT NOT NULL REFERENCES messages(id),user_id TEXT NOT NULL REFERENCES users(id),PRIMARY KEY(message_id,user_id));
CREATE INDEX IF NOT EXISTS mention_user ON message_mentions(user_id,message_id);
CREATE TABLE IF NOT EXISTS folders(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),name TEXT NOT NULL,filter_json TEXT NOT NULL,sort_order INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS folders_user ON folders(user_id,sort_order);
CREATE INDEX IF NOT EXISTS chat_activity ON chats(last_activity DESC,id);
CREATE INDEX IF NOT EXISTS member_dialogs ON members(user_id,archived,pin_order,chat_id);
CREATE INDEX IF NOT EXISTS notification_mute_expiry ON members(notification_mute_until) WHERE notification_mute_until>0;
UPDATE devices SET push_provider='mipush' WHERE push_provider='xiaomi';
UPDATE devices SET push_provider='none' WHERE push_provider='';
CREATE INDEX IF NOT EXISTS push_coalesce ON push_jobs(user_id,chat_id,done);
PRAGMA user_version=3;`

func audit(tx *sql.Tx, cid, actor, action, target string, details any) error {
	b, e := json.Marshal(details)
	if e != nil {
		return e
	}
	_, e = tx.Exec("INSERT INTO audit_log(chat_id,actor_id,action,target_id,details_json,created) VALUES(?,?,?,?,?,?)", cid, actor, action, target, string(b), now())
	return e
}
func jsonText(v any, empty string) string {
	if v == nil {
		return empty
	}
	b, e := json.Marshal(v)
	if e != nil {
		panic(fmt.Sprint(e))
	}
	if string(b) == "null" {
		return empty
	}
	return string(b)
}

const p2Schema = `
CREATE INDEX IF NOT EXISTS messages_album ON messages(chat_id,album_id) WHERE album_id<>'';
CREATE INDEX IF NOT EXISTS chat_avatar ON chats(avatar) WHERE avatar<>'';
PRAGMA user_version=5;
`

const p3Schema = `
CREATE TABLE IF NOT EXISTS contacts(owner TEXT NOT NULL REFERENCES users(id),user_id TEXT NOT NULL REFERENCES users(id),first_name TEXT NOT NULL DEFAULT '',last_name TEXT NOT NULL DEFAULT '',created TEXT NOT NULL,PRIMARY KEY(owner,user_id));
CREATE TABLE IF NOT EXISTS notification_scopes(user_id TEXT NOT NULL REFERENCES users(id),scope TEXT NOT NULL,mute_until INTEGER NOT NULL DEFAULT 0,show_preview INTEGER NOT NULL DEFAULT 1,settings_json TEXT NOT NULL DEFAULT '{}',PRIMARY KEY(user_id,scope));
CREATE TABLE IF NOT EXISTS privacy_rules(user_id TEXT NOT NULL REFERENCES users(id),setting TEXT NOT NULL,rules_json TEXT NOT NULL,PRIMARY KEY(user_id,setting));
CREATE TABLE IF NOT EXISTS checklists(id TEXT PRIMARY KEY,chat_id TEXT NOT NULL REFERENCES chats(id),message_id TEXT UNIQUE REFERENCES messages(id),creator_id TEXT NOT NULL REFERENCES users(id),title TEXT NOT NULL,others_can_add INTEGER NOT NULL DEFAULT 0,others_can_mark INTEGER NOT NULL DEFAULT 1,created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS checklist_tasks(id TEXT PRIMARY KEY,checklist_id TEXT NOT NULL REFERENCES checklists(id),task_no INTEGER NOT NULL,text TEXT NOT NULL,completed_by TEXT NOT NULL DEFAULT '',completed_at TEXT NOT NULL DEFAULT '',UNIQUE(checklist_id,task_no));
CREATE TABLE IF NOT EXISTS sticker_packs(id TEXT PRIMARY KEY,owner TEXT NOT NULL DEFAULT '',title TEXT NOT NULL,is_emoji INTEGER NOT NULL DEFAULT 0,created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sticker_files(id TEXT PRIMARY KEY,mime TEXT NOT NULL,bytes INTEGER NOT NULL,sha256 TEXT NOT NULL,data BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS stickers(id TEXT PRIMARY KEY,pack_id TEXT NOT NULL REFERENCES sticker_packs(id),emoji TEXT NOT NULL,media_id TEXT NOT NULL DEFAULT '',file_id TEXT NOT NULL DEFAULT '',sort_order INTEGER NOT NULL DEFAULT 0,format TEXT NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS sticker_favorites(user_id TEXT NOT NULL REFERENCES users(id),sticker_id TEXT NOT NULL REFERENCES stickers(id),created TEXT NOT NULL,PRIMARY KEY(user_id,sticker_id));
CREATE INDEX IF NOT EXISTS stickers_pack ON stickers(pack_id,sort_order);
PRAGMA user_version=6;
`

const p4Schema = `
CREATE TABLE IF NOT EXISTS stories(author_id TEXT NOT NULL REFERENCES users(id),story_no INTEGER NOT NULL,media_id TEXT NOT NULL,kind TEXT NOT NULL,caption TEXT NOT NULL DEFAULT '',entities_json TEXT NOT NULL DEFAULT '[]',privacy_json TEXT NOT NULL DEFAULT '{"type":"everyone"}',areas_json TEXT NOT NULL DEFAULT '[]',created INTEGER NOT NULL,expires INTEGER NOT NULL,deleted INTEGER NOT NULL DEFAULT 0,posted_to_page INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(author_id,story_no));
CREATE INDEX IF NOT EXISTS stories_active ON stories(author_id,expires,deleted);
CREATE TABLE IF NOT EXISTS story_views(author_id TEXT NOT NULL,story_no INTEGER NOT NULL,viewer_id TEXT NOT NULL REFERENCES users(id),viewed_at INTEGER NOT NULL,PRIMARY KEY(author_id,story_no,viewer_id));
CREATE TABLE IF NOT EXISTS story_reactions(author_id TEXT NOT NULL,story_no INTEGER NOT NULL,user_id TEXT NOT NULL REFERENCES users(id),emoji TEXT NOT NULL,PRIMARY KEY(author_id,story_no,user_id));
CREATE TABLE IF NOT EXISTS story_reads(viewer_id TEXT NOT NULL REFERENCES users(id),author_id TEXT NOT NULL,max_read_no INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(viewer_id,author_id));
CREATE TABLE IF NOT EXISTS story_reports(id TEXT PRIMARY KEY,reporter_id TEXT NOT NULL REFERENCES users(id),author_id TEXT NOT NULL,story_no INTEGER NOT NULL,reason TEXT NOT NULL,created TEXT NOT NULL);
PRAGMA user_version=7;
`

const p5Schema = `
CREATE TABLE IF NOT EXISTS login_challenges(token_hash TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),platform TEXT NOT NULL,app_name TEXT NOT NULL DEFAULT '',app_version TEXT NOT NULL DEFAULT '',device_model TEXT NOT NULL DEFAULT '',last_ip TEXT NOT NULL DEFAULT '',expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS story_albums(id TEXT PRIMARY KEY,owner TEXT NOT NULL REFERENCES users(id),title TEXT NOT NULL,sort_order INTEGER NOT NULL DEFAULT 0,created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS story_album_items(album_id TEXT NOT NULL REFERENCES story_albums(id) ON DELETE CASCADE,story_no INTEGER NOT NULL,sort_order INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(album_id,story_no));
CREATE INDEX IF NOT EXISTS story_albums_owner ON story_albums(owner,sort_order,id);
CREATE INDEX IF NOT EXISTS story_album_items_story ON story_album_items(story_no,album_id);
CREATE INDEX IF NOT EXISTS login_challenges_expiry ON login_challenges(expires);
CREATE INDEX IF NOT EXISTS users_deleted ON users(deleted);
PRAGMA user_version=8;
`

const p6Schema = `
CREATE TABLE IF NOT EXISTS bots(user_id TEXT PRIMARY KEY REFERENCES users(id),owner_id TEXT NOT NULL REFERENCES users(id),token_hash TEXT NOT NULL UNIQUE,api_id INTEGER NOT NULL UNIQUE,webhook_url TEXT NOT NULL DEFAULT '',webhook_secret TEXT NOT NULL DEFAULT '',created TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS bot_updates(bot_id TEXT NOT NULL REFERENCES bots(user_id) ON DELETE CASCADE,update_id INTEGER NOT NULL,payload TEXT NOT NULL,delivered INTEGER NOT NULL DEFAULT 0,created TEXT NOT NULL,PRIMARY KEY(bot_id,update_id));
CREATE INDEX IF NOT EXISTS bot_updates_pending ON bot_updates(bot_id,update_id) WHERE delivered=0;
CREATE TABLE IF NOT EXISTS api_ids(kind TEXT NOT NULL,id TEXT NOT NULL,api_id INTEGER NOT NULL UNIQUE,PRIMARY KEY(kind,id));
CREATE TABLE IF NOT EXISTS bot_callbacks(id TEXT PRIMARY KEY,bot_id TEXT NOT NULL REFERENCES bots(user_id),chat_id TEXT NOT NULL,message_id TEXT NOT NULL,from_user TEXT NOT NULL,data TEXT NOT NULL,created TEXT NOT NULL,answered INTEGER NOT NULL DEFAULT 0);
PRAGMA user_version=9;
`

const p7Schema = `
CREATE TABLE IF NOT EXISTS chat_invites(code TEXT PRIMARY KEY,chat_id TEXT NOT NULL REFERENCES chats(id),creator TEXT NOT NULL REFERENCES users(id),name TEXT NOT NULL DEFAULT '',created TEXT NOT NULL,expires INTEGER NOT NULL DEFAULT 0,member_limit INTEGER NOT NULL DEFAULT 0,uses INTEGER NOT NULL DEFAULT 0,revoked INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS chat_invites_chat ON chat_invites(chat_id,revoked,created);
CREATE TABLE IF NOT EXISTS chat_wallpapers(user_id TEXT NOT NULL REFERENCES users(id),chat_id TEXT NOT NULL,document TEXT NOT NULL,PRIMARY KEY(user_id,chat_id));
PRAGMA user_version=10;
`

const p8Schema = `
CREATE TABLE IF NOT EXISTS scheduled_messages(id TEXT PRIMARY KEY,chat_id TEXT NOT NULL,sender TEXT NOT NULL,client_id TEXT NOT NULL,kind TEXT NOT NULL,text TEXT NOT NULL DEFAULT '',media_id TEXT NOT NULL DEFAULT '',reply_to TEXT NOT NULL DEFAULT '',extra_json TEXT NOT NULL DEFAULT '',ttl INTEGER NOT NULL DEFAULT 0,send_at INTEGER NOT NULL DEFAULT 0,when_online INTEGER NOT NULL DEFAULT 0,payload_hash TEXT NOT NULL DEFAULT '',created TEXT NOT NULL,UNIQUE(sender,client_id));
CREATE INDEX IF NOT EXISTS scheduled_due ON scheduled_messages(send_at,when_online);
PRAGMA user_version=11;
`
