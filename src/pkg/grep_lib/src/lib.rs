use std::{
    error::Error,
    ffi::CStr,
};

use grep::{
    regex::RegexMatcherBuilder,
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
            // TODO: only return N-lines of context instead of the entire freakin' buffer
            text: value.buffer().to_vec(),
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

fn search(pattern: &str, paths: &[&str]) -> Result<SimpleSink, Box<dyn Error>> {
    let matcher = RegexMatcherBuilder::new()
        .case_smart(true)
        .fixed_strings(true)
        .build(pattern)?;
    let mut searcher = SearcherBuilder::new()
        .binary_detection(BinaryDetection::quit(b'\x00'))
        .line_number(true)
        .build();

    let mut sink = SimpleSink::default();
    for path in paths {
        for result in WalkDir::new(path).into_iter().filter_entry(|dent| {
            if dent.file_type().is_dir()
                && (dent.path().ends_with("target") || dent.path().ends_with(".git"))
            {
                return false;
            }

            true
        }) {
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

#[repr(C)]
struct GrepResult {
    line_number: u64,
    column: u64,

    text_len: u32,
    path_len: u32,

    text: *const u8,
    path: *const u8,
}

impl From<Match> for GrepResult {
    fn from(value: Match) -> Self {
        Self {
            line_number: value.line_number.unwrap_or(1),
            column: value.column,
            // this won't totally bite me later
            text_len: value.text.len() as u32,
            path_len: value.path.len() as u32,
            text: Box::into_raw(value.text.into_boxed_slice()) as _,
            path: Box::into_raw(value.path.into_bytes().into_boxed_slice()) as _,
        }
    }
}
impl From<GrepResult> for Match {
    fn from(value: GrepResult) -> Self {
        unsafe {
            let text = Box::from_raw(std::slice::from_raw_parts_mut(value.text as *mut _, value.text_len as usize)).to_vec();

            let path = Box::from_raw(std::slice::from_raw_parts_mut(value.path as *mut _, value.path_len as usize)).to_vec();
            let path = String::from_utf8_unchecked(path);

            Self {
                text,
                path,
                line_number: Some(value.line_number),
                column: value.column,
            }
        }
    }
}

#[repr(C)]
struct GrepResults {
    results: *const GrepResult,
    len: u32,
}

// NOTE(pcleavelin): for some reason the current odin compiler (2025-04 as of this comment) is providing an extra argument (I assume a pointer to the odin context struct)
#[unsafe(no_mangle)]
extern "C" fn grep(
    // _: *const std::ffi::c_char,
    pattern: *const std::ffi::c_char,
    directory: *const std::ffi::c_char,
) -> GrepResults {
    let (pattern, directory) = unsafe {
        (
            CStr::from_ptr(pattern).to_string_lossy(),
            CStr::from_ptr(directory).to_string_lossy(),
        )
    };

    println!("pattern: '{pattern}', directory: '{directory}'");

    let boxed = search(&pattern, &[&directory])
        .into_iter()
        .map(|sink| sink.matches.into_iter())
        .flatten()
        .map(|v| GrepResult::from(v))
        .collect::<Vec<_>>()
        .into_boxed_slice();

    let len = boxed.len() as u32;

    GrepResults {
        results: Box::into_raw(boxed) as _,
        len,
    }
}

#[unsafe(no_mangle)]
extern "C" fn free_grep_results(results: GrepResults) {
    unsafe {
        let mut array = std::slice::from_raw_parts_mut(results.results as *mut GrepResult, results.len as usize);
        let array = Box::from_raw(array);

        for v in array {
            let _ = Match::from(v);
        }
    }
}
