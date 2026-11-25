module vaxis

// InternalCell is the retained previous-frame representation from pinned
// InternalScreen.zig. Public strings borrow private owned byte buffers,
// retaining Source ArrayList fit reuse and borrowed-view mutation behavior.
pub struct InternalCell {
pub mut:
	char_    string
	style    Style
	uri      string
	uri_id   string
	skipped  bool
	default_ bool = true
	skip     bool
	scale    CellScale = CellScale{}
mut:
	char_storage   []u8
	uri_storage    []u8
	uri_id_storage []u8
}

pub fn (old InternalCell) eql(cell Cell) bool {
	if old.default_ && cell.default_ {
		return true
	}
	return old.char_ == cell.char_.grapheme && old.style.eql(cell.style) && old.uri == cell.link.uri
		&& old.uri_id == cell.link.params
}

@[heap]
pub struct InternalScreen {
pub mut:
	width        u16
	height       u16
	buf          []InternalCell @[required]
	cursor_row   u16
	cursor_col   u16
	cursor_vis   bool
	cursor_shape CursorShape = .default
	mouse_shape  MouseShape  = .default
}

// Source allocates usize cells; V arrays use signed int lengths.
fn internal_screen_cell_count(width u16, height u16) int {
	count := uint(width) * uint(height)
	if count > uint(2147483647) { panic('V array length limit') }
	return int(count)
}

pub fn InternalScreen.new(width u16, height u16) InternalScreen {
	// A heap owner keeps pinned V's production GC from repeatedly scanning a
	// scoped aggregate while populating its per-cell owned strings.
	mut screen := &InternalScreen{
		width:  width
		height: height
		buf:    []InternalCell{len: internal_screen_cell_count(width, height)}
	}
	for i in 0 .. screen.buf.len {
		screen.buf[i].char_storage = [u8(32)]
		screen.buf[i].char_ = unsafe { tos(screen.buf[i].char_storage.data, 1) }
	}
	return *screen
}

pub fn (mut s InternalScreen) deinit() {
	s.buf = []InternalCell{}
}

pub fn (mut s InternalScreen) write_cell(col u16, row u16, cell Cell) {
	if s.width < col || s.height < row {
		return
	}
	index := uint(row) * uint(s.width) + uint(col)
	if index >= uint(s.buf.len) { panic('Assertion failed') }
	internal_screen_retained_write(mut s.buf[int(index)], 0, cell.char_.grapheme)
	internal_screen_retained_write(mut s.buf[int(index)], 1, cell.link.uri)
	internal_screen_retained_write(mut s.buf[int(index)], 2, cell.link.params)
	s.buf[int(index)].style = cell.style
	s.buf[int(index)].default_ = cell.default_
}

pub fn (s &InternalScreen) read_cell(col u16, row u16) ?Cell {
	if s.width < col || s.height < row {
		return none
	}
	product := u32(row) * u32(s.width)
	if product > 65535 { panic('integer overflow') }
	index := product + u32(col)
	if index > 65535 { panic('integer overflow') }
	if uint(index) >= uint(s.buf.len) { panic('Assertion failed') }
	cell := s.buf[int(index)]
	return Cell{
		char_:    CellCharacter{
			grapheme: cell.char_
		}
		style:    cell.style
		link:     CellHyperlink{
			uri:    cell.uri
			params: cell.uri_id
		}
		default_: cell.default_
	}
}

// Source ArrayList(u8).growCapacity uses std.atomic.cache_line as its byte
// increment. This covers the native/cross targets supported by this port.
fn internal_screen_growth_increment() uint {
	$if amd64 || arm64 { return 128 }
	$if arm32 { return 32 }
	return 64
}

// Public header updates follow clearRetainingCapacity, ensureTotalCapacity,
// then appendSliceAssumeCapacity: new length is visible before the memcpy.
fn internal_screen_retained_write(mut cell InternalCell, field int, text string) {
	match field {
		0 {
			cell.char_ = internal_screen_retained_view(cell.char_storage, 0)
			internal_screen_retained_prepare(mut cell.char_storage, text.len)
			cell.char_ = internal_screen_retained_view(cell.char_storage, text.len)
			internal_screen_retained_copy(cell.char_storage, text)
		}
		1 {
			cell.uri = internal_screen_retained_view(cell.uri_storage, 0)
			internal_screen_retained_prepare(mut cell.uri_storage, text.len)
			cell.uri = internal_screen_retained_view(cell.uri_storage, text.len)
			internal_screen_retained_copy(cell.uri_storage, text)
		}
		else {
			cell.uri_id = internal_screen_retained_view(cell.uri_id_storage, 0)
			internal_screen_retained_prepare(mut cell.uri_id_storage, text.len)
			cell.uri_id = internal_screen_retained_view(cell.uri_id_storage, text.len)
			internal_screen_retained_copy(cell.uri_id_storage, text)
		}
	}
}

fn internal_screen_retained_prepare(mut storage []u8, length int) {
	if storage.len < length {
		mut capacity := uint(storage.len)
		for capacity < uint(length) {
			capacity += capacity / 2 + internal_screen_growth_increment()
			if capacity > uint(2147483647) { panic('V array length limit') }
		}
		// Source has already cleared its old list length before growth; copying
		// unused old bytes is unnecessary. Allocator remapping/address behavior
		// across growth remains a managed-storage representation boundary.
		storage = []u8{len: int(capacity)}
	}
}

fn internal_screen_retained_view(storage []u8, length int) string {
	if storage.len == 0 { return '' }
	return unsafe { tos(storage.data, length) }
}

fn internal_screen_retained_copy(storage []u8, text string) {
	if text.len > 0 {
		dst := uint(storage.data)
		src := uint(text.str)
		length := uint(text.len)
		if (dst <= src && src - dst < length) || (src < dst && dst - src < length) {
			panic('@memcpy arguments alias')
		}
		unsafe { vmemcpy(storage.data, text.str, text.len) }
	}
}
