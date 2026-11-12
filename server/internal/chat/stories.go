package chat

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func (a *App) storyRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/stories", a.auth(a.createStory))
	mux.HandleFunc("GET /v1/stories/active", a.auth(a.activeStories))
	mux.HandleFunc("GET /v1/stories/{author}/{no}", a.auth(a.getStory))
	mux.HandleFunc("PATCH /v1/stories/{author}/{no}", a.auth(a.editStory))
	mux.HandleFunc("DELETE /v1/stories/{author}/{no}", a.auth(a.deleteStory))
	mux.HandleFunc("POST /v1/stories/{author}/{no}/open", a.auth(a.openStory))
	mux.HandleFunc("PUT /v1/stories/{author}/{no}/privacy", a.auth(a.setStoryPrivacy))
	mux.HandleFunc("PUT /v1/stories/{author}/{no}/reaction", a.auth(a.setStoryReaction))
	mux.HandleFunc("GET /v1/stories/{author}/{no}/interactions", a.auth(a.storyInteractions))
	mux.HandleFunc("POST /v1/stories/{author}/{no}/report", a.auth(a.reportStory))
	mux.HandleFunc("GET /v1/users/{id}/stories", a.auth(a.listUserStories))
}

type storyPrivacy struct {
	Type    string   `json:"type"`
	UserIDs []string `json:"user_ids,omitempty"`
}

type storySpec struct {
	ClientID      string          `json:"client_story_id"`
	MediaID       string          `json:"media_id"`
	Kind          string          `json:"kind"`
	Caption       string          `json:"caption"`
	Entities      []Entity        `json:"entities"`
	Privacy       storyPrivacy    `json:"privacy"`
	Areas         json.RawMessage `json:"areas"`
	PostedToPage  *bool           `json:"posted_to_page"`
	TTLHours      int             `json:"ttl_hours"`
}

func normalizeStoryPrivacy(p *storyPrivacy) error {
	if p.Type == "" {
		p.Type = "everyone"
	}
	switch p.Type {
	case "everyone", "contacts", "close_friends":
		p.UserIDs = nil
	case "users":
		if len(p.UserIDs) == 0 || len(p.UserIDs) > 200 {
			return ErrInvalid
		}
		for _, id := range p.UserIDs {
			if !keyRE.MatchString(id) {
				return ErrInvalid
			}
		}
	default:
		return ErrInvalid
	}
	return nil
}

func (a *App) canViewStory(viewer, author string, no int, privacy storyPrivacy, expires, deleted int64) bool {
	if deleted == 1 {
		return false
	}
	if viewer == author {
		return true
	}
	if expires > 0 && expires <= time.Now().Unix() && !a.storyInAlbum(author, no) {
		return false
	}
	switch privacy.Type {
	case "everyone", "":
		return true
	case "contacts", "close_friends":
		var n int
		a.DB.QueryRow("SELECT count(*) FROM contacts WHERE owner=? AND user_id=?", author, viewer).Scan(&n)
		return n == 1
	case "users":
		for _, id := range privacy.UserIDs {
			if id == viewer {
				return true
			}
		}
		return false
	default:
		return false
	}
}

func (a *App) storyViewers(author string, privacy storyPrivacy) []string {
	out := []string{author}
	seen := map[string]bool{author: true}
	add := func(id string) {
		if id == "" || seen[id] {
			return
		}
		seen[id] = true
		out = append(out, id)
	}
	switch privacy.Type {
	case "everyone", "":
		rows, e := a.DB.Query("SELECT DISTINCT user_id FROM contacts WHERE owner=? UNION SELECT DISTINCT owner FROM contacts WHERE user_id=?", author, author)
		if e == nil {
			defer rows.Close()
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					add(id)
				}
			}
		}
		rows2, e := a.DB.Query("SELECT DISTINCT m2.user_id FROM members m1 JOIN chats c ON c.id=m1.chat_id AND c.kind='direct' JOIN members m2 ON m2.chat_id=c.id AND m2.user_id<>m1.user_id WHERE m1.user_id=?", author)
		if e == nil {
			defer rows2.Close()
			for rows2.Next() {
				var id string
				if rows2.Scan(&id) == nil {
					add(id)
				}
			}
		}
	case "contacts", "close_friends":
		rows, e := a.DB.Query("SELECT user_id FROM contacts WHERE owner=?", author)
		if e == nil {
			defer rows.Close()
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					add(id)
				}
			}
		}
	case "users":
		for _, id := range privacy.UserIDs {
			add(id)
		}
	}
	return out
}

