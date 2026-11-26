module apprt

fn test_action_c_enum_layouts_and_ordinals() {
	assert sizeof(ActionKey) == 4
	mut action_count := 0
	$for enum_value in ActionKey.values {
		assert i32(enum_value.value) == i32(action_count)
		action_count++
	}
	assert action_count == 63
	assert i32(ActionKey.quit) == 0
	assert i32(ActionKey.reserved_29) == 29
	assert i32(ActionKey.render_inspector) == 30
	assert i32(ActionKey.readonly) == 62

	assert sizeof(SplitDirection) == 4
	assert [SplitDirection.right, .down, .left, .up].map(i32(it)) == [i32(0), 1, 2, 3]
	assert sizeof(GotoSplit) == 4
	assert [GotoSplit.previous, .next, .up, .left, .down, .right].map(i32(it)) == [
		i32(0),
		1,
		2,
		3,
		4,
		5,
	]
	assert sizeof(GotoWindow) == 4
	assert [GotoWindow.previous, .next].map(i32(it)) == [i32(0), 1]
	assert sizeof(ResizeSplitDirection) == 4
	assert [ResizeSplitDirection.up, .down, .left, .right].map(i32(it)) == [i32(0), 1, 2, 3]

	assert sizeof(GotoTab) == 4
	assert [GotoTab.previous, .next, .last].map(i32(it)) == [i32(-1), -2, -3]
	tab_index := 17
	assert i32(unsafe { GotoTab(tab_index) }) == tab_index

	assert sizeof(Fullscreen) == 4
	assert [Fullscreen.native, .macos_non_native, .macos_non_native_visible_menu,
		.macos_non_native_padded_notch].map(i32(it)) == [i32(0), 1, 2, 3]
	assert sizeof(FloatWindow) == 4
	assert [FloatWindow.on, .off, .toggle].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(SecureInput) == 4
	assert [SecureInput.on, .off, .toggle].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(InspectorAction) == 4
	assert [InspectorAction.toggle, .show, .hide].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(QuitTimer) == 4
	assert [QuitTimer.start, .stop].map(i32(it)) == [i32(0), 1]
	assert sizeof(Readonly) == 4
	assert [Readonly.off, .on].map(i32(it)) == [i32(0), 1]
	assert sizeof(MouseVisibility) == 4
	assert [MouseVisibility.visible, .hidden].map(i32(it)) == [i32(0), 1]
	assert sizeof(PromptTitle) == 4
	assert [PromptTitle.surface, .tab].map(i32(it)) == [i32(0), 1]

	assert sizeof(KeyTableTag) == 4
	assert [KeyTableTag.activate, .deactivate, .deactivate_all].map(i32(it)) == [
		i32(0),
		1,
		2,
	]
	assert sizeof(ColorKind) == 4
	assert [ColorKind.foreground, .background, .cursor].map(i32(it)) == [i32(-1), -2, -3]
	palette_index := 255
	assert i32(unsafe { ColorKind(palette_index) }) == palette_index
	assert sizeof(OpenUrlKind) == 4
	assert [OpenUrlKind.unknown, .text, .html].map(i32(it)) == [i32(0), 1, 2]
	assert sizeof(CloseTabMode) == 4
	assert [CloseTabMode.this, .other, .right].map(i32(it)) == [i32(0), 1, 2]
}

// Test that action key enum has all expected values.
fn test_action_key_values() {
	// Verify first and last values exist
	assert ActionKey.quit == .quit
	assert ActionKey.readonly == .readonly
}

// Test SplitDirection enum values.
fn test_split_direction() {
	assert SplitDirection.right == .right
	assert SplitDirection.down == .down
	assert SplitDirection.left == .left
	assert SplitDirection.up == .up
}

// Test GotoSplit enum values.
fn test_goto_split() {
	assert GotoSplit.previous == .previous
	assert GotoSplit.next == .next
	assert GotoSplit.up == .up
	assert GotoSplit.right == .right
}

// Test GotoWindow enum values.
fn test_goto_window() {
	assert GotoWindow.previous == .previous
	assert GotoWindow.next == .next
}

// Test GotoTab special values.
fn test_goto_tab() {
	assert int(GotoTab.previous) == -1
	assert int(GotoTab.next) == -2
	assert int(GotoTab.last) == -3
}

