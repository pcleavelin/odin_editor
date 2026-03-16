# Plan: Grep Preview — Proper File Context

## Problem

The grep panel's right-side preview pane shows only the single matching line. It does this by storing the matching line's raw bytes in `GrepQueryResult.file_context` and rendering them into a flat `GlyphBuffer`. This has three issues:

1. **One line of context.** The preview pane has plenty of vertical space but only ever shows one line — the matched line itself.
2. **No syntax highlighting.** The glyph buffer is populated from raw bytes without running tree-sitter.
3. **Wasted storage.** `file_context` is cloned per-match from the Rust side (`value.buffer().to_vec()`), but is **never shown in the result list** — only `line:col: relative/path` is displayed there.

## Constraint: Arena Allocator

`GrepPanel` lives inside the panel's 64 MB arena allocator. Arena allocators do not support freeing individual allocations — `delete` is a no-op and memory is only reclaimed when the entire arena is freed (i.e., when the panel is closed).

This rules out any approach that allocates a new `FileBuffer` per navigation (the old buffer's data would accumulate in the arena until it fills up), or that calls `free_file_buffer` / `free_history` to "destroy" a buffer before creating a new one.

## Solution

Add a new proc `reload_file_into_buffer` that **updates an existing `FileBuffer` in-place** without deallocating anything. The `FileBuffer` is allocated once in `create` and kept for the panel's lifetime; on each navigation event its dynamic arrays are cleared and refilled with new file data.

### Why this works

- **`PieceTable.content` and `.chunks`** are `[dynamic]` arrays. `clear()` zeroes the length without touching the backing allocation. Appending new data reuses the existing capacity. No deallocation, no arena growth beyond the initial allocation (unless the new file is larger than any previous one).
- **`FileHistory.snapshots`** is a pre-allocated `[]Snapshot` slice. Since the preview buffer is never edited (no undo needed), we skip `push_new_snapshot` entirely. We just reset the `next`, `first`, and `cursor` fields to zero — no allocation or deallocation.
- **Tree-sitter state** is C-heap allocated. The tree-sitter allocator callbacks use `runtime.default_context()`, so tree-sitter's memory goes to the global heap, not the panel arena. It is safe to call `ts.delete_state` + `ts.make_state` when the file language changes, even from within an arena context.
- **String metadata** (`file_path`, `directory`, `extension`) — new strings are cloned into `buffer.allocator` (the panel arena). Old strings remain in the arena but are no longer referenced. This leaks a few bytes of strings per navigation — entirely acceptable.

---

## Changes

### 1. `src/core/file_buffer.odin` — `FileBufferSource` abstraction

#### The problem with the current structure

`make_file_buffer` and the proposed `reload_file_into_buffer` share identical logic for: resolving path metadata, determining language type, and reading bytes from disk. Duplicating that would make the two procs hard to keep in sync and impossible to test without real files.

#### Solution: `FileBufferSource`

Introduce a small struct that represents resolved file data — a seam between "loading from disk" and "applying to a buffer":

```odin
FileBufferSource :: struct {
    content:   []u8,            // raw file bytes; caller owns and must delete
    full_path: string,
    directory: string,
    extension: string,
    language:  ts.LanguageType,
}
```

Three procs build on this:

**`load_file_buffer_source`** — disk I/O only; produces a `FileBufferSource`:
```odin
load_file_buffer_source :: proc(file_path: string, base_dir: string = "") -> (FileBufferSource, Error) {
    fd, err := os.open(file_path)
    if err != nil { return {}, make_error(.FileIOError, ...) }
    defer os.close(fd)

    fi, fstat_err := os.fstat(fd)
    if fstat_err != nil { return {}, make_error(.FileIOError, ...) }

    extension := filepath.ext(fi.fullpath)
    dir       := base_dir if base_dir != "" else filepath.dir(fi.fullpath)

    language: ts.LanguageType = .None
    if extension == ".odin" { language = .Odin }
    else if extension == ".rs"   { language = .Rust }
    else if extension == ".json" { language = .Json }

    content, ok := os.read_entire_file_from_handle(fd)
    if !ok { return {}, make_error(.FileIOError, ...) }

    return FileBufferSource{
        content   = content,
        full_path = fi.fullpath,
        directory = dir,
        extension = extension,
        language  = language,
    }, error()
}
```

**`init_file_buffer_from_source`** — creates a brand-new `FileBuffer`; replaces the body of `make_file_buffer`:
```odin
init_file_buffer_from_source :: proc(allocator: mem.Allocator, source: FileBufferSource) -> FileBuffer {
    context.allocator = allocator

    buffer := FileBuffer {
        allocator = allocator,
        file_path = strings.clone(source.full_path, allocator),
        directory = strings.clone(source.directory, allocator),
        extension = source.extension,
        tree      = ts.make_state(source.language),
        history   = make_history(source.content),
        glyphs    = make_glyph_buffer(256, 256),
    }

    push_new_snapshot(&buffer.history)
    ts.parse_buffer(&buffer.tree, tree_sitter_file_buffer_input(&buffer))

    return buffer
}
```

**`apply_source_to_file_buffer`** — updates an existing `FileBuffer` in-place; no deallocations:
```odin
apply_source_to_file_buffer :: proc(buffer: ^FileBuffer, source: FileBufferSource) {
    context.allocator = buffer.allocator

    // 1. Refill the piece table in-place (clear reuses backing memory)
    t := &buffer.history.piece_table
    clear(&t.content)
    append(&t.content, ..source.content)
    clear(&t.chunks)
    append(&t.chunks, ContentIndex{ start = 0, len = len(t.content) })

    // 2. Reset history scalars (no undo needed for preview)
    buffer.history.cursor = Cursor{}
    buffer.history.next   = 0
    buffer.history.first  = 0

    // 3. Reset display state
    buffer.top_line  = 0
    buffer.last_col  = 0
    buffer.selection = nil
    buffer.flags     = {}

    // 4. Update string metadata (old strings stay in arena — acceptable)
    buffer.file_path  = strings.clone(source.full_path, buffer.allocator)
    buffer.directory  = strings.clone(source.directory, buffer.allocator)
    buffer.extension  = source.extension

    // 5. Update tree-sitter (C-heap — safe to delete/recreate inside arena)
    if source.language != buffer.tree.language_type {
        ts.delete_state(&buffer.tree)
        buffer.tree = ts.make_state(source.language)
    }
    ts.parse_buffer(&buffer.tree, tree_sitter_file_buffer_input(buffer))
}
```

#### Refactored public procs

`make_file_buffer` and `reload_file_into_buffer` become thin wrappers:

```odin
make_file_buffer :: proc(allocator: mem.Allocator, file_path: string, base_dir: string = "") -> (FileBuffer, Error) {
    source, err := load_file_buffer_source(file_path, base_dir)
    if err.type != .None { return FileBuffer{}, err }
    defer delete(source.content)

    return init_file_buffer_from_source(allocator, source), error()
}

reload_file_into_buffer :: proc(buffer: ^FileBuffer, file_path: string, base_dir: string = "") -> Error {
    source, err := load_file_buffer_source(file_path, base_dir)
    if err.type != .None { return err }
    defer delete(source.content)

    apply_source_to_file_buffer(buffer, source)
    return error()
}
```

#### Testing seam

Tests construct a `FileBufferSource` directly — no filesystem, no temp files:

```odin
source := core.FileBufferSource{
    content   = []u8("package main\n\nmain :: proc() {}\n"),
    full_path = "/fake/main.odin",
    directory = "/fake",
    extension = ".odin",
    language  = .Odin,
}

// Test make path
buffer := core.init_file_buffer_from_source(context.allocator, source)
// assert cursor at start, piece table content matches, tree parsed, etc.

// Test reload path
core.apply_source_to_file_buffer(&buffer, other_source)
// assert old content gone, new content present, cursor reset, etc.
```

No mocking, no proc pointers, no vtables — just a plain data struct as the boundary.

---

### 2. `src/panels/grep.odin`

#### `GrepPanel` struct

Replace:
```odin
glyphs: core.GlyphBuffer,
```
With:
```odin
preview_buffer:    core.FileBuffer,
preview_file_path: string,
```

#### New helper: `update_preview_to_result`

```odin
update_preview_to_result :: proc(panel_state: ^GrepPanel, state: ^core.State, result: ^GrepQueryResult) {
    if result.file_path != panel_state.preview_file_path {
        core.reload_file_into_buffer(&panel_state.preview_buffer, result.file_path, state.directory)
        panel_state.preview_file_path = result.file_path
    }
    core.move_cursor_to_location(&panel_state.preview_buffer, result.line, result.col)
}
```

Only calls `reload_file_into_buffer` when the file path changes. Navigating between results from the same file only updates the cursor position.

#### `create` proc

Replace:
```odin
panel_state.glyphs = core.make_glyph_buffer(256, 256)
```
With:
```odin
panel_state.preview_buffer = core.new_virtual_file_buffer(allocator = panel.allocator)
```

`new_virtual_file_buffer` already allocates the piece table dynamic arrays and glyph buffer — exactly the in-place update target.

#### `drop` proc

Replace any glyph buffer cleanup with:
```odin
ts.delete_state(&panel_state.preview_buffer.tree)
```
This frees the C-heap tree-sitter allocations. The dynamic arrays (`content`, `chunks`, glyph buffer) and snapshot slice are in the arena and are freed when the arena is freed.

#### J / K key actions

Replace both `core.update_glyph_buffer_from_bytes(...)` calls with:
```odin
update_preview_to_result(panel_state, state, &panel_state.query_results[panel_state.selected_result])
```

#### `pop_job_results`

Replace:
```odin
core.update_glyph_buffer_from_bytes(
    &panel_state.glyphs,
    transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
    panel_state.query_results[panel_state.selected_result].line,
)
```
With:
```odin
update_preview_to_result(panel_state, state, &panel_state.query_results[0])
```

#### `render` proc

Replace:
```odin
core.update_glyph_buffer_from_bytes(
    &panel_state.glyphs,
    transmute([]u8)selected_result.file_context,
    selected_result.line,
)
render_glyph_buffer(state, s, &panel_state.glyphs)
```
With:
```odin
render_raw_buffer(state, s, &panel_state.preview_buffer)
```

`update_preview_to_result` is called from J/K/pop only — not on every render frame.

---

### 3. Rust / `GrepQueryResult` cleanup (independent, can be done separately)

`file_context` / `Match.text` is unused in the result list and becomes unused in the preview too. It can be removed to eliminate per-result allocations on both sides of the FFI:

- **`src/pkg/grep_lib/src/lib.rs`**: Remove `text: Vec<u8>` from `Match`; remove `text_len`/`text` from `GrepResult`; update `From<Match> for GrepResult`, `From<GrepResult> for Match`, and `free_grep_results`.
- **`src/panels/grep.odin`**: Remove `text_len`/`text` from `RS_GrepResult`; remove `file_context` from `GrepQueryResult`; remove the `strings.clone_from_ptr` call for text in `rs_grep_as_results`.

This is a straight mechanical cleanup once the preview buffer is working.

---

## What Does Not Change

- `render_raw_buffer` — already renders a `FileBuffer`; no changes needed.
- `render_glyph_buffer` — can be removed once unused; or kept if it has other callers.
- `make_file_buffer` — used for the search input buffer (`panel_state.buffer`) and for opening files in editor panels; unchanged.
- The job queue, query flow, result list rendering — all unchanged.

---

## Memory Behaviour Summary

| Event | Arena growth |
|---|---|
| Panel open (`create`) | One `FileBuffer` worth: ~2 MB piece table, ~256×256 glyph buffer, 1024-slot snapshot slice |
| Navigate to result (same file) | Zero — only cursor moved |
| Navigate to result (different file) | Small: O(len(file_path)) string clones, plus O(len(file)) if file is larger than current capacity |
| Tree-sitter language change | Zero arena impact — C-heap only |
| Panel close (`drop`) | Arena freed entirely; `ts.delete_state` frees C-heap |
