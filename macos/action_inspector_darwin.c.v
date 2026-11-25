module macos
import input
import math
#flag darwin -framework MetalKit

// InspectorView.swift MTKView/NSTextInputClient presentation. Backend callbacks
// are the translated embedded inspector API; all native view events are live.
pub struct NativeInspectorCallbacks {
pub:
 init fn (voidptr,voidptr) voidptr = unsafe{nil}
 alive fn (voidptr) bool = unsafe{nil}
 destroy fn (voidptr) = unsafe{nil}
 render fn (voidptr,voidptr,voidptr) = unsafe{nil}
 size fn (voidptr,u32,u32,f64,f64) = unsafe{nil}
 focus fn (voidptr,bool) = unsafe{nil}
 button fn (voidptr,input.MouseButtonState,input.MouseButton,int) = unsafe{nil}
 motion fn (voidptr,f64,f64) = unsafe{nil}
 scroll fn (voidptr,f64,f64,int) = unsafe{nil}
 key fn (voidptr,input.KeyAction,input.Key,int) = unsafe{nil}
 text fn (voidptr,string) = unsafe{nil}
}
@[heap]
struct NativeInspectorView {
mut:
 surface &NativeActionSurface = unsafe{nil}
 view ObjId
 queue ObjId
 backend voidptr
 marked ObjId
 closed bool
}
fn C.witty_action_inspector_new(cls voidptr,device voidptr,width f64,height f64) voidptr
fn C.witty_action_to_backing(view voidptr,width f64,height f64) C.witty_action_inspector_size
struct C.witty_action_inspector_size { width f64 height f64 }
fn inspector_state(self ObjId) ?&NativeInspectorView {
 ptr := C.macos_objc_get_ptr_ivar(self,cstr('inspector'))
 if is_nil(ptr) { return none }; return unsafe{&NativeInspectorView(ptr)}
}
fn (state &NativeInspectorView) valid() bool {
 return !state.closed && !state.surface.closed && !is_nil(state.backend) && (state.surface.callbacks.inspector.alive == unsafe{nil} || state.surface.callbacks.inspector.alive(state.surface.userdata))
}
fn register_inspector_view() {
 if !is_nil(get_class('WittyInspectorView')) { return }
 cls := C.macos_objc_allocate_class_pair(get_class('MTKView'),cstr('WittyInspectorView'),0)
 add_ptr_ivar(cls,'inspector')
 add_method(cls,'acceptsFirstResponder',voidptr(inspector_accepts),'B@:')
 add_method(cls,'becomeFirstResponder',voidptr(inspector_become),'B@:')
 add_method(cls,'resignFirstResponder',voidptr(inspector_resign),'B@:')
 add_method(cls,'drawRect:',voidptr(inspector_draw),'v@:{CGRect={CGPoint=dd}{CGSize=dd}}')
 add_method(cls,'viewDidChangeBackingProperties',voidptr(inspector_backing),'v@:')
 add_method(cls,'updateTrackingAreas',voidptr(inspector_tracking),'v@:')
 add_method(cls,'occlusion:',voidptr(inspector_occlusion),'v@:@')
 for selector in ['mouseDown:','mouseUp:','rightMouseDown:','rightMouseUp:'] { add_method(cls,selector,voidptr(inspector_mouse_button),'v@:@') }
 for selector in ['mouseMoved:','mouseDragged:'] { add_method(cls,selector,voidptr(inspector_mouse_motion),'v@:@') }
 add_method(cls,'scrollWheel:',voidptr(inspector_scroll),'v@:@')
 add_method(cls,'keyDown:',voidptr(inspector_key_down),'v@:@')
 add_method(cls,'keyUp:',voidptr(inspector_key_up),'v@:@')
 add_method(cls,'flagsChanged:',voidptr(inspector_flags),'v@:@')
 add_method(cls,'hasMarkedText',voidptr(inspector_has_marked),'B@:')
 add_method(cls,'markedRange',voidptr(inspector_marked_range),'{_NSRange=QQ}@:')
 add_method(cls,'selectedRange',voidptr(inspector_selected_range),'{_NSRange=QQ}@:')
 add_method(cls,'setMarkedText:selectedRange:replacementRange:',voidptr(inspector_set_marked),'v@:@{_NSRange=QQ}{_NSRange=QQ}')
 add_method(cls,'unmarkText',voidptr(inspector_unmark),'v@:')
 add_method(cls,'validAttributesForMarkedText',voidptr(inspector_attributes),'@@:')
 add_method(cls,'attributedSubstringForProposedRange:actualRange:',voidptr(inspector_substring),'@@:{_NSRange=QQ}^{_NSRange=QQ}')
 add_method(cls,'characterIndexForPoint:',voidptr(inspector_character),'Q@:{CGPoint=dd}')
 add_method(cls,'firstRectForCharacterRange:actualRange:',voidptr(inspector_first_rect),'{CGRect={CGPoint=dd}{CGSize=dd}}@:{_NSRange=QQ}^{_NSRange=QQ}')
 add_method(cls,'insertText:replacementRange:',voidptr(inspector_insert),'v@:@{_NSRange=QQ}')
 add_method(cls,'doCommandBySelector:',voidptr(inspector_command),'v@::')
 C.macos_objc_register_class_pair(cls)
}
pub fn (mut surface NativeActionSurface) control_inspector(mode int) {
 if mode !in [0, 1, 2] { return }
 if surface.closed || surface.scroll == unsafe{nil} { return }
 visible := surface.inspector != unsafe{nil}
 desired := if mode == 0 { !visible } else { mode == 1 }
 if visible == desired { return }
 if !desired { surface.hide_inspector(); return }
 register_inspector_view()
 device := C.MTLCreateSystemDefaultDevice()
 if is_nil(device) { eprintln('GPU not available'); return }
 queue := msg_id(device,'newCommandQueue')
 if is_nil(queue) { eprintln('GPU not available'); return }
 view := C.witty_action_inspector_new(get_class('WittyInspectorView'),device,view_width(surface.view),view_height(surface.view)/2)
 mut state := &NativeInspectorView{surface:&surface,view:view,queue:queue,marked:msg_id1(alloc('NSMutableAttributedString'),'initWithString:',nsstring(''))}
 C.macos_objc_set_ptr_ivar(view,cstr('inspector'),voidptr(state))
 if surface.callbacks.inspector.init != unsafe{nil} { state.backend = surface.callbacks.inspector.init(surface.userdata,device) }
 msg_void_bool(view,'setPaused:',false)
 msg_void_u64(view,'setPreferredFramesPerSecond:',30)
 C.witty_macos_objc_msg_void_clear_color(view,sel('setClearColor:'),MetalClearColor{red:40.0/255,green:44.0/255,blue:52.0/255,alpha:1})
 inspector_tracking(view,nil_obj())
 C.witty_macos_observe(msg_id(get_class('NSNotificationCenter'),'defaultCenter'),view,sel('occlusion:'),nsstring('NSWindowDidChangeOcclusionStateNotification'),voidptr(nil_obj()))
 surface.inspector = state
 surface.scroll.inspector = view
 msg_void1(surface.scroll.container,'addSubview:',view)
 bounds := msg_rect(surface.scroll.container, 'bounds')
 surface.scroll.inspector_divider = msg_id_rect(alloc('WittyInspectorDividerOverlay'), 'initWithFrame:', bounds)
 C.witty_canvas_place_overlay(surface.scroll.container, surface.scroll.inspector_divider, nil_obj())
 msg_void(surface.scroll.inspector_divider, 'release')
 surface.scroll.layout()
 dispatch_main(inspector_focus_main,voidptr(state))
}
fn inspector_focus_main(context voidptr) { state := unsafe{&NativeInspectorView(context)}; if state.valid() { msg_bool(state.surface.view,'resignFirstResponder'); msg_bool1(view_window(voidptr(state.view)),'makeFirstResponder:',state.view) } }
fn (mut surface NativeActionSurface) hide_inspector() {
 if surface.inspector == unsafe{nil} { return }
 mut state := surface.inspector
 state.closed = true
 msg_void_bool(state.view,'setPaused:',true)
 msg_void1(msg_id(get_class('NSNotificationCenter'),'defaultCenter'),'removeObserver:',state.view)
 move_focus(surface.view,unsafe{nil},none)
 surface.scroll.inspector = nil_obj()
 surface.scroll.inspector_dragging = false
 msg_void(surface.scroll.inspector_divider, 'removeFromSuperview')
 surface.scroll.inspector_divider = nil_obj()
 surface.inspector = unsafe{nil}
 msg_void(state.view,'removeFromSuperview')
 if surface.callbacks.inspector.destroy != unsafe{nil} { surface.callbacks.inspector.destroy(surface.userdata) }
 C.macos_objc_set_ptr_ivar(state.view,cstr('inspector'),nil_obj())
 msg_void(state.marked,'release'); msg_void(state.queue,'release'); msg_void(state.view,'release')
 surface.scroll.layout()
}
pub fn (surface &NativeActionSurface) render_inspector() {
 if surface.inspector != unsafe{nil} { msg_void_bool(surface.inspector.view,'setNeedsDisplay:',true) }
}
fn inspector_accepts(_self ObjId,_cmd Sel) bool { return true }
fn inspector_become(self ObjId,_cmd Sel) bool {
 result := view_super_bool(self,'WittyInspectorView','becomeFirstResponder')
 if state := inspector_state(self) { if result && state.valid() && state.surface.callbacks.inspector.focus != unsafe{nil} { state.surface.callbacks.inspector.focus(state.backend,true) } }; return result
}
fn inspector_resign(self ObjId,_cmd Sel) bool {
 result := view_super_bool(self,'WittyInspectorView','resignFirstResponder')
 if state := inspector_state(self) { if result && state.valid() && state.surface.callbacks.inspector.focus != unsafe{nil} { state.surface.callbacks.inspector.focus(state.backend,false) } }; return result
}
fn inspector_update_size(state &NativeInspectorView) {
 if !state.valid() { return }
 frame := msg_rect(state.view,'frame')
 if frame.width <= 0 || frame.height <= 0 { return }
 backing := C.witty_action_to_backing(state.view,frame.width,frame.height)
 if state.surface.callbacks.inspector.size != unsafe{nil} { state.surface.callbacks.inspector.size(state.backend,u32(backing.width),u32(backing.height),backing.width/frame.width,backing.height/frame.height) }
}
fn inspector_backing(self ObjId,_cmd Sel) { view_super_void(self,'WittyInspectorView','viewDidChangeBackingProperties'); if state := inspector_state(self) { inspector_update_size(state) } }
fn inspector_draw(self ObjId,_cmd Sel,_dirty ObjCRect) {
 state := inspector_state(self) or{return}
 command := msg_id(state.queue,'commandBuffer')
 descriptor := msg_id(self,'currentRenderPassDescriptor')
 if is_nil(command) || is_nil(descriptor) || !state.valid() { return }
 inspector_update_size(state)
 if state.surface.callbacks.inspector.render != unsafe{nil} { state.surface.callbacks.inspector.render(state.backend,command,descriptor) }
 drawable := msg_id(self,'currentDrawable'); if is_nil(drawable) { return }
 msg_void1(command,'presentDrawable:',drawable); msg_void(command,'commit')
}
fn inspector_occlusion(self ObjId,_cmd Sel,notification ObjId) {
 window := msg_id(notification,'object'); if window != view_window(voidptr(self)) { return }
 msg_void_bool(self,'setPaused:',msg_u64(window,'occlusionState') & 2 == 0)
}
fn inspector_tracking(self ObjId,_cmd Sel) { setup_view_tracking(voidptr(self)) }
fn inspector_mouse_button(self ObjId,cmd Sel,event ObjId) {
 state := inspector_state(self) or{return}; if !state.valid() || state.surface.callbacks.inspector.button == unsafe{nil} { return }
 pressed := cmd in [sel('mouseDown:'),sel('rightMouseDown:')]
 right := cmd in [sel('rightMouseDown:'),sel('rightMouseUp:')]
 state.surface.callbacks.inspector.button(state.backend,if pressed { input.MouseButtonState.press } else { input.MouseButtonState.release },if right { input.MouseButton.right } else { input.MouseButton.left },event_mods(voidptr(event)))
}
fn inspector_mouse_motion(self ObjId,_cmd Sel,event ObjId) {
 state := inspector_state(self) or{return}; if !state.valid() || state.surface.callbacks.inspector.motion == unsafe{nil} { return }
 point := msg_point_point_obj(self,'convertPoint:fromView:',msg_point(event,'locationInWindow'),nil_obj())
 state.surface.callbacks.inspector.motion(state.backend,point.x,msg_rect(self,'frame').height-point.y)
}
fn inspector_scroll(self ObjId,_cmd Sel,event ObjId) {
 state := inspector_state(self) or{return}; if !state.valid() || state.surface.callbacks.inspector.scroll == unsafe{nil} { return }
 mods := (if msg_bool(event,'hasPreciseScrollingDeltas') { 1 } else { 0 }) | (match msg_u64(event,'momentumPhase') { 1 { 1 } 2 { 2 } 4 { 3 } 8 { 4 } 16 { 5 } 32 { 6 } else { 0 } } << 1)
 state.surface.callbacks.inspector.scroll(state.backend,msg_f64(event,'scrollingDeltaX'),msg_f64(event,'scrollingDeltaY'),mods)
}
fn inspector_key_action(self ObjId,event ObjId,action input.KeyAction) {
 state := inspector_state(self) or{return}; if !state.valid() || state.surface.callbacks.inspector.key == unsafe{nil} { return }
 key := input.mac_keycode_to_key(event_keycode(voidptr(event))); if key == .unidentified { return }
 state.surface.callbacks.inspector.key(state.backend,action,key,event_mods(voidptr(event)))
}
fn inspector_key_down(self ObjId,_cmd Sel,event ObjId) {
 inspector_key_action(self,event,if msg_bool(event,'isARepeat') { .repeat } else { .press })
 msg_void1(self,'interpretKeyEvents:',C.witty_macos_array(&event,1))
}
fn inspector_key_up(self ObjId,_cmd Sel,event ObjId) { inspector_key_action(self,event,.release) }
fn inspector_flags(self ObjId,_cmd Sel,event ObjId) {
 mask := match event_keycode(voidptr(event)) { 0x39 { 16 } 0x38,0x3c { 1 } 0x3b,0x3e { 2 } 0x3a,0x3d { 4 } 0x37,0x36 { 8 } else { return } }
 inspector_key_action(self,event,if event_mods(voidptr(event)) & mask != 0 { .press } else { .release })
}
fn inspector_has_marked(self ObjId,_cmd Sel) bool { if state := inspector_state(self) { return msg_u64(state.marked,'length') > 0 }; return false }
fn inspector_marked_range(self ObjId,_cmd Sel) NativeRange { if state := inspector_state(self) { return NativeRange{length:uint(msg_u64(state.marked,'length'))} }; return NativeRange{} }
fn inspector_selected_range(_self ObjId,_cmd Sel) NativeRange { return NativeRange{} }
fn inspector_set_marked(self ObjId,_cmd Sel,value ObjId,_selected NativeRange,_replacement NativeRange) {
 mut state := inspector_state(self) or{return}
 if !msg_bool1(value,'isKindOfClass:',get_class('NSString')) && !msg_bool1(value,'isKindOfClass:',get_class('NSAttributedString')) { eprintln('unknown marked text'); return }
 selector := if msg_bool1(value,'isKindOfClass:',get_class('NSAttributedString')) { 'initWithAttributedString:' } else { 'initWithString:' }
 msg_void(state.marked,'release'); state.marked = msg_id1(alloc('NSMutableAttributedString'),selector,value)
}
fn inspector_unmark(self ObjId,_cmd Sel) { if state := inspector_state(self) { msg_void1(msg_id(state.marked,'mutableString'),'setString:',nsstring('')) } }
fn inspector_attributes(_self ObjId,_cmd Sel) ObjId { return msg_id(get_class('NSArray'),'array') }
fn inspector_substring(_self ObjId,_cmd Sel,_range NativeRange,_actual voidptr) ObjId { return nil_obj() }
fn inspector_character(_self ObjId,_cmd Sel,_point ObjCPoint) uint { return 0 }
fn inspector_first_rect(self ObjId,_cmd Sel,_range NativeRange,_actual voidptr) ObjCRect { frame := msg_rect(self,'frame'); return objc_rect(frame.x,frame.y,0,0) }
fn inspector_insert(self ObjId,_cmd Sel,value ObjId,_replacement NativeRange) {
 state := inspector_state(self) or{return}; if is_nil(msg_id(shared_app(),'currentEvent')) || !state.valid() || state.surface.callbacks.inspector.text == unsafe{nil} { return }
 string_value := if msg_bool1(value,'isKindOfClass:',get_class('NSAttributedString')) { msg_id(value,'string') } else if msg_bool1(value,'isKindOfClass:',get_class('NSString')) { value } else { return }
 state.surface.callbacks.inspector.text(state.backend,objc_utf8_string(string_value))
}
fn inspector_command(_self ObjId,_cmd Sel,_selector Sel) {
 // Source intentionally absorbs commands to suppress interpretKeyEvents NSBeep.
}
fn set_surface_inspector_divider_color(view voidptr, color u32) {
	surface := g_action_surfaces[u64(view)] or { return }
	mut scroll := surface.scroll
	if scroll == unsafe { nil } || scroll.inspector_divider_color == color { return }
	scroll.inspector_divider_color = color
	msg_void_bool(scroll.inspector_divider, 'setNeedsDisplay:', true)
}

