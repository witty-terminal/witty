module vaxis

fn test_internal_screen_owns_caller_text_to_detect_later_frame_changes() {
	mut data := 'abcURIid0'.bytes()
	value := Cell{
		char_: CellCharacter{
			grapheme: unsafe { tos(data.data, 3) }
			width:    2
		}
		link:  CellHyperlink{
			uri:    unsafe { tos(&u8(data.data) + 3, 3) }
			params: unsafe { tos(&u8(data.data) + 6, 3) }
		}
		style: Style{
			bold: true
			fg:   ColorIndex{
				index: 5
			}
		}
	}
	mut s := InternalScreen.new(1, 1)
	s.write_cell(0, 0, value)
	read := s.read_cell(0, 0) or { panic('missing') }
	assert s.buf[0].eql(value)
	assert uint(read.char_.grapheme.str) != uint(data.data)
	assert uint(read.link.uri.str) != uint(data.data) + 3
	data[0] = 88
	data[3] = 89
	data[6] = 90
	assert read.char_.grapheme == 'abc' && read.link.uri == 'URI' && read.link.params == 'id0'
	assert !s.buf[0].eql(value)
	s.write_cell(0, 0, value)
	assert (s.read_cell(0, 0) or { panic('missing') }).char_.grapheme == 'Xbc'
	assert s.buf[0].eql(value)
}

fn test_internal_screen_default_cell_differs_from_initialized_space() {
	default := InternalCell{}
	assert default.char_ == '' && default.uri == '' && default.uri_id == ''
	assert default.default_ && !default.skip && !default.skipped
	assert default.scale.eql(CellScale{})
	mut s := InternalScreen.new(1, 1)
	assert s.buf[0].char_ == ' ' && s.buf[0].default_
	assert s.buf[0].eql(Cell{
		default_: true
		char_:    CellCharacter{
			grapheme: 'different'
		}
	})
	assert !s.buf[0].eql(Cell{
		char_: CellCharacter{
			grapheme: 'different'
		}
	})
	s.deinit()
	assert s.buf.len == 0
}

fn test_internal_screen_writes_unallocated_hyperlink_text() {
	mut s := InternalScreen.new(1, 1)
	unsafe {
		s.buf[0].uri.str = nil
		s.buf[0].uri_id.str = nil
	}
	s.write_cell(0, 0, Cell{
		char_: CellCharacter{ grapheme: 'a' }
		link:  CellHyperlink{ uri: 'https://example.org', params: 'id=a' }
	})
	read := s.read_cell(0, 0) or { panic('missing') }
	assert read.char_.grapheme == 'a'
	assert read.link.uri == 'https://example.org'
	assert read.link.params == 'id=a'
}

fn test_internal_screen_keeps_flags_and_ignores_nonretained_cell_metadata() {
	mut s := InternalScreen.new(1, 1)
	s.buf[0].skip = true
	s.buf[0].skipped = true
	s.buf[0].scale = CellScale.init(7, 0, 15, .bottom)
	value := Cell{
		char_:   CellCharacter{
			grapheme: 'a'
			width:    255
		}
		wrapped: true
		image:   ImagePlacement{
			img_id:  1
			options: ImageDrawOptions{}
		}
		scale:   CellScale.init(3, 4, 5, .center)
	}
	s.write_cell(0, 0, value)
	assert s.buf[0].skip && s.buf[0].skipped
	assert s.buf[0].scale.eql(CellScale.init(7, 0, 15, .bottom))
	assert s.buf[0].eql(value)
	read := s.read_cell(0, 0) or { panic('missing') }
	assert read.char_.width == 1 && !read.wrapped && read.image == none
	assert read.scale.eql(CellScale{})
}

fn test_internal_screen_source_strict_edge_bounds_and_current_borrow() {
	mut s := InternalScreen{
		width:  1
		height: 1
		buf:    [InternalCell{}, InternalCell{}, InternalCell{}]
	}
	s.write_cell(1, 0, Cell{
		char_: CellCharacter{
			grapheme: 'a'
		}
	})
	assert (s.read_cell(1, 0) or { panic('strict column edge missing') }).char_.grapheme == 'a'
	s.write_cell(0, 1, Cell{
		char_: CellCharacter{
			grapheme: 'b'
		}
	})
	read := s.read_cell(0, 1) or { panic('strict row edge missing') }
	assert read.char_.grapheme == 'b'
	unsafe {
		read.char_.grapheme.str[0] = 67
	}
	assert s.buf[1].char_ == 'C'
	assert s.read_cell(2, 0) == none
	assert s.read_cell(0, 2) == none
	mut high := InternalScreen{
		width:  65535
		height: 65535
		buf:    [InternalCell{}]
	}
	high.write_cell(0, 0, Cell{
		char_: CellCharacter{
			grapheme: 'a'
		}
	})
	assert (high.read_cell(0, 0) or { panic('missing') }).char_.grapheme == 'a'
}

fn test_internal_screen_old_views_follow_same_capacity_writes() {
	mut s := InternalScreen.new(1, 1)
	s.write_cell(0, 0, Cell{
		char_: CellCharacter{
			grapheme: 'abc'
		}
		link:  CellHyperlink{
			uri:    'URI'
			params: 'id0'
		}
	})
	old := s.read_cell(0, 0) or { panic('missing') }
	s.write_cell(0, 0, Cell{
		char_: CellCharacter{
			grapheme: 'def'
		}
		link:  CellHyperlink{
			uri:    'NEW'
			params: 'id1'
		}
	})
	current := s.read_cell(0, 0) or { panic('missing') }
	assert old.char_.grapheme == 'def' && old.link.uri == 'NEW' && old.link.params == 'id1'
	assert uint(old.char_.grapheme.str) == uint(current.char_.grapheme.str)
	s.write_cell(0, 0, Cell{
		char_: CellCharacter{
			grapheme: 'x'
		}
	})
	assert old.char_.grapheme == 'xef'
	assert (s.read_cell(0, 0) or { panic('missing') }).char_.grapheme == 'x'
}

fn test_internal_screen_initialized_spaces_have_independent_owned_buffers() {
	mut s := InternalScreen.new(2, 1)
	a := s.read_cell(0, 0) or { panic('missing') }
	b := s.read_cell(1, 0) or { panic('missing') }
	assert uint(a.char_.grapheme.str) != uint(b.char_.grapheme.str)
	unsafe {
		a.char_.grapheme.str[0] = 88
	}
	assert s.buf[0].char_ == 'X'
	assert s.buf[1].char_ == ' '
}
