package chat

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"
)

func (a *App) albumRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/story-albums", a.auth(a.listStoryAlbums))
	mux.HandleFunc("POST /v1/story-albums", a.auth(a.createStoryAlbum))
	mux.HandleFunc("GET /v1/story-albums/{id}", a.auth(a.getStoryAlbum))
	mux.HandleFunc("PATCH /v1/story-albums/{id}", a.auth(a.renameStoryAlbum))
	mux.HandleFunc("DELETE /v1/story-albums/{id}", a.auth(a.deleteStoryAlbum))
	mux.HandleFunc("PUT /v1/story-albums/{id}/stories", a.auth(a.putStoryAlbumStories))
	mux.HandleFunc("POST /v1/story-albums/reorder", a.auth(a.reorderStoryAlbums))
}

func (a *App) storyInAlbum(author string, no int) bool {
	var n int
	if e := a.DB.QueryRow("SELECT count(*) FROM story_album_items i JOIN story_albums a ON a.id=i.album_id WHERE a.owner=? AND i.story_no=?", author, no).Scan(&n); e != nil {
		return false
	}
	return n > 0
}

func (a *App) listStoryAlbums(w http.ResponseWriter, r *http.Request, p Principal) {
	owner := strings.TrimSpace(r.URL.Query().Get("owner"))
	if owner == "" {
		owner = p.UserID
	}
	rows, e := a.DB.Query("SELECT id,title,sort_order,created FROM story_albums WHERE owner=? ORDER BY sort_order,id", owner)
	if e != nil {
		fail(w, e)
		return
	}
	type albumRow struct {
		id, title, created string
		sort               int
	}
	var albums []albumRow
	for rows.Next() {
		var row albumRow
		if e = rows.Scan(&row.id, &row.title, &row.sort, &row.created); e != nil {
			rows.Close()
			fail(w, e)
			return
		}
		albums = append(albums, row)
	}
	if e = rows.Err(); e != nil {
		rows.Close()
		fail(w, e)
		return
	}
	rows.Close()
	out := []map[string]any{}
	for _, row := range albums {
		items, e := a.albumStoryNos(row.id, owner, p.UserID)
		if e != nil {
			fail(w, e)
			return
		}
		out = append(out, map[string]any{"id": row.id, "owner": owner, "title": row.title, "sort_order": row.sort, "created_at": row.created, "story_nos": items})
	}
	respond(w, 200, map[string]any{"albums": out})
}

func (a *App) albumStoryNos(albumID, owner, viewer string) ([]int, error) {
	rows, e := a.DB.Query("SELECT story_no FROM story_album_items WHERE album_id=? ORDER BY sort_order,story_no", albumID)
	if e != nil {
		return nil, e
	}
	nos := []int{}
	for rows.Next() {
		var no int
		if e = rows.Scan(&no); e != nil {
			rows.Close()
			return nil, e
		}
		nos = append(nos, no)
	}
	if e = rows.Err(); e != nil {
		rows.Close()
		return nil, e
	}
	rows.Close()
	out := []int{}
	for _, no := range nos {
		if a.albumItemVisible(owner, no, viewer) {
			out = append(out, no)
		}
	}
	return out, nil
}

func (a *App) albumItemVisible(author string, no int, viewer string) bool {
	story, e := a.loadStory(author, no, viewer, true)
	return e == nil && story != nil
}

func (a *App) createStoryAlbum(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Title    string `json:"title"`
		StoryNos []int  `json:"story_nos"`
	}
	if !decode(w, r, &b) {
		return
	}
	title := strings.TrimSpace(b.Title)
	if title == "" || len(title) > 64 || len(b.StoryNos) > 100 {
		fail(w, ErrInvalid)
		return
	}
	if e := a.ensureOwnStories(p.UserID, b.StoryNos); e != nil {
		fail(w, e)
		return
	}
	aid := id()
	var sort int
	a.DB.QueryRow("SELECT COALESCE(max(sort_order)+1,0) FROM story_albums WHERE owner=?", p.UserID).Scan(&sort)
	e := a.transaction(func(tx *sql.Tx) error {
		if _, e := tx.Exec("INSERT INTO story_albums(id,owner,title,sort_order,created) VALUES(?,?,?,?,?)", aid, p.UserID, title, sort, now()); e != nil {
			return e
		}
		return replaceAlbumItems(tx, aid, b.StoryNos)
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 201, map[string]any{"id": aid, "owner": p.UserID, "title": title, "sort_order": sort, "story_nos": b.StoryNos})
}