func (a *App) loadStory(author string, no int, viewer string, includeExpired bool) (map[string]any, error) {
	var media, kind, caption, entities, privacyRaw, areas string
	var created, expires, deleted, page int64
	e := a.DB.QueryRow("SELECT media_id,kind,caption,entities_json,privacy_json,areas_json,created,expires,deleted,posted_to_page FROM stories WHERE author_id=? AND story_no=?", author, no).Scan(&media, &kind, &caption, &entities, &privacyRaw, &areas, &created, &expires, &deleted, &page)
	if e != nil {
		return nil, ErrForbidden
	}
	var priv storyPrivacy
	_ = json.Unmarshal([]byte(privacyRaw), &priv)
	if !includeExpired && !a.canViewStory(viewer, author, no, priv, expires, deleted) {
		return nil, ErrForbidden
	}
	if includeExpired && (deleted == 1 || (viewer != author && !a.canViewStory(viewer, author, no, priv, 0, deleted))) {
		return nil, ErrForbidden
	}
	var views, reactions int
	a.DB.QueryRow("SELECT count(*) FROM story_views WHERE author_id=? AND story_no=?", author, no).Scan(&views)
	a.DB.QueryRow("SELECT count(*) FROM story_reactions WHERE author_id=? AND story_no=?", author, no).Scan(&reactions)
	var chosen string
	a.DB.QueryRow("SELECT emoji FROM story_reactions WHERE author_id=? AND story_no=? AND user_id=?", author, no, viewer).Scan(&chosen)
	recent := []string{}
	if viewer == author {
		rows, e := a.DB.Query("SELECT viewer_id FROM story_views WHERE author_id=? AND story_no=? ORDER BY viewed_at DESC LIMIT 10", author, no)
		if e == nil {
			for rows.Next() {
				var id string
				if rows.Scan(&id) == nil {
					recent = append(recent, id)
				}
			}
			rows.Close()
		}
	}
	ents := []Entity{}
	_ = json.Unmarshal([]byte(entities), &ents)
	var area any
	if areas != "" && areas != "[]" {
		_ = json.Unmarshal([]byte(areas), &area)
	}
	if area == nil {
		area = []any{}
	}
	out := map[string]any{
		"author_id": author, "story_no": no, "media_id": media, "kind": kind,
		"caption": caption, "entities": ents, "privacy": priv, "areas": area,
		"created": created, "expires": expires, "posted_to_page": page == 1,
		"view_count": views, "reaction_count": reactions, "recent_viewer_ids": recent,
		"can_delete": viewer == author, "can_edit": viewer == author,
		"can_get_interactions": viewer == author,
	}
	if chosen != "" {
		out["chosen_reaction"] = chosen
	}
	return out, nil
}

