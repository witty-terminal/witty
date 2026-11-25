module terminal

// Kitty graphics protocol image storage.
//
// Source: kitty/graphics_storage.zig
//
// An image storage is associated with a terminal screen (i.e. main
// screen, alt screen) and contains all the transmitted images and
// placements.

import math

// ============================================================
// PlacementTag - distinguishes internal vs external placement IDs
// ============================================================

pub enum PlacementTag as u8 {
	internal
	external
}

// ============================================================
// PlacementId - the placement portion of a PlacementKey
// ============================================================

pub struct PlacementId {
	value u64
}

pub fn PlacementId.init(tag PlacementTag, id u32) PlacementId {
	return PlacementId{
		value: u64(tag) | (u64(id) << 1)
	}
}

pub fn (id PlacementId) tag() PlacementTag {
	return unsafe { PlacementTag(id.value & 0x1) }
}

pub fn (id PlacementId) id() u32 {
	return u32(id.value >> 1)
}

pub fn (id PlacementId) int_val() u64 {
	return id.value
}

fn (id PlacementId) preferred_over(other PlacementId) bool {
	if id.tag() != other.tag() {
		return id.tag() == .external
	}
	return id.id() < other.id()
}

// ============================================================
// PlacementKey - uniquely identifies a placement
// ============================================================

// Every placement is uniquely identified by the image ID and the
// placement ID. If an image ID isn't specified it is assumed to be 0.
// Likewise, if a placement ID isn't specified it is assumed to be 0.
pub struct PlacementKey {
pub:
	image_id     u32
	placement_id PlacementId
}

fn (a PlacementKey) == (b PlacementKey) bool {
	return a.image_id == b.image_id && a.placement_id.int_val() == b.placement_id.int_val()
}

// ============================================================
// Placement - describes where and how an image is drawn
// ============================================================

pub struct Placement {
pub mut:
	// The location where this placement should be drawn.
	location PlacementLocation
	// Offset of the x/y from the top-left of the cell.
	x_offset u32
	y_offset u32
	// Source rectangle for the image to pull from.
	source_x      u32
	source_y      u32
	source_width  u32
	source_height u32
	// The columns/rows this image occupies.
	columns u32
	rows    u32
	// The z-index for this placement.
	z i32
}

// PlacementLocation describes where a placement is anchored.
pub type PlacementLocation = PlacementPin | PlacementVirtual | PlacementRelative

// Exactly placed on a screen pin.
pub struct PlacementPin {
pub:
	pin &Pin = unsafe { nil }
}

// Virtual placement (U=1) for unicode placeholders.
pub struct PlacementVirtual {}

// Anchored to another Kitty placement.
pub struct PlacementRelative {
pub:
	parent        PlacementKey
	column_offset i32
	row_offset    i32
}

pub fn (self &Placement) deinit(mut s Screen) {
	if self.location is PlacementPin {
		s.pages.untrack_pin(self.location.pin)
	}
}

pub struct PlacementSourceRect {
pub:
	x      u32
	y      u32
	width  u32
	height u32
}

// Intersect the requested source rectangle with the image. A zero requested
// extent defaults to the image dimension before intersection.
pub fn (self &Placement) source_rect(image Image) PlacementSourceRect {
	x := math.min(self.source_x, image.width)
	y := math.min(self.source_y, image.height)
	width := if self.source_width > 0 { self.source_width } else { image.width }
	height := if self.source_height > 0 { self.source_height } else { image.height }
	return PlacementSourceRect{
		x:      x
		y:      y
		width:  math.min(width, image.width - x)
		height: math.min(height, image.height - y)
	}
}

fn kitty_cell_offset(offset u32, cell_extent u32) u32 {
	return if cell_extent > 0 { math.min(offset, cell_extent - 1) } else { u32(0) }
}

pub fn (self &Placement) cell_offset(t &Terminal) (u32, u32) {
	return kitty_cell_offset(self.x_offset, t.width_px / u32(t.cols)), kitty_cell_offset(self.y_offset, t.height_px / u32(t.rows))
}

fn scale_kitty_dimension(value u32, numerator u32, denominator u32) u32 {
	if denominator == 0 {
		return 0
	}
	rounded := (u64(value) * numerator + denominator / 2) / denominator
	return u32(math.min(rounded, u64(max_u32)))
}

