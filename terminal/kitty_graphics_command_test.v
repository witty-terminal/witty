module terminal

fn test_graphics_command_source_tag_layouts_and_ordinals() {
	assert sizeof(CommandParserState) == 1
	assert u8(CommandParserState.control_key) == 0
	assert u8(CommandParserState.control_key_ignore) == 1
	assert u8(CommandParserState.control_value) == 2
	assert u8(CommandParserState.control_value_ignore) == 3
	assert u8(CommandParserState.data) == 4
	assert sizeof(CommandAction) == 1
	assert u8(CommandAction.query) == 0
	assert u8(CommandAction.transmit) == 1
	assert u8(CommandAction.transmit_and_display) == 2
	assert u8(CommandAction.display) == 3
	assert u8(CommandAction.delete_) == 4
	assert u8(CommandAction.transmit_animation_frame) == 5
	assert u8(CommandAction.control_animation) == 6
	assert u8(CommandAction.compose_animation) == 7
	assert sizeof(Quiet) == 1
	assert u8(Quiet.no) == 0
	assert u8(Quiet.ok) == 1
	assert u8(Quiet.failures) == 2
	assert sizeof(TransmissionFormat) == 1
	assert u8(TransmissionFormat.rgb) == 0
	assert u8(TransmissionFormat.rgba) == 1
	assert u8(TransmissionFormat.png) == 2
	assert u8(TransmissionFormat.gray_alpha) == 3
	assert u8(TransmissionFormat.gray) == 4
	assert sizeof(TransmissionMedium) == 1
	assert u8(TransmissionMedium.direct) == 0
	assert u8(TransmissionMedium.file) == 1
	assert u8(TransmissionMedium.temporary_file) == 2
	assert u8(TransmissionMedium.shared_memory) == 3
	assert sizeof(TransmissionCompression) == 1
	assert u8(TransmissionCompression.none_) == 0
	assert u8(TransmissionCompression.zlib_deflate) == 1
	assert sizeof(CursorMovement) == 1
	assert u8(CursorMovement.after) == 0
	assert u8(CursorMovement.none_) == 1
	assert sizeof(AnimationAction) == 1
	assert u8(AnimationAction.invalid) == 0
	assert u8(AnimationAction.stop) == 1
	assert u8(AnimationAction.run_wait) == 2
	assert u8(AnimationAction.run) == 3
	assert sizeof(CompositionMode) == 1
	assert u8(CompositionMode.alpha_blend) == 0
	assert u8(CompositionMode.overwrite) == 1
}

fn test_transmission_command() {
	input := 'f=24,s=10,v=20'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlTransmit
	v := (command.control as ControlTransmit).transmission
	assert v.format_ == .rgb
	assert v.width == 10
	assert v.height == 20
}

fn test_transmission_ignores_m_if_medium_is_not_direct() {
	input := 'a=t,t=t,m=1'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlTransmit
	v := (command.control as ControlTransmit).transmission
	assert v.medium == .temporary_file
	assert !v.more_chunks
}

fn test_transmission_respects_m_if_medium_is_direct() {
	input := 'a=t,t=d,m=1'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlTransmit
	v := (command.control as ControlTransmit).transmission
	assert v.medium == .direct
	assert v.more_chunks
}

fn test_query_command() {
	input := 'i=31,s=1,v=1,a=q,t=d,f=24;QUFBQQ'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlQuery
	v := (command.control as ControlQuery).transmission
	assert v.medium == .direct
	assert v.width == 1
	assert v.height == 1
	assert v.image_id == 31
	assert command.data == 'AAAA'.bytes()
}

fn test_display_command() {
	input := 'a=p,U=1,i=31,c=80,r=120'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Display
	v := command.control as Display
	assert v.columns == 80
	assert v.rows == 120
	assert v.image_id == 31
}

fn test_delete_command() {
	input := 'a=d,d=p,x=3,y=4'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Delete
	fd := command.control as Delete
	assert fd is DeleteIntersectCell
	dv := fd as DeleteIntersectCell
	assert !dv.delete
	assert dv.x == 3
	assert dv.y == 4
}

fn test_no_control_data() {
	input := ';QUFBQQ'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlTransmit
	assert command.data == 'AAAA'.bytes()
}

fn test_invalid_base64_payload() {
	CommandParser.parse_string(';AA!A') or {
		assert err.msg().contains('InvalidData')
		return
	}
	assert false, 'expected invalid payload data'
}

fn test_command_to_owned_data_clears_command_data() {
	mut command := CommandParser.parse_string(';QUFBQQ') or { panic(err) }
	data := command.to_owned_data()
	assert data == 'AAAA'.bytes()
	assert command.data.len == 0
}

fn test_command_deinit_clears_data() {
	mut command := CommandParser.parse_string(';QUFBQQ') or { panic(err) }
	command.deinit()
	assert command.data.len == 0
}

fn test_ignore_unknown_keys_long() {
	input := 'f=24,s=10,v=20,hello=world'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlTransmit
	v := (command.control as ControlTransmit).transmission
	assert v.format_ == .rgb
	assert v.width == 10
	assert v.height == 20
}

fn test_ignore_very_long_values() {
	// Very long value should overflow and be treated as 0
	input := 'f=24,s=10,v=2000000000000000000000000000000000000000'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is ControlTransmit
	v := (command.control as ControlTransmit).transmission
	assert v.format_ == .rgb
	assert v.width == 10
	// Very long value overflows the accumulator and gets ignored
	assert v.height == 0
}