func (a *App) createStory(w http.ResponseWriter, r *http.Request, p Principal) {
	var b storySpec
	if !decode(w, r, &b) {
		return
	}
	if b.MediaID == "" || (b.Kind != "photo" && b.Kind != "video") {
		fail(w, ErrInvalid)
		return
	}
	if _, e := validateEntities(b.Caption, b.Entities); e != nil {
		fail(w, e)
		return
	}
	if e := normalizeStoryPrivacy(&b.Privacy); e != nil {
		fail(w, e)
		return
	}
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM media WHERE id=? AND owner=?", b.MediaID, p.UserID).Scan(&n); e != nil || n != 1 {
		fail(w, ErrInvalid)
		return
	}
	ttl := b.TTLHours
	if ttl <= 0 {
		ttl = 24
	}
	if ttl > 24*7 {
		ttl = 24 * 7
	}
	posted := 1
	if b.PostedToPage != nil && !*b.PostedToPage {
		posted = 0
	}
	areas := "[]"
	if len(b.Areas) > 0 {
		areas = string(b.Areas)
	}
	var no int
	now := time.Now().Unix()
	e := a.transaction(func(tx *sql.Tx) error {
		if e := tx.QueryRow("SELECT COALESCE(max(story_no),0)+1 FROM stories WHERE author_id=?", p.UserID).Scan(&no); e != nil {
			return e
		}
		active := 0
		tx.QueryRow("SELECT count(*) FROM stories WHERE author_id=? AND deleted=0 AND expires>?", p.UserID, now).Scan(&active)
		if active >= 100 {
			return ErrInvalid
		}
		_, e := tx.Exec("INSERT INTO stories(author_id,story_no,media_id,kind,caption,entities_json,privacy_json,areas_json,created,expires,posted_to_page) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
			p.UserID, no, b.MediaID, b.Kind, b.Caption, jsonText(b.Entities, "[]"), jsonText(b.Privacy, `{"type":"everyone"}`), areas, now, now+int64(ttl)*3600, posted)
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	story, e := a.loadStory(p.UserID, no, p.UserID, true)
	if e != nil {
		fail(w, e)
		return
	}
	viewers := a.storyViewers(p.UserID, b.Privacy)
	_ = a.transaction(func(tx *sql.Tx) error {
		return emit(tx, viewers, "story.created", "", story)
	})
	respond(w, 201, story)
}

func (a *App) activeStories(w http.ResponseWriter, r *http.Request, p Principal) {
	now := time.Now().Unix()
	rows, e := a.DB.Query("SELECT author_id,story_no,privacy_json,created,expires,deleted FROM stories WHERE deleted=0 AND expires>? ORDER BY created DESC LIMIT 500", now)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	type item struct {
		Author, Privacy string
		No, Created, Expires, Deleted int64
	}
	raw := []item{}
	for rows.Next() {
		var it item
		if e = rows.Scan(&it.Author, &it.No, &it.Privacy, &it.Created, &it.Expires, &it.Deleted); e != nil {
			fail(w, e)
			return
		}
		raw = append(raw, it)
	}
	grouped := map[string][]map[string]any{}
	order := []string{}
	for _, it := range raw {
		var priv storyPrivacy
		_ = json.Unmarshal([]byte(it.Privacy), &priv)
		if !a.canViewStory(p.UserID, it.Author, int(it.No), priv, it.Expires, it.Deleted) {
			continue
		}
		if _, ok := grouped[it.Author]; !ok {
			order = append(order, it.Author)
		}
		grouped[it.Author] = append(grouped[it.Author], map[string]any{"story_no": it.No, "created": it.Created})
	}
	out := []map[string]any{}
	for _, author := range order {
		var maxRead int
		a.DB.QueryRow("SELECT max_read_no FROM story_reads WHERE viewer_id=? AND author_id=?", p.UserID, author).Scan(&maxRead)
		out = append(out, map[string]any{"author_id": author, "max_read_story_no": maxRead, "stories": grouped[author]})
	}
	respond(w, 200, map[string]any{"chats": out})
}

func (a *App) getStory(w http.ResponseWriter, r *http.Request, p Principal) {
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil || no <= 0 {
		fail(w, ErrInvalid)
		return
	}
	story, e := a.loadStory(r.PathValue("author"), no, p.UserID, false)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, story)
}

