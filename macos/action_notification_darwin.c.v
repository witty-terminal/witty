@[has_globals]
module macos

// Ghostty.App.{showDesktopNotification,shouldPresentNotification,
// handleUserNotification}, SurfaceView_AppKit.{showUserNotification,
// focusDidChange}, AppDelegate's UNUserNotificationCenterDelegate.
#flag darwin -framework UserNotifications
#insert "@VMODROOT/macos/notification_bridge.h"

fn C.witty_action_notification_settings(center voidptr, callback voidptr, context voidptr)
fn C.witty_action_notification_authorize(center voidptr, options u64, callback voidptr, context voidptr)
fn C.witty_action_notification_add(center voidptr, request voidptr, callback voidptr, context voidptr)
fn C.witty_action_notification_action(identifier voidptr, title voidptr, options u64) voidptr
fn C.witty_action_notification_category(identifier voidptr, actions voidptr, intents voidptr, options u64) voidptr
fn C.witty_action_complete_void(block voidptr)
fn C.witty_action_complete_options(block voidptr, options u64)

struct C.witty_action_notification_delivery {
	object     voidptr
	completion voidptr
}

fn C.witty_action_notification_dispatch(object voidptr, completion voidptr, callback voidptr)
fn C.witty_action_notification_delivery_free(delivery &C.witty_action_notification_delivery)
fn C.witty_action_sheet(alert voidptr, window voidptr, callback voidptr, context voidptr)

const notification_category = 'com.alexander.witty.userNotification'
const notification_show = 'com.alexander.witty.userNotification.Show'

@[heap]
struct NativeNotificationJob {
mut:
	surface    &NativeActionSurface = unsafe { nil }
	title      string
	body       string
	identifier string
	result     ObjId
	operation  int
	granted    bool
}

__global (
	g_notification_delegate ObjId
	g_notification_jobs     map[u64]&NativeNotificationJob
)

fn notification_center() ObjId {
	return msg_id(get_class('UNUserNotificationCenter'), 'currentNotificationCenter')
}

fn register_action_notification_methods(cls ObjId) {
	add_method(cls, 'notificationExpiration:', voidptr(notification_expiration), 'v@:@')
}

fn notification_setup() {
	if !is_nil(g_notification_delegate) { return }
	cls := C.macos_objc_allocate_class_pair(get_class('NSObject'),
		cstr('WittyNotificationDelegate'), 0)
	C.macos_class_add_protocol(cls,
		C.macos_objc_get_protocol(cstr('UNUserNotificationCenterDelegate')))
	add_method(cls, 'userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:',
		voidptr(notification_response), 'v@:@@@')
	add_method(cls, 'userNotificationCenter:willPresentNotification:withCompletionHandler:',
		voidptr(notification_present), 'v@:@@@')
	C.macos_objc_register_class_pair(cls)
	g_notification_delegate = msg_id(alloc('WittyNotificationDelegate'), 'init')
	center := notification_center()
	msg_void1(center, 'setDelegate:', g_notification_delegate)
	actions := msg_id(get_class('NSMutableArray'), 'array')
	show := C.witty_action_notification_action(nsstring(notification_show), nsstring('Show'), 0)
	msg_void1(actions, 'addObject:', show)
	category := C.witty_action_notification_category(nsstring(notification_category), actions, msg_id(get_class('NSArray'),
		'array'), 1)
	categories := msg_id1(get_class('NSSet'), 'setWithObject:', category)
	msg_void1(center, 'setNotificationCategories:', categories)
}

fn new_notification_job(surface &NativeActionSurface, operation int) &NativeNotificationJob {
	job := &NativeNotificationJob{
		surface:   surface
		operation: operation
	}
	g_notification_jobs[u64(job)] = job
	return job
}

fn notification_job_complete(job &NativeNotificationJob) {
	g_notification_jobs.delete(u64(job))
}

