#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <CoreGraphics/CoreGraphics.h>
#endif
// Objective-C/block ABI adapters for translated controller algorithms.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_controller_dispatch_after(double seconds, void* callback, void* context) { dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*1000000000.0)),dispatch_get_main_queue(),context,(dispatch_function_t)callback); }
static inline void* witty_controller_timer(double seconds, void* target, void* selector) { return ((id (*)(id,SEL,double,id,SEL,id,bool))objc_msgSend)((id)objc_getClass("NSTimer"),sel_registerName("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"),seconds,(id)target,(SEL)selector,nil,false); }
static inline void witty_controller_register_undo(void* manager, void* target, void* selector) { ((void (*)(id,SEL,id,SEL,id))objc_msgSend)((id)manager,sel_registerName("registerUndoWithTarget:selector:object:"),(id)target,(SEL)selector,nil); }
typedef struct witty_controller_block_descriptor { unsigned long reserved, size; } witty_controller_block_descriptor;
typedef struct witty_controller_animation_block {
    void* isa; int flags; int reserved;
    void (*invoke)(struct witty_controller_animation_block*,void*);
    const witty_controller_block_descriptor* descriptor;
    void* context;
    void (*callback)(void*,void*);
} witty_controller_animation_block;
typedef struct witty_controller_completion_block {
    void* isa; int flags; int reserved;
    void (*invoke)(struct witty_controller_completion_block*);
    const witty_controller_block_descriptor* descriptor;
    void* context;
    void (*callback)(void*);
} witty_controller_completion_block;
static const witty_controller_block_descriptor witty_controller_animation_descriptor = {0,sizeof(witty_controller_animation_block)};
static const witty_controller_block_descriptor witty_controller_completion_descriptor = {0,sizeof(witty_controller_completion_block)};
static void witty_controller_animation_invoke(witty_controller_animation_block* block, void* animation_context) { block->callback(block->context,animation_context); }
static void witty_controller_completion_invoke(witty_controller_completion_block* block) { block->callback(block->context); }
static inline void witty_controller_animate(void* context, void* change, void* complete) {
    witty_controller_animation_block animation = {_NSConcreteStackBlock,0,0,witty_controller_animation_invoke,&witty_controller_animation_descriptor,context,(void (*)(void*,void*))change};
    witty_controller_completion_block completion = {_NSConcreteStackBlock,0,0,witty_controller_completion_invoke,&witty_controller_completion_descriptor,context,(void (*)(void*))complete};
    ((void (*)(id,SEL,id,id))objc_msgSend)((id)objc_getClass("NSAnimationContext"),sel_registerName("runAnimationGroup:completionHandler:"),(id)&animation,(id)&completion);
}
#endif

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern void CoreDockGetOrientationAndPinning(int32_t*,int32_t*);
typedef struct witty_controller_sheet_block {
    void* isa; int flags; int reserved;
    void (*invoke)(struct witty_controller_sheet_block*,long);
    const witty_controller_block_descriptor* descriptor;
    void* context; void (*callback)(void*,long);
} witty_controller_sheet_block;
static const witty_controller_block_descriptor witty_controller_sheet_descriptor = {0,sizeof(witty_controller_sheet_block)};
static void witty_controller_sheet_invoke(witty_controller_sheet_block* block, long response) { block->callback(block->context,response); }
static inline void witty_controller_sheet(void* alert, void* window, void* context, void* callback) {
    witty_controller_sheet_block completion = {_NSConcreteStackBlock,0,0,witty_controller_sheet_invoke,&witty_controller_sheet_descriptor,context,(void (*)(void*,long))callback};
    ((void (*)(id,SEL,id,id))objc_msgSend)((id)alert,sel_registerName("beginSheetModalForWindow:completionHandler:"),(id)window,(id)&completion);
}
extern bool CoreDockGetAutoHideEnabled(void);
extern void CoreDockSetAutoHideEnabled(bool);
#endif
