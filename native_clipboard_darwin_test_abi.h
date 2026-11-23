#include <AppKit/AppKit.h>
#include <objc/runtime.h>

// Redirect only the app's selection-board lookup to a unique fixture board.
// No read or write reaches the system general or named selection pasteboards.
static NSPasteboard* witty_clipboard_board;
static IMP witty_clipboard_original_named;
static IMP witty_clipboard_original_alert;
static bool witty_clipboard_allow;
static int witty_clipboard_alerts;
static NSString* witty_clipboard_prompt;
static NSString* witty_clipboard_before_prompt;
static id witty_clipboard_named(id self, SEL command, NSString* name) {
    if ([name isEqualToString:@"com.wittyterminal.witty.selection"])
        return witty_clipboard_board;
    return ((id (*)(id, SEL, id))witty_clipboard_original_named)(self, command, name);
}
static NSInteger witty_clipboard_modal(id self, SEL command) {
    witty_clipboard_alerts++;
    [witty_clipboard_prompt release];
    witty_clipboard_prompt = [[self informativeText] copy];
    [witty_clipboard_before_prompt release];
    witty_clipboard_before_prompt = [[witty_clipboard_board stringForType:NSPasteboardTypeString] copy];
    return witty_clipboard_allow ? NSAlertFirstButtonReturn : NSAlertSecondButtonReturn;
}
static inline void witty_clipboard_begin(void) {
    witty_clipboard_board = [[NSPasteboard pasteboardWithUniqueName] retain];
    Method named = class_getClassMethod(NSPasteboard.class, @selector(pasteboardWithName:));
    witty_clipboard_original_named = method_setImplementation(named, (IMP)witty_clipboard_named);
    Method modal = class_getInstanceMethod(NSAlert.class, @selector(runModal));
    witty_clipboard_original_alert = method_setImplementation(modal, (IMP)witty_clipboard_modal);
}
static inline void witty_clipboard_end(void) {
    method_setImplementation(class_getClassMethod(NSPasteboard.class, @selector(pasteboardWithName:)), witty_clipboard_original_named);
    method_setImplementation(class_getInstanceMethod(NSAlert.class, @selector(runModal)), witty_clipboard_original_alert);
    [witty_clipboard_board releaseGlobally];
    [witty_clipboard_board release];
    witty_clipboard_board = nil;
    [witty_clipboard_prompt release]; witty_clipboard_prompt = nil;
    [witty_clipboard_before_prompt release]; witty_clipboard_before_prompt = nil;
}
static inline void witty_clipboard_clear(void) { [witty_clipboard_board clearContents]; }
static inline void witty_clipboard_text(const char* bytes, size_t length) {
    NSString* value = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
    [witty_clipboard_board setString:value forType:NSPasteboardTypeString];
    [value release];
}
static inline void witty_clipboard_urls(int scenario) {
    NSArray* urls;
    if (scenario == 0) urls = @[[NSURL fileURLWithPath:@"/tmp/a b;$?.txt"]];
    else if (scenario == 1) urls = @[[NSURL URLWithString:@"https://example.org/a%20b?x=1&y=2"]];
    else urls = @[[NSURL fileURLWithPath:@"/tmp/a b"], [NSURL URLWithString:@"https://example.org/c?x=1&y=2"]];
    [witty_clipboard_board writeObjects:urls];
}
static inline const char* witty_clipboard_type(void) {
    return [[witty_clipboard_board.types firstObject] UTF8String];
}
static inline bool witty_clipboard_has_type(const char* type) {
    return [witty_clipboard_board.types containsObject:[NSString stringWithUTF8String:type]];
}
static inline const char* witty_clipboard_value(const char* type) {
    return [[witty_clipboard_board stringForType:[NSString stringWithUTF8String:type]] UTF8String];
}
static inline void witty_clipboard_accept(bool value) { witty_clipboard_allow = value; }
static inline int witty_clipboard_alert_count(void) { return witty_clipboard_alerts; }
static inline const char* witty_clipboard_prompt_text(void) { return witty_clipboard_prompt.UTF8String; }
static inline const char* witty_clipboard_before_text(void) { return witty_clipboard_before_prompt.UTF8String; }
