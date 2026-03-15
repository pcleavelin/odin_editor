package panels

import "base:runtime"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

import "vendor:sdl2"

import ts "../tree_sitter"
import "../core"
import "../ui"

MAX_FILE_FINDER_RESULTS :: 5000

SKIP_DIRS :: []string{".git", "target", "bin", ".claude", "node_modules"}

FileFinderEntry :: struct {
	path:         string, // absolute path; allocated in panel arena
	recency_rank: int, // 0 = most recently modified
	sort_id:      int, // combined fuzzy+recency score for current query
}

FileFinderPanel :: struct {
	buffer:            core.FileBuffer, // search input
	selected_result:   int,
	results_start:     int,
	preview_buffer:    core.FileBuffer,
	preview_file_path: string,

	// Collected once on create; sorted by mod_time descending
	// Lives in panel arena — no per-keystroke allocation of path strings
	all_entries:      []FileFinderEntry,

	// Rebuilt on every keystroke: pointers into all_entries, sorted by sort_id
	// [dynamic] so backing array grows monotonically (clear+append, no free)
	filtered_results: [dynamic]^FileFinderEntry,
}

open_file_finder_panel :: proc(state: ^core.State) {
	open(state, make_file_finder_panel())
	state.mode = .Insert
	sdl2.StartTextInput()
}

CollectedFile :: struct {
	path:     string,
	mod_nsec: i64, // modification_time._nsec for sorting
}

@(private)
collect_workspace_files_recursive :: proc(
	dir: string,
	raw: ^[dynamic]CollectedFile,
	path_allocator: mem.Allocator,
) {
	fd, err := os.open(dir)
	if err != nil {return}
	defer os.close(fd)

	infos, read_err := os.read_dir(fd, -1, context.temp_allocator)
	if read_err != nil {return}
	defer os.file_info_slice_delete(infos, context.temp_allocator)

	for fi in infos {
		base := fi.name

		if fi.is_dir {
			skip := false
			for s in SKIP_DIRS {
				if base == s {
					skip = true
					break
				}
			}
			if !skip {
				collect_workspace_files_recursive(fi.fullpath, raw, path_allocator)
			}
		} else {
			if len(base) > 0 && base[0] == '.' {continue}

			append(
				raw,
				CollectedFile{
					path     = strings.clone(fi.fullpath, path_allocator),
					mod_nsec = fi.modification_time._nsec,
				},
			)
		}
	}
}

@(private)
collect_workspace_files :: proc(dir: string, allocator: mem.Allocator) -> []FileFinderEntry {
	raw := make([dynamic]CollectedFile, allocator)
	collect_workspace_files_recursive(dir, &raw, allocator)

	// Sort by modification time descending (most recent first)
	slice.sort_by(raw[:], proc(a, b: CollectedFile) -> bool {
		return a.mod_nsec > b.mod_nsec
	})

	entries := make([]FileFinderEntry, len(raw), allocator)
	for r, i in raw {
		entries[i] = FileFinderEntry {
			path         = r.path,
			recency_rank = i, // 0 = most recent
		}
	}

	// raw backing array can be discarded (strings live in allocator)
	delete(raw)
	return entries
}

// Returns the gap-distance score for matching needle as a subsequence of
// haystack. Lower is better. Returns 0 for empty needle.
@(private)
fuzzy_score :: proc(needle, haystack: string) -> int {
	if len(needle) == 0 {return 0}

	haystack_index := 0
	dist := -1

	for needle_char in needle {
		letter_found := false

		if haystack_index >= len(haystack) {
			dist += 1
			continue
		}

		for haystack_char, i in haystack[haystack_index:] {
			if haystack_char == needle_char {
				letter_found = true

				if haystack_index > 0 {
					dist += i
				} else if dist < 0 {
					dist = 0
				}

				haystack_index += i + 1
				break
			}
		}

		if !letter_found {
			// penalise but don't disqualify — matches the command palette behaviour
			dist += len(haystack) - haystack_index
			dist = max(dist, 0)
		}
	}

	return dist
}

