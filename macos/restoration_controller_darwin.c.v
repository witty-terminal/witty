@[has_globals]
module macos

pub type NativeControllerEncoder = fn (voidptr, bool) ?voidptr
pub type NativeControllerDecoder = fn (voidptr, bool) ?voidptr
pub type NativeRestorationAllowed = fn () bool
__global (
	g_controller_encoder NativeControllerEncoder
	g_controller_decoder NativeControllerDecoder
	g_restoration_allowed NativeRestorationAllowed
)
pub fn set_native_restoration_callbacks(encode NativeControllerEncoder, decode NativeControllerDecoder, allowed NativeRestorationAllowed) { g_controller_encoder=encode; g_controller_decoder=decode; g_restoration_allowed=allowed }
fn restoration_allowed() bool { return g_restoration_allowed != unsafe { nil } && g_restoration_allowed() }
fn native_supports_secure_restoration(_self ObjId,_cmd Sel,_app ObjId) bool { return true }
fn native_app_encode_restoration(_self ObjId,_cmd Sel,_app ObjId,coder ObjId) {
	if !restoration_allowed() || g_controller_encoder == unsafe { nil } { return }
	if value := g_controller_encoder(unsafe { nil },true) { encode_native_restorable(voidptr(coder),value,1) }
}
fn native_app_decode_restoration(_self ObjId,_cmd Sel,_app ObjId,coder ObjId) {
	if !restoration_allowed() || g_controller_decoder == unsafe { nil } { return }
	if value := decode_native_restorable(voidptr(coder),1) { g_controller_decoder(value,true) }
}
fn native_window_encode_restoration(_self ObjId,_cmd Sel,window ObjId,coder ObjId) {
	if g_controller_encoder == unsafe { nil } { return }
	view := terminal_view_for_window(window)
	if value := g_controller_encoder(voidptr(view),false) { encode_native_restorable(voidptr(coder),value,7) }
}
fn restoration_error(code int) ObjId { return msg_id3(get_class('NSError'),'errorWithDomain:code:userInfo:',nsstring('Witty.TerminalRestoreError'),ObjId(code),nil_obj()) }
fn native_restore_window(_self ObjId,_cmd Sel,identifier ObjId,coder ObjId,completion voidptr) {
	if objc_utf8_string(identifier) != 'TerminalWindowRestoration' { C.witty_restoration_complete(completion,nil_obj(),restoration_error(1)); return }
	if g_controller_decoder == unsafe { nil } { C.witty_restoration_complete(completion,nil_obj(),restoration_error(0)); return }
	if !restoration_allowed() { C.witty_restoration_complete(completion,nil_obj(),nil_obj()); return }
	value := decode_native_restorable(voidptr(coder),7) or { C.witty_restoration_complete(completion,nil_obj(),restoration_error(2)); return }
	window := g_controller_decoder(value,false) or { C.witty_restoration_complete(completion,nil_obj(),restoration_error(3)); return }
	C.witty_restoration_complete(completion,window,nil_obj())
}
fn native_restoration_class() ObjId {
	mut cls := get_class('VTTerminalWindowRestoration')
	if !is_nil(cls) { return cls }
	cls=C.macos_objc_allocate_class_pair(get_class('NSObject'),cstr('VTTerminalWindowRestoration'),0)
	C.class_addProtocol(cls,C.objc_getProtocol(cstr('NSWindowRestoration')))
	add_method(C.object_getClass(cls),'restoreWindowWithIdentifier:state:completionHandler:',voidptr(native_restore_window),'v@:@@@?')
	C.macos_objc_register_class_pair(cls)
	return cls
}
pub fn configure_native_restoration(view voidptr, restorable bool) {
	window := msg_id(view,'window')
	msg_void_bool(window,'setRestorable:',restorable)
	if restorable { msg_void1(window,'setRestorationClass:',native_restoration_class()); msg_void1(window,'setIdentifier:',nsstring('TerminalWindowRestoration')) }
}
fn register_native_restoration_methods(cls ObjId) {
	add_method(cls,'applicationSupportsSecureRestorableState:',voidptr(native_supports_secure_restoration),'B@:@')
	add_method(cls,'application:willEncodeRestorableState:',voidptr(native_app_encode_restoration),'v@:@@')
	add_method(cls,'application:didDecodeRestorableState:',voidptr(native_app_decode_restoration),'v@:@@')
	add_method(cls,'window:willEncodeRestorableState:',voidptr(native_window_encode_restoration),'v@:@@')
}
pub fn native_fullscreen_mode(view voidptr) NativeFullscreenMode { if state := g_fullscreen_states[u64(msg_id(view,'window'))] { return state.mode }; return .native }
pub fn quick_terminal_initialized() ?&NativeQuickTerminal { if g_quick_terminal == unsafe { nil } { return none }; return g_quick_terminal }
pub fn native_date_object(seconds f64) voidptr { return msg_id_f64(get_class('NSDate'),'dateWithTimeIntervalSince1970:',seconds) }
pub fn native_uuid_valid(value string) bool { uuid:=msg_id1(msg_id(get_class('NSUUID'),'alloc'),'initWithUUIDString:',nsstring(value)); valid:=!is_nil(uuid); msg_void(uuid,'release'); return valid }
pub fn native_uuid_string(value string) ?string { uuid:=msg_id1(msg_id(get_class('NSUUID'),'alloc'),'initWithUUIDString:',nsstring(value)); if is_nil(uuid) { return none }; result:=objc_utf8_string(msg_id(uuid,'UUIDString')); msg_void(uuid,'release'); return result }
pub fn apply_native_save_state(value int) { defaults:=msg_id(get_class('NSUserDefaults'),'standardUserDefaults'); key:=nsstring('NSQuitAlwaysKeepsWindows'); if value == 0 { msg_void1(defaults,'removeObjectForKey:',key) } else { msg_void2(defaults,'setObject:forKey:',codable_bool(value==2),key) } }
pub fn restore_native_window_focus(view voidptr) { window:=msg_id(view,'window'); msg_bool1(window,'makeFirstResponder:',view); if msg_bool(window,'isMainWindow') { msg_void1(window,'orderFront:',nil_obj()) } }
