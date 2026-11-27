#ifndef WITTY_NOTIFICATION_BRIDGE_H
#define WITTY_NOTIFICATION_BRIDGE_H
#include <stdbool.h>
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <objc/runtime.h>
#include <objc/message.h>
#endif
/* Block ABI adapters. The notification policy and lifecycle are translated in V. */
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern void* _NSConcreteStackBlock[32];
typedef void (*witty_action_callback)(void*,void*,long long,bool);
typedef struct witty_action_block_descriptor { unsigned long reserved,size; } witty_action_block_descriptor;
typedef struct witty_action_block {
 void* isa; int flags,reserved; void* invoke;
 const witty_action_block_descriptor* descriptor;
 witty_action_callback callback; void* context;
} witty_action_block;
static const witty_action_block_descriptor witty_action_block_desc={0,sizeof(witty_action_block)};
static inline witty_action_block witty_action_make_block(void* invoke, void* callback, void* context) {
 witty_action_block b={_NSConcreteStackBlock,0,0,invoke,&witty_action_block_desc,(witty_action_callback)callback,context}; return b;
}
static void witty_action_object_invoke(witty_action_block* b,void* object) { b->callback(b->context,object,0,false); }
static void witty_action_authorization_invoke(witty_action_block* b,bool granted,void* error) { b->callback(b->context,error,0,granted); }
static void witty_action_response_invoke(witty_action_block* b,long long response) { b->callback(b->context,NULL,response,false); }
static inline void witty_action_notification_settings(void* center, void* callback, void* context) {
 witty_action_block b=witty_action_make_block(witty_action_object_invoke,callback,context);
 ((void(*)(id,SEL,void*))objc_msgSend)((id)center,sel_registerName("getNotificationSettingsWithCompletionHandler:"),&b);
}
static inline void witty_action_notification_authorize(void* center, unsigned long options, void* callback, void* context) {
 witty_action_block b=witty_action_make_block(witty_action_authorization_invoke,callback,context);
 ((void(*)(id,SEL,unsigned long,void*))objc_msgSend)((id)center,sel_registerName("requestAuthorizationWithOptions:completionHandler:"),options,&b);
}
static inline void witty_action_notification_add(void* center, void* request, void* callback, void* context) {
 witty_action_block b=witty_action_make_block(witty_action_object_invoke,callback,context);
 ((void(*)(id,SEL,id,void*))objc_msgSend)((id)center,sel_registerName("addNotificationRequest:withCompletionHandler:"),(id)request,&b);
}
static inline void witty_action_sheet(void* alert, void* window, void* callback, void* context) {
 witty_action_block b=witty_action_make_block(witty_action_response_invoke,callback,context);
 ((void(*)(id,SEL,id,void*))objc_msgSend)((id)alert,sel_registerName("beginSheetModalForWindow:completionHandler:"),(id)window,&b);
}
static inline void witty_action_complete_void(void* block) { ((void(*)(void*))((witty_action_block*)block)->invoke)(block); }
static inline void witty_action_complete_options(void* block,unsigned long options) { ((void(*)(void*,unsigned long))((witty_action_block*)block)->invoke)(block,options); }
static inline void* witty_action_notification_action(void* identifier,void* title,unsigned long options) {
 return ((id(*)(id,SEL,id,id,unsigned long))objc_msgSend)((id)objc_getClass("UNNotificationAction"),sel_registerName("actionWithIdentifier:title:options:"),(id)identifier,(id)title,options);
}
static inline void* witty_action_notification_category(void* identifier,void* actions,void* intents,unsigned long options) {
 return ((id(*)(id,SEL,id,id,id,unsigned long))objc_msgSend)((id)objc_getClass("UNNotificationCategory"),sel_registerName("categoryWithIdentifier:actions:intentIdentifiers:options:"),(id)identifier,(id)actions,(id)intents,options);
}
#endif

// Retained Objective-C parameters cross the delegate's MainActor boundary.
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
extern void* _Block_copy(const void*);
extern void _Block_release(const void*);
#endif
typedef struct witty_action_notification_delivery { void* object; void* completion; } witty_action_notification_delivery;
#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
static inline void witty_action_notification_dispatch(void* object,void* completion,void* callback) {
 witty_action_notification_delivery* delivery=malloc(sizeof(*delivery));
 delivery->object=((id(*)(id,SEL))objc_msgSend)((id)object,sel_registerName("retain"));
 delivery->completion=_Block_copy(completion);
 dispatch_async_f(dispatch_get_main_queue(),delivery,(dispatch_function_t)callback);
}
static inline void witty_action_notification_delivery_free(witty_action_notification_delivery* delivery) {
 ((void(*)(id,SEL))objc_msgSend)((id)delivery->object,sel_registerName("release"));
 _Block_release(delivery->completion); free(delivery);
}
#endif

#endif
