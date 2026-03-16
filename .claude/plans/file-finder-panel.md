# Plan: File Finder Panel

## Overview

A new panel that lets the user fuzzy-search files in the workspace by name/path.
It mirrors the visual layout of the grep panel (query input + result list on the
left, file preview on the right) and reuses `reload_file_into_buffer` /
`render_raw_buffer` for the preview pane.

Unlike grep, file-name walking is fast enough to run **synchronously** on every
keystroke — no background job queue needed.

---

## Fuzzy Matching & Ranking

### Inspiration: command palette algorithm

The command palette (`command_palette.odin`) already has a simple but effective
fuzzy scorer. For each query character it scans the haystack forward from the
last match position, accumulating the gap distance between matched characters:

```
query  = "gr"
target = "grep.odin"   → matches at 0, 1  → dist = 0  (tight prefix)
target = "glyph_buffer.odin" → matches at 0, 13 → dist = 13 (large gap)
target = "core.odin"   → 'g' not found → dist = large penalty
```

Items where all query characters are found get `sort_id = dist` (lower = better).
Items where any character is missing are not excluded but scored high — so they
sort to the bottom rather than being filtered out entirely.

For files, the same algorithm is applied to the **relative path** (from workspace
root), so `panels/grep.odin` can be found with `pg` or `panels/g`.

### Ranking formula

Files have two sort dimensions:
- **Fuzzy score** — primary (lower gap distance = better match)
- **Recency rank** — tiebreaker (0 = most recently modified file)

Combined: `sort_id = fuzzy_dist * len(all_entries) + recency_rank`

Multiplying by `len(all_entries)` makes fuzzy score strictly dominant: every
unit of fuzzy gap distance is worth more than the full recency spread, so two
files with the same fuzzy score are ordered by recency, but a 1-gap-worse match
never beats a tighter match regardless of how recent it is.

When the query is empty, all files are shown pre-sorted by recency (most
recently modified first) — no fuzzy scoring applied.

---

## Odin Directory Walking API

`core:os` provides a `Walker` for recursive traversal:

```odin
walker := os.walker_create_path(dir)
defer os.walker_destroy(&walker)

for {
    fi, err, ok := os.walker_walk(&walker)
    if !ok { break }
    if err != nil { continue }

    if fi.is_dir {
        base := filepath.base(fi.fullpath)
        for skip in SKIP_DIRS {
            if base == skip {
                os.walker_skip_dir(&walker)
                break
            }
        }
        continue
    }

    // fi.fullpath  — absolute path
    // fi.modified  — last modified time (os.File_Time)
}
```

`walker_skip_dir` must be called while the walker is still on the directory
entry (before the next `walker_walk` call). `fi.modified` is an `os.File_Time`
(platform integer, comparable with `<`).

---

## New File: `src/panels/file_finder.odin`

### Data structures

```odin
MAX_FILE_FINDER_RESULTS :: 5000

SKIP_DIRS :: []string { ".git", "target", "bin", ".claude", "node_modules" }

FileFinderEntry :: struct {
    path:         string,   // absolute path; allocated in panel arena
    recency_rank: int,      // 0 = most recently modified
    sort_id:      int,      // combined fuzzy+recency score for current query
}

FileFinderPanel :: struct {
    buffer:            core.FileBuffer,          // search input
    selected_result:   int,
    results_start:     int,

    preview_buffer:    core.FileBuffer,
    preview_file_path: string,

    // Collected once on create; sorted by mod_time descending
    // Lives in panel arena — no per-keystroke allocation of path strings
    all_entries: []FileFinderEntry,

    // Rebuilt on every keystroke: pointers into all_entries, sorted by sort_id
    // [dynamic] so backing array grows monotonically (clear+append, no free)
    filtered_results: [dynamic]^FileFinderEntry,
}
```

Using `[dynamic]^FileFinderEntry` (pointers into `all_entries`) means
`filter_and_rank` can sort the filtered subset independently without touching
`all_entries`, and the per-keystroke allocation cost is just pointer copies.

---

### Directory collection + initial sort

