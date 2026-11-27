// Native callback fixtures exercise the real Objective-C Block ABI.
typedef struct witty_update_test_block_abi { void *isa; int flags,reserved; void (*invoke)(void*,...); void *descriptor; } witty_update_test_block_abi;
static int witty_update_test_calls, witty_update_test_last;
static void *witty_update_test_response;
static void witty_update_test_void(void *block) { (void)block; witty_update_test_calls++; }
static void witty_update_test_other_void(void *block) { (void)block; witty_update_test_calls++; witty_update_test_last=44; }
static void witty_update_test_choice(void *block,long value) { (void)block; witty_update_test_calls++; witty_update_test_last=(int)value; }
static void witty_update_test_obj(void *block,void *value) { (void)block; witty_update_test_calls++; witty_update_test_response=((id (*)(id,SEL))objc_msgSend)((id)value,sel_registerName("retain")); }
static const unsigned long witty_update_test_descriptor[]={0,sizeof(witty_update_test_block_abi)};
static witty_update_test_block_abi witty_update_test_blocks[]={
    {_NSConcreteGlobalBlock,1<<28,0,(void (*)(void*,...))witty_update_test_void,(void*)witty_update_test_descriptor},
    {_NSConcreteGlobalBlock,1<<28,0,(void (*)(void*,...))witty_update_test_choice,(void*)witty_update_test_descriptor},
    {_NSConcreteGlobalBlock,1<<28,0,(void (*)(void*,...))witty_update_test_obj,(void*)witty_update_test_descriptor},
    {_NSConcreteGlobalBlock,1<<28,0,(void (*)(void*,...))witty_update_test_other_void,(void*)witty_update_test_descriptor}
};
static void *witty_update_test_block(int kind) { return &witty_update_test_blocks[kind]; }
static int witty_update_test_count(void) { return witty_update_test_calls; }
static int witty_update_test_value(void) { return witty_update_test_last; }
static void witty_update_test_reset(void) { witty_update_test_calls=0; witty_update_test_last=0; }
static void *witty_update_test_object(void) { return witty_update_test_response; }
