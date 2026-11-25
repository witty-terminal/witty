// Objective-C message/block ABI only. Update policy and transitions are in V.
#include <AppKit/AppKit.h>
#include <Block.h>
#include <CoreText/CoreText.h>
#include <math.h>
#include "canvas_overlay_darwin.h"
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern id objc_initWeak(id*,id);
extern id objc_loadWeakRetained(id*);
extern void objc_destroyWeak(id*);
typedef struct witty_update_weak { id owner; unsigned refs; } witty_update_weak;
static inline void *witty_update_weak_new(void *owner) { witty_update_weak *weak=calloc(1,sizeof(*weak)); if(!weak) abort(); objc_initWeak(&weak->owner,(id)owner); return weak; }
static inline void *witty_update_weak_retain(void *owner) { if(owner) ((witty_update_weak*)owner)->refs++; return owner; }
static inline void witty_update_weak_release(void *owner) { if(!owner) return; witty_update_weak *weak=owner; if(--weak->refs) return; objc_destroyWeak(&weak->owner); free(weak); }
static inline void *witty_update_weak_load(void *owner) { return owner ? objc_loadWeakRetained(&((witty_update_weak*)owner)->owner) : nil; }
typedef struct witty_update_delayed { witty_update_weak *owner; void (*callback)(void*); } witty_update_delayed;
static void witty_update_delayed_invoke(void *context) { witty_update_delayed *task=context; id owner=witty_update_weak_load(task->owner); if(owner) { task->callback(owner); ((void (*)(id,SEL))objc_msgSend)(owner,sel_registerName("release")); } witty_update_weak_release(task->owner); free(task); }
static inline void witty_update_dispatch_after_weak(void *owner,double seconds,void *callback) { witty_update_delayed *task=calloc(1,sizeof(*task)); if(!task) abort(); task->owner=witty_update_weak_retain(witty_update_weak_new(owner)); task->callback=callback; dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*1000000000.0)),dispatch_get_main_queue(),task,witty_update_delayed_invoke); }
typedef struct witty_update_block { void *isa; int flags,reserved; void (*invoke)(void*,...); void *descriptor; } witty_update_block;
static inline void *witty_update_block_copy(void *block) { return block ? _Block_copy(block) : NULL; }
static inline void witty_update_block_release(void *block) { if (block) _Block_release(block); }
static inline void witty_update_block_void(void *block) { if (!block) return; void *copy=_Block_copy(block); ((void (*)(void*))((witty_update_block*)copy)->invoke)(copy); _Block_release(copy); }
static inline void witty_update_block_choice(void *block,int value) { if (!block) return; void *copy=_Block_copy(block); ((void (*)(void*,long))((witty_update_block*)copy)->invoke)(copy,(long)value); _Block_release(copy); }
static inline void witty_update_block_object(void *block,void *value) { if (!block) return; void *copy=_Block_copy(block); ((void (*)(void*,id))((witty_update_block*)copy)->invoke)(copy,(id)value); _Block_release(copy); }
static inline void *witty_update_init(void *object,void *host,void *application,void *driver,void *delegate) { return ((id (*)(id,SEL,id,id,id,id))objc_msgSend)((id)object,sel_registerName("initWithHostBundle:applicationBundle:userDriver:delegate:"),(id)host,(id)application,(id)driver,(id)delegate); }
static inline bool witty_update_start(void *object,void **error) { return ((BOOL (*)(id,SEL,id*))objc_msgSend)((id)object,sel_registerName("startUpdater:"),(id*)error); }
static inline void witty_update_message_bool_object(void *object,void *selector,bool value,void *other) { ((void (*)(id,SEL,BOOL,id))objc_msgSend)((id)object,(SEL)selector,value,(id)other); }
static inline void *witty_update_permission(bool checks) { return ((id (*)(id,SEL,BOOL,BOOL))objc_msgSend)(((id (*)(id,SEL))objc_msgSend)((id)objc_getClass("SUUpdatePermissionResponse"),sel_registerName("alloc")),sel_registerName("initWithAutomaticUpdateChecks:sendSystemProfile:"),checks,false); }
typedef struct witty_update_range { unsigned long location,length; } witty_update_range;
static inline void *witty_update_regex(void *string,void *pattern) { witty_update_range range=((witty_update_range (*)(id,SEL,id,unsigned long))objc_msgSend)((id)string,sel_registerName("rangeOfString:options:"),(id)pattern,1024); if(range.location==LONG_MAX) return nil; return ((id (*)(id,SEL,witty_update_range))objc_msgSend)((id)string,sel_registerName("substringWithRange:"),range); }
static inline void witty_update_message3(void *object,void *selector,void *a,void *b,void *c) { ((void (*)(id,SEL,id,id,id))objc_msgSend)((id)object,(SEL)selector,(id)a,(id)b,(id)c); }
static inline void *witty_update_blend(void *color,double fraction,void *other) { return ((id (*)(id,SEL,double,id))objc_msgSend)((id)color,sel_registerName("blendedColorWithFraction:ofColor:"),fraction,(id)other); }
static inline double witty_update_text_width(void *text,void *font) { id attributes=((id (*)(id,SEL,id,id))objc_msgSend)((id)objc_getClass("NSDictionary"),sel_registerName("dictionaryWithObject:forKey:"),(id)font,(id)CFSTR("NSFont")); CGSize size=((CGSize (*)(id,SEL,id))objc_msgSend)((id)text,sel_registerName("sizeWithAttributes:"),attributes); return size.width; }
typedef struct witty_update_os_version {long major,minor,patch;} witty_update_os_version;
static inline bool witty_update_is_tahoe(void) { id process=((id (*)(id,SEL))objc_msgSend)((id)objc_getClass("NSProcessInfo"),sel_registerName("processInfo")); witty_update_os_version minimum={26,0,0}; return ((BOOL (*)(id,SEL,witty_update_os_version))objc_msgSend)(process,sel_registerName("isOperatingSystemAtLeastVersion:"),minimum); }
extern const CGFloat NSFontWeightMedium;
extern const CGFloat NSFontWeightSemibold;
static inline void *witty_update_font(void) { return ((id (*)(id,SEL,double,double))objc_msgSend)((id)objc_getClass("NSFont"),sel_registerName("systemFontOfSize:weight:"),11,NSFontWeightMedium); }
static inline void *witty_update_title_font(void) { return ((id (*)(id,SEL,double,double))objc_msgSend)((id)objc_getClass("NSFont"),sel_registerName("systemFontOfSize:weight:"),13,NSFontWeightSemibold); }
static inline CTLineRef witty_update_line(NSString *text, NSDictionary *attributes) {
    NSAttributedString *value = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)value);
    [value release];
    return line;
}

