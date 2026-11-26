#ifndef WITTY_CONTROLLER_TREE_FOCUS_TEST_ABI_H
#define WITTY_CONTROLLER_TREE_FOCUS_TEST_ABI_H
#include <Foundation/Foundation.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>

static id witty_tree_focus_views[16];
static Class witty_tree_focus_parents[16];
static int witty_tree_focus_resigns[16];
static int witty_tree_focus_count;
static int witty_tree_focus_class_count;

static BOOL witty_tree_focus_resign(id self, SEL command) {
    for (int i = 0; i < witty_tree_focus_count; i++) {
        if (witty_tree_focus_views[i] != self) continue;
        witty_tree_focus_resigns[i]++;
        struct objc_super parent = { self, witty_tree_focus_parents[i] };
        return ((BOOL (*)(struct objc_super*, SEL))objc_msgSendSuper)(&parent, command);
    }
    return YES;
}
static void witty_tree_focus_reset(void) { witty_tree_focus_count = 0; }
static void witty_tree_focus_track(void* view) {
    char name[80];
    snprintf(name, sizeof(name), "WittyTreeFocusViewFixture%d", ++witty_tree_focus_class_count);
    Class parent = object_getClass((id)view);
    Class cls = objc_allocateClassPair(parent, name, 0);
    class_addMethod(cls, sel_registerName("resignFirstResponder"), (IMP)witty_tree_focus_resign, "B@:");
    objc_registerClassPair(cls);
    int index = witty_tree_focus_count++;
    witty_tree_focus_views[index] = (id)view;
    witty_tree_focus_parents[index] = parent;
    witty_tree_focus_resigns[index] = 0;
    object_setClass((id)view, cls);
}
static int witty_tree_focus_calls(void* view) {
    for (int i = 0; i < witty_tree_focus_count; i++)
        if (witty_tree_focus_views[i] == (id)view) return witty_tree_focus_resigns[i];
    return -1;
}
static void witty_tree_focus_clear_calls(void) {
    for (int i = 0; i < witty_tree_focus_count; i++) witty_tree_focus_resigns[i] = 0;
}
static void witty_tree_focus_hide_window(void* window) {
    ((void (*)(id, SEL, id))objc_msgSend)((id)window, sel_registerName("orderOut:"), nil);
}
static void* witty_tree_focus_first_responder(void* window) {
    return ((id (*)(id, SEL))objc_msgSend)((id)window, sel_registerName("firstResponder"));
}
static unsigned long witty_tree_focus_retain_count(void* view) {
    return ((unsigned long (*)(id, SEL))objc_msgSend)((id)view, sel_registerName("retainCount"));
}
static BOOL witty_tree_focus_accepts(id self, SEL command) { return YES; }
static void witty_tree_focus_neutral_responder(void* container, void* window) {
    Class cls = objc_getClass("WittyTreeFocusNeutralFixture");
    if (!cls) {
        cls = objc_allocateClassPair(objc_getClass("NSView"), "WittyTreeFocusNeutralFixture", 0);
        class_addMethod(cls, sel_registerName("acceptsFirstResponder"), (IMP)witty_tree_focus_accepts, "B@:");
        objc_registerClassPair(cls);
    }
    id view = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
    view = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("init"));
    ((void (*)(id, SEL, id))objc_msgSend)((id)container, sel_registerName("addSubview:"), view);
    ((BOOL (*)(id, SEL, id))objc_msgSend)((id)window, sel_registerName("makeFirstResponder:"), view);
    ((void (*)(id, SEL))objc_msgSend)(view, sel_registerName("release"));
}
static void witty_tree_focus_launch(void) {
    id app = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
    ((void (*)(id, SEL))objc_msgSend)(app, sel_registerName("finishLaunching"));
}
static void witty_tree_focus_pump(double seconds) {
    id loop = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("NSRunLoop"), sel_registerName("currentRunLoop"));
    id until = ((id (*)(id, SEL, double))objc_msgSend)((id)objc_getClass("NSDate"), sel_registerName("dateWithTimeIntervalSinceNow:"), seconds);
    ((void (*)(id, SEL, id))objc_msgSend)(loop, sel_registerName("runUntilDate:"), until);
}
#endif
