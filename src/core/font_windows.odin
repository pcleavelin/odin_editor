package core

load_default_system_font_path :: proc(font_height: i32) -> cstring {
	return "bin\\JetBrainsMono-Regular.ttf"
}

load_system_font_list :: proc(allocator := context.temp_allocator) -> []SystemFont {
    return nil
}
