module font

import sync
import internal_hash
import tripwire

// This structure represents the state required to render a terminal
// grid using the font subsystem. It is "shared" because it is able to
// be shared across multiple surfaces.
//
// It is desirable for the grid state to be shared because the font
// configuration for a set of surfaces is almost always the same and
// font data is relatively memory intensive. Further, the font subsystem
// should be read-heavy compared to write-heavy, so it handles concurrent
// reads well. Going even further, the font subsystem should be very rarely
// read at all since it should only be necessary when the grid actively
// changes.
//
// SharedGrid does NOT support resizing, font-family changes, font removals
// in collections, etc. Because the Grid is shared this would cause a
// major disruption in the rendering of multiple surfaces (i.e. increasing
// the font size in one would increase it in all). In many cases this isn't
// desirable so to implement configuration changes the grid should be
// reinitialized and all surfaces should switch over to using that one.
//
// Translated from ghostty/src/font/SharedGrid.zig

// ============================================================
// SharedGrid
// ============================================================

// SharedGrid is a font grid shared across surfaces. It contains
// the font atlas textures, glyph caches, and metrics, protected by a lock.
@[heap]
pub struct SharedGrid {
pub mut:
	// Cache for codepoints to font indexes in a group. V maps cannot use this
	// struct key directly, so each source hash points to a collision-safe bucket.
	codepoints map[u64][]CodepointCacheEntry

	// Cache for glyph renders into the atlas. As above, retain the complete key
	// in each bucket so equal hashes never alias unrelated glyphs.
	glyphs map[u64][]GlyphCacheEntry

	// The texture atlas to store renders in. The Glyph data in the glyphs
	// cache is dependent on the atlas matching.
	atlas_grayscale Atlas
	atlas_color     Atlas

	// The underlying resolver for font data, fallbacks, etc. The shared
	// grid takes ownership of the resolver and will free it.
	resolver CodepointResolver

	// The currently active grid metrics dictating the layout of the grid.
	// This is calculated based on the resolver and current fonts.
	metrics Metrics

	// The RwLock used to protect the shared grid. Callers are expected to use
	// this directly if they need to i.e. access the atlas directly. Because
	// callers can use this lock directly, maintainers need to be extra careful
	// to review call sites to ensure they are using the lock correctly.
	lock &sync.RwMutex = unsafe { nil }
}

pub enum SharedGridInitFailPoint as u8 {
	codepoints_capacity
	glyphs_capacity
	reload_metrics
}

pub enum SharedGridRenderGlyphFailPoint as u8 {
	get_presentation
}

struct SharedGridTripwires {
mut:
	init         tripwire.TripwireModule[SharedGridInitFailPoint]
	render_glyph tripwire.TripwireModule[SharedGridRenderGlyphFailPoint]
}

const shared_grid_tripwires = &SharedGridTripwires{}

pub fn shared_grid_init_tripwire() &tripwire.TripwireModule[SharedGridInitFailPoint] {
	return unsafe { &shared_grid_tripwires.init }
}

pub fn shared_grid_render_glyph_tripwire() &tripwire.TripwireModule[SharedGridRenderGlyphFailPoint] {
	return unsafe { &shared_grid_tripwires.render_glyph }
}

// Initialize the grid.
//
// The resolver must have a collection that supports deferred loading
// (collection.load_options != null). This is because we need the load
// options data to determine grid metrics and setup our sprite font.
//
// SharedGrid always configures the sprite font. This struct is expected to be
// used with a terminal grid and therefore the sprite font is always
// necessary for correct rendering.
pub fn SharedGrid.init(resolver CodepointResolver) !SharedGrid {
	mut tw := shared_grid_init_tripwire()
	// We need to support loading options since we use the size data
	assert resolver.collection.load_options != none

	// Larger glyph sets grow the two atlases independently.
	mut atlas_grayscale := Atlas.init(256, .grayscale)!
	atlas_color := Atlas.init(128, .bgra) or {
		atlas_grayscale.deinit()
		return err
	}

	mut result := SharedGrid{
		resolver:        resolver
		atlas_grayscale: atlas_grayscale
		atlas_color:     atlas_color
		metrics:         Metrics{} // Loaded below
		lock:            sync.new_rwmutex()
	}

	// These checks represent the source map-capacity allocations. V maps grow
	// under GC and don't expose allocation errors, but the test-only tripwire
	// retains the source failure boundaries.
	tw.check(.codepoints_capacity) or {
		result.atlas_grayscale.deinit()
		result.atlas_color.deinit()
		return err
	}
	tw.check(.glyphs_capacity) or {
		result.atlas_grayscale.deinit()
		result.atlas_color.deinit()
		return err
	}

	// Initialize our metrics.
	tw.check(.reload_metrics) or {
		result.atlas_grayscale.deinit()
		result.atlas_color.deinit()
		return err
	}
	result.reload_metrics() or {
		result.atlas_grayscale.deinit()
		result.atlas_color.deinit()
		return err
	}

	return result
}

