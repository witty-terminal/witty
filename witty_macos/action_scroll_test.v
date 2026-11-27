@[has_globals]
module witty_macos
__global g_scroll_test_actions = []string{}
fn scroll_test_binding(_userdata voidptr, action string) bool { g_scroll_test_actions << action; return true }
fn test_native_scrollback_document_and_live_row_inversion() {
 app_init()
 view := create_window(640,480,'scroll')
 mut surface := new_action_surface(view,unsafe{nil},ActionCallbacks{binding:scroll_test_binding})
 defer { surface.deinit(); close_tab(view) }
 surface.configure_scroll(false,false)
 surface.scroll.layout()
 surface.set_scroll_cell_height(14)
 surface.set_scrollbar(100,80,20)
 layer := metal_iosurface_layer_new()
 assert !is_nil(layer)
 defer { metal_release(layer) }
 metal_install_iosurface_layer(view, layer, view_backing_scale(view))
 content_height := C.witty_action_content_height(surface.scroll.scroll)
 assert surface.scroll.document_height() == 100*14 + content_height-20*14
 assert (surface.scroll.last_row or {-1}) == 80
 clip := msg_id(surface.scroll.scroll,'contentView')
 surface_scroll_live_start(surface.scroll.container,nil_obj(),nil_obj())
 C.witty_action_scroll_point(clip,70)
 surface_scroll_live_changed(surface.scroll.container,nil_obj(),nil_obj())
 count := g_scroll_test_actions.len
 assert count == 1
 visible := msg_rect(clip,'documentVisibleRect')
 assert visible.y > 0
 assert msg_rect(view, 'frame').y == visible.y
 // AppKit updates the backing hierarchy during the next display pass.
 msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:',
  msg_id_f64(get_class('NSDate'), 'dateWithTimeIntervalSinceNow:', 0.1))
 assert msg_rect(layer, 'frame') == msg_rect(view, 'frame')
 expected := int((surface.scroll.document_height()-visible.y-visible.height)/14)
 assert g_scroll_test_actions[0] == 'scroll_to_row:${expected}'
 surface_scroll_live_changed(surface.scroll.container,nil_obj(),nil_obj())
 assert g_scroll_test_actions.len == count
 surface.set_scrollbar(100,80,20)
 assert msg_rect(clip,'documentVisibleRect').y == visible.y
 surface_scroll_live_end(surface.scroll.container,nil_obj(),nil_obj())
 surface.set_scrollbar(100,80,20)
 assert msg_rect(clip,'documentVisibleRect').y == 0
 surface.configure_scroll(true,true)
 assert !msg_bool(surface.scroll.scroll,'hasVerticalScroller')
}
