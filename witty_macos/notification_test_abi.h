/* Notification delegate completion Block ABI fixture; policy remains in V. */
static void witty_action_test_void_invoke(witty_action_block* b) { b->callback(b->context,NULL,0,false); }
static void witty_action_test_options_invoke(witty_action_block* b,unsigned long options) { b->callback(b->context,NULL,(long long)options,false); }
static inline void witty_action_test_dispatch(void* object,void* handler,void* completed,void* context,bool options) {
 witty_action_block b=witty_action_make_block(options ? (void*)witty_action_test_options_invoke : (void*)witty_action_test_void_invoke,completed,context);
 witty_action_notification_dispatch(object,&b,handler);
}
