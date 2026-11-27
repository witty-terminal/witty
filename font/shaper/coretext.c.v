module shaper

import datastruct
import font
import internal_os
import log
import witty_macos as macos
import math
import unicode

$if macos || ios {

	// Shaper that uses CoreText.
	//
	// CoreText shaping differs in subtle ways from HarfBuzz so it may result
	// in inconsistent rendering across platforms. But it also fixes many
	// issues (some macOS specific):
	//
	//   - Theta hat offset is incorrect in HarfBuzz but correct by default
	//     on macOS applications using CoreText. (See:
	//     https://github.com/harfbuzz/harfbuzz/discussions/4525)
	//
	//   - Hyphens (U+2010) can be synthesized by CoreText but not by HarfBuzz.
	//     See: https://github.com/mitchellh/ghostty/issues/1643
	//
	pub struct Shaper {
	pub mut:
		// The string used for shaping the current run.
		run_state RunState
		// CoreFoundation Dictionary which represents our font feature settings.
		features &macos.CFDictionary = unsafe { nil }
		// A version of the features dictionary with the default features excluded.
		features_no_default &macos.CFDictionary = unsafe { nil }
		// The shared memory used for shaping results.
		cell_buf []font.ShapeCell
		// Cached attributes dict for creating CTTypesetter objects.
		// The values in this never change so we can avoid overhead
		// by just creating it once and saving it for reuse.
		typesetter_attr_dict &macos.CFDictionary = unsafe { nil }
		// List where we cache fonts, so we don't have to remake them for
		// every single shaping operation.
		//
		// Fonts are cached as attribute dictionaries to be applied directly to
		// attributed strings.
		cached_fonts []?&macos.CFDictionary
		// The grid that our cached fonts correspond to.
		// If the grid changes then we need to reset our cache.
		cached_font_grid uint
		// The list of CoreFoundation objects to release on the dedicated
		// release thread. This is built up over the course of shaping and
		// sent to the release thread when end_frame is called.
		cf_release_pool []voidptr
		// Dedicated thread for releasing CoreFoundation objects. Some objects,
		// such as those produced by CoreText, have excessively slow release
		// callback logic.
		cf_release_thread &internal_os.CFReleaseThread = unsafe { nil }
		cf_release_thr    ?thread
		// User-specified font features.
		feature_strings []string
	}

	// Codepoint associates a Unicode codepoint with a cluster (cell) index.
	pub struct Codepoint {
	pub:
		codepoint u32
		cluster   u32
	}

	// RunState holds the codepoints and UTF-16 string built during run iteration.
	pub struct RunState {
	pub mut:
		codepoints []Codepoint
		unichars   []u16
	}

	pub fn RunState.init() RunState {
		return RunState{
			codepoints: []Codepoint{}
			unichars:   []u16{}
		}
	}

	pub fn (mut s RunState) deinit() {
		s.codepoints = []
		s.unichars = []
	}

	pub fn (mut s RunState) reset() {
		s.codepoints.clear()
		s.unichars.clear()
	}

	// Offset tracks the current x offset (sum of advance.width) and the
	// furthest cluster we've seen so far.
	struct Offset {
	mut:
		cluster u32
		x       f64
	}

	// Feature is defined in feature.v (shared across all shaper backends).

	// Default features applied to all fonts by the CoreText shaper.
	// These are in addition to the features from feature.v's default_features.
	pub const ct_default_features = [
		Feature{
			tag:   [u8(`c`), u8(`a`), u8(`l`), u8(`t`)]!
			value: 1
		},
		Feature{
			tag:   [u8(`l`), u8(`i`), u8(`g`), u8(`a`)]!
			value: 1
		},
		Feature{
			tag:   [u8(`c`), u8(`l`), u8(`i`), u8(`g`)]!
			value: 1
		},
	]

	// Create a CoreFoundation Dictionary suitable for setting the font features
	// of a CoreText font.
	fn make_features_dict(feats []Feature) !&macos.CFDictionary {
		mut list := macos.CFMutableArray.create()!
		defer { list.release() }

		for feat in feats {
			value_num := int(feat.value)

			// Keys can only be ASCII.
			mut key := macos.CFString.create_with_bytes(feat.tag[..], .ascii, false)!
			defer { key.release() }
			mut value := macos.CFNumber.create(.int_type, &value_num)!
			defer { value.release() }

			keys := [voidptr(macos.k_ct_font_open_type_feature_tag()),
				voidptr(macos.k_ct_font_open_type_feature_value())]
			vals := [voidptr(key), voidptr(value)]
			dict := macos.CFDictionary.create(keys, vals)!
			defer { dict.release() }

			list.append_value(voidptr(dict))
		}

		outer_keys := [voidptr(macos.k_ct_font_feature_settings_attribute())]
		outer_vals := [voidptr(list)]
		dict := macos.CFDictionary.create(outer_keys, outer_vals)!

		return dict
	}

	// init creates a new CoreText shaper.
	// The features parameter is a list of OpenType feature strings (e.g. "dlig").
	pub fn Shaper.init(opts font.ShaperOptions) !Shaper {
		// Build feature list from user-specified strings.
		mut feats := []Feature{}
		for feature_string in opts.features {
			// Ghostty deliberately treats invalid settings as non-fatal: one bad
			// user setting must not disable shaping for the entire terminal.
			if feature := Feature.from_string(feature_string) {
				feats << feature
			}
		}

		// Combine default features with user features.
		mut feats_df := []Feature{cap: feats.len + ct_default_features.len}
		for df in ct_default_features {
			feats_df << df
		}
		for f in feats {
			feats_df << f
		}

		features := make_features_dict(feats_df)!
		features_no_default := make_features_dict(feats)!

		run_state := RunState.init()

		// For now we only support LTR text. If we shape RTL text then
		// rendering will be very wrong so we need to explicitly force
		// LTR no matter what.
		//
		// See: https://github.com/mitchellh/ghostty/issues/1737
		// See: https://github.com/mitchellh/ghostty/issues/1442
		//
		// We used to do this by setting the writing direction attribute
		// on the attributed string we used, but it seems like that will
		// still allow some weird results, for example a single space at
		// the end of a line composed of RTL characters will be cause it
		// to output a run containing just that space, BEFORE it outputs
		// the rest of the line as a separate run, very weirdly with the
		// "right to left" flag set in the single space run's run status...
		//
		// So instead what we do is use a CTTypesetter to create our line,
		// using the kCTTypesetterOptionForcedEmbeddingLevel attribute to
		// force CoreText not to try doing any sort of BiDi, instead just
		// treat all text as embedding level 0 (left to right).
		zero_val := int(0)
		num := macos.CFNumber.create(.int_type, &zero_val)!
		defer { num.release() }
		ts_keys := [voidptr(macos.k_ct_typesetter_option_forced_embedding_level())]
		ts_vals := [voidptr(num)]
		typesetter_attr_dict := macos.CFDictionary.create(ts_keys, ts_vals)!

		// Create the CF release thread.
		mut cf_release_thread := &internal_os.CFReleaseThread{}
		unsafe {
			*cf_release_thread = internal_os.CFReleaseThread.init()!
		}
		// Start the CF release thread.
		cf_release_thr := spawn cf_release_thread.thread_main()

		return Shaper{
			run_state:            run_state
			features:             features
			features_no_default:  features_no_default
			cell_buf:             []font.ShapeCell{}
			typesetter_attr_dict: typesetter_attr_dict
			cached_fonts:         []?&macos.CFDictionary{}
			cached_font_grid:     0
			cf_release_pool:      []voidptr{}
			cf_release_thread:    cf_release_thread
			cf_release_thr:       cf_release_thr
			feature_strings:      opts.features.clone()
		}
	}

	pub fn (mut self Shaper) deinit() {
		self.cell_buf = []
		self.run_state.deinit()
		if self.features != unsafe { nil } {
			self.features.release()
		}
		if self.features_no_default != unsafe { nil } {
			self.features_no_default.release()
		}
		if self.typesetter_attr_dict != unsafe { nil } {
			self.typesetter_attr_dict.release()
		}

		for ft in self.cached_fonts {
			if f := ft {
				f.release()
			}
		}
		self.cached_fonts = []

		if self.cf_release_pool.len > 0 {
			for ref in self.cf_release_pool {
				macos.cf_release(ref)
			}

			// For tests this logic is normal because we don't want to
			// wait for a release thread. But in production this is a bug
			// and we should warn.
			$if !test {
				log.warn('BUG: CFRelease pool was not empty, releasing remaining objects')
			}
		}
		self.cf_release_pool = []

		// Stop the CF release thread
		if self.cf_release_thread != unsafe { nil } {
			self.cf_release_thread.stop.notify() or {
				log.error('error notifying cf release thread to stop, may stall err=${err}')
			}
			if thr := self.cf_release_thr {
				thr.wait()
			}
			self.cf_release_thr = none
			self.cf_release_thread.deinit()
			self.cf_release_thread = unsafe { nil }
		}
	}

	// Signal that we're done processing the current frame.
	// Sends accumulated CF objects to the dedicated release thread.
	pub fn (mut self Shaper) end_frame() {
		if self.cf_release_pool.len == 0 {
			return
		}

		// Get all the items in the pool as an owned slice so we can
		// send it to the dedicated release thread.
		items := self.cf_release_pool.clone()
		self.cf_release_pool.clear()

		// Send the items. If the send succeeds then we wake up the
		// thread to process the items. If the send fails then do a manual
		// cleanup.
		if self.cf_release_thread.mailbox.push(internal_os.CFReleaseMessage{
			release: internal_os.CFReleaseMessageRelease{
				refs: items
			}
		}, datastruct.blocking_queue_forever) != 0 {
			self.cf_release_thread.wakeup.notify() or {
				log.warn('error notifying cf release thread to wake up, may stall err=${err}')
			}
			return
		}

		for ref in items {
			macos.cf_release(ref)
		}
	}

	// Create a run iterator for the given options.
	pub fn (mut self Shaper) run_iterator(opts font.RunOptions) font.RunIterator {
		return font.RunIterator.new_with_hooks(unsafe { &self }, opts, font.RunIteratorHooks{
			prepare:  coretext_run_prepare
			add:      coretext_run_add
			finalize: coretext_run_finalize
		})
	}

	fn coretext_run_prepare(shaper_ptr voidptr) {
		mut shaper := unsafe { &Shaper(shaper_ptr) }
		shaper.run_state.reset()
	}

	fn coretext_run_add(shaper_ptr voidptr, cp u32, cluster u32) ! {
		mut shaper := unsafe { &Shaper(shaper_ptr) }
		sp := macos.get_surrogate_pair(cp)
		shaper.run_state.unichars << sp.hi
		if sp.is_pair {
			shaper.run_state.unichars << sp.lo
		}
		shaper.run_state.codepoints << Codepoint{
			codepoint: cp
			cluster:   cluster
		}
		if sp.is_pair {
			shaper.run_state.codepoints << Codepoint{
				codepoint: 0
				cluster:   cluster
			}
		}
	}

	fn coretext_run_finalize(_ voidptr) {}

	// Shape a text run into positioned glyphs.
	//
	// Note that this will accumulate garbage in the release pool. The
	// caller must ensure you're properly calling end_frame to release
	// all the objects.
	pub fn (mut self Shaper) shape(run font.TextRun) ![]font.ShapeCell {
		state := &self.run_state

		// {
		//     log.debug("shape -----------------------------------", .{});
		//     for (state.codepoints.items) |entry| {
		//         log.debug("cp={X} cluster={}", .{ entry.codepoint, entry.cluster });
		//     }
		//     log.debug("shape end -------------------------------", .{});
		// }

		// Special fonts aren't shaped and their codepoint == glyph so we
		// can just return the codepoints as-is.
		if _ := run.font_index.special() {
			self.cell_buf.clear()
			for entry in state.codepoints {
				// We use null codepoints to pad out our list so indices match
				// the UTF-16 string we constructed for CoreText. We don't want
				// to emit these if this is a special font, since they're not
				// part of the original run.
				if entry.codepoint == 0 {
					continue
				}

				self.cell_buf << font.ShapeCell{
					x:           u32(entry.cluster)
					glyph_index: entry.codepoint
				}
			}

			return self.cell_buf
		}

		// Get the font attribute dictionary for this run.
		attr_dict := self.get_font(run)!

		// Create an attributed string from the UTF-16 codepoints, shape it with
		// CoreText, and iterate the resulting CTRun objects.
		str := macos.CFString.create_with_characters_no_copy(state.unichars)
		self.cf_release_pool << voidptr(str)

		// Create an attributed string from our string
		attr_str := macos.CFAttributedString.create(str, attr_dict)!
		self.cf_release_pool << voidptr(attr_str)

		// Create a typesetter from the attributed string and the cached
		// attr dict. (See comment in init for more info on the attr dict.)
		typesetter := macos.CTTypesetter.create_with_attributed_string_and_options(attr_str,
			self.typesetter_attr_dict)!
		self.cf_release_pool << voidptr(typesetter)

		// Create a line from the typesetter
		line := typesetter.create_line(macos.CFRange{ location: 0, length: 0 })
		self.cf_release_pool << voidptr(line)

		// This keeps track of the current x offset (sum of advance.width) and
		// the furthest cluster we've seen so far (max).
		mut run_offset := Offset{}

		// This keeps track of the cell starting x and cluster.
		mut cell_offset := Offset{}

		// For debugging positions, turn this on:
		// mut run_offset_y := f64(0.0)
		// mut cell_offset_y := f64(0.0)

		// Clear our cell buf and make sure we have enough room for the whole
		// line of glyphs, so that we can just assume capacity when appending
		// instead of maybe allocating.
		self.cell_buf.clear()

		// CoreText, despite our insistence with an enforced embedding level,
		// may sometimes output runs that are non-monotonic. In order to fix
		// this, we check the run status for each run and if any aren't ltr
		// we set this to true, which indicates that we must sort our buffer.
		mut non_ltr := false

		// CoreText may generate multiple runs even though our input to
		// CoreText is already split into runs by our own run iterator.
		// The runs as far as I can tell are always sequential to each
		// other so we can iterate over them and just append to our
		// cell buffer.
		runs := line.get_glyph_runs()
		for run_i in 0 .. runs.get_count() {
			run_ptr := runs.get_value_at_index(run_i)
			if isnil(run_ptr) {
				return error('CoreText returned a null glyph run')
			}
			ctrun := unsafe { &macos.CTRun(run_ptr) }
			status := ctrun.get_status()
			if status.non_monotonic || status.right_to_left {
				non_ltr = true
			}

			glyphs := ctrun.get_glyphs()
			advances := ctrun.get_advances()
			positions := ctrun.get_positions()
			indices := ctrun.get_string_indices()
			if glyphs.len != advances.len || glyphs.len != positions.len || glyphs.len != indices.len {
				return error('CoreText returned inconsistent glyph run lengths')
			}

			for idx in 0 .. glyphs.len {
				index := indices[idx]
				if index < 0 || index >= state.codepoints.len {
					return error('CoreText returned an invalid string index')
				}
				cluster := state.codepoints[index].cluster
				if cell_offset.cluster != cluster {
					is_after_glyph_from_current_or_next_clusters := cluster <= run_offset.cluster

					mut is_first_codepoint_in_cluster := true
					mut i := index
					for i > 0 {
						i--
						codepoint := state.codepoints[i]
						if codepoint.codepoint == 0 {
							continue
						}
						is_first_codepoint_in_cluster = codepoint.cluster != cluster
						break
					}

					if is_first_codepoint_in_cluster && !is_after_glyph_from_current_or_next_clusters {
						cell_offset = Offset{
							cluster: cluster
							x:       run_offset.x
						}
					}
				}

				position := positions[idx]
				self.cell_buf << font.ShapeCell{
					x:           cell_offset.cluster
					x_offset:    i32(math.round(position.x - cell_offset.x))
					y_offset:    i32(math.round(position.y))
					glyph_index: glyphs[idx]
				}

				run_offset.x += advances[idx].width
				if cluster > run_offset.cluster {
					run_offset.cluster = cluster
				}
			}
		}

		// If our buffer contains some non-ltr sections we need to sort it :/
		if non_ltr {
			// This is EXCEPTIONALLY rare. Only happens for languages with
			// complex shaping which we don't even really support properly
			// right now, so are very unlikely to be used heavily by users
			// of Ghostty.
			self.cell_buf.sort(a.x < b.x)
		}

		return self.cell_buf
	}

	// Get an attr dict for a font from a specific index.
	// These items are cached, do not retain or release them.
	fn (mut self Shaper) get_font(run font.TextRun) !&macos.CFDictionary {
		// If this grid doesn't match the one we've cached fonts for,
		// then we reset the cache list since it's no longer valid.
		// We use an int rather than direct pointer comparison
		// because we don't want anyone to inadvertently use the pointer.
		if run.grid == unsafe { nil } {
			return error('CoreText shaper has no font grid')
		}
		grid_id := uint(voidptr(run.grid))
		if grid_id != self.cached_font_grid {
			if self.cached_font_grid > 0 {
				// Put all the currently cached fonts in to
				// the release pool before clearing the list.
				for ft in self.cached_fonts {
					if f := ft {
						self.cf_release_pool << voidptr(f)
					}
				}
				self.cached_fonts.clear()
			}

			self.cached_font_grid = grid_id
		}

		index_int := int(run.font_index.int())

		// The cached fonts are indexed directly by the font index, since
		// this number is usually low. Therefore, we set any index we haven't
		// seen to null.
		for self.cached_fonts.len <= index_int {
			self.cached_fonts << ?&macos.CFDictionary(none)
		}

		// If we have it, return the cached attr dict.
		if cached := self.cached_fonts[index_int] {
			return cached
		}

		// The CoreText shaper relies on CoreText and CoreText claims
		// that CTFonts are threadsafe. See:
		// https://developer.apple.com/documentation/coretext/
		//
		// Quote:
		// All individual functions in Core Text are thread-safe. Font
		// objects (CTFont, CTFontDescriptor, and associated objects) can
		// be used simultaneously by multiple operations, work queues, or
		// threads. However, the layout objects (CTTypesetter,
		// CTFramesetter, CTRun, CTLine, CTFrame, and associated objects)
		// should be used in a single operation, work queue, or thread.

		mut grid := unsafe { run.grid }
		grid.lock.rlock()
		face := grid.resolver.collection.get_face(run.font_index) or {
			grid.lock.runlock()
			return err
		}
		if isnil(face.ct_font) {
			grid.lock.runlock()
			return error('CoreText shaper face has no CoreText font')
		}
		original := unsafe { &macos.CTFont(face.ct_font) }
		disable_defaults := face.quirks_disable_default_font_features
		grid.lock.runlock()

		feature_attrs := if disable_defaults { self.features_no_default } else { self.features }
		desc := macos.CTFontDescriptor.create_with_attributes(feature_attrs)!
		defer { desc.release() }
		run_font := original.copy_with_attributes(0, unsafe { nil }, voidptr(desc))!
		defer { run_font.release() }

		attr_keys := [macos.StringAttribute.font.key()]
		attr_values := [voidptr(run_font)]
		attr_dict := macos.CFDictionary.create(attr_keys, attr_values)!
		self.cached_fonts[index_int] = attr_dict
		return attr_dict
	}

	// RunIteratorHook provides hooks for the RunIterator to build up
	// the shaper's run state (UTF-16 string and codepoint list).
	pub struct RunIteratorHook {
	pub mut:
		shaper &Shaper = unsafe { nil }
	}

	// Reset the run state before starting a new run.
	pub fn (mut self RunIteratorHook) prepare() {
		self.shaper.run_state.reset()
		// log.warn("----------- run reset -------------", .{});
	}

	// Add a codepoint and its associated cluster to the current run.
	pub fn (mut self RunIteratorHook) add_codepoint(cp u32, cluster u32) ! {
		mut state := &self.shaper.run_state

		// Build our UTF-16 string for CoreText
		sp := macos.get_surrogate_pair(cp)

		state.unichars << sp.hi
		if sp.is_pair {
			state.unichars << sp.lo
		}

		// Build our reverse lookup table for codepoints to clusters
		state.codepoints << Codepoint{
			codepoint: cp
			cluster:   cluster
		}

		// log.warn("run cp={X}", .{cp});

		// If the UTF-16 codepoint is a pair then we need to insert
		// a dummy entry so that the CTRunGetStringIndices() function
		// maps correctly.
		if sp.is_pair {
			state.codepoints << Codepoint{
				codepoint: 0
				cluster:   cluster
			}
		}
	}

	// Finalize the run (no-op for CoreText shaper).
	pub fn (self RunIteratorHook) finalize() {
		// nothing to do
	}

	// debug_positions logs detailed position/advance debug info.
	// Normally this is not called; enable it by uncommenting calls in shape().
	fn (self &Shaper) debug_positions(run_offset Offset, run_offset_y f64, cell_offset Offset, cell_offset_y f64, position macos.CGPoint, index int) {
		state := &self.run_state
		x_offset := position.x - cell_offset.x
		advance_x_offset := run_offset.x - cell_offset.x
		advance_y_offset := run_offset_y - cell_offset_y
		x_offset_diff := x_offset - advance_x_offset
		y_offset_diff := position.y - advance_y_offset
		positions_differ := math.abs(x_offset_diff) > 0.0001 || math.abs(y_offset_diff) > 0.0001
		old_offset_y := position.y - cell_offset_y
		position_y_differs := math.abs(cell_offset_y) > 0.0001
		cluster := state.codepoints[index].cluster
		cluster_differs := cluster != cell_offset.cluster

		// To debug every loop, flip this to true:
		extra_debugging := false

		mut is_previous_codepoint_prepend := false
		if cluster_differs || extra_debugging {
			mut i := index
			for i > 0 {
				i--
				codepoint := state.codepoints[i]

				// Skip surrogate pair padding.
				if codepoint.codepoint == 0 {
					continue
				}

				is_previous_codepoint_prepend = unicode.get(codepoint.codepoint).grapheme_break() == .prepend
				break
			}
		}

		mut formatted_cps := ''
		if positions_differ || position_y_differs || cluster_differs || extra_debugging {
			mut codepoints_text := []string{}
			mut last_cluster := ?u32(none)
			for i, cp in state.codepoints {
				if i64(cp.cluster) >= i64(cell_offset.cluster) - 1
					&& u64(cp.cluster) <= u64(cluster) + 1 && cp.codepoint != 0 {
					mut formatted := ''
					if last := last_cluster {
						if cp.cluster != last {
							formatted += ' '
						}
					}
					if i == index {
						formatted += '▸'
					}
					formatted += if cp.codepoint > 0xffff {
						'\\U${cp.codepoint:08x}'
					} else {
						'\\u${cp.codepoint:04x}'
					}
					codepoints_text << formatted
					last_cluster = cp.cluster
				}
			}
			formatted_cps = codepoints_text.join('') + ' → '
			for cp in state.codepoints {
				if i64(cp.cluster) >= i64(cell_offset.cluster) - 1
					&& u64(cp.cluster) <= u64(cluster) + 1 && cp.codepoint != 0 {
					formatted_cps += rune(cp.codepoint).str()
				}
			}
		}

		if extra_debugging {
			log.warn('extra debugging of positions index=${index} cell_offset.cluster=${cell_offset.cluster} cluster=${cluster} run_offset.cluster=${run_offset.cluster} diff=${i64(cluster) - i64(cell_offset.cluster)} pos=(${x_offset:.2f},${position.y:.2f}) run_offset=(${run_offset.x:.2f},${run_offset_y:.2f}) cell_offset=(${cell_offset.x:.2f},${cell_offset_y:.2f}) is_prev_prepend=${is_previous_codepoint_prepend} cps = ${formatted_cps}')
		}

		if positions_differ {
			log.warn('position differs from advance: cluster=${cluster} pos=(${x_offset:.2f},${position.y:.2f}) adv=(${advance_x_offset:.2f},${advance_y_offset:.2f}) diff=(${x_offset_diff:.2f},${y_offset_diff:.2f}) cps = ${formatted_cps}')
		}

		if position_y_differs {
			log.warn('position.y differs from old offset.y: cluster=${cluster} pos=(${x_offset:.2f},${position.y:.2f}) run_offset=(${run_offset.x:.2f},${run_offset_y:.2f}) cell_offset=(${cell_offset.x:.2f},${cell_offset_y:.2f}) old offset.y=${old_offset_y:.2f} cps = ${formatted_cps}')
		}

		if cluster_differs {
			log.warn('cell_offset.cluster differs from cluster (potential ligature detected) cell_offset.cluster=${cell_offset.cluster} cluster=${cluster} run_offset.cluster=${run_offset.cluster} diff=${i64(cluster) - i64(cell_offset.cluster)} pos=(${x_offset:.2f},${position.y:.2f}) run_offset=(${run_offset.x:.2f},${run_offset_y:.2f}) cell_offset=(${cell_offset.x:.2f},${cell_offset_y:.2f}) is_prev_prepend=${is_previous_codepoint_prepend} cps = ${formatted_cps}')
		}
	}
}
