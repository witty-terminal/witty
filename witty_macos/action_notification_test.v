@[has_globals]
module witty_macos

#insert "@VMODROOT/witty_macos/notification_bridge.h"
#insert "@VMODROOT/witty_macos/notification_test_abi.h"

fn C.witty_action_test_dispatch(object voidptr, handler voidptr, completed voidptr, context voidptr, options bool)

__global (
	notification_test_done      bool
	notification_test_options   i64
	notification_test_presented int
)

fn test_native_user_notification_content_has_source_identity_and_sound() {
	surface := &NativeActionSurface{
		uuid:  '550e8400-e29b-41d4-a716-446655440000'
		title: 'terminal title'
	}
	content := notification_content(surface, 'event title', 'event body')
	defer { msg_void(content, 'release') }
	assert objc_utf8_string(msg_id(content, 'title')) == 'event title'
	assert objc_utf8_string(msg_id(content, 'subtitle')) == 'terminal title'
	assert objc_utf8_string(msg_id(content, 'body')) == 'event body'
	assert objc_utf8_string(msg_id(content, 'categoryIdentifier')) == 'com.alexander.witty.userNotification'
	assert !is_nil(msg_id(content, 'sound'))
	info := msg_id(content, 'userInfo')
	assert objc_utf8_string(msg_id1(info, 'objectForKey:', nsstring('surface'))) == surface.uuid
}

fn notification_fixture_get(self ObjId, cmd Sel) ObjId {
	name := if cmd == sel('request') {
		'request'
	} else if cmd == sel('notification') {
		'notification'
	} else {
		'action'
	}
	return C.macos_objc_get_ptr_ivar(self, cstr(name))
}

fn notification_fixture_complete(_context voidptr, _object ObjId, options i64, _granted bool) {
	assert msg_bool(get_class('NSThread'), 'isMainThread')
	notification_test_done = true
	notification_test_options = options
}

fn notification_fixture_present(_context voidptr, _view voidptr) { notification_test_presented++ }

fn test_native_notification_delegate_main_queue_and_completion_lifetime() {
	app_init()
	view := create_window(640, 480, 'notifications')
	mut surface := new_action_surface(view, unsafe { nil }, ActionCallbacks{ present: notification_fixture_present })
	defer {
		surface.deinit()
		close_tab(view)
	}
	mut cls := get_class('WittyNotificationFixture')
	if is_nil(cls) {
		cls = C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('WittyNotificationFixture'), 0)
		for name in ['request', 'notification', 'action'] { add_ptr_ivar(cls, name) }
		for name in ['request', 'notification', 'actionIdentifier'] {
			add_method(cls, name, voidptr(notification_fixture_get), '@@:')
		}
		C.macos_objc_register_class_pair(cls)
	}
	notification := msg_id(msg_id(cls, 'alloc'), 'init')
	response := msg_id(msg_id(cls, 'alloc'), 'init')
	defer {
		msg_void(notification, 'release')
		msg_void(response, 'release')
	}
	content := notification_content(surface, 'title', 'body')
	defer { msg_void(content, 'release') }
	request := msg_id3(get_class('UNNotificationRequest'), 'requestWithIdentifier:content:trigger:', nsstring('scheduled'), content, nil_obj())
	C.macos_objc_set_ptr_ivar(notification, cstr('request'), request)
	C.macos_objc_set_ptr_ivar(response, cstr('notification'), notification)
	C.macos_objc_set_ptr_ivar(response, cstr('action'), nsstring(notification_show))
	surface.notification_identifiers = ['scheduled']
	notification_test_done = false
	C.witty_action_test_dispatch(response, voidptr(notification_response_main), voidptr(notification_fixture_complete), unsafe { nil }, false)
	assert !notification_test_done
	msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:', msg_id_f64(get_class('NSDate'), 'dateWithTimeIntervalSinceNow:', 0.03))
	assert notification_test_done
	assert notification_test_presented == 1
	assert surface.notification_identifiers.len == 0
	surface.focused = false
	notification_test_done = false
	C.witty_action_test_dispatch(notification, voidptr(notification_present_main), voidptr(notification_fixture_complete), unsafe { nil }, true)
	msg_void1(msg_id(get_class('NSRunLoop'), 'currentRunLoop'), 'runUntilDate:', msg_id_f64(get_class('NSDate'), 'dateWithTimeIntervalSinceNow:', 0.03))
	assert notification_test_done
	assert notification_test_options == 18
}