func (a *App) listUserStories(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("id")
	archived := r.URL.Query().Get("archived") == "1"
	from, _ := strconv.Atoi(r.URL.Query().Get("from_no"))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	now := time.Now().Unix()
	q := "SELECT story_no FROM stories WHERE author_id=? AND deleted=0"
	args := []any{author}
	if archived {
		if p.UserID != author {
			fail(w, ErrForbidden)
			return
		}
		q += " AND expires<=?"
		args = append(args, now)
	} else {
		q += " AND expires>?"
		args = append(args, now)
	}
	if from > 0 {
		q += " AND story_no<?"
		args = append(args, from)
	}
	q += " ORDER BY story_no DESC LIMIT ?"
	args = append(args, limit)
	rows, e := a.DB.Query(q, args...)
	if e != nil {
		fail(w, e)
		return
	}
	nos := []int{}
	for rows.Next() {
		var no int
		if rows.Scan(&no) == nil {
			nos = append(nos, no)
		}
	}
	rows.Close()
	items := []map[string]any{}
	for _, no := range nos {
		s, e := a.loadStory(author, no, p.UserID, archived)
		if e != nil {
			continue
		}
		items = append(items, s)
	}
	respond(w, 200, map[string]any{"stories": items})
}

func (a *App) editStory(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil || author != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	var b struct {
		Caption      *string         `json:"caption"`
		Entities     []Entity        `json:"entities"`
		Areas        json.RawMessage `json:"areas"`
		PostedToPage *bool           `json:"posted_to_page"`
	}
	if !decode(w, r, &b) {
		return
	}
	sets := []string{}
	args := []any{}
	if b.Caption != nil {
		if _, e := validateEntities(*b.Caption, b.Entities); e != nil {
			fail(w, e)
			return
		}
		sets = append(sets, "caption=?", "entities_json=?")
		args = append(args, *b.Caption, jsonText(b.Entities, "[]"))
	}
	if len(b.Areas) > 0 {
		sets = append(sets, "areas_json=?")
		args = append(args, string(b.Areas))
	}
	if b.PostedToPage != nil {
		sets = append(sets, "posted_to_page=?")
		args = append(args, boolInt(*b.PostedToPage))
	}
	if len(sets) == 0 {
		fail(w, ErrInvalid)
		return
	}
	args = append(args, author, no)
	res, e := a.DB.Exec("UPDATE stories SET "+strings.Join(sets, ",")+" WHERE author_id=? AND story_no=? AND deleted=0", args...)
	if e != nil {
		fail(w, e)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fail(w, ErrForbidden)
		return
	}
	story, e := a.loadStory(author, no, p.UserID, true)
	if e != nil {
		fail(w, e)
		return
	}
	priv, _ := story["privacy"].(storyPrivacy)
	viewers := a.storyViewers(author, priv)
	_ = a.transaction(func(tx *sql.Tx) error {
		return emit(tx, viewers, "story.updated", "", story)
	})
	respond(w, 200, story)
}

func (a *App) deleteStory(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil || author != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	res, e := a.DB.Exec("UPDATE stories SET deleted=1 WHERE author_id=? AND story_no=? AND deleted=0", author, no)
	if e != nil {
		fail(w, e)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fail(w, ErrForbidden)
		return
	}
	payload := map[string]any{"author_id": author, "story_no": no}
	viewers := a.storyViewers(author, storyPrivacy{Type: "everyone"})
	_ = a.transaction(func(tx *sql.Tx) error {
		return emit(tx, viewers, "story.deleted", "", payload)
	})
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) openStory(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil {
		fail(w, ErrInvalid)
		return
	}
	story, e := a.loadStory(author, no, p.UserID, false)
	if e != nil {
		fail(w, e)
		return
	}
	if author != p.UserID {
		_, _ = a.DB.Exec("INSERT OR IGNORE INTO story_views(author_id,story_no,viewer_id,viewed_at) VALUES(?,?,?,?)", author, no, p.UserID, time.Now().Unix())
	}
	_, _ = a.DB.Exec("INSERT INTO story_reads(viewer_id,author_id,max_read_no) VALUES(?,?,?) ON CONFLICT(viewer_id,author_id) DO UPDATE SET max_read_no=max(max_read_no,excluded.max_read_no)", p.UserID, author, no)
	respond(w, 200, story)
}

