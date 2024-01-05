// The default syntax highlighter plugin for Odin
package highlighter;

import "core:runtime"
import "core:fmt"

import p "../../../src/plugin"

Plugin :: p.Plugin;
Iterator :: p.Iterator;
BufferIter :: p.BufferIter;
BufferIndex :: p.BufferIndex;

@export
OnInitialize :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();
    fmt.println("Hello from the Odin Highlighter Plugin!");

    plugin.register_highlighter(plugin.state, ".odin", color_buffer_odin);
    plugin.register_highlighter(plugin.state, ".rs", color_buffer_rust);
}

@export
OnExit :: proc "c" () {
    context = runtime.default_context();
    fmt.println("Goodbye from the Odin Highlighter Plugin!");
}

@export
OnDraw :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();
}

iterate_buffer :: proc(state: rawptr, iter_funcs: Iterator, it: ^BufferIter) -> (character: u8, idx: BufferIndex, cond: bool) {
    result := iter_funcs.iterate_buffer(state, it);

    return result.char, it.cursor.index, result.should_stop;
}

iterate_buffer_reverse :: proc(state: rawptr, iter_funcs: Iterator, it: ^BufferIter) -> (character: u8, idx: BufferIndex, cond: bool) {
    result := iter_funcs.iterate_buffer_reverse(state, it);

    return result.char, it.cursor.index, result.should_stop;
}

iterate_buffer_until :: proc(plugin: Plugin, it: ^BufferIter, until_proc: rawptr) {
    plugin.iter.iterate_buffer_until(plugin.state, it, until_proc);
}

iterate_buffer_peek :: proc(plugin: Plugin, it: ^BufferIter) -> (character: u8, idx: BufferIndex, cond: bool) {
    result := plugin.iter.iterate_buffer_peek(plugin.state, it);

    return result.char, it.cursor.index, result.should_stop;
}

is_odin_keyword :: proc(plugin: Plugin, start: BufferIter, end: BufferIter) -> (matches: bool) {
    keywords := []string {
        "using",
        "transmute",
        "cast",
        "distinct",
        "opaque",
        "where",
        "struct",
        "enum",
        "union",
        "bit_field",
        "bit_set",
        "if",
        "when",
        "else",
        "do",
        "for",
        "switch",
        "case",
        "continue",
        "break",
        "size_of",
        "offset_of",
        "type_info_of",
        "typeid_of",
        "type_of",
        "align_of",
        "or_return",
        "or_else",
        "inline",
        "no_inline",
        "string",
        "cstring",
        "bool",
        "b8",
        "b16",
        "b32",
        "b64",
        "rune",
        "any",
        "rawptr",
        "f16",
        "f32",
        "f64",
        "f16le",
        "f16be",
        "f32le",
        "f32be",
        "f64le",
        "f64be",
        "u8",
        "u16",
        "u32",
        "u64",
        "u128",
        "u16le",
        "u32le",
        "u64le",
        "u128le",
        "u16be",
        "u32be",
        "u64be",
        "u128be",
        "uint",
        "uintptr",
        "i8",
        "i16",
        "i32",
        "i64",
        "i128",
        "i16le",
        "i32le",
        "i64le",
        "i128le",
        "i16be",
        "i32be",
        "i64be",
        "i128be",
        "int",
        "complex",
        "complex32",
        "complex64",
        "complex128",
        "quaternion",
        "quaternion64",
        "quaternion128",
        "quaternion256",
        "matrix",
        "typeid",
        "true",
        "false",
        "nil",
        "dynamic",
        "map",
        "proc",
        "in",
        "notin",
        "not_in",
        "import",
        "export",
        "foreign",
        "const",
        "package",
        "return",
        "defer",
    };

    for keyword in keywords {
        it := start;
        keyword_index := 0;

        for character in iterate_buffer(plugin.state, plugin.iter, &it) {
            if character != keyword[keyword_index] {
                break;
            }

            keyword_index += 1;
            if keyword_index >= len(keyword)-1 && it == end {
                if plugin.iter.get_char_at_iter(plugin.state, &it) == keyword[keyword_index] {
                    matches = true;
                }

                break;
            } else if keyword_index >= len(keyword)-1 {
                break;
            } else if it == end {
                break;
            }
        }

        if matches {
            break;
        }
    }

    return;
}

