module witty_macos

pub struct NativeSavedSurface {
pub:
	pwd ?string
	uuid string
	title ?string
	is_user_set_title bool
}
pub type NativeSaveSurface = fn (voidptr) NativeSavedSurface
pub type NativeLoadSurface = fn (NativeSavedSurface, bool) ?voidptr
fn encode_saved_surface(surface NativeSavedSurface) voidptr {
	d := codable_dictionary()
	mut pwd_object := codable_null()
	if pwd := surface.pwd { pwd_object=codable_string(pwd) }
	codable_put(d,'pwd',pwd_object)
	codable_put(d,'uuid',codable_string(surface.uuid))
	mut title_object := codable_null()
	if title := surface.title { title_object=codable_string(title) }
	codable_put(d,'title',title_object)
	codable_put(d,'isUserSetTitle',codable_bool(surface.is_user_set_title))
	return d
}
fn decode_saved_surface(value voidptr) !NativeSavedSurface {
	if !codable_is_dictionary(value) { return error('Invalid surface record') }
	uuid := codable_as_string(codable_get(value,'uuid')) or { return error('Missing surface UUID') }
	if is_nil(codable_get(value,'pwd')) { return error('Missing surface directory') }
	return NativeSavedSurface{pwd:codable_as_optional_string(codable_get(value,'pwd')),uuid:uuid,title:codable_as_optional_string(codable_get(value,'title')),is_user_set_title:(codable_as_int(codable_get(value,'isUserSetTitle')) or { 0 }) != 0}
}
fn encode_split_node(node &NativeSplitNode, save NativeSaveSurface) voidptr {
	d := codable_dictionary()
	if node.is_leaf() { codable_put(d,'view',encode_saved_surface(save(node.view))); return d }
	split := codable_dictionary()
	direction := codable_dictionary()
	codable_put(direction,if node.axis == .horizontal { 'horizontal' } else { 'vertical' },codable_dictionary())
	codable_put(split,'direction',direction)
	codable_put(split,'ratio',codable_double(node.ratio))
	codable_put(split,'left',encode_split_node(node.left,save))
	codable_put(split,'right',encode_split_node(node.right,save))
	codable_put(d,'split',split)
	return d
}
pub fn encode_native_split_tree(tree NativeSplitTree, save NativeSaveSurface) voidptr {
	d := codable_dictionary()
	codable_put(d,'version',codable_int(1))
	if tree.root != unsafe { nil } { codable_put(d,'root',encode_split_node(tree.root,save)) }
	if tree.zoomed != unsafe { nil } { if path := tree.root.path(tree.zoomed) {
		components := codable_array()
		for right in path { component := codable_dictionary(); codable_put(component,if right { 'right' } else { 'left' },codable_dictionary()); codable_add(components,component) }
		zoomed := codable_dictionary(); codable_put(zoomed,'path',components); codable_put(d,'zoomed',zoomed)
	} }
	return d
}
fn decode_split_node(value voidptr, quick bool, load NativeLoadSurface) !&NativeSplitNode {
	if !codable_is_dictionary(value) { return error('No valid node type found') }
	view := codable_get(value,'view')
	if !is_nil(view) { saved := decode_saved_surface(view)!; restored := load(saved,quick) or { return error('Surface restoration failed') }; return native_split_leaf(restored) }
	split := codable_get(value,'split')
	if !codable_is_dictionary(split) { return error('No valid node type found') }
	direction := codable_get(split,'direction')
	axis := if !is_nil(codable_get(direction,'horizontal')) { SplitAxis.horizontal } else if !is_nil(codable_get(direction,'vertical')) { SplitAxis.vertical } else { return error('Invalid split direction') }
	ratio := codable_as_double(codable_get(split,'ratio')) or { return error('Missing split ratio') }
	left := decode_split_node(codable_get(split,'left'),quick,load)!
	right := decode_split_node(codable_get(split,'right'),quick,load)!
	return &NativeSplitNode{axis:axis,ratio:ratio,left:left,right:right}
}
pub fn decode_native_split_tree(value voidptr, quick bool, load NativeLoadSurface) !NativeSplitTree {
	if !codable_is_dictionary(value) || (codable_as_int(codable_get(value,'version')) or { 0 }) != 1 { return error('Unsupported SplitTree version') }
	r := codable_get(value,'root')
	mut root := unsafe { &NativeSplitNode(nil) }
	if !is_nil(r) { root = decode_split_node(r,quick,load)! }
	mut zoomed := unsafe { &NativeSplitNode(nil) }
	z := codable_get(value,'zoomed')
	if root != unsafe { nil } && !is_nil(z) {
		components := codable_get(z,'path')
		if !codable_is_array(components) { return error('Invalid split path') }
		mut path := []bool{}
		for i in 0 .. codable_count(components) { component := codable_at(components,i); if !is_nil(codable_get(component,'left')) { path << false } else if !is_nil(codable_get(component,'right')) { path << true } else { return error('Invalid split path component') } }
		if target := root.at(path) { zoomed = target }
	}
	return NativeSplitTree{root:root,zoomed:zoomed}
}
pub fn encode_quick_screen_cache(cache QuickScreenCache) voidptr {
	// Dictionary<UUID, DisplayEntry> uses Codable's alternating key/value array.
	entries := codable_array()
	for uuid, entry in cache.entries {
		value := codable_dictionary()
		frame := codable_array(); origin := codable_array(); size := codable_array()
		codable_add(origin,codable_double(entry.frame.x)); codable_add(origin,codable_double(entry.frame.y))
		codable_add(size,codable_double(entry.frame.width)); codable_add(size,codable_double(entry.frame.height))
		codable_add(frame,origin); codable_add(frame,size)
		screen_size := codable_array(); codable_add(screen_size,codable_double(entry.screen_width)); codable_add(screen_size,codable_double(entry.screen_height))
		codable_put(value,'frame',frame); codable_put(value,'screenSize',screen_size); codable_put(value,'scale',codable_double(entry.scale))
		codable_put(value,'lastSeen',voidptr(msg_id_f64(get_class('NSDate'),'dateWithTimeIntervalSince1970:',entry.last_seen)))
		codable_add(entries,codable_string(uuid)); codable_add(entries,value)
	}
	return entries
}
pub fn decode_quick_screen_cache(value voidptr) !QuickScreenCache {
	if !codable_is_array(value) || codable_count(value)%2 != 0 { return error('Invalid screen cache') }
	mut cache := QuickScreenCache{}
	for i:=0; i<codable_count(value); i+=2 {
		uuid := codable_as_string(codable_at(value,i)) or { return error('Invalid display UUID') }
		key := native_uuid_string(uuid) or { return error('Invalid display UUID') }
		entry := codable_at(value,i+1)
		frame := codable_get(entry,'frame'); screen := codable_get(entry,'screenSize')
		if !codable_is_array(frame) || codable_count(frame)!=2 || !codable_is_array(screen) || codable_count(screen)!=2 { return error('Invalid screen geometry') }
		origin := codable_at(frame,0); size := codable_at(frame,1)
		if !codable_is_array(origin) || codable_count(origin)!=2 || !codable_is_array(size) || codable_count(size)!=2 { return error('Invalid screen frame') }
		date := codable_get(entry,'lastSeen'); if !msg_bool1(date,'isKindOfClass:',get_class('NSDate')) { return error('Invalid last-seen date') }
		cache.entries[key] = QuickScreenEntry{frame:SplitBounds{x:codable_as_double(codable_at(origin,0)) or { return error('Invalid x') },y:codable_as_double(codable_at(origin,1)) or { return error('Invalid y') },width:codable_as_double(codable_at(size,0)) or { return error('Invalid width') },height:codable_as_double(codable_at(size,1)) or { return error('Invalid height') }},screen_width:codable_as_double(codable_at(screen,0)) or { return error('Invalid screen width') },screen_height:codable_as_double(codable_at(screen,1)) or { return error('Invalid screen height') },scale:codable_as_double(codable_get(entry,'scale')) or { return error('Invalid scale') },last_seen:msg_f64(date,'timeIntervalSince1970')}
	}
	return cache
}