func (a *App) getStoryAlbum(w http.ResponseWriter, r *http.Request, p Principal) {
	album, owner, title, e := a.loadAlbum(r.PathValue("id"))
	if e != nil {
		fail(w, ErrForbidden)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 100
	}
	if offset < 0 {
		offset = 0
	}
	nos, e := a.albumStoryNos(album, owner, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	if offset > len(nos) {
		offset = len(nos)
	}
	end := offset + limit
	if end > len(nos) {
		end = len(nos)
	}
	stories := []map[string]any{}
	for _, no := range nos[offset:end] {
		s, e := a.loadStory(owner, no, p.UserID, true)
		if e == nil {
			stories = append(stories, s)
		}
	}
	respond(w, 200, map[string]any{"id": album, "owner": owner, "title": title, "story_nos": nos, "stories": stories, "offset": offset, "total": len(nos)})
}

func (a *App) renameStoryAlbum(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		Title string `json:"title"`
	}
	if !decode(w, r, &b) {
		return
	}
	title := strings.TrimSpace(b.Title)
	if title == "" || len(title) > 64 {
		fail(w, ErrInvalid)
		return
	}
	album, owner, _, e := a.loadAlbum(r.PathValue("id"))
	if e != nil || owner != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	if _, e = a.DB.Exec("UPDATE story_albums SET title=? WHERE id=?", title, album); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"id": album, "title": title})
}

func (a *App) deleteStoryAlbum(w http.ResponseWriter, r *http.Request, p Principal) {
	album, owner, _, e := a.loadAlbum(r.PathValue("id"))
	if e != nil || owner != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	e = a.transaction(func(tx *sql.Tx) error {
		if _, e := tx.Exec("DELETE FROM story_album_items WHERE album_id=?", album); e != nil {
			return e
		}
		_, e := tx.Exec("DELETE FROM story_albums WHERE id=?", album)
		return e
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) putStoryAlbumStories(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		StoryNos []int  `json:"story_nos"`
		Op       string `json:"op"`
	}
	if !decode(w, r, &b) {
		return
	}
	album, owner, _, e := a.loadAlbum(r.PathValue("id"))
	if e != nil || owner != p.UserID {
		fail(w, ErrForbidden)
		return
	}
	if len(b.StoryNos) > 100 {
		fail(w, ErrInvalid)
		return
	}
	op := b.Op
	if op == "" {
		op = "set"
	}
	current, e := a.albumStoryNos(album, owner, p.UserID)
	if e != nil {
		fail(w, e)
		return
	}
	var next []int
	switch op {
	case "set", "reorder":
		if e := a.ensureOwnStories(p.UserID, b.StoryNos); e != nil {
			fail(w, e)
			return
		}
		next = uniqueStoryNos(b.StoryNos)
	case "add":
		if e := a.ensureOwnStories(p.UserID, b.StoryNos); e != nil {
			fail(w, e)
			return
		}
		next = uniqueStoryNos(append(append([]int{}, current...), b.StoryNos...))
	case "remove":
		drop := map[int]bool{}
		for _, n := range b.StoryNos {
			drop[n] = true
		}
		for _, n := range current {
			if !drop[n] {
				next = append(next, n)
			}
		}
	default:
		fail(w, ErrInvalid)
		return
	}
	if len(next) > 100 {
		fail(w, ErrInvalid)
		return
	}
	if e := a.transaction(func(tx *sql.Tx) error { return replaceAlbumItems(tx, album, next) }); e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]any{"id": album, "story_nos": next})
}

func (a *App) reorderStoryAlbums(w http.ResponseWriter, r *http.Request, p Principal) {
	var b struct {
		AlbumIDs []string `json:"album_ids"`
	}
	if !decode(w, r, &b) {
		return
	}
	if len(b.AlbumIDs) > 100 {
		fail(w, ErrInvalid)
		return
	}
	e := a.transaction(func(tx *sql.Tx) error {
		for i, id := range b.AlbumIDs {
			res, e := tx.Exec("UPDATE story_albums SET sort_order=? WHERE id=? AND owner=?", i, id, p.UserID)
			if e != nil {
				return e
			}
			n, _ := res.RowsAffected()
			if n != 1 {
				return ErrForbidden
			}
		}
		return nil
	})
	if e != nil {
		fail(w, e)
		return
	}
	respond(w, 200, map[string]bool{"ok": true})
}

func (a *App) loadAlbum(id string) (album, owner, title string, err error) {
	err = a.DB.QueryRow("SELECT id,owner,title FROM story_albums WHERE id=?", id).Scan(&album, &owner, &title)
	return
}

func (a *App) ensureOwnStories(user string, nos []int) error {
	for _, no := range nos {
		if no <= 0 {
			return ErrInvalid
		}
		var deleted int
		e := a.DB.QueryRow("SELECT deleted FROM stories WHERE author_id=? AND story_no=?", user, no).Scan(&deleted)
		if e != nil || deleted == 1 {
			return ErrForbidden
		}
	}
	return nil
}

func replaceAlbumItems(tx *sql.Tx, album string, nos []int) error {
	if _, e := tx.Exec("DELETE FROM story_album_items WHERE album_id=?", album); e != nil {
		return e
	}
	for i, no := range nos {
		if _, e := tx.Exec("INSERT INTO story_album_items(album_id,story_no,sort_order) VALUES(?,?,?)", album, no, i); e != nil {
			return e
		}
	}
	return nil
}

func uniqueStoryNos(nos []int) []int {
	seen := map[int]bool{}
	out := []int{}
	for _, n := range nos {
		if n <= 0 || seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	return out
}

