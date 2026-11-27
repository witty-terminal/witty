#include <AppKit/AppKit.h>
static inline void* witty_input_test_event(unsigned long long type, unsigned long long flags, double timestamp, unsigned short keycode, const char* chars) {
	return [NSEvent keyEventWithType:(NSEventType)type location:NSZeroPoint modifierFlags:(NSEventModifierFlags)flags timestamp:timestamp windowNumber:0 context:nil characters:[NSString stringWithUTF8String:chars] charactersIgnoringModifiers:[NSString stringWithUTF8String:chars] isARepeat:NO keyCode:keycode];
}
static inline void witty_input_test_set_marked(void* view, void* text) {
	[(id<NSTextInputClient>)view setMarkedText:(id)text selectedRange:NSMakeRange(0,0) replacementRange:NSMakeRange(0,0)];
}
static inline void witty_input_test_insert(void* view, const char* text) {
	[(id<NSTextInputClient>)view insertText:[NSString stringWithUTF8String:text] replacementRange:NSMakeRange(0,0)];
}
static inline void* witty_input_test_swizzle_current_event(void* implementation) {
	return method_setImplementation(class_getInstanceMethod([NSApplication class], @selector(currentEvent)), (IMP)implementation);
}
static inline void witty_input_test_run_main_for(double seconds) {
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static inline void* witty_input_test_pasteboard(void) { return [NSPasteboard pasteboardWithUniqueName]; }
