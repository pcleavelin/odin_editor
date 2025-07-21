package tree_sitter

import "base:runtime"
import "core:strings"
import "core:fmt"
import "core:log"
import "core:os"
import "core:mem"

import "../theme"

foreign import ts "../../bin/libtree-sitter.a"
@(default_calling_convention = "c", link_prefix="ts_")
foreign ts {
    parser_new :: proc() -> Parser ---
    parser_delete :: proc(parser: Parser) -> Parser ---

    parser_set_language :: proc(parser: Parser, language: Language) -> bool ---
    parser_set_logger :: proc(parser: Parser, logger: TSLogger) ---
    parser_print_dot_graphs :: proc(parser: Parser, fd: int) ---

    parser_parse :: proc(parser: Parser, old_tree: Tree, input: Input) -> Tree ---
    parser_parse_string :: proc(parser: Parser, old_tree: Tree, source: []u8, len: u32) -> Tree ---

    tree_root_node :: proc(tree: Tree) -> Node ---
    tree_delete :: proc(tree: Tree) ---

    tree_cursor_new :: proc(node: Node) -> TreeCursor ---
    tree_cursor_reset :: proc(tree: ^TreeCursor, node: Node) ---
    tree_cursor_delete :: proc(tree: ^TreeCursor) ---
    tree_cursor_current_node :: proc(tree: ^TreeCursor) -> Node ---
    tree_cursor_current_field_name :: proc(tree: ^TreeCursor) -> cstring ---

    tree_cursor_goto_first_child :: proc(self: ^TreeCursor) -> bool ---
    tree_cursor_goto_first_child_for_point :: proc(self: ^TreeCursor, goal_point: Point) -> u64 ---

    node_start_point :: proc(self: Node) -> Point ---
    node_end_point :: proc(self: Node) -> Point ---
    node_type :: proc(self: Node) -> cstring ---
    node_named_child :: proc(self: Node, child_index: u32) -> Node ---
    node_child_count :: proc(self: Node) -> u32 ---
    node_is_null :: proc(self: Node) -> bool ---
    node_string :: proc(self: Node) -> cstring ---

    query_new :: proc(language: Language, source: []u8, source_len: u32, error_offset: ^u32, error_type: ^QueryError) -> Query ---
    query_delete :: proc(query: Query) ---
    query_cursor_new :: proc() -> QueryCursor ---
    query_cursor_exec :: proc(cursor: QueryCursor, query: Query, node: Node) ---
    query_cursor_next_match :: proc(cursor: QueryCursor, match: ^QueryMatch) -> bool ---

    query_capture_name_for_id :: proc(query: Query, index: u32, length: ^u32) -> ^u8 ---

    @(link_name = "ts_set_allocator")
    ts_set_allocator :: proc(new_malloc: MallocProc, new_calloc: CAllocProc, new_realloc: ReAllocProc, new_free: FreeProc) ---
}

TS_ALLOCATOR: mem.Allocator

MallocProc :: proc "c" (size: uint) -> rawptr
CAllocProc :: proc "c" (num: uint, size: uint) -> rawptr
ReAllocProc :: proc "c" (ptr: rawptr, size: uint) -> rawptr
FreeProc :: proc "c" (ptr: rawptr)

set_allocator :: proc(allocator := context.allocator) {
    TS_ALLOCATOR = allocator

    new_malloc :: proc "c" (size: uint) -> rawptr {
        context = runtime.default_context() 

        data, _ := TS_ALLOCATOR.procedure(TS_ALLOCATOR.data, .Alloc, int(size), runtime.DEFAULT_ALIGNMENT, nil, 0)
        return raw_data(data)
    }

    new_calloc :: proc "c" (num: uint, size: uint) -> rawptr {
        context = runtime.default_context() 

        data, _ := TS_ALLOCATOR.procedure(TS_ALLOCATOR.data, .Alloc, int(num * size), runtime.DEFAULT_ALIGNMENT, nil, 0)
        return raw_data(data)
    }

    new_realloc :: proc "c" (old_ptr: rawptr, size: uint) -> rawptr {
        context = runtime.default_context() 

        data, _ := TS_ALLOCATOR.procedure(TS_ALLOCATOR.data, .Resize, int(size), runtime.DEFAULT_ALIGNMENT, old_ptr, 0)
        return raw_data(data)
    }

    new_free :: proc "c" (ptr: rawptr) {
        context = runtime.default_context() 

        TS_ALLOCATOR.procedure(TS_ALLOCATOR.data, .Free, 0, runtime.DEFAULT_ALIGNMENT, ptr, 0)
    }
}