// Calculate the drawn extent after applying the source crop and cell offsets.
pub fn (self &Placement) calculated_size(image Image, t &Terminal) (u32, u32) {
	source := self.source_rect(image)
	if self.columns == 0 && self.rows == 0 {
		return source.width, source.height
	}

	cell_width := t.width_px / u32(t.cols)
	cell_height := t.height_px / u32(t.rows)
	if self.columns > 0 {
		width := scale_kitty_dimension(cell_width, self.columns, 1) - kitty_cell_offset(self.x_offset, cell_width)
		if self.rows == 0 {
			return width, scale_kitty_dimension(width, source.height, source.width)
		}
		height := scale_kitty_dimension(cell_height, self.rows, 1) - kitty_cell_offset(self.y_offset, cell_height)
		return width, height
	}

	height := scale_kitty_dimension(cell_height, self.rows, 1) - kitty_cell_offset(self.y_offset, cell_height)
	return scale_kitty_dimension(height, source.width, source.height), height
}

fn kitty_grid_extent(pixels u32, offset u32, cell_extent u32) u32 {
	if cell_extent == 0 {
		return 0
	}
	extent := math.min(u64(pixels) + offset, u64(max_u32))
	return u32((extent + cell_extent - 1) / cell_extent)
}

// Returns the size in grid cells that this placement takes up.
pub fn (self &Placement) grid_size(image Image, t &Terminal) (u32, u32) {
	// If we have a specified columns and rows then this is trivial.
	if self.columns > 0 && self.rows > 0 {
		return self.columns, self.rows
	}

	calc_width, calc_height := self.calculated_size(image, t)
	cell_width := t.width_px / u32(t.cols)
	cell_height := t.height_px / u32(t.rows)
	return kitty_grid_extent(calc_width, kitty_cell_offset(self.x_offset, cell_width), cell_width),
		kitty_grid_extent(calc_height, kitty_cell_offset(self.y_offset, cell_height), cell_height)
}

// Returns a rect of the entire rectangle this placement
// occupies within the screen. Returns none if the placement
// doesn't have an associated rect (i.e. a virtual placement).
pub fn (self &Placement) rect(image Image, t &Terminal) ?Rect {
	pin := match self.location {
		PlacementPin { self.location.pin }
		else { return none }
	}
	if isnil(pin) || pin.garbage {
		return none
	}

	grid_cols, grid_rows := self.grid_size(image, t)
	if grid_cols == 0 || grid_rows == 0 {
		return none
	}

	overflow := pin.down_overflow(uint(grid_rows) - 1)
	mut br := match overflow {
		DownOverflowOffset { overflow.pin }
		DownOverflowOverflow { overflow.end }
	}
	br.x = u16(math.min(u64(pin.x) + grid_cols - 1, u64(t.cols) - 1))

	return Rect{
		top_left:     *pin
		bottom_right: br
	}
}

// ============================================================
// PlacementEntry - a key-value pair for the placement map
// ============================================================

pub struct PlacementEntry {
pub mut:
	key   PlacementKey
	value Placement
}

struct KittyScrollPin {
	pin      &Pin
	position Coordinate
}

// Record the placement positions before the row operation changes tracked pins.
// In-place scrolls only affect pins in the affected rows, whereas scrolling
// into history can shift pins throughout the active area.
fn (t &Terminal) prepare_kitty_scroll(delta int, shifts_window bool) []KittyScrollPin {
	region := t.scrolling_region
	mut screen := t.screens.active
	mut storage := &screen.kitty_images
	if storage.placements.len == 0 || delta == 0
		|| (region.top == 0 && region.bottom == t.rows - 1 && region.left == 0
		&& region.right == t.cols - 1) {
		return []
	}

	mut restores := []KittyScrollPin{}
	placement_count := storage.placements.len
	mut i := 0
	for i < storage.placements.len {
		entry := storage.placements[i]
		mut placement := entry.value
		i++
		pin := match placement.location {
			PlacementPin { placement.location.pin }
			else { continue }
		}
		if isnil(pin) || pin.garbage {
			continue
		}
		point := screen.pages.point_from_pin(.active, *pin) or { continue }
		mut position := point.coord()
		if !shifts_window && (position.y < region.top || position.y > region.bottom) {
			continue
		}

		if image := storage.image_by_id(entry.key.image_id) {
			position.y = placement.scroll_within_margins(t, image, position, delta) or {
				// Keep the transmitted image available for subsequent placements.
				placement.deinit(mut screen)
				i--
				storage.placements.delete(i)
				storage.dirty = true
				continue
			}
			storage.placements[i - 1].value = placement
		}
		restores << KittyScrollPin{
			pin:      pin
			position: position
		}
	}
	if storage.placements.len != placement_count {
		storage.remove_orphans(false)
	}
	return restores
}