```odin
CollectedFile :: struct {
    path:      string,
    mod_time:  os.File_Time,
}

@(private)
collect_workspace_files :: proc(dir: string, allocator: mem.Allocator) -> []FileFinderEntry {
    context.allocator = allocator

    raw := make([dynamic]CollectedFile)

    walker := os.walker_create_path(dir)
    defer os.walker_destroy(&walker)

    for {
        fi, err, ok := os.walker_walk(&walker)
        if !ok { break }
        if err != nil { continue }

        base := filepath.base(fi.fullpath)

        if fi.is_dir {
            for skip in SKIP_DIRS {
                if base == skip {
                    os.walker_skip_dir(&walker)
                    break
                }
            }
            continue
        }

        if len(base) > 0 && base[0] == '.' { continue }

        append(&raw, CollectedFile {
            path     = strings.clone(fi.fullpath),
            mod_time = fi.modified,
        })
    }

    // Sort by mod_time descending (most recent first)
    slice.sort_by(raw[:], proc(a, b: CollectedFile) -> bool {
        return a.mod_time > b.mod_time
    })

    entries := make([]FileFinderEntry, len(raw))
    for r, i in raw {
        entries[i] = FileFinderEntry {
            path         = r.path,
            recency_rank = i,   // 0 = most recent
        }
    }

    // raw slice itself (not the strings) can be discarded
    delete(raw)
    return entries
}
```

`CollectedFile` and `raw` are a temporary intermediate — they're needed for
sorting before assigning recency ranks. The `raw` dynamic array is deleted after
the entries slice is populated; the path strings (in `entries`) remain in the
panel arena.

---

### Fuzzy scoring (adapted from command palette)

```odin
// Returns the gap-distance score for matching needle as a subsequence of
// haystack. Lower is better. Returns -1 if not all needle chars are found.
@(private)
fuzzy_score :: proc(needle, haystack: string) -> int {
    if len(needle) == 0 { return 0 }

    haystack_index := 0
    dist := -1

    for needle_char in needle {
        letter_found := false

        if haystack_index >= len(haystack) {
            dist += 1
            continue
        }

        for haystack_char, i in haystack[haystack_index:] {
            if haystack_char == needle_char {
                letter_found = true

                if haystack_index > 0 {
                    dist += i
                } else if dist < 0 {
                    dist = 0
                }

                haystack_index += i + 1
                break
            }
        }

        if !letter_found {
            // penalise but don't disqualify — matches the command palette behaviour
            dist += len(haystack) - haystack_index
            dist = max(dist, 0)
        }
    }

    return dist
}
```

---

### Filter + rank

```odin
@(private)
filter_and_rank :: proc(
    panel_state: ^FileFinderPanel,
    query:       string,
    directory:   string,
) {
    clear(&panel_state.filtered_results)

    if len(query) == 0 {
        // No query: show all in recency order (all_entries is already sorted)
        for &entry in panel_state.all_entries {
            append(&panel_state.filtered_results, &entry)
            if len(panel_state.filtered_results) >= MAX_FILE_FINDER_RESULTS { break }
        }
        return
    }

    n := len(panel_state.all_entries)

    for &entry in panel_state.all_entries {
        // Match against relative path so e.g. "panels/g" works
        rel := entry.path[len(directory):]
        score := fuzzy_score(query, rel)

        // sort_id: fuzzy score is strictly primary, recency is tiebreaker
        entry.sort_id = score * n + entry.recency_rank
        append(&panel_state.filtered_results, &entry)

        if len(panel_state.filtered_results) >= MAX_FILE_FINDER_RESULTS * 2 { break }
    }

    slice.sort_by(panel_state.filtered_results[:], proc(a, b: ^FileFinderEntry) -> bool {
        return a.sort_id < b.sort_id
    })

    if len(panel_state.filtered_results) > MAX_FILE_FINDER_RESULTS {
        panel_state.filtered_results = panel_state.filtered_results[:MAX_FILE_FINDER_RESULTS]
    }
}
```

Differences from command palette:
- Operates on a slice of **pointers** → sorting doesn't move path strings
- Scores are computed fresh each keystroke; `all_entries` order is never mutated
- `rel` strips the workspace prefix before scoring so the user never has to type
  the absolute path root

