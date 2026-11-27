module witty_macos

fn C.objc_initWeak(location &voidptr, value voidptr) voidptr
fn C.objc_loadWeak(location &voidptr) voidptr
fn C.objc_destroyWeak(location &voidptr)
@[heap]
pub struct NativeWeakObject { mut: value voidptr }
pub fn new_native_weak_object(object voidptr) &NativeWeakObject { mut weak := &NativeWeakObject{}; C.objc_initWeak(&weak.value, object); return weak }
pub fn (object &NativeWeakObject) object() voidptr { return C.objc_loadWeak(unsafe { &object.value }) }
pub fn (mut object NativeWeakObject) deinit() { C.objc_destroyWeak(&object.value) }
pub fn release_native_object(object voidptr) { msg_void(object, 'release') }