// Deinit. Assumes no concurrent access so no lock is taken.
pub fn (mut self SharedGrid) deinit() {
	self.codepoints = map[u64][]CodepointCacheEntry{}
	self.glyphs = map[u64][]GlyphCacheEntry{}
	self.atlas_grayscale.deinit()
	self.atlas_color.deinit()
	self.resolver.deinit()
	if self.lock != unsafe { nil } {
		self.lock.destroy()
	}
}

fn (mut self SharedGrid) reload_metrics() ! {
	self.resolver.collection.update_metrics()!

	self.metrics = self.resolver.collection.metrics or {
		return error('no metrics available')
	}

	// Setup our sprite font.
	self.resolver.sprite = SpriteFace{
		metrics: self.metrics
	}
}

// Returns the grid cell size.
//
// This is not thread safe.
pub fn (self &SharedGrid) cell_size() CellSize {
	return CellSize{
		width:  self.metrics.cell_width
		height: self.metrics.cell_height
	}
}

// Get the font index for a given codepoint. This is cached.
//
// This always forces loading any deferred fonts since we assume that if
// you're looking up an index that the caller plans to use the font. By
// loading the font in this function we can ensure thread-safety on the
// load without complicating future calls.
//
// Returns a CodepointValue where has_value indicates whether a font was found.
// V cannot currently represent Zig's error union containing an optional, so
// this wrapper preserves both states without discarding loading errors.
pub fn (mut self SharedGrid) get_index(cp u32, style Style, p ?Presentation) !CodepointValue {
	key := CodepointKey{
		style:        style
		codepoint:    cp
		presentation: p
	}
	h := key.hash_key()

	// Fast path: the cache has the value. This is almost always true and
	// only requires a read lock.
	self.lock.rlock()
	if value := codepoint_cache_get(self.codepoints, h, key) {
		self.lock.runlock()
		return value
	}
	self.lock.runlock()

	// Slow path: we need to search this codepoint
	self.lock.lock()
	defer { self.lock.unlock() }

	// Another thread may have filled the cache while we waited for the write
	// lock, so check again before performing discovery or loading a face.
	if value := codepoint_cache_get(self.codepoints, h, key) {
		return value
	}

	// Load a value and cache it. This even caches negative matches.
	value := self.resolver.get_index(cp, style, p)

	if idx := value {
		result := CodepointValue{
			has_value: true
			index:     idx
		}
		codepoint_cache_put(mut self.codepoints, h, key, result)

		// If the font is a sprite font then we don't need to preload
		// because getFace doesn't work with special fonts.
		if idx.special() == none {
			// Load the face in case its deferred. If this fails then we would've
			// failed to load it in the future anyways so we want to undo all
			// the caching we did.
			self.resolver.collection.get_face(idx) or {
				codepoint_cache_delete(mut self.codepoints, h, key)
				return err
			}
		}

		return result
	}

	// Cache negative result
	result := CodepointValue{
		has_value: false
	}
	codepoint_cache_put(mut self.codepoints, h, key, result)
	return result
}

// Returns true if the given font index has the codepoint and presentation.
pub fn (self &SharedGrid) has_codepoint(idx Index, cp u32, p ?Presentation) bool {
	self.lock.rlock()
	defer { self.lock.runlock() }
	return self.resolver.collection.has_codepoint(idx, cp, if pr := p {
		PresentationMode.explicit(pr)
	} else {
		PresentationMode.any()
	})
}

