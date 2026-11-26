module macos

import math

// SurfaceScrollView.swift: viewport renderer inside a document sized to the
// scrollback grid, with AppKit's bottom-origin coordinate conversion.
@[heap]
struct NativeSurfaceScroll {
mut:
 surface &NativeActionSurface = unsafe { nil }
 container ObjId
 scroll ObjId
 document ObjId
 cell_height f64
 has_scrollbar bool
 total uint
 offset uint
 len uint
 live bool
 last_row ?int
 inspector ObjId
 inspector_ratio f64 = 0.5
 inspector_dragging bool
 inspector_divider ObjId
 inspector_divider_color u32
 split_dimming ObjId
 split_dimming_fill ?u32
}
fn C.witty_action_scroll_point(clip voidptr, y f64)
fn C.witty_action_content_height(scroll voidptr) f64
fn C.witty_action_content_width(scroll voidptr) f64
struct C.witty_action_insets { top f64 left f64 bottom f64 right f64 }
fn C.witty_action_os_major() i64
fn C.witty_action_os_minor() i64

fn native_surface_scroll(self ObjId) ?&NativeSurfaceScroll {
 ptr := C.macos_objc_get_ptr_ivar(self,cstr('scroll'))
 if is_nil(ptr) { return none }
 return unsafe { &NativeSurfaceScroll(ptr) }
}
fn register_surface_scroll() {
 if !is_nil(get_class('WittySurfaceContainer')) { return }
 cls := C.macos_objc_allocate_class_pair(get_class('NSView'),cstr('WittySurfaceContainer'),0)
 add_ptr_ivar(cls,'scroll')
 add_method(cls,'resizeSubviewsWithOldSize:',voidptr(surface_scroll_resize),'v@:{CGSize=dd}')
 add_method(cls,'hitTest:',voidptr(surface_inspector_hit_test),'@@:{CGPoint=dd}')
 add_method(cls,'mouseDown:',voidptr(surface_inspector_down),'v@:@')
 add_method(cls,'mouseDragged:',voidptr(surface_inspector_dragged),'v@:@')
 add_method(cls,'mouseUp:',voidptr(surface_inspector_up),'v@:@')
 add_method(cls,'layout',voidptr(surface_scroll_layout),'v@:')
 add_method(cls,'viewDidChangeEffectiveAppearance',voidptr(surface_scroll_appearance_changed),'v@:')
 add_method(cls,'safeAreaInsets',voidptr(surface_scroll_insets),'{NSEdgeInsets=dddd}@:')
 add_method(cls,'boundsChanged:',voidptr(surface_scroll_bounds),'v@:@')
 add_method(cls,'liveStart:',voidptr(surface_scroll_live_start),'v@:@')
 add_method(cls,'liveEnd:',voidptr(surface_scroll_live_end),'v@:@')
 add_method(cls,'liveChanged:',voidptr(surface_scroll_live_changed),'v@:@')
 add_method(cls,'styleChanged:',voidptr(surface_scroll_style),'v@:@')
 add_method(cls,'pocketFrameChanged:',voidptr(surface_scroll_pocket),'v@:@')
 add_method(cls,'mouseMoved:',voidptr(surface_scroll_mouse_moved),'v@:@')
 add_method(cls,'updateTrackingAreas',voidptr(surface_scroll_tracking),'v@:')
 C.macos_objc_register_class_pair(cls)

 divider := C.macos_objc_allocate_class_pair(get_class('NSView'),cstr('WittyInspectorDividerOverlay'),0)
 add_method(divider,'isFlipped',voidptr(action_flipped),'B@:')
 add_method(divider,'hitTest:',voidptr(action_passive_hit),'@@:{CGPoint=dd}')
 add_method(divider,'drawRect:',voidptr(surface_inspector_draw),'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
 C.macos_objc_register_class_pair(divider)
}
fn surface_scroll_insets(_self ObjId,_cmd Sel) C.witty_action_insets { return C.witty_action_insets{} }
fn new_surface_scroll(surface &NativeActionSurface) &NativeSurfaceScroll {
 register_surface_scroll()
 frame := msg_rect(surface.view,'frame')
 container := msg_id_rect(alloc('WittySurfaceContainer'),'initWithFrame:',frame)
 scroll := msg_id_rect(alloc('NSScrollView'),'initWithFrame:',objc_rect(0,0,frame.width,frame.height))
 document := msg_id_rect(alloc('NSView'),'initWithFrame:',objc_rect(0,0,frame.width,frame.height))
 state := &NativeSurfaceScroll{surface: surface,container:container,scroll:scroll,document:document}
 C.macos_objc_set_ptr_ivar(container,cstr('scroll'),voidptr(state))
 msg_void_bool(scroll,'setHasVerticalScroller:',false)
 msg_void_bool(scroll,'setHasHorizontalScroller:',false)
 msg_void_bool(scroll,'setAutohidesScrollers:',false)
 msg_void_bool(scroll,'setUsesPredominantAxisScrolling:',true)
 msg_void_u64(scroll,'setScrollerStyle:',1)
 msg_void_bool(scroll,'setDrawsBackground:',false)
 clip := msg_id(scroll,'contentView')
 msg_void_bool(clip,'setClipsToBounds:',false)
 msg_void1(scroll,'setDocumentView:',document)
 window := view_window(surface.view)
 msg_void(surface.view,'retain')
 if !is_nil(window) && msg_id(window,'contentView') == surface.view { msg_void1(window,'setContentView:',container) }
 msg_void1(document,'addSubview:',surface.view)
 msg_void(surface.view,'release')
 msg_void1(container,'addSubview:',scroll)
 msg_void_bool(clip,'setPostsBoundsChangedNotifications:',true)
 center := msg_id(get_class('NSNotificationCenter'),'defaultCenter')
 C.witty_macos_observe(center,container,sel('boundsChanged:'),nsstring('NSViewBoundsDidChangeNotification'),clip)
 for pair in [['NSScrollViewWillStartLiveScrollNotification','liveStart:'],['NSScrollViewDidEndLiveScrollNotification','liveEnd:'],['NSScrollViewDidLiveScrollNotification','liveChanged:']] {
  C.witty_macos_observe(center,container,sel(pair[1]),nsstring(pair[0]),scroll)
 }
 C.witty_macos_observe(center,container,sel('styleChanged:'),nsstring('NSPreferredScrollerStyleDidChangeNotification'),nil_obj())
 if C.witty_action_os_major() == 26 && C.witty_action_os_minor() == 0 {
  C.witty_macos_observe(center,container,sel('pocketFrameChanged:'),nsstring('NSViewFrameDidChangeNotification'),nil_obj())
 }
 return state
}
fn (mut state NativeSurfaceScroll) deinit() {
 msg_void1(msg_id(get_class('NSNotificationCenter'),'defaultCenter'),'removeObserver:',state.container)
 msg_void(state.container,'removeFromSuperview')
 msg_void(state.document,'release')
 msg_void(state.scroll,'release')
 msg_void(state.container,'release')
}
pub fn surface_container(view voidptr) voidptr {
 if surface := g_action_surfaces[u64(view)] { if surface.scroll != unsafe { nil } { return surface.scroll.container } }
 return view
}
pub fn surface_container_layout(view voidptr) {
 if mut surface := g_action_surfaces[u64(view)] { if surface.scroll != unsafe { nil } { surface.scroll.layout() } }
}

fn set_surface_split_dimming(view voidptr, fill u32, opacity f64) {
	mut surface := g_action_surfaces[u64(view)] or { return }
	if surface.scroll == unsafe { nil } { return }
	mut scroll := surface.scroll
	if opacity <= 0 {
		if !is_nil(scroll.split_dimming) {
			msg_void_bool(scroll.split_dimming, 'setHidden:', true)
		}
		return
	}
	if is_nil(scroll.split_dimming) {
		scroll.split_dimming = msg_id_rect(alloc('WittyPassiveOverlay'), 'initWithFrame:', msg_rect(scroll.scroll, 'frame'))
		msg_void1(scroll.split_dimming, 'setLayer:', msg_id(get_class('CALayer'), 'layer'))
		msg_void_bool(scroll.split_dimming, 'setWantsLayer:', true)
		C.witty_canvas_place_overlay(scroll.container, scroll.split_dimming, scroll.scroll)
		msg_void(scroll.split_dimming, 'release')
	}
	layer := msg_id(scroll.split_dimming, 'layer')
	transaction := get_class('CATransaction')
	msg_void(transaction, 'begin')
	msg_void_bool(transaction, 'setDisableActions:', true)
	if scroll.split_dimming_fill != ?u32(fill) {
		tile := native_canvas_fill_tile(fill)
		if !is_nil(tile) {
			msg_void1(layer, 'setContents:', ObjId(tile))
			C.CFRelease(tile)
			scroll.split_dimming_fill = fill
		}
	}
	// Apply opacity during composition so the opaque tile transforms to the window color space first.
	C.witty_macos_msg_void_f32(layer, sel('setOpacity:'), f32(opacity))
	msg_void_bool(scroll.split_dimming, 'setHidden:', false)
	msg_void(transaction, 'commit')
}

fn surface_scroll_resize(self ObjId,_cmd Sel,_size ObjCSize) { if mut state := native_surface_scroll(self) { state.layout() } }
fn surface_scroll_layout(self ObjId,_cmd Sel) { if mut state := native_surface_scroll(self) { state.layout() } }
fn surface_scroll_appearance_changed(self ObjId, _cmd Sel) {
	view_super_void(self, 'WittySurfaceContainer', 'viewDidChangeEffectiveAppearance')
	if mut state := native_surface_scroll(self) { state.surface.refresh_hover_appearance() }
}
fn (mut state NativeSurfaceScroll) layout() {
 bounds := msg_rect(state.container,'bounds')
 height := if is_nil(state.inspector) { bounds.height } else { native_split_first_extent(bounds.height, state.inspector_ratio, 1) }
 scroll_y := bounds.height - height
 scroll_frame := objc_rect(0,scroll_y,bounds.width,height)
 msg_void_rect(state.scroll,'setFrame:',scroll_frame)
 if !is_nil(state.split_dimming) { msg_void_rect(state.split_dimming, 'setFrame:', scroll_frame) }
 if !is_nil(state.inspector) {
  msg_void_rect(state.inspector,'setFrame:',objc_rect(0,0,bounds.width,math.max(0,scroll_y-0.5)))
  msg_void_rect(state.inspector_divider,'setFrame:',bounds)
  msg_void_bool(state.inspector_divider,'setNeedsDisplay:',true)
 }
 visible := msg_rect(state.scroll,'bounds')
 doc := msg_rect(state.document,'frame')
 msg_void_rect(state.document,'setFrame:',objc_rect(doc.x,doc.y,visible.width,doc.height))
 msg_void_rect(state.surface.view,'setFrame:',objc_rect(0,0,visible.width,visible.height))
 state.synchronize()
 state.synchronize_surface()
 state.synchronize_core()
}
fn (state &NativeSurfaceScroll) document_height() f64 {
 height := C.witty_action_content_height(state.scroll)
 return if state.cell_height > 0 && state.has_scrollbar { f64(state.total)*state.cell_height + height - f64(state.len)*state.cell_height } else { height }
}
fn (mut state NativeSurfaceScroll) synchronize() {
 frame := msg_rect(state.document,'frame')
 msg_void_rect(state.document,'setFrame:',objc_rect(frame.x,frame.y,frame.width,state.document_height()))
 clip := msg_id(state.scroll,'contentView')
 if !state.live && state.cell_height > 0 && state.has_scrollbar {
  C.witty_action_scroll_point(clip,f64(state.total-state.offset-state.len)*state.cell_height)
  state.last_row = int(state.offset)
 }
 msg_void1(state.scroll,'reflectScrolledClipView:',clip)
}
fn (state &NativeSurfaceScroll) synchronize_surface() {
 visible := msg_rect(msg_id(state.scroll,'contentView'),'documentVisibleRect')
 frame := msg_rect(state.surface.view,'frame')
 msg_void_rect(state.surface.view,'setFrame:',objc_rect(visible.x,visible.y,frame.width,frame.height))
}
fn (state &NativeSurfaceScroll) synchronize_core() {
 width := C.witty_action_content_width(state.scroll)
 height := msg_rect(state.surface.view,'frame').height
 if width > 0 && height > 0 {
  vt_view_frame_did_change(state.surface.view,nil_obj(),nil_obj())
  if state.surface.callbacks.size != unsafe { nil } { state.surface.callbacks.size(state.surface.userdata,width,height) }
 }
}
pub fn (mut surface NativeActionSurface) set_scrollbar(total uint,offset uint,len uint) {
 if surface.scroll == unsafe { nil } { return }
 surface.scroll.has_scrollbar = true
 surface.scroll.total = total
 surface.scroll.offset = offset
 surface.scroll.len = len
 surface.scroll.synchronize()
}
pub fn (mut surface NativeActionSurface) set_scroll_cell_height(height f64) {
 if surface.scroll == unsafe { nil } { return }
 surface.scroll.cell_height = height
 surface.scroll.synchronize()
}
pub fn (mut surface NativeActionSurface) configure_scroll(never bool,light bool) {
 if surface.scroll == unsafe { nil } { return }
 msg_void_bool(surface.scroll.scroll,'setHasVerticalScroller:',!never)
 msg_void1(surface.scroll.scroll,'setAppearance:',msg_id1(get_class('NSAppearance'),'appearanceNamed:',nsstring(if light { 'NSAppearanceNameAqua' } else { 'NSAppearanceNameDarkAqua' })))
 surface_scroll_tracking(surface.scroll.container,nil_obj())
 surface.scroll.synchronize_core()
}
fn surface_scroll_bounds(self ObjId,_cmd Sel,_notification ObjId) { if state := native_surface_scroll(self) { state.synchronize_surface() } }
fn surface_scroll_live_start(self ObjId,_cmd Sel,_notification ObjId) { if mut state := native_surface_scroll(self) { state.live = true } }
fn surface_scroll_live_end(self ObjId,_cmd Sel,_notification ObjId) { if mut state := native_surface_scroll(self) { state.live = false } }
fn surface_scroll_live_changed(self ObjId,_cmd Sel,_notification ObjId) {
 mut state := native_surface_scroll(self) or { return }
 if state.cell_height <= 0 { return }
 visible := msg_rect(msg_id(state.scroll,'contentView'),'documentVisibleRect')
 row := int((msg_rect(state.document,'frame').height-visible.y-visible.height)/state.cell_height)
 if previous := state.last_row { if previous == row { return } }
 state.last_row = row
 state.surface.perform('scroll_to_row:${row}')
}
fn surface_scroll_style(self ObjId,_cmd Sel,_notification ObjId) {
 state := native_surface_scroll(self) or { return }
 msg_void_u64(state.scroll,'setScrollerStyle:',1)
 state.synchronize_core()
}
fn surface_scroll_pocket(self ObjId,_cmd Sel,notification ObjId) {
 state := native_surface_scroll(self) or { return }
 window := view_window(state.surface.view)
 if config := native_window_data(window) { if config.config.titlebar_style != 3 { return } } else { return }
 if msg_u64(window,'styleMask') & u64(1<<14) != 0 { return }
 view := msg_id(notification,'object')
 if !objc_utf8_string(msg_id(view,'className')).contains('NSScrollPocket') { return }
 if !msg_bool1(msg_id(state.scroll,'subviews'),'containsObject:',view) { return }
 msg_void_bool(view,'setPostsFrameChangedNotifications:',false)
 msg_void_rect(view,'setFrame:',objc_rect(0,0,0,0))
 msg_void_bool(view,'setPostsFrameChangedNotifications:',true)
}
fn surface_scroll_mouse_moved(self ObjId,_cmd Sel,_event ObjId) {
 state := native_surface_scroll(self) or { return }
 if msg_u64(get_class('NSScroller'),'preferredScrollerStyle') == 0 { msg_void(state.scroll,'flashScrollers') }
}
fn surface_scroll_tracking(self ObjId,_cmd Sel) {
 state := native_surface_scroll(self) or { return }
 areas := msg_id(self,'trackingAreas')
 for i := int(msg_u64(areas,'count'))-1; i >= 0; i-- { msg_void1(self,'removeTrackingArea:',msg_id_u64(areas,'objectAtIndex:',u64(i))) }
 scroller := msg_id(state.scroll,'verticalScroller')
 if is_nil(scroller) { return }
 rect := msg_rect(scroller,'frame')
 area := msg_id_rect_u64_obj_obj(alloc('NSTrackingArea'),'initWithRect:options:owner:userInfo:',rect,2|16,self,nil_obj())
 msg_void1(self,'addTrackingArea:',area)
 msg_void(area,'release')
}
