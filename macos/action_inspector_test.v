@[has_globals]
module macos
import input
#insert "@VMODROOT/macos/input_client_test_bridge.h"
fn C.witty_input_test_event(type_ u64, flags u64, timestamp f64, keycode u16, chars &char) voidptr
__global (
 g_inspector_test_sizes []f64
 g_inspector_test_keys []input.Key
 g_inspector_test_destroyed int
)
fn inspector_test_init(_userdata voidptr,_device voidptr) voidptr { return voidptr(1) }
fn inspector_test_alive(_userdata voidptr) bool { return true }
fn inspector_test_size(_backend voidptr,w u32,h u32,x f64,y f64) { g_inspector_test_sizes=[f64(w),f64(h),x,y] }
fn inspector_test_destroy(_userdata voidptr, backend voidptr) {
 assert backend == voidptr(1)
 g_inspector_test_destroyed++
}
fn inspector_test_key(_backend voidptr,_action input.KeyAction,key input.Key,_mods int) { g_inspector_test_keys << key }
fn test_native_inspector_metal_view_size_key_and_ime_consumers() {
 app_init()
 msg_void(shared_app(),'finishLaunching')
 view := create_window(640,480,'inspector')
 mut surface := new_action_surface(view,unsafe{nil},ActionCallbacks{inspector:NativeInspectorCallbacks{init:inspector_test_init,alive:inspector_test_alive,size:inspector_test_size,destroy:inspector_test_destroy,key:inspector_test_key}})
 mut host := create_split_host(view)
 defer { surface.deinit(); close_tab(view); msg_void(host.container, 'release') }
 msg_void1(msg_id(get_class('NSRunLoop'),'currentRunLoop'),'runUntilDate:',msg_id_f64(get_class('NSDate'),'dateWithTimeIntervalSinceNow:',0.1))
 surface.control_inspector(1)
 assert surface.inspector != unsafe{nil}
 inspector := surface.inspector
 scroll := surface.scroll
 assert msg_id(msg_id(scroll.container, 'subviews'), 'lastObject') == scroll.inspector_divider
 bounds := msg_rect(scroll.container, 'bounds')
 top_height := native_split_first_extent(bounds.height, 0.5, 1)
 terminal_frame := msg_rect(scroll.scroll, 'frame')
 inspector_frame := msg_rect(inspector.view, 'frame')
 assert terminal_frame.height == top_height
 assert inspector_frame.height == terminal_frame.y - 0.5
 assert scroll.inspector_divider_hit(ObjCPoint{ x: 4, y: terminal_frame.y + 3 })
 assert scroll.inspector_divider_hit(ObjCPoint{ x: 4, y: terminal_frame.y - 3 })
 assert !scroll.inspector_divider_hit(ObjCPoint{ x: 4, y: terminal_frame.y + 4 })
 parent_point := msg_point_point_obj(msg_id(scroll.container, 'superview'), 'convertPoint:fromView:',
  ObjCPoint{ x: 4, y: terminal_frame.y - 3 }, scroll.container)
 assert surface_inspector_hit_test(scroll.container, nil_obj(), parent_point) == scroll.container
 config := NativeWindowConfig{ split_divider_color: u32(0x47637c) }
 host.set_appearance(config, view)
 assert scroll.inspector_divider_color == 0x47637c
 host.set_appearance(NativeWindowConfig{ ...config, split_divider_color: u32(0xa85b66) }, view)
 assert scroll.inspector_divider_color == 0xa85b66
 msg_void1(msg_id(get_class('NSRunLoop'),'currentRunLoop'),'runUntilDate:',msg_id_f64(get_class('NSDate'),'dateWithTimeIntervalSinceNow:',0.03))
 assert msg_id(view_window(view),'firstResponder') == inspector.view
 assert msg_u64(inspector.view,'preferredFramesPerSecond') == 30
 assert !msg_bool(inspector.view,'isPaused')
 inspector_update_size(inspector)
 assert g_inspector_test_sizes.len == 4
 assert g_inspector_test_sizes[0] > 0 && g_inspector_test_sizes[1] > 0
 event := C.witty_input_test_event(10,0,0,0,cstr('a'))
 inspector_key_action(inspector.view,event,.press)
 assert g_inspector_test_keys == [input.Key.key_a]
 inspector_set_marked(inspector.view,nil_obj(),nsstring('候補'),NativeRange{},NativeRange{})
 assert inspector_has_marked(inspector.view,nil_obj())
 assert inspector_marked_range(inspector.view,nil_obj()).length == 2
 inspector_unmark(inspector.view,nil_obj())
 assert !inspector_has_marked(inspector.view,nil_obj())
 surface.control_inspector(99)
 assert surface.inspector == inspector
 assert g_inspector_test_destroyed == 0
 surface.control_inspector(0)
 assert surface.inspector == unsafe{nil}
 assert is_nil(scroll.inspector_divider)
 msg_void1(msg_id(get_class('NSRunLoop'),'currentRunLoop'),'runUntilDate:',msg_id_f64(get_class('NSDate'),'dateWithTimeIntervalSinceNow:',0.03))
 assert msg_id(view_window(view),'firstResponder') == view
 assert g_inspector_test_destroyed == 1
}