fn (t &Terminal) restore_kitty_scroll(restores []KittyScrollPin) {
	if restores.len == 0 {
		return
	}
	mut screen := t.screens.active
	for restore in restores {
		new_pin := screen.pages.pin(Point.new(.active, restore.position)) or { continue }
		mut pin := unsafe { restore.pin }
		unsafe { *pin = new_pin }
	}
	screen.kitty_images.dirty = true
}

fn (mut p Placement) scroll_within_margins(t &Terminal, image Image, position Coordinate, delta int) ?u32 {
	region := t.scrolling_region
	cols, rows := p.grid_size(image, t)
	x, y := i64(position.x), i64(position.y)
	// Only placements wholly inside the scrolling rectangle move.
	if cols == 0 || rows == 0 || y < region.top || y + rows - 1 > region.bottom
		|| x < region.left || math.min(x + cols - 1, i64(t.cols) - 1) > region.right {
		return position.y
	}

	new_y := y + delta
	top_clip := math.max(i64(0), i64(region.top) - new_y)
	bottom_clip := math.max(i64(0), new_y + rows - 1 - i64(region.bottom))
	if top_clip >= rows || bottom_clip >= rows {
		return none
	}
	if top_clip + bottom_clip > 0
		&& !p.clip_scroll_rows(image, t.height_px / u32(t.rows), rows, u32(top_clip), u32(bottom_clip)) {
		return none
	}
	return u32(math.max(new_y, i64(region.top)))
}

// Materialize the source rectangle so clipped portions stay gone after
// subsequent scrolls. A zero source extent would request the full image.
fn (mut p Placement) clip_scroll_rows(image Image, cell_height u32, span u32, top u32, bottom u32) bool {
	source := p.source_rect(image)
	height := source.height
	if source.width == 0 || height == 0 {
		return false
	}

	mut source_y := source.y
	mut source_height := height
	if p.rows > 0 {
		crop := u32(u64(height) * (top + bottom) / span)
		if top + bottom >= p.rows || crop >= height {
			return false
		}
		if top > 0 {
			source_y += crop
		}
		source_height -= crop
		p.rows -= top + bottom
	} else if top > 0 {
		crop := u64(cell_height) * top
		if crop >= height {
			return false
		}
		source_y += u32(crop)
		source_height -= u32(crop)
	} else {
		visible := u64(cell_height) * (span - bottom)
		offset_y := kitty_cell_offset(p.y_offset, cell_height)
		if visible <= offset_y {
			return false
		}
		source_height = u32(math.min(u64(height), visible - offset_y))
	}
	p.source_x = source.x
	p.source_y = source_y
	p.source_width = source.width
	p.source_height = source_height
	return true
}

// ============================================================
// ImageStorage
// ============================================================

pub struct ImageStorage {
pub mut:
	// Dirty is set to true if placements or images change. This is
	// purely informational for the renderer and doesn't affect the
	// correctness of the program. The renderer must set this to false
	// if it cares about this value.
	dirty bool

	// This is the next candidate for an automatically assigned image ID.
	next_image_id u32 = 2147483647

	// This is the next automatically assigned placement ID. This is never
	// user-facing so we can start at 0. This is 32-bits because we use
	// the same space for external placement IDs. We can start at zero
	// because any number is valid.
	next_internal_placement_id u32

	// The set of images that are currently known.
	images map[u32]Image

	// The set of placements for loaded images.
	placements []PlacementEntry