fn (state &NativeSurfaceScroll) inspector_divider_line(bounds ObjCRect) SplitBounds {
	top := native_split_first_extent(bounds.height, state.inspector_ratio, 1)
	return SplitBounds{y: top - 0.5, width: bounds.width, height: 1}
}

fn (state &NativeSurfaceScroll) inspector_divider_hit(point ObjCPoint) bool {
	if is_nil(state.inspector) { return false }
	bounds := msg_rect(state.container, 'bounds')
	line := state.inspector_divider_line(bounds)
	y := bounds.height - point.y
	return point.x >= 0 && point.x <= bounds.width && y >= line.y - 3 && y <= line.y + line.height + 3
}

fn surface_inspector_hit_test(self ObjId, _cmd Sel, point ObjCPoint) ObjId {
	if state := native_surface_scroll(self) {
		local := msg_point_point_obj(self, 'convertPoint:fromView:', point, msg_id(self, 'superview'))
		if state.inspector_divider_hit(local) { return self }
	}
	return C.witty_action_hit_super(self, get_class('WittySurfaceContainer'), point.x, point.y)
}

fn surface_inspector_down(self ObjId, _cmd Sel, event ObjId) {
	mut state := native_surface_scroll(self) or { return }
	point := msg_point_point_obj(self, 'convertPoint:fromView:', msg_point(event, 'locationInWindow'), nil_obj())
	if !state.inspector_divider_hit(point) { return }
	if msg_u64(event, 'clickCount') == 2 {
		state.surface.perform('equalize_splits')
		return
	}
	state.inspector_dragging = true
}
fn surface_inspector_dragged(self ObjId,_cmd Sel,event ObjId) {
 mut state := native_surface_scroll(self) or{return}; if !state.inspector_dragging { return }
 height := msg_rect(self,'bounds').height
 point := msg_point_point_obj(self,'convertPoint:fromView:',msg_point(event,'locationInWindow'),nil_obj())
 state.inspector_ratio = math.min(math.max(10.0,height-point.y),height-10)/height
 state.layout()
}
fn surface_inspector_up(self ObjId,_cmd Sel,_event ObjId) { if mut state := native_surface_scroll(self) { state.inspector_dragging = false } }

fn surface_inspector_draw(self ObjId, _cmd Sel, _dirty ObjCRect) {
	state := native_surface_scroll(msg_id(self, 'superview')) or { return }
	state.draw_inspector_divider(native_canvas_overlay_context(), msg_rect(self, 'bounds'),
		view_backing_scale(voidptr(self)))
}

fn (state &NativeSurfaceScroll) draw_inspector_divider(context voidptr, bounds ObjCRect, scale f64) {
	line := native_canvas_overlay_rect(state.inspector_divider_line(bounds), scale)
	native_canvas_fill_rects(context, state.inspector_divider_color, [line])
}
