use std::{error::Error, ffi::OsString, path::Path, str::FromStr};

use grep::{
    regex::RegexMatcher,
    searcher::{BinaryDetection, SearcherBuilder, Sink, SinkError},
};
use plugin_rs_bindings::{Buffer, Closure, Hook, InputMap, Key, PaletteColor, Plugin};
use walkdir::WalkDir;

#[derive(Debug)]
pub enum SimpleSinkError {
    StandardError,
    NoLine,
    BadString,
}

impl SinkError for SimpleSinkError {
    fn error_message<T: std::fmt::Display>(message: T) -> Self {
        eprintln!("{message}");

        Self::StandardError
    }
}

#[derive(Debug)]
struct Match {
    text: Vec<u8>,
    path: String,
    line_number: Option<u64>,
    column: u64,
}
impl Match {
    fn from_sink_match_with_path(
        value: &grep::searcher::SinkMatch<'_>,
        path: Option<String>,
    ) -> Result<Self, SimpleSinkError> {
        let line = value
            .lines()
            .next()
            .ok_or(SimpleSinkError::NoLine)?
            .to_vec();
        let column = value.bytes_range_in_buffer().len() as u64;

        Ok(Self {
            text: line,
            path: path.unwrap_or_default(),
            line_number: value.line_number(),
            column,
        })
    }
}

#[derive(Default, Debug)]
struct SimpleSink {
    current_path: Option<String>,
    matches: Vec<Match>,
}
impl Sink for SimpleSink {
    type Error = SimpleSinkError;

    fn matched(
        &mut self,
        _searcher: &grep::searcher::Searcher,
        mat: &grep::searcher::SinkMatch<'_>,
    ) -> Result<bool, Self::Error> {
        self.matches.push(Match::from_sink_match_with_path(
            mat,
            self.current_path.clone(),
        )?);

        Ok(true)
    }
}

fn search(pattern: &str, paths: &[OsString]) -> Result<SimpleSink, Box<dyn Error>> {
    let matcher = RegexMatcher::new_line_matcher(pattern)?;
    let mut searcher = SearcherBuilder::new()
        .binary_detection(BinaryDetection::quit(b'\x00'))
        .line_number(true)
        .build();

    let mut sink = SimpleSink::default();
    for path in paths {
        for result in WalkDir::new(path) {
            let dent = match result {
                Ok(dent) => dent,
                Err(err) => {
                    eprintln!("{}", err);
                    continue;
                }
            };
            if !dent.file_type().is_file() {
                continue;
            }
            sink.current_path = Some(dent.path().to_string_lossy().into());

            let result = searcher.search_path(&matcher, dent.path(), &mut sink);

            if let Err(err) = result {
                eprintln!("{}: {:?}", dent.path().display(), err);
            }
        }
    }

    Ok(sink)
}

#[derive(Default)]
struct GrepWindow {
    sink: Option<SimpleSink>,
    selected_match: usize,
    top_index: usize,
    input_buffer: Option<Buffer>,
}

#[no_mangle]
pub extern "C" fn OnInitialize(plugin: Plugin) {
    println!("Grep Plugin Initialized");

    plugin.register_hook(Hook::BufferInput, on_buffer_input);
    plugin.register_input_group(
        None,
        Key::Space,
        Closure!((plugin: Plugin, input_map: InputMap) => {
            (plugin.register_input)(
                input_map,
                Key::R,
                Closure!((plugin: Plugin) => {
                    let window = GrepWindow {
                        selected_match: 0,
                        top_index: 0,
                        input_buffer: Some(plugin.buffer_table.open_virtual_buffer()),
                        sink: None,
                    };

                    plugin.create_window(window, Closure!((plugin: Plugin, input_map: InputMap) => {
                        (plugin.enter_insert_mode)();

                        (plugin.register_input)(input_map, Key::I, Closure!((plugin: Plugin) => {
                            (plugin.enter_insert_mode)()
                        }), "\0".as_ptr());
                        (plugin.register_input)(input_map, Key::Enter, Closure!((plugin: Plugin) => {
                            if let Some(window) = unsafe { plugin.get_window::<GrepWindow>() } {
                                match &window.sink {
                                    Some(sink) => if window.selected_match < sink.matches.len() {
                                        let mat = unsafe { &sink.matches.get_unchecked(window.selected_match) };
                                        plugin.buffer_table.open_buffer(&mat.path, (mat.line_number.unwrap_or(1)-1) as i32, 0);
                                        (plugin.request_window_close)();
                                    },
                                    None => {},
                                }
                            }
                        }), "move selection up\0".as_ptr());
                        (plugin.register_input)(input_map, Key::K, Closure!((plugin: Plugin) => {
                            if let Some(window) = unsafe { plugin.get_window::<GrepWindow>() } {

                                if window.selected_match > 0 {
                                    window.selected_match -= 1;

                                    if window.selected_match < window.top_index {
                                        window.top_index = window.selected_match;
                                    }
                                } else {
                                    window.selected_match = match &window.sink {
                                        Some(sink) => sink.matches.len()-1,
                                        None => 0,
                                    };

                                    window.top_index = window.selected_match;
                                }
                            }
                        }), "move selection up\0".as_ptr());
                        (plugin.register_input)(input_map, Key::J, Closure!((plugin: Plugin) => {
                            if let Some(window) = unsafe { plugin.get_window::<GrepWindow>() } {
                                let screen_height = (plugin.get_screen_height)() as i32;
                                let font_height = (plugin.get_font_height)() as i32;
                                let height = screen_height - screen_height / 4;
                                let max_mats_to_draw = (height - font_height * 2) / (font_height) - 1;

                                let match_count = match &window.sink {
                                    Some(sink) => sink.matches.len(),
                                    None => 0,
                                };

                                let index_threshold = std::cmp::max(max_mats_to_draw-4, 0) as usize;

                                if window.selected_match < match_count-1 {
                                    window.selected_match += 1;

                                    if window.selected_match - window.top_index > index_threshold {
                                        window.top_index += 1;
                                    }
                                } else {
                                    window.selected_match = 0;
                                    window.top_index = 0;
                                }
                            }
                        }), "move selection down\0".as_ptr());
                    }), draw_window, free_window, Some(Closure!((_plugin: Plugin, window: *const std::ffi::c_void) -> Buffer => {
                        let window = Box::leak(unsafe { Box::<GrepWindow>::from_raw(window as *mut GrepWindow) });

                        if let Some(buffer) = window.input_buffer {
                            return buffer;
                        } else {
                            return Buffer::null();
                        }
                    })));
                }),
                "Open Grep Window\0".as_ptr(),
            );
        }),
    );
}