	// Non-null if there is an in-progress loading image.
	loading ?&LoadingImage
	animations_idle bool = true

	// The total bytes of image data that have been loaded and the limit.
	// If the limit is reached, the oldest images will be evicted to make
	// space. Unused images take priority.
	total_bytes uint
	total_limit uint = 320 * 1000 * 1000 // 320MB
}

fn (mut self ImageStorage) abort_loading() {
	if mut loading := self.loading {
		loading.destroy()
		self.loading = none
	}
}

// Deinitialize the storage, freeing all images and placements.
pub fn (mut self ImageStorage) deinit(mut s Screen) {
	self.abort_loading()

	for _, mut img in self.images {
		img.deinit()
	}
	self.images = map[u32]Image{}

	self.clear_placements(mut s)
	self.placements = []
	self.animations_idle = true
}

// Kitty image protocol is enabled if we have a non-zero limit.
pub fn (self &ImageStorage) enabled() bool {
	return self.total_limit != 0
}

// Sets the limit in bytes for the total amount of image data that
// can be loaded. If this limit is lower, this will do an eviction
// if necessary. If the value is zero, then Kitty image protocol will
// be disabled.
pub fn (mut self ImageStorage) set_limit(mut s Screen, limit uint) {
	// Special case disabling by quickly deleting all
	if limit == 0 {
		self.deinit(mut s)
		self.images = map[u32]Image{}
		self.placements = []
		self.total_bytes = 0
		self.total_limit = 0
		self.dirty = false
		self.next_image_id = 2147483647
		self.next_internal_placement_id = 0
		return
	}

	// If we're lowering our limit, check if we need to evict.
	if limit < self.total_bytes {
		req_bytes := self.total_bytes - limit
		self.evict_image(mut s, req_bytes, none)
	}

	self.total_limit = limit
}

fn (mut self ImageStorage) allocate_image_id() u32 {
	mut id := self.next_image_id
	for id == 0 || id in self.images {
		id++
	}
	self.next_image_id = if id == max_u32 { u32(1) } else { id + 1 }
	return id
}

// Store a completed transmission. Reusing an ID removes the old image and
// its placements. The new data can be placed after the transmission commits.
pub fn (mut self ImageStorage) add_image(mut s Screen, img Image) ! {
	new_len := img.storage_size()
	if new_len > self.total_limit {
		return error('OutOfMemory: image exceeds total limit')
	}

	existing := self.image_by_id(img.id)
	old_len := if old := existing { old.storage_size() } else { uint(0) }
	used_bytes := self.total_bytes - old_len
	available_bytes := self.total_limit - new_len
	if used_bytes > available_bytes {
		if !self.evict_image(mut s, used_bytes - available_bytes, img.id) {
			return error('OutOfMemory: failed to evict enough images')
		}
	}

	mut stored := img
	if old := existing {
		self.delete_by_id(mut s, img.id, 0, false)
		self.delete_if_unused(img.id)
		// The renderer compares timestamps to detect replacement pixels.
		if stored.transmit_time <= old.transmit_time {
			stored.transmit_time = old.transmit_time + 1
		}
	}

	self.images[img.id] = stored
	self.total_bytes += new_len
	self.dirty = true
}

// Add a placement for an existing image. Storage takes ownership of its pin.
pub fn (mut self ImageStorage) add_placement(mut s Screen, image_id u32, placement_id u32, p Placement) {
	assert image_id in self.images
	if self.images[image_id].animation.state != .stop {
		self.animations_idle = false
	}

	// Reclaim anchors pruned with scrollback outside the scrolling hot path.
	self.reap_placements(mut s, false)

	// The important piece here is that the placement ID needs to
	// be marked internal if it is zero. This allows multiple placements
	// to be added for the same image. If it is non-zero, then it is
	// an external placement ID and we can only have one placement
	// per (image id, placement id) pair.
	key := PlacementKey{
		image_id:     image_id
		placement_id: if placement_id == 0 {
			pid := self.next_internal_placement_id
			self.next_internal_placement_id += 1
			PlacementId.init(.internal, pid)
		} else {
			PlacementId.init(.external, placement_id)
		}
	}

	// Check if entry already exists; if so, overwrite
	for mut entry in self.placements {
		if entry.key == key {
			entry.value.deinit(mut s)
			entry.value = p
			self.dirty = true
			return
		}
	}

	self.placements << PlacementEntry{
		key:   key
		value: p
	}
	self.dirty = true
}

