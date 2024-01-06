// A simple window to view/search open buffers
package buffer_search;

import "core:runtime"
import "core:fmt"

import p "../../src/plugin"

Plugin :: p.Plugin;
Iterator :: p.Iterator;
BufferIter :: p.BufferIter;
BufferIndex :: p.BufferIndex;
Key :: p.Key;

@export
OnInitialize :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();
    fmt.println("builtin buffer search plugin initialized!");

    plugin.register_input_group(nil, .SPACE, proc "c" (plugin: Plugin, input_map: rawptr) {
        plugin.register_input(input_map, .B, open_buffer_window, "show list of open buffers");
    });
}

@export
OnExit :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();
}

open_buffer_window :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();

    fmt.println("Look you tried opening a window from a plugin!");
}
