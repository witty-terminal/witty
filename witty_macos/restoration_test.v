module witty_macos

import os

fn saved_fixture_surface(view voidptr) NativeSavedSurface {
	index:=int(u64(view))
	mut pwd:=?string(none)
	if index==1 { pwd='/tmp/one' } else if index==3 { pwd='/tmp/three' }
	return NativeSavedSurface{uuid:'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE${index}',pwd:pwd,title:if index==1 { 'one' } else if index==2 { 'manual' } else { '' },is_user_set_title:index==2}
}
fn loaded_fixture_surface(saved NativeSavedSurface,quick bool) ?voidptr {
	assert !quick
	index:=saved.uuid[saved.uuid.len-1]-`0`
	assert saved == saved_fixture_surface(voidptr(u64(index)))
	return voidptr(u64(index))
}
fn fixture_tree() NativeSplitTree {
	right:=&NativeSplitNode{axis:.vertical,ratio:0.6,left:native_split_leaf(voidptr(2)),right:native_split_leaf(voidptr(3))}
	return NativeSplitTree{root:&NativeSplitNode{axis:.horizontal,ratio:0.3,left:native_split_leaf(voidptr(1)),right:right},zoomed:right}
}
fn read_codable_inner(path string) voidptr {
	data:=msg_id1(get_class('NSData'),'dataWithContentsOfFile:',nsstring(path))
	assert !is_nil(data)
	decoder:=msg_id2(alloc('NSKeyedUnarchiver'),'initForReadingFromData:error:',data,nil_obj())
	assert !is_nil(decoder)
	return voidptr(msg_id2(decoder,'decodeObjectOfClasses:forKey:',codable_classes(),nsstring('value')))
}
fn test_decode_original_swift_codable_split_tree_archive() {
	path:=os.join_path(@VMODROOT,'macos','testdata','source-split-tree.archive')
	value:=read_codable_inner(path)
	tree:=decode_native_split_tree(value,false,loaded_fixture_surface) or { panic(err) }
	assert tree.root.equal(fixture_tree().root)
	assert tree.zoomed == tree.root.right
}
fn test_native_secure_codable_bridge_version_and_reference_roundtrip() {
	value:=encode_native_split_tree(fixture_tree(),saved_fixture_surface)
	coder:=msg_id1(alloc('NSKeyedArchiver'),'initRequiringSecureCoding:',ObjId(1))
	encode_native_restorable(coder,value,7)
	data:=msg_id(coder,'encodedData')
	decoder:=msg_id2(alloc('NSKeyedUnarchiver'),'initForReadingFromData:error:',data,nil_obj())
	assert decode_native_restorable(decoder,1)==none
	decoded:=decode_native_restorable(decoder,7) or { panic('secure bridge failed') }
	tree:=decode_native_split_tree(decoded,false,loaded_fixture_surface) or { panic(err) }
	assert tree.root.equal(fixture_tree().root)
	assert tree.zoomed == tree.root.right
	inner:=msg_id1(alloc('NSKeyedArchiver'),'initRequiringSecureCoding:',ObjId(1))
	msg_void2(inner,'encodeObject:forKey:',value,nsstring('value'))
	assert msg_bool2(msg_id(inner,'encodedData'),'writeToFile:atomically:',nsstring('/tmp/witty-ultra-fixes/native-v-split-tree.archive'),ObjId(1))
}
fn test_restoration_rejects_unknown_tree_version_and_missing_node_type() {
	value:=encode_native_split_tree(fixture_tree(),saved_fixture_surface)
	codable_put(value,'version',codable_int(2))
	if _:=decode_native_split_tree(value,false,loaded_fixture_surface) { assert false }
	codable_put(value,'version',codable_int(1)); codable_put(value,'root',codable_dictionary())
	if _:=decode_native_split_tree(value,false,loaded_fixture_surface) { assert false }
}
fn test_quick_screen_cache_restores_fractional_geometry_and_native_dates() {
	cache:=QuickScreenCache{entries:{'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1':QuickScreenEntry{frame:SplitBounds{x:4,y:5,width:479.52,height:350},screen_width:1440,screen_height:900,scale:2,last_seen:1700000000}}}
	restored:=decode_quick_screen_cache(encode_quick_screen_cache(cache)) or { panic(err) }
	assert restored==cache
	from_swift:=decode_quick_screen_cache(read_codable_inner(os.join_path(@VMODROOT,'macos','testdata','source-quick-screen-cache.archive'))) or { panic(err) }
	assert from_swift==cache
	inner:=msg_id1(alloc('NSKeyedArchiver'),'initRequiringSecureCoding:',ObjId(1))
	msg_void2(inner,'encodeObject:forKey:',encode_quick_screen_cache(cache),nsstring('value'))
	assert msg_bool2(msg_id(inner,'encodedData'),'writeToFile:atomically:',nsstring('/tmp/witty-ultra-fixes/native-v-quick-screen-cache.archive'),ObjId(1))
}
