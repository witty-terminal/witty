module witty_macos

fn C.witty_controller_timer(seconds f64, target ObjId, selector Sel) ObjId
fn C.witty_controller_register_undo(manager ObjId, target ObjId, selector Sel)

#flag darwin -framework ApplicationServices

#insert "@VMODROOT/witty_macos/controller_abi.h"
fn C.witty_controller_dispatch_after(seconds f64, callback voidptr, context voidptr)
fn C.witty_controller_timer(seconds f64, target ObjId, selector Sel) ObjId
fn C.witty_controller_animate(context voidptr, change voidptr, complete voidptr)
pub fn dispatch_after(seconds f64, callback fn (voidptr), context voidptr) { C.witty_controller_dispatch_after(seconds, voidptr(callback), context) }