---

### Preview helper

```odin
@(private)
update_file_finder_preview :: proc(panel_state: ^FileFinderPanel, state: ^core.State) {
    if len(panel_state.filtered_results) == 0 { return }

    path := panel_state.filtered_results[panel_state.selected_result].path
    if path != panel_state.preview_file_path {
        core.reload_file_into_buffer(&panel_state.preview_buffer, path, state.directory)
        panel_state.preview_file_path = path
    }
    core.move_cursor_to_location(&panel_state.preview_buffer, 0, 0)
}
```

---

### Panel entry point

```odin
open_file_finder_panel :: proc(state: ^core.State) {
    open(state, make_file_finder_panel())
    state.mode = .Insert
    sdl2.StartTextInput()
}
```

---

### `make_file_finder_panel` VTable

**`create`**
1. `context.allocator = panel.allocator`
2. Alloc + zero `FileFinderPanel`
3. `panel_state.buffer = core.new_virtual_file_buffer()`
4. `panel_state.preview_buffer = core.new_virtual_file_buffer(panel.allocator)`
5. `panel_state.all_entries = collect_workspace_files(state.directory, panel.allocator)`
6. `panel_state.filtered_results = make([dynamic]^FileFinderEntry)` in panel arena
7. `filter_and_rank(panel_state, "", state.directory)` — populate with all files
8. If results exist, `update_file_finder_preview`
9. Register input map (J/K/Enter/Escape/I — same as grep)

**`drop`**
```odin
ts.delete_state(&panel_state.buffer.tree)
ts.delete_state(&panel_state.preview_buffer.tree)
// all_entries, filtered_results, path strings all in panel arena
```

**`buffer`** — returns `&panel_state.buffer`

**`on_buffer_input`**
```odin
query := core.buffer_to_string(&panel_state.buffer, allocator = context.temp_allocator)
// strip trailing newline (submit gesture)
if len(query) > 0 && query[len(query)-1] == '\n' {
    if len(panel_state.filtered_results) > 0 {
        path := panel_state.filtered_results[panel_state.selected_result].path
        core.open_buffer_file(state, path, 0, 0)
        close(state, panel.id)
        state.mode = .Normal
        sdl2.StopTextInput()
        core.reset_input_map(state)
    }
    return
}
filter_and_rank(panel_state, query, state.directory)
panel_state.selected_result = 0
update_file_finder_preview(panel_state, state)
```

**`render`** — two-column layout matching the grep panel:
- Left: query input box + `ui.list` over `filtered_results`, showing relative path
- Right: `render_raw_buffer(state, s, &panel_state.preview_buffer)` when results exist

**J / K** — guard with `len(filtered_results) > 0`, navigate, call `update_file_finder_preview`

**Enter** — same logic as `on_buffer_input` newline branch

---

## `src/main.odin` — Register Command

```odin
core.register_editor_command(
    &state.commands,
    "nl.spacegirl.editor.core",
    "find-file",
    "Find a file in the workspace",
    proc(state: ^core.State, _: rawptr) {
        panels.open_file_finder_panel(state)
    },
)
```

---

## `src/panels/panels.odin` — Leader Key Binding (optional)

```odin
core.register_key_action(&leader_actions, .F, proc(state: ^core.State, _: rawptr) {
    open_file_finder_panel(state)
}, "Find file")
```

---

## Memory Profile

| Event | Arena growth |
|---|---|
| Panel open | `all_entries`: O(n_files × avg_path_len). `filtered_results` backing: O(n_files × ptr_size). Two `FileBuffer`s (~33 KB each). |
| Keystroke (filter) | `clear` on `filtered_results` dynamic array, then pointer copies — zero path string allocation |
| Preview (new file) | O(len(file)) if larger than current capacity, else zero |
| Panel close | Arena freed entirely; two `ts.delete_state` calls for C-heap |

---

## Files Changed

| File | Change |
|---|---|
| `src/panels/file_finder.odin` | **New file** — entire panel implementation |
| `src/main.odin` | +4 lines — register `find-file` command |
| `src/panels/panels.odin` | +4 lines (optional) — leader key binding |