static inline void witty_update_draw_pill_text(CGContextRef context, NSString *text, NSColor *color,
        double origin, double baseline, double width, double height, double scale, bool flipped) {
    if (width <= 0) return;
    NSRange newline = [text rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
    if (newline.location != NSNotFound) {
        text = [[text substringToIndex:newline.location] stringByAppendingString:@"…"];
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: (NSFont *)witty_update_font(),
        NSForegroundColorAttributeName: color,
    };
    CTLineRef line = witty_update_line(text, attributes);
    if (!line) return;
    double advance = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    if (advance > width + 0.0001) {
        CTLineRef token = witty_update_line(@"…", attributes);
        CTLineRef truncated = token ? CTLineCreateTruncatedLine(line, width, kCTLineTruncationEnd, token) : NULL;
        if (token) CFRelease(token);
        CFRelease(line);
        line = truncated;
        if (!line) return;
        advance = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    }
    double laidOutWidth = ceil(advance * scale) / scale;
    double x = round((origin + (width - laidOutWidth) / 2) * scale) / scale;
    CGContextSaveGState(context);
    if (flipped) {
        CGContextTranslateCTM(context, 0, height);
        CGContextScaleCTM(context, 1, -1);
    }
    CGContextClipToRect(context, CGRectMake(origin, 0, width, height));
    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    CGContextSetTextPosition(context, x, baseline);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
}

static inline NSImage *witty_update_pill_symbol(NSString *name, double width, double height,
        double scale, CGRect *frame) {
    NSImage *image = witty_canvas_system_symbol(name, 13, NSFontWeightRegular);
    if (!image) return nil;
    NSRect aligned = image.alignmentRect;
    double x = round(((width - aligned.size.width) / 2 - aligned.origin.x) * scale) / scale;
    double y = (height - image.size.height) / 2;
    *frame = CGRectMake(x, y, image.size.width, image.size.height);
    return image;
}
#endif