#[no_mangle]
pub extern "C" fn OnExit(_plugin: Plugin) {
    println!("Grep Plugin Exiting");
}

extern "C" fn draw_window(plugin: Plugin, window: *const std::ffi::c_void) {
    let window = Box::leak(unsafe { Box::<GrepWindow>::from_raw(window as *mut GrepWindow) });

    let screen_width = (plugin.get_screen_width)() as i32;
    let screen_height = (plugin.get_screen_height)() as i32;
    let font_width = (plugin.get_font_width)() as i32;
    let font_height = (plugin.get_font_height)() as i32;

    let x = screen_width / 8;
    let y = screen_height / 8;
    let width = screen_width - screen_width / 4;
    let height = screen_height - screen_height / 4;

    let buffer_prev_width = (width - font_width * 2) / 2;

    let glyph_buffer_width = buffer_prev_width / font_width - 1;
    let glyph_buffer_height = 1;

    let dir = plugin.get_current_directory();
    let directory = Path::new(dir.as_ref());

    (plugin.draw_rect)(x, y, width, height, PaletteColor::Background4);

    if let Some(buffer) = window.input_buffer {
        (plugin.draw_rect)(
            x + font_width,
            y + height - font_height * 2,
            buffer_prev_width,
            font_height,
            PaletteColor::Background2,
        );
        (plugin.draw_buffer)(
            buffer,
            (x + font_width) as isize,
            (y + height - font_height * 2) as isize,
            (glyph_buffer_width) as isize,
            (glyph_buffer_height) as isize,
            false,
        );
    }

    if let Some(sink) = &window.sink {
        if !sink.matches.is_empty() {
            let num_mats_to_draw = std::cmp::min(
                (sink.matches.len() - window.top_index) as i32,
                (height - font_height * 2) / (font_height) - 1,
            );

            for (i, mat) in sink.matches[window.top_index..].iter().enumerate() {
                let index = i + window.top_index;
                if i as i32 >= num_mats_to_draw {
                    break;
                }

                let path = Path::new(&mat.path);
                let relative_file_path = path
                    .strip_prefix(directory)
                    .unwrap_or(path)
                    .to_str()
                    .unwrap_or("");

                let matched_text = String::from_utf8_lossy(&mat.text);
                let text = match mat.line_number {
                    Some(line_number) => format!(
                        "{} - {}:{}:{}: {}\0",
                        index, relative_file_path, line_number, mat.column, matched_text
                    ),
                    None => format!("{}:{}: {}\0", relative_file_path, mat.column, matched_text),
                };

                if index == window.selected_match {
                    (plugin.draw_rect)(
                        x + font_width,
                        y + font_height + ((index - window.top_index) as i32) * font_height,
                        (text.len() as i32) * font_width,
                        font_height,
                        PaletteColor::Background2,
                    );
                }

                (plugin.draw_text)(
                    text.as_ptr() as *const i8,
                    (x + font_width) as f32,
                    (y + font_height + ((index - window.top_index) as i32) * font_height) as f32,
                    PaletteColor::Foreground2,
                );
            }
        }
    }
}

extern "C" fn on_buffer_input(plugin: Plugin, buffer: Buffer) {
    // NOTE(pcleavelin): this is super jank, because another plugin could have a window open when
    // this gets called, however its fine here because we aren't manipulating any data, and a check
    // is made between the buffer pointers which will only be correct if its our window.
    if let Some(window) = unsafe { plugin.get_window::<GrepWindow>() } {
        if window.input_buffer == Some(buffer) {
            window.selected_match = 0;
            window.top_index = 0;

            if let Some(buffer_info) = plugin.buffer_table.get_buffer_info(buffer) {
                if let Some(input) = buffer_info.input.try_as_str() {
                    let directory = OsString::from_str(plugin.get_current_directory().as_ref());
                    window.sink = match directory {
                        Ok(dir) => search(&input, &[dir]).ok(),
                        Err(_) => {
                            eprintln!("failed to parse directory");
                            None
                        }
                    };
                }
            }
        }
    }
}

extern "C" fn free_window(plugin: Plugin, window: *const std::ffi::c_void) {
    let mut window = unsafe { Box::<GrepWindow>::from_raw(window as *mut GrepWindow) };
    if let Some(buffer) = window.input_buffer {
        plugin.buffer_table.free_virtual_buffer(buffer);
        window.input_buffer = None;
    }
}
