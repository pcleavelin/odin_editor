// The default syntax highlighter plugin for Odin
package odin_highlighter;

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

    it := plugin.iter.get_current_buffer_iterator(plugin.state);

    fmt.println("Look I have an iterator!", it);
}

@export
OnExit :: proc "c" () {
    context = runtime.default_context();
    fmt.println("Goodbye from the Odin Highlighter Plugin!");
}

@export
OnDraw :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();

    color_buffer(plugin);
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

is_keyword :: proc(plugin: Plugin, start: BufferIter, end: BufferIter) -> (matches: bool) {
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

color_buffer :: proc(plugin: Plugin) {
    start_it := plugin.iter.get_current_buffer_iterator(plugin.state);
    it := plugin.iter.get_current_buffer_iterator(plugin.state);

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
                plugin.buffer.color_char_at(plugin.state, start_it.cursor, it.cursor, 9);
            } else if character == '*' {
                // TODO: block comments
            }
        } else if character == '\'' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            // jump into the quoted text
            iterate_buffer_until(plugin, &it, plugin.iter.until_single_quote);
            plugin.buffer.color_char_at(plugin.state, start_it.cursor, it.cursor, 12);

            iterate_buffer(plugin.state, plugin.iter, &it);
        } else if character == '"' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);

            // jump into the quoted text
            iterate_buffer_until(plugin, &it, plugin.iter.until_double_quote);
            plugin.buffer.color_char_at(plugin.state, start_it.cursor, it.cursor, 12);

            iterate_buffer(plugin.state, plugin.iter, &it);
        } else if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character == '_' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_buffer_reverse(plugin.state, plugin.iter, &start_it);
            it = start_it;

            iterate_buffer_until(plugin, &it, plugin.iter.until_end_of_word);

            if is_keyword(plugin, start_it, it) {
                plugin.buffer.color_char_at(plugin.state, start_it.cursor, it.cursor, 13);
            } 
            //else {
            //    break;
            //}
            // else if character, _, cond := iterate_peek(&it, iterate_file_buffer); cond {
            //     if character == '(' {
            //         color_character(buffer, start_it.cursor, it.cursor, .Green);
            //     }
            // } 

            iterate_buffer(plugin.state, plugin.iter, &it);
        }
    }
}
