# Odin Editor — Design Document

A modal GUI text editor written in [Odin](https://odin-lang.org/), using SDL2 for windowing and rendering.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Program Lifecycle](#2-program-lifecycle)
3. [Global State](#3-global-state)
4. [Text Buffer: Piece Table](#4-text-buffer-piece-table)
5. [Cursor, Selection, and History](#5-cursor-selection-and-history)
6. [Input and Mode System](#6-input-and-mode-system)
7. [Panel System](#7-panel-system)
8. [UI Layout Engine](#8-ui-layout-engine)
9. [Rendering Pipeline](#9-rendering-pipeline)
10. [Syntax Highlighting (Tree-sitter)](#10-syntax-highlighting-tree-sitter)
11. [Job System](#11-job-system)
12. [Command System](#12-command-system)
13. [Font Loading](#13-font-loading)
14. [Theme System](#14-theme-system)
15. [Memory Management](#15-memory-management)
16. [Utility Structures](#16-utility-structures)
17. [Data Flow: Keystroke to Pixels](#17-data-flow-keystroke-to-pixels)
18. [Platform-Specific Code](#18-platform-specific-code)
19. [Known Issues and TODOs](#19-known-issues-and-todos)

---

## 1. High-Level Architecture

The editor is organized into packages under `src/`:

```
src/
├── main.odin           # Entry point, SDL init, event loop, top-level draw
├── core/               # All editor state, text buffers, input maps, font loading
│   ├── core.odin       # State struct, modes, commands, panels, buffers
│   ├── piece_table.odin
│   ├── file_buffer.odin
│   ├── history.odin
│   ├── gfx.odin        # Font atlas generation, draw primitives
│   ├── glyph_buffer.odin
│   ├── font_darwin.odin
│   └── font_windows.odin
├── ui/
│   └── ui.odin         # Immediate-mode layout engine
├── panels/             # Concrete panel implementations
│   ├── panels.odin     # Panel helpers (open, close, navigation)
│   ├── file_buffer.odin
│   ├── command_palette.odin
│   ├── grep.odin
│   ├── font_selector.odin
│   └── debug.odin
├── tree_sitter/
│   └── ts.odin         # Tree-sitter FFI bindings and highlight extraction
├── jobs/
│   └── job.odin        # Thread pool and job queue
├── theme/
│   └── theme.odin      # Gruvbox palette
├── util/
│   └── list.odin       # StaticList generic
└── pkg/                # External packages (Rust grep library)
```

**Key dependencies:**
- **SDL2**: windowing, input events, texture rendering
- **SDL2_TTF**: font loading and glyph rasterization
- **tree-sitter**: incremental syntax parsing
- **Rust grep library**: workspace-wide search (via FFI)

---

## 2. Program Lifecycle

### Startup

```
main()
  ├── ttf.Init()
  ├── sdl2.Init()
  ├── sdl2.CreateWindow()
  ├── sdl2.CreateRenderer()
  ├── core.load_default_system_font()  →  FontAtlas
  ├── Register built-in commands (scratch, grep, open-file, select-font, quit)
  ├── Open initial FileBuffer panels from CLI args
  └── Enter main event loop
```

### Main Loop

```
for !state.should_close:
  sdl2.WaitEvent(&sdl_event)

  switch sdl_event.type:
    .KEYDOWN  →  dispatch to current input map (mode-aware)
    .TEXTINPUT  →  insert characters (Insert mode only)
    .WINDOWEVENT  →  resize, focus
    .QUIT  →  state.should_close = true

  draw(&state)
    ├── sdl2.RenderClear()
    ├── Build UI element tree via open/close_element()
    ├── ui.compute_layout()
    ├── ui.draw()  →  sdl2.RenderPresent()
    └── runtime.free_all(context.temp_allocator)
```

---

## 3. Global State

`core.State` is a single struct allocated on the stack in `main()` and threaded as a pointer through everything.

```odin
State :: struct {
    // SDL handles
    sdl_window:    ^sdl2.Window,
    sdl_renderer:  ^sdl2.Renderer,

    // Rendering
    font_atlas:          FontAtlas,
    font:                SystemFont,
    source_font_width:   int,
    source_font_height:  int,
    screen_width:        int,
    screen_height:       int,
    width_dpi_ratio:     f32,
    height_dpi_ratio:    f32,

    // Editor
    mode:             Mode,            // Normal | Insert | Visual
    should_close:     bool,
    directory:        string,
    yank_register:    Register,
    log_buffer:       FileBuffer,
    current_input_map: ^InputActions,

    // Panels and buffers
    current_panel:  Maybe(int),
    last_panel:     Maybe(int),
    panels:         util.StaticList(Panel),
    buffers:        util.StaticList(FileBuffer),

    // Commands
    commands:      EditorCommandList,
    command_args:  [dynamic]EditorCommandArgument,

    // UI
    ui: rawptr,  // ^ui.State, stored as rawptr to avoid circular import
}
```

`panels` and `buffers` are `StaticList`s — pre-allocated fixed-size arrays with slot reuse (see §16).

---

## 4. Text Buffer: Piece Table

All text storage uses a **piece table**, a data structure that avoids moving bytes on every edit.

### Structures

```odin
PieceTable :: struct {
    content: [dynamic]u8,         // All bytes ever appended (originals + inserts)
    chunks:  [dynamic]ContentIndex,  // Ordered list of slices into content
}

ContentIndex :: struct {
    start: int,
    len:   int,
}

PieceTableIndex :: struct {
    chunk_index: int,   // Which chunk
    char_index:  int,   // Offset within that chunk
}
```

`content` is append-only. `chunks` defines the logical order of content. The actual file text at any moment is the concatenation of `content[chunk.start : chunk.start+chunk.len]` for each chunk in `chunks`.

### Key Operations

| Operation | Mechanism |
|-----------|-----------|
| **Insert** | Append bytes to `content`; inject a new `ContentIndex` at the right position in `chunks` (splitting an existing chunk if inserting mid-chunk) |
| **Delete** | Split chunks at start/end of deletion range; remove the chunks between them |
| **Save** | Iterate all chunks, write their slices to disk |
| **Iterate** | Walk `chunks` sequentially using a `PieceTableIndex` as cursor |

Splitting is the core primitive: given a `PieceTableIndex`, split the chunk at that position into two chunks and return both halves. Insert and delete build on this.

### FileBuffer

`FileBuffer` wraps a piece table with higher-level editor concepts:

```odin
FileBuffer :: struct {
    allocator:  mem.Allocator,
    directory:  string,
    file_path:  string,
    extension:  string,

    flags:      BufferFlagSet,   // e.g., UnsavedChanges
    last_col:   int,             // Remembered column for vertical movement
    top_line:   int,             // Scroll offset (first visible line)
    selection:  Maybe(Selection),

    tree:     ts.State,          // Tree-sitter parse state
    history:  FileHistory,
    glyphs:   GlyphBuffer,
}
```

---

## 5. Cursor, Selection, and History

### Cursor

```odin
Cursor :: struct {
    col:   int,
    line:  int,
    index: PieceTableIndex,
}
```

A cursor has both a **logical** position (line/col for display) and a **physical** position (piece table index for O(1) insert/delete at the cursor). These are always kept in sync.

`last_col` on `FileBuffer` stores the column the cursor was at before a vertical move, allowing the cursor to "snap back" to the correct column when moving over shorter lines — the same behavior as vim.

### Selection

```odin
Selection :: struct {
    start: Cursor,
    end:   Cursor,
}
```

Selections can be inverted (end before start); `swap_selections()` normalizes direction before operations.

### History (Undo/Redo)

```odin
FileHistory :: struct {
    piece_table: PieceTable,       // Live piece table
    cursor:      Cursor,
    snapshots:   []Snapshot,       // Circular buffer
    next:        int,              // Next write index
    first:       int,              // Oldest entry index
}

Snapshot :: struct {
    chunks: [dynamic]ContentIndex,
    cursor: Cursor,
}
```

The history stores full **chunk array snapshots** (not diffs). `content` is not snapshotted — it is append-only, so all historical chunk references remain valid.

| Operation | Mechanism |
|-----------|-----------|
| **Push** | Clone `chunks`, save cursor → write to `snapshots[next]`, advance `next` |
| **Undo** | Restore `chunks` and cursor from `snapshots[prev]` |
| **Redo** | Restore `chunks` and cursor from `snapshots[next]` |

When the circular buffer fills, the oldest snapshot is overwritten.

---

## 6. Input and Mode System

### Modes

```odin
Mode :: enum { Normal, Insert, Visual }
```

The editor is always in exactly one mode. Modes determine which input map is consulted for keystrokes and whether `SDL_TEXTINPUT` events are processed.

### Input Map Structure

```odin
InputMap :: struct {
    mode: map[Mode]InputActions,
}

InputActions :: struct {
    key_actions:        map[Key]Action,
    ctrl_key_actions:   map[Key]Action,
    shift_key_actions:  map[Key]Action,
    show_help:          bool,
}

Action :: struct {
    action:      InputGroup,
    description: string,
}

InputGroup :: union {
    EditorAction,   // proc(state: ^State, user_data: rawptr)
    InputActions,   // Nested map for multi-key sequences
}
```

Each panel has its own `InputMap`. When a key is pressed:

1. Look up the key in the current panel's `InputActions` for the current mode (plain, ctrl, or shift).
2. If the action is an `EditorAction`, call it immediately.
3. If the action is an `InputActions` (sub-map), set `state.current_input_map` to that sub-map — the next key will be looked up there. This is how vim-style leader key sequences work (e.g., `space` → `r` for grep).

Multi-key sequences show a help overlay via `show_help = true` on the sub-map.

---

## 7. Panel System

Panels are the primary extensibility and layout mechanism. Every visible region is a panel.

### Panel Structure

```odin
Panel :: struct {
    using vtable:   Panel_VTable,
    arena:          mem.Arena,      // 64 MB backing arena
    allocator:      mem.Allocator,

    id:             int,
    state:          PanelState,     // rawptr to panel-specific data
    input_map:      InputMap,
    is_floating:    bool,
    is_file_buffer: bool,
}

Panel_VTable :: struct {
    create:          proc(panel: ^Panel, state: ^State, data: rawptr),
    drop:            proc(panel: ^Panel, state: ^State),
    on_buffer_input: proc(panel: ^Panel, state: ^State),
    buffer:          proc(panel: ^Panel, state: ^State) -> (^FileBuffer, bool),
    render:          proc(panel: ^Panel, state: ^State) -> bool,
    name:            proc(panel: ^Panel) -> string,
    _set_buffer:     proc(panel: ^Panel, buffer_id: int),
}
```

`using vtable` means vtable fields are promoted to the top level of `Panel`, so you call `panel.render(panel, state)` directly.

### Panel Lifecycle

```
panels.open(state, panel_definition, data):
  ├── Allocate slot in state.panels (StaticList)
  ├── Initialize 64 MB arena
  ├── Call panel.create(panel, state, data)
  └── Set state.current_panel

panels.close(state, panel_id):
  ├── Call panel.drop(panel, state)
  ├── Free arena backing memory
  ├── Mark slot inactive
  └── Switch focus to last_panel or first active panel
```

### Floating vs. Tiled Panels

- **Tiled panels** (`is_floating = false`): laid out side by side in the main area. The UI engine distributes screen width evenly.
- **Floating panels** (`is_floating = true`): rendered on top of everything, centered over the full screen. Used for command palette, font selector, help overlay.

### Concrete Panels

#### File Buffer Panel
The main editor view. Holds a `buffer_id` pointing to a `FileBuffer` in `state.buffers`.

Implements:
- Normal/Insert/Visual mode bindings (hjkl, wbe, i/a, v, u, /, d, y, p, ctrl+s, ctrl+u/d, ctrl+±)
- In-buffer search (populates `query_results`, navigates between matches)
- `space` leader key for workspace actions

#### Command Palette
Floating panel. Searches `state.commands` as the user types. Displays command group, name, and description. Pressing Enter executes the selected command.

#### Grep Panel
Floating panel. Runs workspace grep on a background job thread. Results are rendered with file path, line number, and content context. Pressing Enter opens the result's file at the matching line.

#### Font Selector
Floating panel. Calls `core.load_system_font_list()` at creation to enumerate monospace fonts, then calls `core.load_font()` when the user confirms a selection.

#### Debug Panel
Floating panel. Displays internal state for debugging.

---

## 8. UI Layout Engine

The UI engine (`ui/ui.odin`) is an **immediate-mode, retained-layout** system. Code builds a tree of elements each frame; the engine computes layout and renders it.

### Element Structure

```odin
UI_Element :: struct {
    first, last:  Maybe(int),    // First/last child index
    next, prev:   Maybe(int),    // Sibling indices
    parent:       Maybe(int),

    kind:    UI_Element_Kind,    // Text | Image | Custom(proc)
    layout:  UI_Layout,
    style:   UI_Style,
}

UI_Layout :: struct {
    dir:      UI_Direction,      // LeftToRight | RightToLeft | TopToBottom | BottomToTop
    kind:     [2]UI_Size_Kind,   // Size mode for [x, y]
    size:     [2]int,            // Computed size
    pos:      [2]int,            // Computed position
    floating: bool,
}

UI_Size_Kind :: union {
    Exact,   // Fixed: Exact(n)
    Fit,     // Shrink-wrap children
    Grow,    // Expand to fill available space
}
```

### Layout Algorithm

Each frame:

1. **Build phase** (`open_element` / `close_element`):
   Panels call `open_element(s, content, layout)` and `close_element(s)` to describe their subtree. Elements are stored in a flat array; parent/child/sibling relationships are indices into that array.

2. **Size computation** (bottom-up, inside `close_element`):
   - `Exact(n)` → size = n
   - `Fit` → size = sum of children sizes along the layout direction
   - `Grow` → size deferred; marked for the growth pass

3. **Growth distribution** (`grow_children`, top-down):
   For each container, sum the sizes of non-growing children, subtract from parent size, divide remainder evenly among `Grow` children.

4. **Position computation** (`compute_layout`):
   Walk the tree top-down. Each element's position is derived from its parent's position and the accumulated sizes of preceding siblings, according to the parent's direction.

5. **Render** (`draw`):
   Walk the tree. For each element: draw background, draw border edges from the `UI_Border_Set`, draw content (text / texture blit / custom proc).

### Helper Procs

The engine provides convenience wrappers used by panel code:

```odin
ui.spacer(s, size)                // Fixed-size empty element
ui.left_to_right(s)               // Open LeftToRight container (Fit sizing)
ui.top_to_bottom(s)               // Open TopToBottom container (Fit sizing)
ui.growing_left_to_right(s)       // Same with Grow sizing
ui.centered(s)                    // Center children horizontally + vertically
ui.list(T, s, items, ...)         // Scrollable list with selection highlighting
```

---

## 9. Rendering Pipeline

### Font Atlas

At startup (and whenever the font changes), a `FontAtlas` is generated:

```odin
FontAtlas :: struct {
    texture:     ^sdl2.Texture,
    font:        ^ttf.Font,
    max_width:   int,
    max_height:  int,
}
```

The atlas is a **single-row SDL2 texture** containing every printable ASCII character (` ` through `~`) rasterized at 2× scale. Each character occupies a fixed-width cell `max_width` pixels wide.

**Generation** (`gen_font_atlas`):
1. Load TTF font at `source_font_height × 2` pt.
2. Measure all glyphs; compute `max_width` and `max_height`.
3. Create an RGBA surface of size `max_width × num_chars` by `max_height`.
4. Render each glyph with `ttf.RenderGlyph32_Blended` and blit into the atlas surface with blend mode `NONE` (important: prevents incorrect alpha compositing).
5. Upload to GPU texture.

**Drawing a character** (`draw_codepoint`):
- Source rect: `x = (codepoint - ' ') * max_width`, full height
- Dest rect: screen position, scaled down by 2
- `sdl2.SetTextureColorMod` applies the glyph's theme color

### Glyph Buffer

Between the piece table and the renderer sits a `GlyphBuffer`:

```odin
GlyphBuffer :: struct {
    buffer: []Glyph,   // width × height cells (max 256×256)
    width:  int,
    height: int,
}

Glyph :: struct {
    codepoint: u8,
    color:     theme.PaletteColor,
}
```

Each frame, `update_glyph_buffer_from_file_buffer` rebuilds the glyph grid:
1. Iterate the piece table starting at `buffer.top_line`, filling the 2D grid.
2. Apply tree-sitter highlights: for each `Highlight{start, end, color}`, paint the covered cells.
3. Overlay cursor and selection coloring.

The glyph buffer is then walked and each cell is drawn via `draw_codepoint`.

### Draw Order

```
draw(state):
  sdl2.RenderClear()

  open_element(root, Grow×Grow)           // Full screen
    for each tiled panel:
      open_element(Grow×Grow)
        panel.render()                    // Builds panel's sub-tree
      close_element()

  for each floating panel:
    open_element(Grow×Grow, floating=true)
      panel.render()
    close_element()
  close_element()

  ui.compute_layout()
  ui.draw()

  sdl2.RenderPresent()
```

---

## 10. Syntax Highlighting (Tree-sitter)

### Binding Layer

`tree_sitter/ts.odin` provides Odin bindings to the tree-sitter C library via `foreign`. Key types: `Parser`, `Tree`, `TreeCursor`, `Node`, `Query`, `QueryCursor`, `Point`.

Tree-sitter memory allocation is routed through Odin's allocator via custom `malloc`/`free`/`realloc`/`calloc` callbacks set with `ts_set_allocator`.

### State

```odin
ts.State :: struct {
    parser:         Parser,
    language:       Language,
    language_type:  LanguageType,   // None | Json | Odin | Rust
    tree:           Tree,
    cursor:         TreeCursor,
    highlights:     [dynamic]Highlight,
}

Highlight :: struct {
    start: Point,   // {row, col}
    end:   Point,
    color: theme.PaletteColor,
}
```

### Parsing Flow

When a file is opened or modified:

1. **Input callback**: tree-sitter calls `tree_sitter_file_buffer_input()` to read bytes. The callback iterates the piece table from the requested position, returning a pointer into the current chunk.
2. **Parse**: `ts_parser_parse()` builds or incrementally updates the syntax tree.
3. **Query**: A language-specific highlight query is run with `ts_query_cursor_exec()`. Each capture is mapped to a `theme.PaletteColor` and appended to `ts.State.highlights`.

### Highlight Application

In `update_glyph_buffer_from_file_buffer`, after filling the glyph grid from the piece table, highlights are applied:

```
for each highlight in buffer.tree.highlights:
    for each glyph in [highlight.start .. highlight.end]:
        glyph.color = highlight.color
```

---

## 11. Job System

Long-running work (grep, future: parsing large files) runs on background threads to avoid blocking the event loop.

### Structures

```odin
JobQueue :: struct {
    threads:           []^thread.Thread,
    job_data:          []Job,
    task_queue:        ring.Queue,
    available_threads: sync.Sema,
    queue_mutex:       sync.Mutex,
    is_running:        bool,
}

Job :: struct {
    queue:         ^JobQueue,
    input:         rawptr,
    output:        rawptr,
    arena:         mem.Arena,
    allocator:     mem.Allocator,
    handler:       proc(job: ^Job),
    finished:      bool,
    finished_sema: sync.Sema,
    mutex:         sync.Mutex,
}
```

### Lifecycle

```
jobs.create_queue(num_threads):
  Spawn N worker threads. Each thread loops:
    acquire available_threads semaphore
    pop Job from task_queue
    call job.handler(job)
    job.finished = true
    release finished_sema

jobs.add(queue, handler, input):
  Allocate Job slot
  Set job.input, job.handler
  Push to task_queue
  Release available_threads semaphore

Main thread each frame:
  job, ok := jobs.pop(&queue)
  if ok:
    consume job.output
    jobs.destroy_job(&queue, job)  // frees arena, marks slot reusable
```

Jobs communicate through `input`/`output` rawptrs. The job's arena allocator provides scratch memory that is freed on `destroy_job`. The ring buffer queue serializes job pointers between producer and consumer.

---

## 12. Command System

Commands are named, group-namespaced actions optionally taking typed arguments. They are the bridge between the command palette UI and editor functionality.

### Registration

```odin
register_editor_command(
    commands:    ^EditorCommandList,
    group:       string,            // e.g., "nl.spacegirl.editor.core"
    name:        string,            // e.g., "open-file"
    description: string,
    arg_type:    typeid,            // Optional struct type describing args
    action:      EditorAction,
)

EditorCommandList :: map[string][dynamic]EditorCommand
```

### Built-in Commands

| Group | Name | Action |
|-------|------|--------|
| `nl.spacegirl.editor.core` | `scratch` | Open new empty buffer |
| `nl.spacegirl.editor.core` | `grep` | Open grep panel |
| `nl.spacegirl.editor.core` | `open-file` | Open file by path |
| `nl.spacegirl.editor.core` | `select-font` | Open font selector |
| `nl.spacegirl.editor.core` | `quit` | Exit editor |

### Argument System

Commands can declare a struct type for arguments. The command palette collects argument values one at a time, storing them as `EditorCommandArgument` (a union of `FilePathArg | NumberArg`). On execution, `attempt_read_command_args(T, args)` uses reflection to map the argument list to the command's struct type.

---

## 13. Font Loading

Font loading is platform-specific. Both platforms implement the same API:

```odin
SystemFont :: struct {
    display_name: string,
    file_path:    string,
    // Windows only: font_w: win.LOGFONTW
}

load_default_system_font(state: ^State, font_height: int) -> FontAtlas
load_font(state: ^State, system_font: SystemFont) -> FontAtlas
load_system_font_list(state: ^State, allocator) -> []SystemFont
```

`load_default_system_font` is called once at startup. `load_font` is called when the user selects a font from the font selector or changes font size. `load_system_font_list` is called by the font selector panel to populate the list.

The cross-platform `gfx.odin` provides `load_front_from_file(state, path) -> FontAtlas` which the darwin implementation delegates to. The Windows implementation loads font data from GDI32 directly into memory and feeds it to SDL_TTF via `SDL_RWFromMem`.

---

## 14. Theme System

All colors are expressed as `theme.PaletteColor` enum values. The palette is the Gruvbox dark theme:

```
Background, Background1–4
Foreground, Foreground1–4
Red, Green, Yellow, Blue, Purple, Aqua, Gray
BrightRed, BrightGreen, BrightYellow, BrightBlue, BrightPurple, BrightAqua, BrightGray
```

`theme.get_palette_color(color) -> sdl2.Color` resolves the enum to an RGBA value. A light palette variant exists but is not currently wired to a toggle.

---

## 15. Memory Management

### Strategy

| Scope | Allocator | Freed when |
|-------|-----------|------------|
| Global (SDL handles, State fields) | Default heap | Program exit |
| Per-panel | 64 MB arena | Panel closed |
| Per-frame temporaries | `context.temp_allocator` | End of each frame (`free_all`) |
| Per-command-invocation | Command arena | After command executes |
| Per-job | Job arena | `destroy_job` |
| Tree-sitter internals | Custom callbacks → Odin allocator | Tree freed |

### Panel Arena Pattern

```odin
arena_bytes, _ := make([]u8, 1024*1024*64)
mem.arena_init(&panel.arena, arena_bytes)
panel.allocator = mem.arena_allocator(&panel.arena)
context.allocator = panel.allocator  // set at top of panel procs
// ...
// On close:
mem.free(raw_data(panel.arena.data))
```

The arena is set as `context.allocator` at the top of each panel procedure, so any allocation within panel code goes into the panel's arena and is freed atomically when the panel is closed.

### Temp Allocator

`context.temp_allocator` (Odin's built-in scratch allocator) is used for all within-frame transient data — string building, format output, intermediate query results. It is reset at the end of every frame with `runtime.free_all(context.temp_allocator)`.

---

## 16. Utility Structures

### StaticList

```odin
StaticList(T) :: struct {
    data: []StaticListSlot(T),
}

StaticListSlot(T) :: struct {
    active: bool,
    data:   T,
}
```

A fixed-capacity array with O(1) lookup by index, stable indices, and slot reuse. `append()` finds the first inactive slot. `delete()` marks a slot inactive. Used for `state.panels` and `state.buffers`.

Slots are never compacted, so indices remain valid for the lifetime of the list. This is important because panels and buffers are referred to by integer ID throughout the code.

### Ring Buffer

`util/ring_buffer/` provides a simple circular queue used by the job system to serialize job pointers between producer (main thread) and consumer (worker threads). Supports push/pop with wrapping.

---

## 17. Data Flow: Keystroke to Pixels

```
SDL_KEYDOWN event
  │
  ▼
main.odin: dispatch to state.current_input_map
  │
  ├─ Action is EditorAction → call proc(state, panel)
  │     e.g., "move cursor right":
  │       core.move_cursor_right(buffer)
  │         ├─ iterate_piece_table_iter()  →  advances PieceTableIndex
  │         └─ update cursor.col, cursor.line
  │
  └─ Action is InputActions → update current_input_map, show help overlay

SDL_TEXTINPUT event (Insert mode only)
  │
  ▼
core.insert_content(buffer, bytes)
  ├─ append bytes to piece_table.content
  ├─ inject new ContentIndex into piece_table.chunks
  ├─ advance cursor
  ├─ set UnsavedChanges flag
  ├─ ts.parse_buffer()     →  rebuild syntax tree
  └─ panel.on_buffer_input()  →  re-run search if searching

──────── end of event handling ────────

draw(state)
  │
  ├─ Build UI tree:
  │   panel.render(panel, state)
  │     └─ draw_file_buffer(state, buffer, rect)
  │           ├─ update_glyph_buffer_from_file_buffer(buffer, w, h)
  │           │    ├─ iterate piece table → fill glyph grid
  │           │    └─ apply ts.highlights → set glyph.color
  │           └─ for each glyph:
  │                draw_codepoint(state, glyph.codepoint, x, y, glyph.color)
  │                  ├─ compute source rect in font atlas
  │                  ├─ sdl2.SetTextureColorMod(atlas.texture, r, g, b)
  │                  └─ sdl2.RenderCopy()
  │
  ├─ ui.compute_layout()
  ├─ ui.draw()            →  backgrounds, borders, text elements
  └─ sdl2.RenderPresent()
```

---

## 18. Platform-Specific Code

Odin's file-name OS suffixes (`_darwin.odin`, `_windows.odin`) control compilation:

| File | Platform | Mechanism |
|------|----------|-----------|
| `core/font_darwin.odin` | macOS | CoreText framework (`CTFont*`), `NSFontManager` via ObjC bindings; font file paths extracted from `CFURL`. |
| `core/font_windows.odin` | Windows | GDI32 `EnumFontFamiliesExW` to enumerate fonts; `GetFontData` to read raw font bytes from device context; SDL_TTF loaded from memory via `SDL_RWFromMem`. |

Tree-sitter grammars are linked differently per platform:
- **macOS/Linux**: system shared libraries (`-ltree-sitter`, `-ltree-sitter-odin`, etc.)
- **Windows**: precompiled static `.lib` files in `bin/`

DPI scaling: at startup the logical window size is compared to the renderer output size; `width_dpi_ratio` and `height_dpi_ratio` are used to scale font sizes and layout coordinates on HiDPI displays.

---

## 19. Known Issues and TODOs

Items collected from source comments and `todo.md`:

| Area | Issue |
|------|-------|
| Piece table | Bounds checking on `get_character_at_piece_table_index` can go out of bounds |
| Command args | `run_command_by_name` passes `nil` instead of parsed args to the action proc |
| Font lifetime | `SystemFont.file_path` strings are not guaranteed to outlive the font list allocation (marked `// FIXME` in `gfx.odin` and `font_windows.odin`) |
| Glyph width | Editor assumes monospace; glyph width is not measured per-character |
| Undo capacity | Limited to `len(snapshots)` steps; oldest steps are silently dropped |
| Yank register | Single register only |
| Linux fonts | No `font_linux.odin`; Linux font enumeration not implemented |
| macOS font selector | Broken after Windows refactor; re-synced by commit `36f68a7` |
| Search | In-buffer search is linear; no index |
| Panel splitting | UI supports side-by-side panels but split is manual (`space v`); no automated tiling |