@(private)
filter_and_rank :: proc(panel_state: ^FileFinderPanel, query: string, directory: string) {
	clear(&panel_state.filtered_results)

	if len(query) == 0 {
		// No query: show all in recency order (all_entries is already sorted)
		for &entry in panel_state.all_entries {
			append(&panel_state.filtered_results, &entry)
			if len(panel_state.filtered_results) >= MAX_FILE_FINDER_RESULTS {break}
		}
		return
	}

	n := len(panel_state.all_entries)

	for &entry in panel_state.all_entries {
		// Match against relative path so e.g. "panels/g" works
		rel := entry.path[len(directory):]
		score := fuzzy_score(query, rel)

		// sort_id: fuzzy score is strictly primary, recency is tiebreaker
		entry.sort_id = score * n + entry.recency_rank
		append(&panel_state.filtered_results, &entry)

		if len(panel_state.filtered_results) >= MAX_FILE_FINDER_RESULTS * 2 {break}
	}

	slice.sort_by(panel_state.filtered_results[:], proc(a, b: ^FileFinderEntry) -> bool {
		return a.sort_id < b.sort_id
	})

	if len(panel_state.filtered_results) > MAX_FILE_FINDER_RESULTS {
		raw := transmute(^runtime.Raw_Dynamic_Array)(&panel_state.filtered_results)
		raw.len = MAX_FILE_FINDER_RESULTS
	}
}

@(private)
update_file_finder_preview :: proc(panel_state: ^FileFinderPanel, state: ^core.State) {
	if len(panel_state.filtered_results) == 0 {return}

	path := panel_state.filtered_results[panel_state.selected_result].path
	if path != panel_state.preview_file_path {
		core.reload_file_into_buffer(&panel_state.preview_buffer, path, state.directory)
		panel_state.preview_file_path = path
	}
	core.move_cursor_to_location(&panel_state.preview_buffer, 0, 0)
}