// Test Fullscreen enum values.
fn test_fullscreen() {
	assert Fullscreen.native == .native
	assert Fullscreen.macos_non_native == .macos_non_native
}

// Test FloatWindow enum values.
fn test_float_window() {
	assert FloatWindow.on == .on
	assert FloatWindow.off == .off
	assert FloatWindow.toggle == .toggle
}

// Test SecureInput enum values.
fn test_secure_input() {
	assert SecureInput.on == .on
	assert SecureInput.off == .off
	assert SecureInput.toggle == .toggle
}

// Test InspectorAction enum values.
fn test_inspector() {
	assert InspectorAction.toggle == .toggle
	assert InspectorAction.show == .show
	assert InspectorAction.hide == .hide
}

// Test QuitTimer enum values.
fn test_quit_timer() {
	assert QuitTimer.start == .start
	assert QuitTimer.stop == .stop
}

// Test MouseVisibility enum values.
fn test_mouse_visibility() {
	assert MouseVisibility.visible == .visible
	assert MouseVisibility.hidden == .hidden
}

// Test ResizeSplit struct creation.
fn test_resize_split() {
	rs := ResizeSplit{
		amount: 10
		direction: .left
	}
	assert rs.amount == 10
	assert rs.direction == .left
}

// Test MoveTab struct creation.
fn test_move_tab() {
	mt := MoveTab{ amount: -1 }
	assert mt.amount == -1

	mt2 := MoveTab{ amount: 1 }
	assert mt2.amount == 1
	assert sizeof(MoveTab) == sizeof(int)
}

// Test SizeLimit struct creation.
fn test_size_limit() {
	sl := SizeLimit{
		min_width: 100
		min_height: 50
		max_width: 1920
		max_height: 1080
	}
	assert sl.min_width == 100
	assert sl.max_height == 1080
}

// Test InitialSize struct creation.
fn test_initial_size() {
	is_ := InitialSize{ width: 800, height: 600 }
	assert is_.width == 800
	assert is_.height == 600
}

// Test CellSize struct creation.
fn test_cell_size_action() {
	cs := CellSize{ width: 8, height: 16 }
	assert cs.width == 8
	assert cs.height == 16
}

// Test DesktopNotificationValue struct creation.
fn test_desktop_notification_value() {
	dn := DesktopNotificationValue{
		title: 'Hello'
		body: 'World'
	}
	assert dn.title == 'Hello'
	assert dn.body == 'World'
	assert dn.format() == 'DesktopNotification{ title: Hello, body: World }'
}

fn test_string_action_payload_formatters() {
	assert SetTitle{ title: 'terminal' }.format() == 'SetTitle{ terminal }'
	assert PwdValue{ pwd: '/tmp/project' }.format() == 'Pwd{ /tmp/project }'
}

// Test ColorChange struct creation.
fn test_color_change() {
	cc := ColorChange{
		kind: .foreground
		r: 255
		g: 128
		b: 0
	}
	assert cc.r == 255
	assert cc.kind == .foreground
}

// Test ColorKind special values.
fn test_color_kind() {
	assert int(ColorKind.foreground) == -1
	assert int(ColorKind.background) == -2
	assert int(ColorKind.cursor) == -3
}

// Test OpenUrl struct.
fn test_open_url() {
	ou := OpenUrl{
		kind: .text
		url: 'file:///tmp/test.txt'
	}
	assert ou.kind == .text
	assert ou.url == 'file:///tmp/test.txt'
}

// Test CloseTabMode enum values.
fn test_close_tab_mode() {
	assert CloseTabMode.this == .this
	assert CloseTabMode.other == .other
	assert CloseTabMode.right == .right
}

// Test Target sumtype.
fn test_target() {
	t := Target(AppTarget{})
	match t {
		AppTarget {
			assert true
		}
		SurfaceTarget {
			assert false
		}
	}

	t2 := Target(SurfaceTarget{ surface: unsafe { nil } })
	match t2 {
		SurfaceTarget {
			assert true
		}
		AppTarget {
			assert false
		}
	}
}

// Test ReloadConfig struct.
fn test_reload_config() {
	rc := ReloadConfig{ soft: true }
	assert rc.soft == true

	rc2 := ReloadConfig{}
	assert rc2.soft == false
}