foreign import ts_odin "../../bin/libtree-sitter-odin.a"
foreign ts_odin {
    tree_sitter_odin :: proc "c" () -> Language ---
}

foreign import ts_json "../../bin/libtree-sitter-json.a"
foreign ts_json {
    tree_sitter_json :: proc "c" () -> Language ---
}

State :: struct {
    parser: Parser,
    language: Language,

    tree: Tree,
    cursor: TreeCursor,

    highlights: [dynamic]Highlight,
}

Highlight :: struct {
    start: Point,
    end: Point,
    color: theme.PaletteColor,
}

LanguageType :: enum {
    Json,
    Odin,
}

TestStuff :: struct {
    start: Point,
    end: Point,
}

Parser :: distinct rawptr
Language :: distinct rawptr

Query :: distinct rawptr
QueryCursor :: distinct rawptr

QueryError :: enum {
    None = 0,
    Syntax,
    NodeType,
    Field,
    Capture,
}

QueryCapture :: struct {
    node: Node,
    index: u32,
}

QueryMatch :: struct {
    id: u32,
    pattern_index: u16,
    capture_count: u16,
    captures: [^]QueryCapture,
}

DecodeFunction :: proc "c" (text: []u8, length: u32, code_point: ^u32) -> u32
Input :: struct {
    payload: rawptr,
    read: proc "c" (payload: rawptr, byte_index: u32, position: Point, bytes_read: ^u32) -> ^u8,
    encoding: InputEncoding,
    decode: DecodeFunction,
}

InputEncoding :: enum {
    UTF8 = 0,
    UTF16LE,
    UTF16BE,
    Custom,
}

Tree :: distinct rawptr

TreeCursor :: struct {
    tree: rawptr,
    id: rawptr,
    ctx: [3]u32,
}

Node :: struct {
    ctx: [4]u32,
    id: rawptr,
    tree: Tree,
}

Point :: struct {
    row: u32,
    column: u32
}

TSLogType :: enum { Parse, Lex }
TSLogger :: struct {
    log: proc "c" (payload: rawptr, log_type: TSLogType, msg: cstring),
    payload: rawptr,
}
log_callback :: proc "c" (payload: rawptr, log_type: TSLogType, msg: cstring) {
    context = runtime.default_context()
    fmt.printf("Tree-sitter log: %s", msg)
}

make_state :: proc(type: LanguageType, allocator := context.allocator) -> State {
    context.allocator = allocator

    parser := parser_new()
    parser_set_logger(parser, TSLogger{log = log_callback, payload = nil})

    language: Language

    switch (type) {
        case .Odin: language = tree_sitter_odin()
        case .Json: language = tree_sitter_json()
    }

    if !parser_set_language(parser, language) {
        log.errorf("failed to set language to '%v'", type)
        return State {}
    }

    return State {
        parser = parser,
        language = language
    }
}

delete_state :: proc(state: ^State) {
    delete(state.highlights)
    tree_cursor_delete(&state.cursor)
    tree_delete(state.tree)
    parser_delete(state.parser)
}

parse_buffer :: proc(state: ^State, input: Input) {
    if state.parser == nil {
        return
    }

    old_tree := state.tree
    if old_tree != nil {
        defer tree_delete(old_tree)
    }

    state.tree = parser_parse(state.parser, nil, input)

    if state.tree == nil {
        log.error("failed to parse buffer")
        return
    }

    state.cursor = tree_cursor_new(tree_root_node(state.tree))
    load_highlights(state)
}

