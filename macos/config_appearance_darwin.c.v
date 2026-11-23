@[has_globals]
module macos

#insert "@VMODROOT/macos/config_appearance_abi.h"

fn C.witty_macos_observe_application_appearance(observer voidptr)
fn C.witty_macos_remove_application_appearance_observer(observer voidptr)

pub type ApplicationAppearanceCallback = fn (dark bool)

__global (
	g_application_appearance_observer ObjId
	g_application_appearance_callback ApplicationAppearanceCallback
)

// NSAppearance+Extension.isDark examines the native appearance's name.
fn native_appearance_is_dark(appearance ObjId) bool {
	return objc_utf8_string(msg_id(appearance, 'name')).to_lower().contains('dark')
}

pub fn native_application_is_dark() bool {
	return native_appearance_is_dark(msg_id(shared_app(), 'effectiveAppearance'))
}

pub fn native_window_is_visible(window voidptr) bool { return msg_bool(window, 'isVisible') }

fn native_application_appearance_observed(_self ObjId, _cmd Sel, key ObjId, _object ObjId, change ObjId, _context voidptr) {
	if objc_utf8_string(key) != 'effectiveAppearance' { return }
	appearance := msg_id1(change, 'objectForKey:', nsstring('new'))
	if is_nil(appearance) || appearance == msg_id(get_class('NSNull'), 'null') { return }
	if g_application_appearance_callback != unsafe { nil } {
		g_application_appearance_callback(native_appearance_is_dark(appearance))
	}
}

pub fn set_application_appearance_callback(callback ApplicationAppearanceCallback) {
	stop_application_appearance_callback()
	if is_nil(get_class('VTApplicationAppearanceObserver')) {
		cls := C.macos_objc_allocate_class_pair(get_class('NSObject'),
			cstr('VTApplicationAppearanceObserver'), 0)
		add_method(cls, 'observeValueForKeyPath:ofObject:change:context:',
			voidptr(native_application_appearance_observed), 'v@:@@@^v')
		C.macos_objc_register_class_pair(cls)
	}
	g_application_appearance_callback = callback
	g_application_appearance_observer = msg_id(alloc('VTApplicationAppearanceObserver'), 'init')
	// AppDelegate observes .new and .initial after libwitty is initialized.
	C.witty_macos_observe_application_appearance(voidptr(g_application_appearance_observer))
}

pub fn stop_application_appearance_callback() {
	if !is_nil(g_application_appearance_observer) {
		C.witty_macos_remove_application_appearance_observer(voidptr(g_application_appearance_observer))
		msg_void(g_application_appearance_observer, 'release')
		g_application_appearance_observer = nil_obj()
	}
	g_application_appearance_callback = unsafe { nil }
}

// AppDelegate.syncAppearance and NSAppearance.init(ghosttyConfig:) project
// window-theme onto NSApplication, independently of per-surface appearance.
pub fn sync_native_application_appearance(config NativeWindowConfig) {
	name := match config.theme {
		0 {
			if native_color_luminance(config.background) > 0.5 {
				'NSAppearanceNameAqua'
			} else {
				'NSAppearanceNameDarkAqua'
			}
		}
		2 {
			'NSAppearanceNameAqua'
		}
		3 {
			'NSAppearanceNameDarkAqua'
		}
		else {
			''
		}
	}

	msg_void1(shared_app(), 'setAppearance:', if name.len > 0 {
		msg_id1(get_class('NSAppearance'), 'appearanceNamed:', nsstring(name))
	} else {
		nil_obj()
	})
}