// Keep image data while releasing anchors whose rows are gone. Before
// erasing history, also release anchors still in the rows about to be erased.
fn (mut self ImageStorage) reap_placements(mut s Screen, erase_history bool) {
	placement_count := self.placements.len
	mut i := 0
	for i < self.placements.len {
		placement := self.placements[i].value
		location := placement.location
		if location is PlacementPin {
			pin := location.pin
			if isnil(pin) || pin.garbage || (erase_history && !s.pages.pin_is_active(*pin)) {
				placement.deinit(mut s)
				self.placements.delete(i)
				self.dirty = true
				continue
			}
		}
		i++
	}
	if self.placements.len != placement_count {
		self.remove_orphans(false)
	}
}

fn (mut self ImageStorage) clear_placements(mut s Screen) {
	for entry in self.placements {
		entry.value.deinit(mut s)
	}
	self.placements.clear()
}

// Remove fixed placements that intersect the active screen. Relative placements
// follow their parents' lifetime, and virtual placements belong to text cells.
fn (mut self ImageStorage) delete_visible_placements(mut t Terminal, delete_unused bool) {
	mut screen := t.screens.active
	mut i := 0
	for i < self.placements.len {
		entry := self.placements[i]
		location := entry.value.location
		pin := match location {
			PlacementPin { location.pin }
			else {
				i++
				continue
			}
		}
		if isnil(pin) || pin.garbage {
			i++
			continue
		}
		if !screen.pages.pin_is_active(*pin) {
			image := self.image_by_id(entry.key.image_id) or {
				i++
				continue
			}
			rect := entry.value.rect(image, &t) or {
				i++
				continue
			}
			if !screen.pages.pin_is_active(rect.bottom_right) {
				i++
				continue
			}
		}

		entry.value.deinit(mut screen)
		self.placements.delete(i)
		if delete_unused {
			self.delete_if_unused(entry.key.image_id)
		}
	}
	self.remove_orphans(delete_unused)
	self.dirty = true
}

// A terminal display erase also drops any transmitted data without placements.
pub fn (mut self ImageStorage) clear_screen_images(mut t Terminal) {
	self.delete_visible_placements(mut t, true)
	for id in self.images.keys() {
		self.delete_if_unused(id)
	}
}

// Get an image by its ID. If the image doesn't exist, return none.
pub fn (self &ImageStorage) image_by_id(image_id u32) ?Image {
	if image_id in self.images {
		return self.images[image_id]
	}
	return none
}

// Get an image by its number. If the image doesn't exist, return none.
pub fn (self &ImageStorage) image_by_number(image_number u32) ?Image {
	mut newest := ?Image(none)

	for _, img in self.images {
		if img.number == image_number {
			if n := newest {
				// Compare transmit times; keep the newer one
				if img.transmit_time > n.transmit_time {
					newest = img
				}
			} else {
				newest = img
			}
		}
	}

	return newest
}