update_cursor :: proc(state: ^State, line: int, col: int) {
    if state.tree == nil {
        return
    }

    root_node := tree_root_node(state.tree)
    tree_cursor_reset(&state.cursor, root_node)

    node := tree_cursor_current_node(&state.cursor)
    for node_child_count(node) > 1 {
        if tree_cursor_goto_first_child_for_point(&state.cursor, Point {
            row = u32(line),
            column = u32(col),
        }) < 0 {
            break
        }

        node = tree_cursor_current_node(&state.cursor)
    }
}

load_highlights :: proc(state: ^State) {
    // TODO: have this be language specific
    capture_to_color := make(map[string]theme.PaletteColor, allocator = context.temp_allocator)
    capture_to_color["include"] = .Red
    capture_to_color["keyword.function"] = .Red
    capture_to_color["keyword.return"] = .Red
    capture_to_color["storageclass"] = .Red

    capture_to_color["keyword.operator"] = .Purple

    capture_to_color["keyword"] = .Blue
    capture_to_color["repeat"] = .Blue
    capture_to_color["conditional"] = .Blue
    capture_to_color["function"] = .Blue

    capture_to_color["type.decl"] = .BrightBlue
    capture_to_color["field"] = .BrightYellow

    capture_to_color["type.builtin"] = .Aqua

    capture_to_color["function.call"] = .Green
    capture_to_color["string"] = .Green

    capture_to_color["comment"] = .Gray

    fd, err := os.open("../tree-sitter-odin/queries/highlights.scm")
    if err != nil {
        log.errorf("failed to open file: errno=%x", err)
        return
    }
    defer os.close(fd);

    if highlight_query, success := os.read_entire_file_from_handle(fd); success {
        error_offset: u32
        error_type: QueryError

        query := query_new(state.language, highlight_query, u32(len(highlight_query)), &error_offset, &error_type)
        defer query_delete(query)

        if error_type != .None {
            log.errorf("got error: '%v'", error_type)
            return
        }

        cursor := query_cursor_new()
        query_cursor_exec(cursor, query, tree_root_node(state.tree))

        if state.highlights != nil {
            clear(&state.highlights)
        } else {
            state.highlights = make([dynamic]Highlight)
        }

        match: QueryMatch
        for query_cursor_next_match(cursor, &match) {
            for i in 0..<match.capture_count {
                cap := &match.captures[i]
                start := node_start_point(cap.node)
                end := node_end_point(cap.node)

                length: u32
                name := query_capture_name_for_id(query, cap.index, &length)

                node_type := string(node_type(cap.node))
                capture_name := strings.string_from_ptr(name, int(length))

                if color, ok := capture_to_color[capture_name]; ok {
                    append(&state.highlights, Highlight { start = start, end = end, color = color })
                }

                // if color, ok := capture_to_color[node_type]; ok {
                //     append(&state.highlights, Highlight { start = start, end = end, color = color })
                // }
            }
        }
    }
}

print_node_type :: proc(state: ^State) {
    if state.tree == nil {
        return
    }

    current_node := tree_cursor_current_node(&state.cursor)
    if node_is_null(current_node) {
        log.error("Current node is null after goto_first_child")
        return
    }

    node_type_str := node_type(current_node)
    fmt.println("\n")
    log.infof("Current node type: %s", node_type_str)

    name := tree_cursor_current_field_name(&state.cursor)
    if name == nil {
        log.info("No field name for current node")
    } else {
        log.infof("Field name: %s", name)
    }

    start_point := node_start_point(current_node)
    end_point := node_end_point(current_node)
    log.infof("Node position: (%d:%d) to (%d:%d)", 
        start_point.row+1, start_point.column+1, 
        end_point.row+1, end_point.column+1)
}