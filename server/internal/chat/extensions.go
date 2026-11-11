package chat

import (
	"database/sql"
	"encoding/json"
	"fmt"
)

func (a *App) migrateExtensions() error {
	for table, columns := range map[string]map[string]string{
		"messages": {"media_meta_json": "TEXT NOT NULL DEFAULT ''", "album_id": "TEXT NOT NULL DEFAULT ''", "entities_json": "TEXT NOT NULL DEFAULT '[]'", "preview_json": "TEXT NOT NULL DEFAULT ''", "reply_markup_json": "TEXT NOT NULL DEFAULT ''", "via_bot_id": "TEXT NOT NULL DEFAULT ''", "forward_origin_json": "TEXT NOT NULL DEFAULT ''"},
		"users":    {"read_receipts_enabled": "INTEGER NOT NULL DEFAULT 1"},
		"chats":    {"last_activity": "INTEGER NOT NULL DEFAULT 0"},
		"members":  {"manual_unread": "INTEGER NOT NULL DEFAULT 0", "archived": "INTEGER NOT NULL DEFAULT 0", "pin_order": "INTEGER NOT NULL DEFAULT 0", "notification_mute_until": "INTEGER NOT NULL DEFAULT 0", "draft_json": "TEXT NOT NULL DEFAULT ''", "joined_at": "INTEGER NOT NULL DEFAULT 0", "muted_until": "INTEGER NOT NULL DEFAULT 0"},
	} {
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
	_, e := a.DB.Exec(extensionSchema + discoverySchema)
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
