module witty_macos

#flag darwin -licucore
#insert "@VMODROOT/witty_macos/source_strings_abi.h"
fn C.witty_source_c_utf8_repair(source &char) ObjId

// Swift String(data: Data(bytes:count:), encoding: .utf8): all bytes participate,
// embedded NUL remains part of the string, and malformed UTF-8 returns nil.
pub fn source_utf8(value string) ?string {
	decoded := nsstring(value)
	if is_nil(decoded) { return none }
	return objc_utf8_string(decoded)
}

// Swift String(cString:encoding: .utf8): the actual C prefix stops at NUL,
// independently of the V slice length or the shared nsstring bridge.
pub fn source_c_utf8(value string) ?string {
	decoded := C.macos_objc_msg_id1(get_class('NSString'), sel('stringWithUTF8String:'), value.str)
	if is_nil(decoded) { return none }
	return objc_utf8_string(decoded)
}

// Ghostty.Action.StartSearch's String(cString:) repairs malformed code units.
pub fn source_c_utf8_repair(value string) string {
	return objc_utf8_string(C.witty_source_c_utf8_repair(&char(value.str)))
}