fn test_response_encode_nothing_without_id_or_image_number() {
	r := Response{}
	assert r.encode() == ''
}

fn test_response_encode_with_only_image_id() {
	r := Response{ id: 4 }
	assert r.encode() == '\x1b_Gi=4;OK\x1b\\'
}

fn test_response_encode_with_only_image_number() {
	r := Response{ image_number: 4 }
	assert r.encode() == '\x1b_GI=4;OK\x1b\\'
}

fn test_response_encode_with_image_id_and_number() {
	r := Response{ id: 12, image_number: 4 }
	assert r.encode() == '\x1b_Gi=12,I=4;OK\x1b\\'
}

fn test_delete_range_command_1() {
	input := 'a=d,d=r,x=3,y=4'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Delete
	fd := command.control as Delete
	assert fd is DeleteRange
	range_ := fd as DeleteRange
	assert !range_.delete
	assert range_.first == 3
	assert range_.last == 4
}

fn test_delete_range_command_2() {
	input := 'a=d,d=R,x=5,y=11'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Delete
	fd := command.control as Delete
	assert fd is DeleteRange
	range_ := fd as DeleteRange
	assert range_.delete
	assert range_.first == 5
	assert range_.last == 11
}

fn test_delete_range_command_preserves_inverted_bounds() ! {
	command := CommandParser.parse_string('a=d,d=R,x=5,y=4')!
	range_ := (command.control as Delete) as DeleteRange
	assert range_.first == 5
	assert range_.last == 4
}

fn test_delete_range_command_defaults_omitted_bounds_to_zero() ! {
	without_last := CommandParser.parse_string('a=d,d=R,x=5')!
	assert ((without_last.control as Delete) as DeleteRange).last == 0
	without_first := CommandParser.parse_string('a=d,d=R,y=5')!
	assert ((without_first.control as Delete) as DeleteRange).first == 0
}

fn test_ensure_large_negative_values() {
	input := 'a=p,i=1,z=-2000000000'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Display
	v := command.control as Display
	assert v.image_id == 1
	assert v.z == -2000000000
}

fn test_animation_frame_background_retains_packed_rgba_word() {
	assert sizeof(AnimBackground) == 4
	command := CommandParser.parse_string('a=f,Y=1144201745') or { panic(err) }
	assert command.control is AnimationFrameLoading
	frame := command.control as AnimationFrameLoading
	assert frame.background.int() == u32(0x44332211)
	assert frame.background.r() == 0x11
	assert frame.background.g() == 0x22
	assert frame.background.b() == 0x33
	assert frame.background.a() == 0x44
}

fn test_integer_fields_match_zig_parse_int_grammar() {
	command := CommandParser.parse_string('a=p,i=4__2,z=-2__0,H=+3,V=-0') or { panic(err) }
	assert command.control is Display
	display := command.control as Display
	assert display.image_id == 42
	assert display.z == -20
	assert display.horizontal_offset == 3
	assert display.vertical_offset == 0
}

fn test_ensure_proper_overflow_error_for_u32() {
	input := 'a=p,i=10000000000'
	CommandParser.parse_string(input) or {
		assert err.msg().contains('Overflow')
		return
	}
	assert false, 'expected overflow error'
}

fn test_ensure_u32_overflow_with_ten_digits_is_rejected() {
	input := 'a=p,i=4294967296'
	CommandParser.parse_string(input) or {
		assert err.msg().contains('Overflow')
		return
	}
	assert false, 'expected overflow error'
}

fn test_ensure_invalid_u32_is_rejected() {
	input := 'a=p,i=12x'
	CommandParser.parse_string(input) or {
		assert err.msg().contains('InvalidCharacter')
		return
	}
	assert false, 'expected invalid character error'
}

fn test_ensure_empty_u32_is_rejected() {
	input := 'a=p,i='
	CommandParser.parse_string(input) or {
		assert err.msg().contains('InvalidCharacter')
		return
	}
	assert false, 'expected invalid character error'
}

fn test_ensure_proper_overflow_error_for_i32() {
	input := 'a=p,i=1,z=-9999999999'
	CommandParser.parse_string(input) or {
		assert err.msg().contains('Overflow')
		return
	}
	assert false, 'expected overflow error'
}

fn test_ensure_i32_overflow_at_boundary_is_rejected() {
	input := 'a=p,i=1,z=2147483648'
	CommandParser.parse_string(input) or {
		assert err.msg().contains('Overflow')
		return
	}
	assert false, 'expected overflow error'
}

fn test_all_i32_values_z() {
	// 'z' (usually z-axis values)
	input := 'a=p,i=1,z=-1'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Display
	v := command.control as Display
	assert v.image_id == 1
	assert v.z == -1
}

fn test_all_i32_values_h() {
	// 'H' (relative placement, horizontal offset)
	input := 'a=p,i=1,H=-1'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Display
	v := command.control as Display
	assert v.image_id == 1
	assert v.horizontal_offset == -1
}

fn test_all_i32_values_v() {
	// 'V' (relative placement, vertical offset)
	input := 'a=p,i=1,V=-1'
	command := CommandParser.parse_string(input) or { panic(err) }

	assert command.control is Display
	v := command.control as Display
	assert v.image_id == 1
	assert v.vertical_offset == -1
}