// Delete placements, images.
pub fn (mut self ImageStorage) delete(mut t Terminal, cmd Delete) {
	match cmd {
		DeleteAll {
			self.delete_visible_placements(mut t, cmd.delete)
		}
		DeleteById {
			self.delete_by_id(mut t.screens.active, cmd.image_id, cmd.placement_id, cmd.delete)
		}
		DeleteByNewest {
			img := self.image_by_number(cmd.image_number) or { return }
			self.delete_by_id(mut t.screens.active, img.id, cmd.placement_id, cmd.delete)
		}
		DeleteIntersectCursor {
			self.delete_intersecting(mut t, Point.new(.active, Coordinate{
				x: u16(t.screens.active.cursor.x)
				y: t.screens.active.cursor.y
			}), cmd.delete, none)
		}
		DeleteIntersectCell {
			if cmd.x <= 0 || cmd.y <= 0 {
				return
			}
			if cmd.x - 1 > max_u16 || cmd.y - 1 > max_u16 {
				return
			}
			self.delete_intersecting(mut t, Point.new(.active, Coordinate{
				x: u16(cmd.x - 1)
				y: cmd.y - 1
			}), cmd.delete, none)
		}
		DeleteIntersectCellZ {
			if cmd.x <= 0 || cmd.y <= 0 {
				return
			}
			if cmd.x - 1 > max_u16 || cmd.y - 1 > max_u16 {
				return
			}
			self.delete_intersecting(mut t, Point.new(.active, Coordinate{
				x: u16(cmd.x - 1)
				y: cmd.y - 1
			}), cmd.delete, cmd.z)
		}
		DeleteColumn {
			if cmd.x <= 0 {
				return
			}
			x := cmd.x - 1
			mut i := 0
			for i < self.placements.len {
				entry := self.placements[i]
				img := self.image_by_id(entry.key.image_id) or {
					i++
					continue
				}
				r := entry.value.rect(img, t) or {
					i++
					continue
				}
				if r.top_left.x <= x && r.bottom_right.x >= x {
					entry.value.deinit(mut t.screens.active)
					self.placements.delete(i)
					if cmd.delete {
						self.delete_if_unused(img.id)
					}
				} else {
					i++
				}
			}
			self.remove_orphans(cmd.delete)
			self.dirty = true
		}
		DeleteRow {
			if cmd.y <= 0 {
				return
			}
			// cmd.y is in active coords so we want to convert it to a pin
			// so we can compare by page offsets.
			if cmd.y - 1 > max_u16 {
				return
			}
			target_pin := t.screens.active.pages.pin(Point.new(.active, Coordinate{
				y: cmd.y - 1
			})) or { return }

			mut i := 0
			for i < self.placements.len {
				entry := self.placements[i]
				img := self.image_by_id(entry.key.image_id) or {
					i++
					continue
				}
				r := entry.value.rect(img, t) or {
					i++
					continue
				}
				// We need to copy our pin to ensure we are at least at
				// the top-left x.
				mut target_pin_copy := target_pin
				target_pin_copy.x = r.top_left.x
				if target_pin_copy.is_between(r.top_left, r.bottom_right) {
					entry.value.deinit(mut t.screens.active)
					self.placements.delete(i)
					if cmd.delete {
						self.delete_if_unused(img.id)
					}
				} else {
					i++
				}
			}
			self.remove_orphans(cmd.delete)
			self.dirty = true
		}
		DeleteZ {
			mut i := 0
			for i < self.placements.len {
				entry := self.placements[i]
				// Virtual placeholders cannot delete by z according to the spec.
				if entry.value.location is PlacementVirtual {
					i++
					continue
				}
				if entry.value.z == cmd.z {
					image_id := entry.key.image_id
					entry.value.deinit(mut t.screens.active)
					self.placements.delete(i)
					if cmd.delete {
						self.delete_if_unused(image_id)
					}
				} else {
					i++
				}
			}
			self.remove_orphans(cmd.delete)
			self.dirty = true
		}
		DeleteRange {
			if cmd.last == 0 || cmd.first > cmd.last {
				return
			}
			mut i := 0
			for i < self.placements.len {
				entry := self.placements[i]
				if entry.key.image_id >= cmd.first && entry.key.image_id <= cmd.last {
					entry.value.deinit(mut t.screens.active)
					self.placements.delete(i)
				} else {
					i++
				}
			}
			if cmd.delete {
				for id in self.images.keys() {
					if id >= cmd.first && id <= cmd.last {
						self.delete_if_unused(id)
					}
				}
			}
			self.remove_orphans(cmd.delete)
			self.dirty = true
		}

		DeleteAnimationFrames {
			self.delete_animation_frame(mut t.screens.active, cmd)
		}
	}
}

