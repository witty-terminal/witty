module witty_macos

#insert "@VMODROOT/witty_macos/restoration_abi.h"
fn C.witty_restoration_encode_int(coder ObjId, value i64, key ObjId)
fn C.witty_restoration_decode_int(coder ObjId, key ObjId) i64
fn C.witty_restoration_number_bool(value bool) ObjId
fn C.witty_restoration_number_int(value i64) ObjId
fn C.witty_restoration_complete(completion voidptr, window voidptr, error voidptr)
fn C.objc_getMetaClass(name &char) ObjId
fn C.object_getClass(object ObjId) ObjId
fn C.objc_getProtocol(name &char) voidptr
fn C.class_addProtocol(cls ObjId, protocol voidptr) bool

// Swift CodableBridge encodes Codable's Foundation object graph at "value"
// in a secure NSKeyedArchiver, and stores that archive's NSData at "data".
// The dictionaries/arrays below are the same Foundation Codable containers.
pub fn codable_dictionary() voidptr { return msg_id(get_class('NSMutableDictionary'),'dictionary') }
pub fn codable_array() voidptr { return msg_id(get_class('NSMutableArray'),'array') }
pub fn codable_put(dictionary voidptr, key string, value voidptr) { msg_void2(dictionary,'setObject:forKey:',value,nsstring(key)) }
pub fn codable_get(dictionary voidptr, key string) voidptr { return msg_id1(dictionary,'objectForKey:',nsstring(key)) }
pub fn codable_string(value string) voidptr { return nsstring(value) }
pub fn codable_int(value int) voidptr { return C.witty_restoration_number_int(i64(value)) }
pub fn codable_double(value f64) voidptr { return msg_id_f64(get_class('NSNumber'),'numberWithDouble:',value) }
pub fn codable_bool(value bool) voidptr { return C.witty_restoration_number_bool(value) }
pub fn codable_null() voidptr { return nsstring('$null') }
pub fn codable_add(array voidptr, value voidptr) { msg_void1(array,'addObject:',value) }
pub fn codable_count(array voidptr) int { return int(msg_u64(array,'count')) }
pub fn codable_at(array voidptr, index int) voidptr { return msg_id_u64(array,'objectAtIndex:',u64(index)) }
pub fn codable_as_string(object voidptr) ?string { if is_nil(object) || !msg_bool1(object,'isKindOfClass:',get_class('NSString')) { return none }; return objc_utf8_string(object) }
pub fn codable_as_optional_string(object voidptr) ?string { value:=codable_as_string(object) or { return none }; if value=='$null' { return none }; return value }
pub fn codable_as_int(object voidptr) ?int { if is_nil(object) || !msg_bool1(object,'isKindOfClass:',get_class('NSNumber')) { return none }; return int(msg_i64(object,'integerValue')) }
pub fn codable_as_double(object voidptr) ?f64 { if is_nil(object) || !msg_bool1(object,'isKindOfClass:',get_class('NSNumber')) { return none }; return msg_f64(object,'doubleValue') }
pub fn codable_is_dictionary(object voidptr) bool { return !is_nil(object) && msg_bool1(object,'isKindOfClass:',get_class('NSDictionary')) }
pub fn codable_is_array(object voidptr) bool { return !is_nil(object) && msg_bool1(object,'isKindOfClass:',get_class('NSArray')) }
pub fn retain_native_object(object voidptr) { msg_void(object,'retain') }
fn codable_classes() ObjId {
	classes := [get_class('NSDictionary'),get_class('NSArray'),get_class('NSString'),get_class('NSNumber'),get_class('NSNull'),get_class('NSDate'),get_class('NSData')]
	return msg_id1(get_class('NSSet'),'setWithArray:',C.witty_macos_array(classes.data,uint(classes.len)))
}
fn bridge_supports_secure_coding(_self ObjId,_cmd Sel) bool { return true }
fn bridge_encode(self ObjId,_cmd Sel,coder ObjId) {
	value := C.macos_objc_get_ptr_ivar(self,cstr('vtValue'))
	archiver := msg_id1(msg_id(get_class('NSKeyedArchiver'),'alloc'),'initRequiringSecureCoding:',ObjId(1))
	msg_void2(archiver,'encodeObject:forKey:',value,nsstring('value'))
	msg_void2(coder,'encodeObject:forKey:',msg_id(archiver,'encodedData'),nsstring('data'))
	msg_void(archiver,'release')
}
fn bridge_init_with_coder(self ObjId,_cmd Sel,coder ObjId) ObjId {
	data := msg_id2(coder,'decodeObjectOfClass:forKey:',get_class('NSData'),nsstring('data'))
	if is_nil(data) { return nil_obj() }
	unarchiver := msg_id2(msg_id(get_class('NSKeyedUnarchiver'),'alloc'),'initForReadingFromData:error:',data,nil_obj())
	if is_nil(unarchiver) { return nil_obj() }
	value := msg_id2(unarchiver,'decodeObjectOfClasses:forKey:',codable_classes(),nsstring('value'))
	if is_nil(value) { msg_void(unarchiver,'release'); return nil_obj() }
	msg_void(value,'retain')
	C.macos_objc_set_ptr_ivar(self,cstr('vtValue'),value)
	msg_void(unarchiver,'release')
	return self
}
fn bridge_dealloc(self ObjId,_cmd Sel) { msg_void(C.macos_objc_get_ptr_ivar(self,cstr('vtValue')),'release'); msg_super_void(self,'dealloc') }
fn codable_bridge_class() ObjId {
	mut cls := get_class('VTTerminalCodableBridge')
	if !is_nil(cls) { return cls }
	cls = C.macos_objc_allocate_class_pair(get_class('NSObject'),cstr('VTTerminalCodableBridge'),0)
	C.macos_class_add_ivar(cls,cstr('vtValue'),sizeof(voidptr),3,cstr('@'))
	C.class_addProtocol(cls,C.objc_getProtocol(cstr('NSSecureCoding')))
	add_method(cls,'initWithCoder:',voidptr(bridge_init_with_coder),'@@:@')
	add_method(cls,'encodeWithCoder:',voidptr(bridge_encode),'v@:@')
	add_method(cls,'dealloc',voidptr(bridge_dealloc),'v@:')
	add_method(C.object_getClass(cls),'supportsSecureCoding',voidptr(bridge_supports_secure_coding),'B@:')
	C.macos_objc_register_class_pair(cls)
	return cls
}
pub fn encode_native_restorable(coder voidptr, value voidptr, version int) {
	C.witty_restoration_encode_int(coder,i64(version),nsstring('version'))
	bridge := msg_id(msg_id(codable_bridge_class(),'alloc'),'init')
	msg_void(value,'retain')
	C.macos_objc_set_ptr_ivar(bridge,cstr('vtValue'),value)
	msg_void2(coder,'encodeObject:forKey:',bridge,nsstring('state'))
	msg_void(bridge,'release')
}
pub fn decode_native_restorable(coder voidptr, version int) ?voidptr {
	if C.witty_restoration_decode_int(coder,nsstring('version')) != version { return none }
	bridge := msg_id2(coder,'decodeObjectOfClass:forKey:',codable_bridge_class(),nsstring('state'))
	if is_nil(bridge) { return none }
	value := C.macos_objc_get_ptr_ivar(bridge,cstr('vtValue'))
	if is_nil(value) { return none }
	return voidptr(value)
}
