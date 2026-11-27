#include <AppKit/AppKit.h>

static inline void witty_tahoe_test_size(void* view, double* width, double* height) {
    NSSize size = [(NSView*)view intrinsicContentSize];
    *width = size.width;
    *height = size.height;
}
static inline float witty_tahoe_test_priority(void* view) {
    return [(NSView*)view contentCompressionResistancePriorityForOrientation:NSLayoutConstraintOrientationHorizontal];
}
@interface WittyTahoeEventFixture: NSObject
@property unsigned long long kind;
@property unsigned long long flags;
@property unsigned long long button;
@property NSPoint point;
@end
@implementation WittyTahoeEventFixture
- (NSEventType)type { return (NSEventType)self.kind; }
- (NSEventModifierFlags)modifierFlags { return (NSEventModifierFlags)self.flags; }
- (NSInteger)buttonNumber { return (NSInteger)self.button; }
- (NSPoint)locationInWindow { return self.point; }
@end
static inline void* witty_tahoe_test_event(unsigned long long kind, unsigned long long flags,
                                         unsigned long long button, double x, double y) {
    WittyTahoeEventFixture* event = [[WittyTahoeEventFixture alloc] init];
    event.kind = kind;
    event.flags = flags;
    event.button = button;
    event.point = NSMakePoint(x, y);
    return event;
}
static IMP witty_tahoe_original_send_event;
static int witty_tahoe_send_event_count;
static void witty_tahoe_test_send_event(id self, SEL command, id event) { witty_tahoe_send_event_count++; }
static inline void witty_tahoe_test_replace_send_event(void) {
    witty_tahoe_send_event_count = 0;
    Method method = class_getInstanceMethod([NSWindow class], @selector(sendEvent:));
    witty_tahoe_original_send_event = method_setImplementation(method, (IMP)witty_tahoe_test_send_event);
}
static inline void witty_tahoe_test_restore_send_event(void) {
    Method method = class_getInstanceMethod([NSWindow class], @selector(sendEvent:));
    method_setImplementation(method, witty_tahoe_original_send_event);
}
static inline int witty_tahoe_test_fallback_count(void) { return witty_tahoe_send_event_count; }

static IMP witty_tahoe_original_add_accessory;
static id witty_tahoe_watched_accessory;
static NSInteger witty_tahoe_super_accessory_layout;
static void witty_tahoe_test_add_accessory(id self, SEL command, id accessory) {
    if (accessory == witty_tahoe_watched_accessory) {
        witty_tahoe_super_accessory_layout = [(NSTitlebarAccessoryViewController*)accessory layoutAttribute];
    }
    ((void (*)(id, SEL, id))witty_tahoe_original_add_accessory)(self, command, accessory);
}
static inline void witty_tahoe_test_watch_add_accessory(void* accessory) {
    witty_tahoe_watched_accessory = (id)accessory;
    witty_tahoe_super_accessory_layout = -1;
    Method method = class_getInstanceMethod([NSWindow class], @selector(addTitlebarAccessoryViewController:));
    witty_tahoe_original_add_accessory = method_setImplementation(method, (IMP)witty_tahoe_test_add_accessory);
}
static inline void witty_tahoe_test_restore_add_accessory(void) {
    Method method = class_getInstanceMethod([NSWindow class], @selector(addTitlebarAccessoryViewController:));
    method_setImplementation(method, witty_tahoe_original_add_accessory);
    witty_tahoe_watched_accessory = nil;
}
static inline long long witty_tahoe_test_super_accessory_layout(void) { return witty_tahoe_super_accessory_layout; }
