#ifndef WITTY_MENU_INPUT_DARWIN_H
#define WITTY_MENU_INPUT_DARWIN_H

#if !defined(V3CACHE_NATIVE_INTERFACE) || defined(V3CACHE_NATIVE_OWNER)
#include <AppKit/AppKit.h>

static inline NSString *witty_macos_writing_key_equivalent(unsigned short code, bool command) {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@""
        charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
    NSString *text = [event charactersByApplyingModifiers:command ? NSEventModifierFlagCommand : 0];
    return text.length > 0 && [text rangeOfComposedCharacterSequenceAtIndex:0].length == text.length
        ? text : nil;
}
#endif

#endif