func (a *App) setStoryPrivacy(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil || author != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	var b storyPrivacy
	if !decode(w, r, &b) {
		return
	}
	if e := normalizeStoryPrivacy(&b); e != nil {
		fail(w, e)
		return
	}
	res, e := a.DB.Exec("UPDATE stories SET privacy_json=? WHERE author_id=? AND story_no=? AND deleted=0", jsonText(b, `{"type":"everyone"}`), author, no)
	if e != nil {
		fail(w, e)
		return
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		fail(w, ErrForbidden)
		return
	}
	story, e := a.loadStory(author, no, p.UserID, true)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, story)
}

func (a *App) setStoryReaction(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil {
		fail(w, ErrInvalid)
		return
	}
	var b struct {
		Emoji  string `json:"emoji"`
		Remove bool   `json:"remove"`
	}
	if !decode(w, r, &b) {
		return
	}
	if _, e := a.loadStory(author, no, p.UserID, false); e != nil {
		fail(w, e)
		return
	}
	if b.Remove || strings.TrimSpace(b.Emoji) == "" {
		_, _ = a.DB.Exec("DELETE FROM story_reactions WHERE author_id=? AND story_no=? AND user_id=?", author, no, p.UserID)
	} else {
		emoji := strings.TrimSpace(b.Emoji)
		if len(emoji) > 16 {
			fail(w, ErrInvalid)
			return
		}
		_, e = a.DB.Exec("INSERT INTO story_reactions(author_id,story_no,user_id,emoji) VALUES(?,?,?,?) ON CONFLICT(author_id,story_no,user_id) DO UPDATE SET emoji=excluded.emoji", author, no, p.UserID, emoji)
		if e != nil {
			fail(w, e)
			return
		}
	}
	story, e := a.loadStory(author, no, p.UserID, false)
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, story)
}

func (a *App) storyInteractions(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil || author != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	rows, e := a.DB.Query(`SELECT v.viewer_id,v.viewed_at,COALESCE(r.emoji,'') FROM story_views v LEFT JOIN story_reactions r ON r.author_id=v.author_id AND r.story_no=v.story_no AND r.user_id=v.viewer_id WHERE v.author_id=? AND v.story_no=? ORDER BY v.viewed_at DESC LIMIT 200`, author, no)
	if e != nil {
		fail(w, e)
		return
	}
	defer rows.Close()
	out := []map[string]any{}
	for rows.Next() {
		var id, emoji string
		var at int64
		if rows.Scan(&id, &at, &emoji) != nil {
			continue
		}
		item := map[string]any{"user_id": id, "viewed_at": at}
		if emoji != "" {
			item["emoji"] = emoji
		}
		out = append(out, item)
	}
	respond(w, 200, map[string]any{"interactions": out})
}

func (a *App) reportStory(w http.ResponseWriter, r *http.Request, p Principal) {
	author := r.PathValue("author")
	no, e := strconv.Atoi(r.PathValue("no"))
	if e != nil {
		fail(w, ErrInvalid)
		return
	}
	if _, e := a.loadStory(author, no, p.UserID, false); e != nil {
		fail(w, e)
		return
	}
	var b struct {
		Reason string `json:"reason"`
	}
	decode(w, r, &b)
	if _, e = a.DB.Exec("INSERT INTO story_reports(id,reporter_id,author_id,story_no,reason,created) VALUES(?,?,?,?,?,?)", id(), p.UserID, author, no, strings.TrimSpace(b.Reason), now()); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}
