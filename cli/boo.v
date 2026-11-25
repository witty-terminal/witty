module cli

import compress.deflate
import vaxis
import vaxis.vxfw

const boo_compressed = $if generated_framedata ? {
	$embed_file('@VMODROOT/.witty-build/generated/framedata.compressed')
} $else {
	$embed_file('framedata.compressed')
}
const boo_frame_width = 100
const boo_frame_height = 41
const boo_frame_rate = u32(1000 / 30)

pub struct BooOptions {}

pub fn (opts BooOptions) deinit() {
	_ = opts
}

pub fn (opts BooOptions) help() ! {
	_ = opts
	action_options_help()!
}

enum BooParseState as u8 {
	normal
	span
	in_tag
	in_closing_tag
}

// All frames borrow their bytes from the one decompressed allocation.
fn decompress_boo_frames() ![]string {
	data := deflate.decompress(boo_compressed.to_bytes())!
	text := unsafe { tos(data.data, data.len) }
	mut frames := []string{cap: 235}
	mut start := 0
	for i, byte in data {
		if byte == 1 {
			frames << unsafe { tos(text.str + start, i - start) }
			start = i + 1
		}
	}
	frames << unsafe { tos(text.str + start, text.len - start) }
	return frames
}

struct Boo {
	frames        []string
	framerate     u32 = boo_frame_rate
	ghostty_style vaxis.Style
	outline_style vaxis.Style = vaxis.Style{
		fg: vaxis.ColorIndex{
			index: 4
		}
	}
mut:
	frame u8
	// A fixed array emits thousands of separate Cell initializers in C.
	buffer []vaxis.Cell = []vaxis.Cell{len: boo_frame_width * boo_frame_height}
}

fn (boo &Boo) widget() vxfw.Widget {
	return vxfw.Widget{
		userdata:      unsafe { voidptr(boo) }
		event_handler: boo_event
		draw_fn:       boo_draw
	}
}

fn boo_event(ptr voidptr, mut ctx vxfw.EventContext, event vxfw.Event) ! {
	mut boo := unsafe { &Boo(ptr) }
	match event {
		vxfw.InitEvent, vxfw.TickEvent {
			boo.update_frame()
			ctx.redraw = true
			ctx.tick(boo.framerate, boo.widget())
		}
		vaxis.Key {
			if event.matches(u32(`c`), vaxis.Modifiers.from_int(4))
				|| event.matches(vaxis.escape, vaxis.Modifiers{}) {
				ctx.quit = true
			}
		}
		else {}
	}
}

fn boo_draw(ptr voidptr, ctx vxfw.DrawContext) !vxfw.Surface {
	boo := unsafe { &Boo(ptr) }
	size := ctx.max.size()
	if size.width < boo_frame_width || size.height < boo_frame_height {
		text := &vxfw.Text{
			text: 'Screen must be at least 100w x 41h'
		}
		center := vxfw.Center{
			child: text.widget()
		}
		return center.draw(ctx)
	}
	mut buffer := []vaxis.Cell{}
	unsafe {
		buffer.data = boo.buffer.data
		buffer.len = boo.buffer.len
		buffer.cap = boo.buffer.len
		buffer.flags = .nofree
	}
	child := vxfw.Surface{
		children: []vxfw.SubSurface{}
		size:     vxfw.Size{
			width:  boo_frame_width
			height: boo_frame_height
		}
		widget:   boo.widget()
		buffer:   buffer
	}
	return vxfw.Surface{
		buffer:   []vaxis.Cell{}
		size:     size
		widget:   boo.widget()
		children: [
			vxfw.SubSurface{
				origin:  vxfw.RelativePoint{
					row: (size.height - boo_frame_height) / 2
					col: (size.width - boo_frame_width) / 2
				}
				surface: child
			},
		]
	}
}

fn (mut boo Boo) update_frame() {
	frame := boo.frames[boo.frame]
	mut cell_idx := 0
	for line in frame.split('\n') {
		mut state := BooParseState.normal
		mut style := boo.ghostty_style
		mut i := 0
		for i < line.len {
			start := i
			byte := line[i]
			i += if byte < 0x80 {
				1
			} else if byte < 0xe0 {
				2
			} else if byte < 0xf0 {
				3
			} else {
				4
			}
			grapheme := unsafe { tos(line.str + start, i - start) }
			match state {
				.normal {
					if grapheme == '<' {
						state = .in_tag
						style = boo.outline_style
						continue
					}
				}
				.span {
					if grapheme == '<' {
						state = .in_tag
						style = boo.ghostty_style
						continue
					}
				}
				.in_tag {
					if grapheme == '/' {
						state = .in_closing_tag
					} else if grapheme == '>' {
						state = .span
					}
					continue
				}
				.in_closing_tag {
					if grapheme == '>' { state = .normal }
					continue
				}
			}

			boo.buffer[cell_idx] = vaxis.Cell{
				char_: vaxis.CellCharacter{
					grapheme: grapheme
					width:    1
				}
				style: style
			}
			cell_idx++
		}
	}
	assert cell_idx == boo.buffer.len
	boo.frame++
	if int(boo.frame) == boo.frames.len { boo.frame = 0 }
}

pub fn run_boo(args []string) !int {
	$if windows || macos || linux || freebsd {
	} $else {
		return 1
	}
	opts := parse_action_options[BooOptions](args)!
	defer { opts.deinit() }
	frames := decompress_boo_frames()!
	mut app := vxfw.App.init()!
	defer { app.deinit() }
	mut boo := Boo{
		frames: frames
	}
	app.run(boo.widget(), vxfw.AppOptions{})!
	return 0
}