fn (mut self ImageStorage) delete_by_id(mut s Screen, image_id u32, placement_id u32, delete_unused bool) {
	mut matched := placement_id == 0
	// If no placement, we delete all placements with the ID
	if placement_id == 0 {
		mut i := 0
		for i < self.placements.len {
			entry := self.placements[i]
			if entry.key.image_id == image_id {
				entry.value.deinit(mut s)
				self.placements.delete(i)
			} else {
				i++
			}
		}
	} else {
		target_key := PlacementKey{
			image_id:     image_id
			placement_id: PlacementId.init(.external, placement_id)
		}
		for i, entry in self.placements {
			if entry.key == target_key {
				entry.value.deinit(mut s)
				self.placements.delete(i)
				matched = true
				break
			}
		}
	}

	self.remove_orphans(delete_unused)
	// If this is specified, then we also delete the image
	// if it is no longer in use.
	if delete_unused && matched {
		self.delete_if_unused(image_id)
	}

	// Mark dirty to force redraw
	self.dirty = true
}

// Delete an image if it is unused.
fn (mut self ImageStorage) delete_if_unused(image_id u32) {
	for entry in self.placements {
		if entry.key.image_id == image_id {
			return
		}
	}

	// If we get here, we can delete the image.
	if image_id in self.images {
		img := self.images[image_id]
		self.total_bytes -= img.storage_size()
		mut img_mut := self.images[image_id]
		img_mut.deinit()
		self.images.delete(image_id)
	}
}

// Deletes all placements intersecting a screen point. `z` is the
// intersect_cell_z filter context: when set, only placements at that
// z-index are deleted.
fn (mut self ImageStorage) delete_intersecting(mut t Terminal, p Point, delete_unused bool, z ?i32) {
	// Convert our target point to a pin for comparison.
	target_pin := t.screens.active.pages.pin(p) or { return }

	mut i := 0
	for i < self.placements.len {
		entry := self.placements[i]
		img := self.image_by_id(entry.key.image_id) or {
			i++
			continue
		}
		r := entry.value.rect(img, t) or {
			i++
			continue
		}
		if r.contains(target_pin) {
			if filter_z := z {
				if entry.value.z != filter_z {
					i++
					continue
				}
			}
			entry.value.deinit(mut t.screens.active)
			self.placements.delete(i)
			if delete_unused {
				self.delete_if_unused(img.id)
			}
		} else {
			i++
		}
	}

	self.remove_orphans(delete_unused)
	// Mark dirty to force redraw
	self.dirty = true
}

// Evict images to make space. This will evict the oldest image,
// prioritizing unused images first, as recommended by the published
// Kitty spec.
//
// This will evict as many images as necessary to make space for
// req bytes.
fn (mut self ImageStorage) evict_image(mut s Screen, req uint, exclude_id ?u32) bool {
	// Build candidate list
	mut candidates := []EvictCandidate{cap: self.images.len}

	for _, img in self.images {
		if id := exclude_id {
			if img.id == id {
				continue
			}
		}
		// Check if image is in use
		mut used := false
		for entry in self.placements {
			if entry.key.image_id == img.id {
				used = true
				break
			}
		}
		candidates << EvictCandidate{
			id:   img.id
			time: img.transmit_time
			used: used
		}
	}

	// Sort candidates: unused first, then by time (oldest first)
	candidates.sort_with_compare(fn (a &EvictCandidate, b &EvictCandidate) int {
		// If usage matches, sort by time
		if a.used == b.used {
			if a.time < b.time {
				return -1
			}
			if a.time > b.time {
				return 1
			}
			if a.id < b.id {
				return -1
			}
			if a.id > b.id {
				return 1
			}
			return 0
		}
		// Unused is a better candidate (comes first)
		if !a.used {
			return -1
		}
		return 1
	})

	// They're in order of best to evict.
	mut evicted := uint(0)
	for c in candidates {
		img := self.image_by_id(c.id) or { continue }
		evicted += img.storage_size()
		self.delete_by_id(mut s, c.id, 0, false)
		self.delete_if_unused(c.id)
		if evicted >= req {
			return true
		}
	}

	return false
}

// Get a placement by key.
pub fn (self &ImageStorage) get_placement(key PlacementKey) ?Placement {
	for entry in self.placements {
		if entry.key == key {
			return entry.value
		}
	}
	return none
}

// Prefer explicit IDs, then the lowest ID within each kind.
fn (self &ImageStorage) best_placement(image_id u32, virtual_only bool) ?PlacementEntry {
	mut best := ?PlacementEntry(none)
	for entry in self.placements {
		if entry.key.image_id != image_id || (virtual_only && entry.value.location !is PlacementVirtual) {
			continue
		}
		if current := best {
			if !entry.key.placement_id.preferred_over(current.key.placement_id) {
				continue
			}
		}
		best = entry
	}
	return best
}