is_rust_keyword :: proc(plugin: Plugin, start: BufferIter, end: BufferIter) -> (matches: bool) {
    keywords := []string {
        "as",
        "break",
        "const",
        "continue",
        "crate",
        "else",
        "enum",
        "extern",
        "false",
        "fn",
        "for",
        "if",
        "impl",
        "in",
        "let",
        "loop",
        "match",
        "mod",
        "move",
        "mut",
        "pub",
        "ref",
        "return",
        "self",
        "Self",
        "static",
        "struct",
        "super",
        "trait",
        "true",
        "type",
        "unsafe",
        "use",
        "where",
        "while",
        "u8",
        "i8",
        "u16",
        "i16",
        "u32",
        "i32",
        "u64",
        "i64",
        "bool",
        "usize",
        "isize",
        "str",
        "String",
        "Option",
        "Result",
    };

    for keyword in keywords {
        it := start;
        keyword_index := 0;

        for character in iterate_buffer(plugin.state, plugin.iter, &it) {
            if character != keyword[keyword_index] {
                break;
            }

            keyword_index += 1;
            if keyword_index >= len(keyword)-1 && it == end {
                if plugin.iter.get_char_at_iter(plugin.state, &it) == keyword[keyword_index] {
                    matches = true;
                }

                break;
            } else if keyword_index >= len(keyword)-1 {
                break;
            } else if it == end {
                break;
            }
        }

        if matches {
            break;
        }
    }

    return;
}

color_buffer_odin :: proc "c" (plugin: Plugin, buffer: rawptr) {
    context = runtime.default_context();

    start_it := plugin.iter.get_buffer_iterator(plugin.state, buffer);
    it := plugin.iter.get_buffer_iterator(plugin.state, buffer);

    buffer := plugin.buffer.get_buffer_info(plugin.state);

    for character in iterate_buffer(plugin.state, plugin.iter, &it) {
        if it.cursor.line > buffer.glyph_buffer_height && (it.cursor.line - buffer.top_line) > buffer.glyph_buffer_height {
            break;
        }

        if character == '/' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            character, _, succ := iterate_buffer(plugin.state, plugin.iter, &it);
            if !succ { break; }

            if character == '/' {
                iterate_buffer_until(plugin, &it, plugin.iter.until_line_break);
                plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 9);
            } else if character == '*' {
                // TODO: block comments
            }
        } else if character == '\'' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            // jump into the quoted text
            iterate_buffer_until(plugin, &it, plugin.iter.until_single_quote);
            plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 12);

            iterate_buffer(plugin.state, plugin.iter, &it);
        } else if character == '"' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            // jump into the quoted text
            iterate_buffer_until(plugin, &it, plugin.iter.until_double_quote);
            plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 12);

            iterate_buffer(plugin.state, plugin.iter, &it);
        } else if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character == '_' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);
            it = start_it;

            iterate_buffer_until(plugin, &it, plugin.iter.until_end_of_word);

            if is_odin_keyword(plugin, start_it, it) {
                plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 13);
            } else if character, _, cond := iterate_buffer_peek(plugin, &it); cond {
                if character == '(' {
                    plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 11);
                }
            } else {
                break;
            }

            iterate_buffer(plugin.state, plugin.iter, &it);
        }
    }
}

color_buffer_rust :: proc "c" (plugin: Plugin, buffer: rawptr) {
    context = runtime.default_context();

    start_it := plugin.iter.get_buffer_iterator(plugin.state, buffer);
    it := plugin.iter.get_buffer_iterator(plugin.state, buffer);

    buffer := plugin.buffer.get_buffer_info(plugin.state);

    for character in iterate_buffer(plugin.state, plugin.iter, &it) {
        if it.cursor.line > buffer.glyph_buffer_height && (it.cursor.line - buffer.top_line) > buffer.glyph_buffer_height {
            break;
        }

        if character == '/' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            character, _, succ := iterate_buffer(plugin.state, plugin.iter, &it);
            if !succ { break; }

            if character == '/' {
                iterate_buffer_until(plugin, &it, plugin.iter.until_line_break);
                plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 9);
            } else if character == '*' {
                // TODO: block comments
            }
        } else if character == '\'' && false {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            // jump into the quoted text
            iterate_buffer_until(plugin, &it, plugin.iter.until_single_quote);
            plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 12);

            iterate_buffer(plugin.state, plugin.iter, &it);
        } else if character == '"' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            // jump into the quoted text
            iterate_buffer_until(plugin, &it, plugin.iter.until_double_quote);
            plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 12);

            iterate_buffer(plugin.state, plugin.iter, &it);
        } else if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character == '_' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);
            it = start_it;

            iterate_buffer_until(plugin, &it, plugin.iter.until_end_of_word);

            if is_rust_keyword(plugin, start_it, it) {
                plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 13);
            } else if character, _, cond := iterate_buffer_peek(plugin, &it); cond {
                if character == '(' || character == '<' {
                    plugin.buffer.color_char_at(plugin.state, it.buffer, start_it.cursor, it.cursor, 11);
                }
            } else {
                break;
            }

            iterate_buffer(plugin.state, plugin.iter, &it);
        }
    }
}
