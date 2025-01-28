package core

import "core:runtime"
import "core:reflect"
import "core:fmt"
import "core:log"

Level_Header := [?]string {
    0..<10 = "[DEBUG]: ",
   10..<20 = "[INFO ]: ",
   20..<30 = "[WARN ]: ",
   30..<40 = "[ERROR]: ",
   40..<50 = "[FATAL]: ",
};

new_logger :: proc(buffer: ^FileBuffer) -> runtime.Logger {
    return runtime.Logger {
        procedure    = logger_proc,
        data         = buffer,
        lowest_level = .Debug,
        options = {
            .Level,
            .Date,
            .Time,
            .Short_File_Path,
            .Thread_Id
        },
    };
}

logger_proc :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
    buffer := cast(^FileBuffer)data;

   if .Level in options {
       insert_content(buffer, transmute([]u8)(Level_Header[level]), true);
   } 

   insert_content(buffer, transmute([]u8)(text), true);
   insert_content(buffer, {'\n'}, true);
}