// Render a codepoint. This uses the first font index that has the codepoint
// and matches the presentation requested. If the codepoint cannot be found
// in any font, none is returned.
pub fn (mut self SharedGrid) render_codepoint(cp u32, style Style, p ?Presentation, opts RenderOptions) !RenderValue {
	// Note: we could optimize the below to use way less locking, but
	// at the time of writing this codepath is only called for preedit
	// text which is relatively rare and almost non-existent in multiple
	// surfaces at the same time.

	// Get the font that has the codepoint
	cv := self.get_index(cp, style, p)!
	if !cv.has_value {
		return RenderValue{}
	}
	index := cv.index

	// Get the glyph for the font
	self.lock.rlock()
	face := self.resolver.collection.get_face(index) or {
		self.lock.runlock()
		return err
	}
	glyph_index := face.glyph_index(cp) or {
		self.lock.runlock()
		return RenderValue{}
	}
	self.lock.runlock()

	// Render
	return RenderValue{
		has_value: true
		render:    self.render_glyph(index, glyph_index, opts)!
	}
}

// Render a glyph index. This automatically determines the correct texture
// atlas to use and caches the result.
pub fn (mut self SharedGrid) render_glyph(index Index, glyph_index u32, opts RenderOptions) !RenderResult {
	mut tw := shared_grid_render_glyph_tripwire()
	key := GlyphKey{
		index: index
		glyph: glyph_index
		opts:  opts
	}
	h := key.hash_key()

	// Fast path: the cache has the value. This is almost always true and
	// only requires a read lock.
	self.lock.rlock()
	if value := glyph_cache_get(self.glyphs, h, key) {
		self.lock.runlock()
		return value
	}
	self.lock.runlock()

	// Slow path: we need to render this glyph
	self.lock.lock()
	defer { self.lock.unlock() }

	// Check again in case another thread beat us to it.
	if value := glyph_cache_get(self.glyphs, h, key) {
		return value
	}

	// Get the presentation to determine what atlas to use
	tw.check(.get_presentation)!
	p := self.resolver.get_presentation(index, glyph_index)!
	mut atlas := match p {
		.text { &self.atlas_grayscale }
		.emoji { &self.atlas_color }
	}

	mut render_opts := opts

	// Always use these constraints for emoji.
	if p == .emoji {
		render_opts.constraint = Constraint{
			// Scale emoji to be as large as possible
			// while preserving their aspect ratio.
			size:             .cover
			// Center the emoji in its cells.
			align_horizontal: .center
			align_vertical:   .center
			// Add a small bit of padding so the emoji
			// doesn't quite touch the edges of the cells.
			pad_left:         0.025
			pad_right:        0.025
		}
	}

	// Render into the atlas
	// A startup glyph can still use the full size of the original atlas's
	// first growth. Once that size is reached, grow at most once per glyph.
	max_size := if atlas.size < 512 { u32(1024) } else { atlas.size * 2 }
	mut glyph := Glyph{}
	for {
		glyph = self.resolver.render_glyph(mut atlas, index, glyph_index, render_opts) or {
			if err.msg() != 'AtlasFull' || atlas.size >= max_size {
				return err
			}
			atlas.grow(atlas.size * 2)!
			continue
		}
		break
	}

	// Cache and return
	result := RenderResult{
		glyph:        glyph
		presentation: p
	}
	glyph_cache_put(mut self.glyphs, h, key, result)

	return result
}

// ============================================================
// CodepointKey
// ============================================================

// CodepointKey is the cache key for codepoint-to-index lookups.
struct CodepointKey {
	style        Style
	codepoint    u32
	presentation ?Presentation
}

struct CodepointCacheEntry {
	key   CodepointKey
	value CodepointValue
}

fn codepoint_key_equal(a CodepointKey, b CodepointKey) bool {
	if a.style != b.style || a.codepoint != b.codepoint {
		return false
	}
	if ap := a.presentation {
		if bp := b.presentation {
			return ap == bp
		}
		return false
	}
	if _ := b.presentation {
		return false
	}
	return true
}

fn codepoint_cache_get(cache map[u64][]CodepointCacheEntry, hash u64, key CodepointKey) ?CodepointValue {
	if hash !in cache {
		return none
	}
	for entry in cache[hash] {
		if codepoint_key_equal(entry.key, key) {
			return entry.value
		}
	}
	return none
}