// A placeholder with no placement ID selects a virtual placement.
pub fn (self &ImageStorage) placeholder_target(image_id u32, placement_id u32) ?PlacementEntry {
	if placement_id == 0 {
		return self.best_placement(image_id, true)
	}
	key := PlacementKey{
		image_id:     image_id
		placement_id: PlacementId.init(.external, placement_id)
	}
	return PlacementEntry{ key: key, value: self.get_placement(key)? }
}

const kitty_parent_chain_limit = 8

fn (mut self ImageStorage) resolve_parent(mut screen Screen, child ?PlacementKey, image_id u32, placement_id u32) !PlacementKey {
	self.reap_placements(mut screen, false)
	if image_id !in self.images {
		return error('ENOPARENT: parent image not found')
	}
	missing := 'ENOPARENT: parent placement not found'
	parent := if placement_id == 0 {
		entry := self.best_placement(image_id, false) or { return error(missing) }
		entry.key
	} else {
		key := PlacementKey{ image_id: image_id, placement_id: PlacementId.init(.external, placement_id) }
		self.get_placement(key) or { return error(missing) }
		key
	}
	if child_key := child {
		if child_key == parent {
			return error('EINVAL: placement cannot be its own parent')
		}
	}
	mut key := parent
	for _ in 0 .. kitty_parent_chain_limit {
		if child_key := child {
			if child_key == key {
				return error('ECYCLE: parent chain creates a cycle')
			}
		}
		placement := self.get_placement(key) or { return error('ENOENT: parent chain ancestor not found') }
		location := placement.location
		if location is PlacementRelative {
			key = location.parent
		} else {
			return parent
		}
	}
	return error('ETOODEEP: parent chain too deep')
}

pub struct KittyRelativeChain {
pub:
	root          PlacementEntry
	column_offset i64
	row_offset    i64
}

// Follow the parent chain to a fixed or virtual root and accumulate cell offsets.
pub fn (self &ImageStorage) resolve_relative_chain(relative PlacementRelative) ?KittyRelativeChain {
	mut key := relative.parent
	mut x := i64(relative.column_offset)
	mut y := i64(relative.row_offset)
	for _ in 0 .. kitty_parent_chain_limit {
		placement := self.get_placement(key)?
		location := placement.location
		if location is PlacementRelative {
			x = math.min(math.max(x + location.column_offset, i64(min_i32)), i64(max_i32))
			y = math.min(math.max(y + location.row_offset, i64(min_i32)), i64(max_i32))
			key = location.parent
			continue
		}
		return KittyRelativeChain{
			root:          PlacementEntry{ key: key, value: placement }
			column_offset: x
			row_offset:    y
		}
	}
	return none
}

// A parent removal can leave an entire chain orphaned.
fn (mut self ImageStorage) remove_orphans(delete_unused bool) {
	for {
		mut removed := false
		mut i := 0
		for i < self.placements.len {
			entry := self.placements[i]
			location := entry.value.location
			if location is PlacementRelative && self.get_placement(location.parent) == none {
				self.placements.delete(i)
				if delete_unused {
					self.delete_if_unused(entry.key.image_id)
				}
				removed = true
				continue
			}
			i++
		}
		if !removed {
			return
		}
		self.dirty = true
	}
}

// Count the number of placements.
pub fn (self &ImageStorage) placement_count() int {
	return self.placements.len
}

// Count the number of images.
pub fn (self &ImageStorage) image_count() int {
	return self.images.len
}

// ============================================================
// EvictCandidate - internal helper for eviction sorting
// ============================================================

struct EvictCandidate {
	id   u32
	time u64
	used bool
}

// ============================================================
// Helpers
// ============================================================

// Our pin for the placement
fn track_pin(mut t Terminal, pt Coordinate) !&Pin {
	return t.screens.active.pages.track_pin(t.screens.active.pages.pin(Point.new(.active,
		pt)) or { panic('placement point is outside the active area') })!
}
