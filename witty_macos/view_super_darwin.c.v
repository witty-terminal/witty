module witty_macos

#insert "@VMODROOT/witty_macos/view_super_abi.h"

fn C.witty_macos_view_super_bool0(view ObjId, defining_class ObjId, selector Sel) bool
fn C.witty_macos_view_super_void0(view ObjId, defining_class ObjId, selector Sel)
fn C.witty_macos_view_super_void1(view ObjId, defining_class ObjId, selector Sel, argument ObjId)

fn view_super_bool(view ObjId, defining_class string, selector string) bool {
	return C.witty_macos_view_super_bool0(view, get_class(defining_class), sel(selector))
}
fn view_super_void(view ObjId, defining_class string, selector string) {
	C.witty_macos_view_super_void0(view, get_class(defining_class), sel(selector))
}
fn view_super_void1(view ObjId, defining_class string, selector string, argument ObjId) {
	C.witty_macos_view_super_void1(view, get_class(defining_class), sel(selector), argument)
}
