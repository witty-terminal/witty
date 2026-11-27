static inline void* witty_window_font_test_attribute(void* value, void* name) {
    return ((id (*)(id, SEL, id, unsigned long, void*))objc_msgSend)((id)value, sel_registerName("attribute:atIndex:effectiveRange:"), (id)name, 0, NULL);
}