pub fn (mut surface NativeActionSurface) desktop_notification(title string, body string) {
	if surface.closed { return }
	notification_setup()
	// The source requests authorization and checks settings independently.
	authorize := new_notification_job(&surface, 0)
	C.witty_action_notification_authorize(notification_center(), 6,
		voidptr(notification_authorized), voidptr(authorize))
	mut settings := new_notification_job(&surface, 1)
	settings.title = title.clone()
	settings.body = body.clone()
	C.witty_action_notification_settings(notification_center(), voidptr(notification_result),
		voidptr(settings))
}

fn notification_authorized(context voidptr, error ObjId, _code i64, granted bool) {
	mut job := unsafe { &NativeNotificationJob(context) }
	job.granted = granted
	if !is_nil(error) { msg_void(error, 'retain') }
	job.result = error
	dispatch_main(notification_process, context)
}

fn notification_result(context voidptr, result ObjId, _code i64, _granted bool) {
	mut job := unsafe { &NativeNotificationJob(context) }
	if !is_nil(result) { msg_void(result, 'retain') }
	job.result = result
	dispatch_main(notification_process, context)
}

fn notification_process(context voidptr) {
	mut job := unsafe { &NativeNotificationJob(context) }
	defer {
		if !is_nil(job.result) { msg_void(job.result, 'release') }
		notification_job_complete(job)
	}
	if job.surface.closed { return }
	match job.operation {
		0 {
			if !is_nil(job.result) {
				eprintln('Error while requesting notification authorization: ${objc_utf8_string(msg_id(job.result, 'localizedDescription'))}')
			}
		}
		1 {
			if msg_i64(job.result, 'authorizationStatus') == 2 {
				job.surface.schedule_notification(job.title, job.body)
			}
		}
		2 {
			if !is_nil(job.result) {
				eprintln('Error scheduling user notification: ${objc_utf8_string(msg_id(job.result, 'localizedDescription'))}')
				return
			}
			job.surface.notification_identifiers << job.identifier
			if job.surface.focused {
				C.witty_action_timer(3, job.surface.owner, sel('notificationExpiration:'),
					nsstring(job.identifier), false)
			}
		}
		3 {
			status := msg_i64(job.result, 'authorizationStatus')
			if status == 2 && msg_i64(job.result, 'badgeSetting') == 2 {
				set_dock_bell_badge()
			} else if status == 0 {
				authorize := new_notification_job(job.surface, 4)
				C.witty_action_notification_authorize(notification_center(), 1,
					voidptr(notification_authorized), voidptr(authorize))
			}
		}
		4 {
			if !is_nil(job.result) {
				eprintln('Error requesting badge authorization: ${objc_utf8_string(msg_id(job.result, 'localizedDescription'))}')
			} else if job.granted {
				set_dock_bell_badge()
			}
		}
		else {}
	}
}

fn (mut surface NativeActionSurface) schedule_notification(title string, body string) {
	content := notification_content(&surface, title, body)
	defer { msg_void(content, 'release') }
	identifier := objc_utf8_string(msg_id(msg_id(get_class('NSUUID'), 'UUID'), 'UUIDString'))
	request := msg_id3(get_class('UNNotificationRequest'),
		'requestWithIdentifier:content:trigger:', nsstring(identifier), content, nil_obj())
	mut job := new_notification_job(&surface, 2)
	job.identifier = identifier
	C.witty_action_notification_add(notification_center(), request, voidptr(notification_result),
		voidptr(job))
}

fn notification_content(surface &NativeActionSurface, title string, body string) ObjId {
	content := new_obj('UNMutableNotificationContent')
	msg_void1(content, 'setTitle:', nsstring(title))
	msg_void1(content, 'setSubtitle:', nsstring(surface.title))
	msg_void1(content, 'setBody:', nsstring(body))
	msg_void1(content, 'setSound:', msg_id(get_class('UNNotificationSound'), 'defaultSound'))
	msg_void1(content, 'setCategoryIdentifier:', nsstring(notification_category))
	info := msg_id2(get_class('NSDictionary'), 'dictionaryWithObject:forKey:',
		nsstring(surface.uuid), nsstring('surface'))
	msg_void1(content, 'setUserInfo:', info)
	return content
}

