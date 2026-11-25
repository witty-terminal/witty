module cimgui

#include "draw_data.h"

@[typedef]
pub struct C.witty_cimgui_draw_frame {
pub:
	data          voidptr
	x             f32
	y             f32
	width         f32
	height        f32
	scale_x       f32
	scale_y       f32
	lists         int
	vertices      int
	indices       int
	vertex_stride int
	index_stride  int
}

@[typedef]
pub struct C.witty_cimgui_draw_list {
pub:
	list         voidptr
	vertices     voidptr
	indices      voidptr
	vertex_count int
	index_count  int
	commands     int
}

@[typedef]
pub struct C.witty_cimgui_draw_command {
pub:
	vertex_offset u32
	index_offset  u32
	count         u32
	left          f32
	top           f32
	right         f32
	bottom        f32
	texture       voidptr
	callback      bool
}

pub type DrawFrame = C.witty_cimgui_draw_frame
pub type DrawList = C.witty_cimgui_draw_list
pub type DrawCommand = C.witty_cimgui_draw_command

fn C.witty_cimgui_draw_frame_get(voidptr) DrawFrame
fn C.witty_cimgui_draw_list_get(voidptr, int) DrawList
fn C.witty_cimgui_draw_command_get(voidptr, int) DrawCommand

// The frame and its draw lists borrow ImGui's storage until the next frame.
pub fn (ctx Context) draw_frame() DrawFrame {
	return C.witty_cimgui_draw_frame_get(ctx.handle)
}

pub fn (frame DrawFrame) draw_list(index int) DrawList {
	return C.witty_cimgui_draw_list_get(frame.data, index)
}

pub fn (list DrawList) command(index int) DrawCommand {
	return C.witty_cimgui_draw_command_get(list.list, index)
}
