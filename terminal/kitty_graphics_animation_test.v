module terminal

fn kitty_animation_command(mut t Terminal, input string) ?Response {
	cmd := CommandParser.parse_string(input) or { panic(err) }
	return t.kitty_graphics(&cmd)
}

fn test_kitty_animation_chunked_frames_compose_and_promote_root() ! {
	mut t := Terminal.init(Options{ cols: 4, rows: 4 })!
	defer { t.deinit() }
	storage := &t.screens.active.kitty_images
	assert (kitty_animation_command(mut t, 'a=T,f=24,i=11,s=1,v=1,c=1,r=1,C=1;/wAA') or { panic('missing root response') }).ok()
	assert kitty_animation_command(mut t, 'a=f,i=11,f=32,s=1,v=1,m=1;AP8A') == none
	reply := kitty_animation_command(mut t, 'm=0;/w==') or { panic('missing frame response') }
	assert reply.ok()
	assert reply.encode() == '\x1b_Gi=11,r=2;OK\x1b\\'
	assert storage.total_bytes == 8

	root := storage.image_by_id(11) or { panic('missing image') }
	assert root.render_data() == [u8(255), 0, 0, 255]
	assert kitty_animation_command(mut t, 'a=a,i=11,c=2') == none
	selected := storage.image_by_id(11) or { panic('missing image') }
	assert selected.render_data() == [u8(0), 255, 0, 255]
	assert selected.pixel_revision > root.pixel_revision

	assert (kitty_animation_command(mut t, 'a=c,i=11,r=2,c=1,C=1') or { panic('missing composition response') }).ok()
	assert kitty_animation_command(mut t, 'a=d,d=f,i=11,r=1') == none
	remaining := storage.image_by_id(11) or { panic('missing image') }
	assert remaining.animation.count() == 1
	assert remaining.animation.current_index == 0
	assert remaining.data == [u8(0), 255, 0, 255]
	assert storage.total_bytes == 4
	assert kitty_animation_command(mut t, 'a=d,d=F,i=11') == none
	assert storage.image_count() == 0
	assert storage.total_bytes == 0
}

fn test_kitty_animation_tick_skips_gapless_frames_and_honors_loop_limit() ! {
	mut t := Terminal.init(Options{ cols: 4, rows: 4 })!
	defer { t.deinit() }
	mut storage := &t.screens.active.kitty_images
	for input in [
		'a=T,f=32,i=12,s=1,v=1,c=1,r=1,C=1;/wAA/w==',
		'a=f,f=32,i=12,s=1,v=1,z=-1;AAD//w==',
		'a=f,f=32,i=12,s=1,v=1,z=40;AP8A/w==',
	] {
		assert (kitty_animation_command(mut t, input) or { panic('missing frame response') }).ok()
	}
	assert kitty_animation_command(mut t, 'a=a,i=12,r=1,z=30,s=3,v=2') == none
	assert (storage.animation_tick(100) or { panic('missing root deadline') }) == 30
	assert (storage.animation_tick(130) or { panic('missing frame deadline') }) == 40
	frame := storage.image_by_id(12) or { panic('missing image') }
	assert frame.render_data() == [u8(0), 255, 0, 255]
	assert frame.animation.current_index == 2
	assert storage.animation_tick(170) == none
	assert storage.animation_tick(250) == none
	frozen := storage.image_by_id(12) or { panic('missing image') }
	assert frozen.pixel_revision == frame.pixel_revision
	assert frozen.animation.current_index == 2
}

fn test_kitty_animation_quota_preserves_frames_on_rejected_upload() ! {
	mut t := Terminal.init(Options{ cols: 4, rows: 4 })!
	defer { t.deinit() }
	mut storage := &t.screens.active.kitty_images
	storage.total_limit = 8
	assert (kitty_animation_command(mut t, 'a=t,f=24,i=13,s=1,v=1;/wAA') or { panic('missing image response') }).ok()
	frame := 'a=f,f=32,i=13,s=1,v=1;AP8A/w=='
	assert (kitty_animation_command(mut t, frame) or { panic('missing frame response') }).ok()
	failure := kitty_animation_command(mut t, frame) or { panic('missing quota response') }
	assert failure.message == 'ENOSPC: animation frame storage full'
	assert storage.total_bytes == 8
	img := storage.image_by_id(13) or { panic('missing image') }
	assert img.animation.count() == 2
	assert img.data == [u8(255), 0, 0, 255]
	assert img.animation.frames[0].data == [u8(0), 255, 0, 255]
}