make_file_finder_panel :: proc() -> core.Panel {
	return core.Panel {
		is_floating = true,
		name = proc(panel: ^core.Panel) -> string {
			return "FileFinderPanel"
		},
		drop = proc(panel: ^core.Panel, state: ^core.State) {
			panel_state := transmute(^FileFinderPanel)panel.state
			ts.delete_state(&panel_state.buffer.tree)
			ts.delete_state(&panel_state.preview_buffer.tree)
			// all_entries, filtered_results, path strings all freed with panel arena
		},
		create = proc(panel: ^core.Panel, state: ^core.State, data: rawptr) {
			context.allocator = panel.allocator

			panel.state = transmute(core.PanelState)new(FileFinderPanel)
			panel_state := transmute(^FileFinderPanel)panel.state
			panel_state^ = FileFinderPanel{}

			panel.input_map = core.new_input_map(show_help = true)
			panel_state.buffer = core.new_virtual_file_buffer()
			panel_state.preview_buffer = core.new_virtual_file_buffer(panel.allocator)
			panel_state.all_entries = collect_workspace_files(state.directory, panel.allocator)
			panel_state.filtered_results = make([dynamic]^FileFinderEntry)

			// Populate the result list with all files sorted by recency
			filter_and_rank(panel_state, "", state.directory)

			if len(panel_state.filtered_results) > 0 {
				update_file_finder_preview(panel_state, state)
			}

			panel_actions := core.new_input_actions(show_help = true)
			register_default_panel_actions(&panel_actions)
			core.register_ctrl_key_action(
				&panel.input_map.mode[.Normal],
				.W,
				panel_actions,
				"Panel Navigation",
			)

			core.register_key_action(
				&panel.input_map.mode[.Normal],
				.ENTER,
				proc(state: ^core.State, user_data: rawptr) {
					this_panel := transmute(^core.Panel)user_data
					panel_state := transmute(^FileFinderPanel)this_panel.state

					if len(panel_state.filtered_results) > 0 {
						path := panel_state.filtered_results[panel_state.selected_result].path
						core.open_buffer_file(state, path, 0, 0)
						close(state, this_panel.id)
						state.mode = .Normal
						sdl2.StopTextInput()
						core.reset_input_map(state)
					}
				},
				"Open File",
			)

			core.register_key_action(
				&panel.input_map.mode[.Normal],
				.I,
				proc(state: ^core.State, user_data: rawptr) {
					this_panel := transmute(^core.Panel)user_data
					panel_state := transmute(^FileFinderPanel)this_panel.state

					core.move_cursor_right(&panel_state.buffer, false)
					state.mode = .Insert
					sdl2.StartTextInput()
				},
				"enter insert mode",
			)

			core.register_key_action(
				&panel.input_map.mode[.Normal],
				.K,
				proc(state: ^core.State, user_data: rawptr) {
					this_panel := transmute(^core.Panel)user_data
					panel_state := transmute(^FileFinderPanel)this_panel.state

					if len(panel_state.filtered_results) > 0 && panel_state.selected_result > 0 {
						panel_state.selected_result -= 1
						update_file_finder_preview(panel_state, state)
					}
				},
				"move selection up",
			)

			core.register_key_action(
				&panel.input_map.mode[.Normal],
				.J,
				proc(state: ^core.State, user_data: rawptr) {
					this_panel := transmute(^core.Panel)user_data
					panel_state := transmute(^FileFinderPanel)this_panel.state

					if len(panel_state.filtered_results) > 0 &&
					   panel_state.selected_result < len(panel_state.filtered_results) - 1 {
						panel_state.selected_result += 1
						update_file_finder_preview(panel_state, state)
					}
				},
				"move selection down",
			)

			core.register_key_action(
				&panel.input_map.mode[.Insert],
				.ESCAPE,
				proc(state: ^core.State, user_data: rawptr) {
					state.mode = .Normal
					sdl2.StopTextInput()
				},
				"exit insert mode",
			)

			core.register_key_action(
				&panel.input_map.mode[.Normal],
				.ESCAPE,
				proc(state: ^core.State, user_data: rawptr) {
					this_panel := transmute(^core.Panel)user_data
					close(state, this_panel.id)
				},
				"close panel",
			)
		},
		buffer = proc(panel: ^core.Panel, state: ^core.State) -> (buffer: ^core.FileBuffer, ok: bool) {
			panel_state := transmute(^FileFinderPanel)panel.state
			return &panel_state.buffer, true
		},
		on_buffer_input = proc(panel: ^core.Panel, state: ^core.State) {
			panel_state := transmute(^FileFinderPanel)panel.state

			query := core.buffer_to_string(
				&panel_state.buffer,
				allocator = context.temp_allocator,
			)

			// Strip trailing newline (submit gesture)
			if len(query) > 0 && query[len(query) - 1] == '\n' {
				if len(panel_state.filtered_results) > 0 {
					path := panel_state.filtered_results[panel_state.selected_result].path
					core.open_buffer_file(state, path, 0, 0)
					close(state, panel.id)
					state.mode = .Normal
					sdl2.StopTextInput()
					core.reset_input_map(state)
				}
				return
			}

			filter_and_rank(panel_state, query, state.directory)
			panel_state.selected_result = 0
			update_file_finder_preview(panel_state, state)
		},
		render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
			context.allocator = panel.allocator

			panel_state := transmute(^FileFinderPanel)panel.state
			s := transmute(^ui.State)state.ui

			ListState :: struct {
				core_state:  ^core.State,
				panel_state: ^FileFinderPanel,
			}
			list_state := ListState {
				core_state  = state,
				panel_state = panel_state,
			}

			ui.open_element(
				s,
				nil,
				{dir = .TopToBottom, kind = {ui.Grow{}, ui.Grow{}}, floating = true},
				style = {background_color = .Background1},
			)
			{
				// query results and file preview side-by-side
				ui.open_element(s, nil, {dir = .LeftToRight, kind = {ui.Grow{}, ui.Grow{}}})
				{
					// left: search input + file list
					ui.open_element(
						s,
						nil,
						{dir = .TopToBottom, kind = {ui.Grow{}, ui.Grow{}}},
						style = {border = {.Right}, border_color = .Background4},
					)
					{
						// search input box
						ui.open_element(
							s,
							nil,
							{
								dir  = .LeftToRight,
								kind = {ui.Grow{}, ui.Exact(state.source_font_height * 2)},
							},
							style = {
								border           = {.Left, .Right, .Top, .Bottom},
								border_color     = .Background4,
								background_color = .Background2,
							},
						)
						{
							ui.centered_top_to_bottom(s)
							{
								ui.left_to_right(s)
								{
									ui.spacer(s, state.source_font_width)
									render_raw_buffer(state, s, &panel_state.buffer)
								}
								ui.close_element(s)
							}
							ui.close_centered_top_to_bottom(s)
						}
						ui.close_element(s)

						// file result list
						ui.list(
							^FileFinderEntry,
							s,
							panel_state.filtered_results[:],
							&list_state,
							&panel_state.selected_result,
							&panel_state.results_start,
							proc(s: ^ui.State, item: rawptr, state: rawptr) {
								entry := (transmute(^^FileFinderEntry)item)^
								list_state := transmute(^ListState)state

								dir := list_state.core_state.directory
								rel := entry.path[len(dir):]
								// strip leading separator so paths show as "src/main.odin"
								if len(rel) > 0 && (rel[0] == '/' || rel[0] == '\\') {
									rel = rel[1:]
								}

								ui.left_to_right(s)
								{
									ui.open_element(s, rel, {kind = {ui.Grow{}, ui.Fit{}}})
									ui.close_element(s)
								}
								ui.close_element(s)
							},
						)
					}
					ui.close_element(s)

					// right: file preview
					if len(panel_state.filtered_results) > 0 {
						render_raw_buffer(state, s, &panel_state.preview_buffer)
					}
				}
				ui.close_element(s)
			}
			ui.close_element(s)

			return true
		},
	}
}