fn codepoint_cache_put(mut cache map[u64][]CodepointCacheEntry, hash u64, key CodepointKey, value CodepointValue) {
	mut bucket := cache[hash]
	for index, entry in bucket {
		if codepoint_key_equal(entry.key, key) {
			bucket[index] = CodepointCacheEntry{key, value}
			cache[hash] = bucket
			return
		}
	}
	bucket << CodepointCacheEntry{key, value}
	cache[hash] = bucket
}

fn codepoint_cache_delete(mut cache map[u64][]CodepointCacheEntry, hash u64, key CodepointKey) {
	if hash !in cache {
		return
	}
	mut bucket := cache[hash]
	for index, entry in bucket {
		if codepoint_key_equal(entry.key, key) {
			bucket.delete(index)
			if bucket.len == 0 {
				cache.delete(hash)
			} else {
				cache[hash] = bucket
			}
			return
		}
	}
}

// hash_key mirrors std.hash.autoHash for Ghostty's CodepointKey. Zig hashes
// the u3 enum in one byte, the u32 in little-endian order, and an optional
// enum's payload only when it is present.
fn (k CodepointKey) hash_key() u64 {
	mut h := SourceHash{}
	h.put_u8(u8(k.style))
	h.put_u32(k.codepoint)
	if p := k.presentation {
		h.put_u8(u8(p))
	}
	return h.final()
}

// ============================================================
// CodepointValue
// ============================================================

// CodepointValue wraps an optional Index for caching.
// V maps return zero values for missing keys, so we use a wrapper
// with a has_value flag to distinguish "not cached" from "cached as none".
pub struct CodepointValue {
pub:
	has_value bool
	index     Index
}

// RenderValue is the V representation of Ghostty's error-union optional
// render result. V cannot return !?RenderResult directly.
pub struct RenderValue {
pub:
	has_value bool
	render    RenderResult
}

// ============================================================
// GlyphKey
// ============================================================

// GlyphKey is the cache key for glyph render lookups.
struct GlyphKey {
	index Index
	glyph u32
	opts  RenderOptions
}

struct GlyphCacheEntry {
	key   GlyphKey
	value RenderResult
}

fn (k GlyphKey) packed_key() u64 {
	cell_width := k.opts.cell_width or { u8(0) }
	assert cell_width <= 3
	assert k.opts.constraint_width <= 3
	mut packed_opts := u16(cell_width)
	if k.opts.thicken {
		packed_opts |= u16(1) << 2
	}
	packed_opts |= u16(k.opts.thicken_strength) << 3
	packed_opts |= u16(k.opts.constraint_width) << 11
	return u64(k.index.int()) | (u64(k.glyph) << 16) | (u64(packed_opts) << 48)
}

fn glyph_key_equal(a GlyphKey, b GlyphKey) bool {
	return a.glyph == b.glyph && a.packed_key() == b.packed_key()
}

fn glyph_cache_get(cache map[u64][]GlyphCacheEntry, hash u64, key GlyphKey) ?RenderResult {
	if hash !in cache {
		return none
	}
	for entry in cache[hash] {
		if glyph_key_equal(entry.key, key) {
			return entry.value
		}
	}
	return none
}

fn glyph_cache_put(mut cache map[u64][]GlyphCacheEntry, hash u64, key GlyphKey, value RenderResult) {
	mut bucket := cache[hash]
	for index, entry in bucket {
		if glyph_key_equal(entry.key, key) {
			bucket[index] = GlyphCacheEntry{key, value}
			cache[hash] = bucket
			return
		}
	}
	bucket << GlyphCacheEntry{key, value}
	cache[hash] = bucket
}

// hash_key reproduces GlyphKey.Context.hash: bit-cast the packed 64-bit key,
// then apply Zig 0.15.2's std.hash.int mixer.
fn (k GlyphKey) hash_key() u64 {
	return internal_hash.int_u64(k.packed_key())
}

// The library is shared by every face in a grid and carries the build backend.
pub fn (self SharedGrid) backend() Backend {
	if options := self.resolver.collection.load_options { return options.library.backend }
	return Backend.selected_()
}