pub fn (mut surface NativeActionSurface) remove_notifications() {
	if surface.notification_identifiers.len == 0 { return }
	identifiers := msg_id(get_class('NSMutableArray'), 'array')
	for id in surface.notification_identifiers {
		msg_void1(identifiers, 'addObject:', nsstring(id))
	}
	msg_void1(notification_center(), 'removeDeliveredNotificationsWithIdentifiers:', identifiers)
	surface.notification_identifiers.clear()
}

fn notification_expiration(self ObjId, _cmd Sel, timer ObjId) {
	mut surface := action_owner_state(self) or { return }
	if surface.closed { return }
	id := objc_utf8_string(msg_id(timer, 'userInfo'))
	surface.notification_identifiers = surface.notification_identifiers.filter(it != id)
	msg_void1(notification_center(), 'removeDeliveredNotificationsWithIdentifiers:', msg_id1(get_class('NSArray'),
		'arrayWithObject:', nsstring(id)))
}

fn notification_surface(notification ObjId) ?&NativeActionSurface {
	content := msg_id(msg_id(notification, 'request'), 'content')
	uuid := objc_utf8_string(msg_id1(msg_id(content, 'userInfo'), 'objectForKey:',
		nsstring('surface')))
	for _, surface in g_action_surfaces {
		if !surface.closed && surface.uuid == uuid { return surface }
	}
	return none
}

fn notification_response(_self ObjId, _cmd Sel, _center ObjId, response ObjId, completion ObjId) {
	C.witty_action_notification_dispatch(response, completion, voidptr(notification_response_main))
}

fn notification_response_main(context voidptr) {
	delivery := unsafe { &C.witty_action_notification_delivery(context) }
	defer { C.witty_action_notification_delivery_free(delivery) }
	response := delivery.object
	completion := delivery.completion
	notification := msg_id(response, 'notification')
	if mut surface := notification_surface(notification) {
		action := objc_utf8_string(msg_id(response, 'actionIdentifier'))
		if action in ['com.apple.UNNotificationDefaultActionIdentifier', notification_show,
			'com.apple.UNNotificationDismissActionIdentifier'] {
			identifier := objc_utf8_string(msg_id(msg_id(notification, 'request'), 'identifier'))
			if identifier in surface.notification_identifiers {
				surface.notification_identifiers =
					surface.notification_identifiers.filter(it != identifier)
				if action != 'com.apple.UNNotificationDismissActionIdentifier' {
					if surface.callbacks.present != unsafe { nil } {
						surface.callbacks.present(surface.userdata, surface.view)
					} else {
						present_view(surface.view)
					}
				}
			}
		}
	}
	C.witty_action_complete_void(completion)
}

fn notification_present(_self ObjId, _cmd Sel, _center ObjId, notification ObjId, completion ObjId) {
	C.witty_action_notification_dispatch(notification, completion, voidptr(notification_present_main))
}

fn notification_present_main(context voidptr) {
	delivery := unsafe { &C.witty_action_notification_delivery(context) }
	defer { C.witty_action_notification_delivery_free(delivery) }
	notification := delivery.object
	completion := delivery.completion
	mut options := u64(0)
	if surface := notification_surface(notification) {
		if !msg_bool(view_window(surface.view), 'isKeyWindow') || !surface.focused { options = 18 }
	}
	C.witty_action_complete_options(completion, options)
}

pub fn (mut surface NativeActionSurface) bell_notification(system bool, attention bool) {
	if system { msg_void(get_class('NSSound'), 'beep') }
	if attention {
		msg_id_u64(shared_app(), 'requestUserAttention:', 10)
		job := new_notification_job(&surface, 3)
		C.witty_action_notification_settings(notification_center(), voidptr(notification_result),
			voidptr(job))
	}
}

fn set_dock_bell_badge() {
	dock := msg_id(shared_app(), 'dockTile')
	msg_void1(dock, 'setBadgeLabel:', nsstring('•'))
	msg_void(dock, 'display')
}

pub fn notification_app_focus(active bool) {
	if active {
		dock := msg_id(shared_app(), 'dockTile')
		msg_void1(dock, 'setBadgeLabel:', nil_obj())
		msg_void(dock, 'display')
	}
}
