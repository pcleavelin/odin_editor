use std::{
    error::Error,
    ffi::{CStr, OsString},
    os::raw::c_char,
    str::FromStr,
};

use grep::{
    regex::RegexMatcher,
    searcher::{BinaryDetection, SearcherBuilder, Sink, SinkError},
};
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

#[repr(C)]
pub struct UnsafeMatch {
    text_str: *mut u8,
    text_len: usize,
    text_cap: usize,

    path_str: *mut u8,
    path_len: usize,
    path_cap: usize,

    line_number: u64,
    column: u64,
}

impl From<Match> for UnsafeMatch {
    fn from(value: Match) -> Self {
        let mut text_boxed = Box::new(value.text);
        let text_str = text_boxed.as_mut_ptr();
        let text_len = text_boxed.len();
        let text_cap = text_boxed.capacity();
        Box::leak(text_boxed);

        let mut path_boxed = Box::new(value.path);
        let path_str = path_boxed.as_mut_ptr();
        let path_len = path_boxed.len();
        let path_cap = path_boxed.capacity();
        Box::leak(path_boxed);

        Self {
            text_str,
            text_len,
            text_cap,
            path_str,
            path_len,
            path_cap,
            line_number: value.line_number.unwrap_or_default(),
            column: value.column,
        }
    }
}

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

#[derive(Default)]
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

#[repr(C)]
pub struct UnsafeMatchArray {
    matches: *mut UnsafeMatch,
    len: usize,
    capacity: usize,
}

impl Default for UnsafeMatchArray {
    fn default() -> Self {
        Self {
            matches: std::ptr::null_mut(),
            len: 0,
            capacity: 0,
        }
    }
}

impl From<SimpleSink> for UnsafeMatchArray {
    fn from(value: SimpleSink) -> Self {
        let matches: Vec<UnsafeMatch> = value.matches.into_iter().map(Into::into).collect();
        let mut boxed_vec = Box::new(matches);

        let ptr = boxed_vec.as_mut_ptr();
        let len = boxed_vec.len();
        let capacity = boxed_vec.capacity();
        Box::leak(boxed_vec);

        Self {
            matches: ptr,
            len,
            capacity,
        }
    }
}

/// # Safety
/// Who knows what'll happen if you don't pass valid strings
#[no_mangle]
pub unsafe extern "C" fn rg_search(
    pattern: *const c_char,
    path: *const c_char,
) -> UnsafeMatchArray {
    let pattern = CStr::from_ptr(pattern);
    let path = CStr::from_ptr(path);
    if let (Ok(path), Ok(pattern)) = (path.to_str(), pattern.to_str()) {
        if let Ok(path) = OsString::from_str(path) {
            return match search(pattern, &[path]) {
                Ok(sink) => sink.into(),
                Err(err) => {
                    eprintln!("rg search failed: {}", err);
                    Default::default()
                }
            };
        }
    }

    Default::default()
}

/// # Safety
/// Who knows what'll happen if you don't pass back the same vec
#[no_mangle]
pub unsafe extern "C" fn drop_match_array(match_array: UnsafeMatchArray) {
    let matches = Vec::from_raw_parts(match_array.matches, match_array.len, match_array.capacity);
    for mat in matches {
        let _ = String::from_raw_parts(mat.text_str, mat.text_len, mat.text_cap);
        let _ = String::from_raw_parts(mat.path_str, mat.path_len, mat.path_cap);
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
