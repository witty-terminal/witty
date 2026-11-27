// Surface represents a single terminal "surface". A terminal surface is

// --- Original Ghostty Comments Start: src/Surface.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/Surface.zig
//
// Surface represents a single terminal "surface". A terminal surface is
// a minimal "widget" where the terminal is drawn and responds to events
// such as keyboard and mouse. Each surface also creates and owns its pty
// session.
//
// The word "surface" is used because it is left to the higher level
// application runtime to determine if the surface is a window, a tab,
// a split, a preview pane in a larger window, etc. This struct doesn't care:
// it just draws and responds to events. The events come from the application
// runtime so the runtime can determine when and how those are delivered
// (i.e. with focus, without focus, and so on).
// The renderer implementation to use.
// Minimum window size in cells. This is used to prevent the window from
// being resized to a size that is too small to be useful. These defaults
// are chosen to match the default size of Mac's Terminal.app, but is
// otherwise somewhat arbitrary.
// The maximum number of key tables that can be active at any
// given time. `activate_key_table` calls after this are ignored.
// Allocator
// The app that this surface is attached to.
// The windowing system surface and app.
// The font structures
// This keeps track of if the font size was ever modified. If it wasn't,
// then config reloading will change the font. If it was manually adjusted,
// we don't change it on config reload since we assume the user wants
// a specific size.
// The renderer for this surface.
// The render state
// The renderer thread manager
// The actual thread
// Mouse state.
// Keyboard input state.
// A currently pressed key. This is used so that we can send a keyboard
// release event when the surface is unfocused. Note that when the surface
// is refocused, a key press event may not be sent again -- this depends
// on the apprt (UI framework) in use, but we want to consistently send
// a release.
//
// This is only sent when a keypress event results in a key event being
// sent to the pty. If it is consumed by a keybinding or other action,
// this is not set.
//
// Also note the utf8 value is not valid for this event so some unfocused
// release events may not send exactly the right data within Kitty keyboard
// events. This seems unspecified in the spec so for now I'm okay with
// this. Plus, its only for release events where the key text is far
// less important.
// The hash value of the last keybinding trigger that we performed. This
// is only set if the last key input matched a keybinding, consumed it,
// and performed it. This is used to prevent sending release/repeat events
// for handled bindings.
// The terminal IO handler.
// Terminal inspector
// All our sizing information.
// The configuration derived from the main config. We "derive" it so that
// we don't have a shared pointer hanging around that we need to worry about
// the lifetime of. This makes updating config at runtime easier.
// The conditional state of the configuration. This can affect
// how certain configurations take effect such as light/dark mode.
// This is managed completely by Ghostty core but an apprt action
// is sent whenever this changes.
// This is set to true if our IO thread notifies us our child exited.
// This is used to determine if we need to confirm, hold open, etc.
// We maintain our focus state and assume we're focused by default.
// If we're not initially focused then apprts can call focusCallback
// to let us know.
// Used to determine whether to continuously scroll.
// True if the surface is in read-only mode. When read-only, no input
// is sent to the PTY but terminal-level operations like selections,
// (native) scrolling, and copy keybinds still work. Warn before quit is
// always enabled in this state.
// Used to send notifications that long running commands have finished.
// Requires that shell integration be active. Should represent a nanosecond
// precision timestamp. It does not necessarily need to correspond to the
// actual time, but we must be able to compare two subsequent timestamps to get
// the wall clock time that has elapsed between timestamps.
// Search state
// Used to rate limit BEL handling.
// The effect of an input event. This can be used by callers to take
// the appropriate action after an input event. For example, key
// input can be forwarded to the OS for further processing if it
// wasn't handled in any way by Ghostty.
// The input was not handled in any way by Ghostty and should be
// forwarded to other subsystems (i.e. the OS) for further
// processing.
// The input was handled and consumed by Ghostty.
// The input resulted in a close event for this surface so
// the surface, runtime surface, etc. pointers may all be
// unsafe to use so exit immediately.
// The search state for the surface.
// Notify the thread to stop
// Wait for the OS thread to quit
// Now it is safe to deinit the state
// Mouse state for the surface.
// The last tracked mouse button state by button.
// The last mods state when the last mouse button (whatever it was) was
// pressed or release.
// The point at which the left mouse click happened. This is in screen
// coordinates so that scrolling preserves the location.
// The starting xpos/ypos of the left click. Note that if scrolling occurs,
// these will point to different "cells", but the xpos/ypos will stay
// stable during scrolling relative to the surface.
// The count of clicks to count double and triple clicks and so on.
// The left click time was the last time the left click was done. This
// is always set on the first left click.
// The last x/y sent for mouse reports.
// The pressure stage for the mouse. This should always be none if
// the mouse is not pressed.
// Pending scroll amounts for high-precision scrolls
// True if the mouse is hidden
// True if the mouse position is currently over a link.
// The last x/y in the cursor position for links. We use this to
// only process link hover events when the mouse actually moves cells.
// Keyboard state for the surface.
// The currently active key sequence for the surface. If this is null
// then we're not currently in a key sequence.
// The queued keys when we're in the middle of a sequenced binding.
// These are flushed when the sequence is completed and unconsumed or
// invalid.
//
// This is naturally bounded due to the configuration maximum
// length of a sequence.
// The stack of tables that is currently active. The first value
// in this is the first activated table (NOT the default keybinding set).
//
// This is bounded by `max_active_key_tables`.
// The last handled binding. This is used to prevent encoding release
// events for handled bindings. We only need to keep track of one because
// at least at the time of writing this, its impossible for two keys of
// a combination to be handled by different bindings before the release
// of the prior (namely since you can't bind modifier-only).
// The configuration that a surface has, this is copied from the main
// Config struct usually to prevent sharing a single value.
// For docs for these, see the associated config they are derived from.
// Build all of our links
// Assignments happen sequentially so we have to do this last
// so that the memory is captured from allocs above.
// Create a new surface. This must be called from the main thread. The
// pointer to the memory for the surface must be provided and must be
// stable due to interfacing with various callbacks.
// Apply our conditional state. If we fail to apply the conditional state
// then we log and attempt to move forward with the old config.
// We want a config pointer for everything so we get that either
// based on our conditional state or the original config.
// We want to preserve our original working directory. We
// don't need to dupe memory here because termio will derive
// it. We preserve this so directory inheritance works.
// Get our configuration
// Initialize our renderer with our initialized surface.
// Determine our DPI configurations so we can properly configure
// font points to pixels and handle other high-DPI scaling factors.
// The font size we desire along with the DPI determined for the surface
// Setup our font group. This will reuse an existing font group if
// it was already loaded.
// Build our size struct which has all the sizes we need.
// Create our terminal grid with the initial size
// The mutex used to protect our renderer state.
// Create the renderer thread
// Create the IO thread
// Our conditional state is initialized to the app state. This
// lets us get the most likely correct color theme and so on.
// The command we're going to execute
// Start our IO implementation
// This separate block ({}) is important because our errdefers must
// be scoped here to be valid.
// If an error occurs, we don't want to block surface startup.
// don't leak GHOSTTY_LOG to any subprocesses
// Initialize our IO backend
// Get the cgroup if we're on linux and have the decl. I'd love
// to change this from a decl to a surface options struct because
// then we can do memory management better (don't need to retain
// the string around).
// Initialize our IO mailbox
// Outside the block, IO has now taken ownership of our temporary state
// so we can just defer this and not the subcomponents.
// Report initial cell size on surface creation
// No max:
// Call our size callback which handles all our retina setup
// Note: this shouldn't be necessary and when we clean up the surface
// init stuff we should get rid of this. But this is required because
// sizeCallback does retina-aware stuff we don't do here and don't want
// to duplicate.
// Give the renderer one more opportunity to finalize any surface
// setup on the main thread prior to spinning up the rendering thread.
// Start our renderer thread
// Start our IO thread
// Determine our initial window size if configured. We need to do this
// quite late in the process because our height/width are in grid dimensions,
// so we need to know our cell sizes first.
//
// Note: it is important to do this after the renderer is setup above.
// This allows the apprt to fully initialize the surface before we
// start messing with the window.
// We don't treat this as a fatal error because not setting
// an initial size shouldn't stop our terminal from working.
// For xdg-terminal-exec execution we special-case and set the window
// title to the command being executed. This allows window managers
// to set custom styling based on the command being executed.
// If a user specifies a command it is appropriate to set the title as argv[0]
// we know in the case of a direct command it has been supplied by the user
// We won't set the title in the case the shell expands the command
// as that should typically be used to launch a shell which should
// set its own titles
// We are no longer the first surface
// Stop search thread
// Stop rendering thread
// We need to become the active rendering thread again
// Stop our IO thread
// We need to deinit AFTER everything is stopped, since there are
// shared values between the two threads.
// Clean up our keyboard state
// Clean up our font grid
// Clean up our render state
// Close this surface. This will trigger the runtime to start the
// close process, which should ultimately deinitialize this surface.
// Returns a mailbox that can be used to send messages to this surface.
// Queue a message for the IO thread.
//
// We centralize all our logic into this spot so we can intercept
// messages for example in readonly mode.
// In readonly mode, we don't allow any writes through to the pty.
// Forces the surface to render. This is useful for when the surface
// is in the middle of animation (such as a resize, etc.) or when
// the render timer is managed manually by the apprt.
// Renderers are required to support `drawFrame` being called from
// the main thread, so that they can update contents during resize.
// Activate the inspector. This will begin collecting inspection data.
// This will not affect the GUI. The GUI must use performAction to
// show/hide the inspector UI.
// Setup the inspector
// Put the inspector onto the render state
// Notify our components we have an inspector active
// Deactivate the inspector and stop collecting any information.
// Remove the inspector from the render state
// Notify our components we have deactivated inspector
// Deinit the inspector
// True if the surface requires confirmation to quit. This should be called
// by apprt to determine if the surface should confirm before quitting.
// If the surface is in read-only mode, always require confirmation
// If the child has exited, then our process is certainly not alive.
// We check this first to avoid the locking overhead below.
// Check the configuration for confirming close behavior.
// Called from the app thread to handle mailbox messages to our specific
// surface.
// We ignore the message in case the title was set via config.
// The ptrCast just gets sliceTo to return the proper type.
// We know that our title should end in 0.
// We always use an allocating message because we don't know
// the length of the title and this isn't a performance critical
// path.
// Notify our apprt, but don't send a mode 2031 DSR report
// because VT sequences were used to change the color.
// Unsupported dynamic color change notification type
// Special colors aren't supported for change notification
// We always allocate for this because we need to null-terminate.
// If we're no longer active then we don't do anything.
// If we don't have a left mouse button down then we
// don't do anything.
// We need our locked state for the remainder
// If our screen changed while this is happening, we stop our
// selection scroll.
// Scroll the viewport as required
// Next, trigger our drag behavior
// We modified our viewport and selection so we need to queue
// a render.
// Mark our flag that we exited immediately
// If our runtime was below some threshold then we assume that this
// was an abnormal exit and we show an error message.
// On macOS, our exit code detection doesn't work, possibly
// because of our `login` wrapper. More investigation required.
// If the exit code is 0 then it was a good exit.
// Try and show a GUI message. If it returns true, don't do anything else.
// If a native GUI notification was not shown, update our terminal to
// note the abnormal exit.
// We output a message so that the user knows what's going on and
// doesn't think their terminal just froze. We show this unconditionally
// on close even if `wait_after_command` is false and the surface closes
// immediately because if a user does an `undo` to restore a closed
// surface then they will see this message and know the process has
// completed.
// First try and show a native GUI message.
// If the native GUI can't be shown, display a text message in the
// terminal.
// We also want to ensure that normal keyboard encoding is on
// so that we can close the terminal. We close the terminal on
// any key press that encodes a character.
// Waiting after command we stop here. The terminal is updated, our
// state is updated, and now its up to the user to decide what to do.
// If we aren't waiting after the command, then we exit immediately
// with no confirmation.
// Called when the child process exited abnormally.
// Build up our command for the error message
// No matter what move the cursor back to the column 0.
// Reset styles
// If there is data in the viewport, we want to scroll down
// a little bit and write a horizontal rule before writing
// our message. This lets the use see the error message the
// command may have output.
// Output our error message
// We don't print this on macOS because the exit code is always 0
// due to the way we launch the process.
// Hide the cursor
// Called when the terminal detects there is a password input prompt.
// If our password input state is unchanged then we don't
// waste time doing anything more.
// Notify our apprt so it can do whatever it wants.
// We ignore this error because we don't want to fail this
// entire operation just because the apprt failed to set
// the secure input state.
// IMPORTANT: This function is run on the SEARCH THREAD! It is NOT SAFE
// to access anything other than values that never change on the surface.
// The surface is guaranteed to be valid for the lifetime of the search
// thread.
// NOTE: This runs on the search thread.
// Copy the flattened match.
// Send the selected index to the surface mailbox
// Reset our selected match
// Reset the selected index
// When we quit, tell our renderer to reset any search state.
// Reset search totals in the surface
// Unhandled, so far.
// Call this when modifiers change. This is safe to call even if modifiers
// match the previous state.
//
// This is not publicly exported because modifier changes happen implicitly
// on mouse callbacks, key callbacks, etc.
//
// The renderer state mutex MUST NOT be held.
// The only place we keep track of mods currently is on the mouse.
// The mouse mods only contain binding modifiers since we don't
// want caps/num lock or sided modifiers to affect the mouse.
// We also need to update the renderer so it knows if it should
// highlight links. Additionally, mark the screen as dirty so
// that the highlight state of all links is properly updated.
// We use the clear screen dirty flag to force a rebuild of all
// rows because changing mouse mods can affect the highlight state
// of a link. If there is no link this seems very wasteful but
// its really only one frame so it's not so bad.
// Not a big deal if this fails.
// Call this whenever the mouse moves or mods changed. The time
// at which this is called may matter for the correctness of other
// mouse events (see cursorPosCallback) but this is shared logic
// for multiple events.
// If the position is outside our viewport, do nothing
// Update the last point that we checked for links so we don't
// recheck if the mouse moves some pixels to the same point.
// We use an arena for everything below to make things easy to clean up.
// In the case we don't do any allocs this is very cheap to setup
// (effectively just struct init).
// Get our link at the current position. This returns null if there
// isn't a link OR if we shouldn't be showing links for some reason
// (see further comments for cases).
// If we clicked and our mouse moved cells then we never
// highlight links until the mouse is unclicked. This follows
// standard macOS and Linux behavior where a click and drag cancels
// mouse actions.
// Show the URL in the status bar
// If we found a link, setup our internal state and notify the
// apprt so it can highlight it.
// No link, if we're previously over a link then we need to clear
// the over-link apprt state.
// Called when our renderer health state changes.
// Called when the scrollbar state changes.
// This should be called anytime `config_conditional_state` changes
// so that the apprt can reload the configuration.
// Update our configuration at runtime. This can be called by the apprt
// to set a surface-specific configuration that differs from the app
// or other surfaces.
// Apply our conditional state. If we fail to apply the conditional state
// then we log and attempt to move forward with the old config.
// We want a config pointer for everything so we get that either
// based on our conditional state or the original config.
// Update our new derived config immediately
// If the derivation fails then we just log and return. We don't
// hard fail in this case because we don't want to error the surface
// when config fails we just want to keep using the old config.
// If our mouse is hidden but we disabled mouse hiding, then show it again.
// If we are in the middle of a key sequence, clear it.
// Deactivate all key tables since they may have changed. Importantly,
// we store pointers into the config as part of our table stack so
// we can't keep them active across config changes. But this behavior
// also matches key sequences.
// Before sending any other config changes, we give the renderer a new font
// grid. We could check to see if there was an actual change to the font,
// but this is easier and pretty rare so it's not a performance concern.
//
// (Calling setFontSize builds and sends a new font grid to the renderer.)
// If we have manually adjusted the font size, keep it that way.
// If we haven't, then we update to the configured font size.
// This allows config changes to update the font size. We used to
// never do this but it was a common source of confusion and people
// assumed that Ghostty was broken! This logic makes more sense.
// We need to store our configs in a heap-allocated pointer so that
// our messages aren't huge.
// With mailbox messages sent, we have to wake them up so they process it.
// If we have a title set then we update our window to have the
// newly configured title.
// Notify the window
// Recalculate the initial size of the window based on the
// configuration and invoke the apprt `initial_size` action if
// necessary.
// Both width and height must be set for this to work, as
// documented on the config options.
// The final values are affected by content scale and we need to
// account for the padding so we get the exact correct grid size.
// Represents text read from the terminal and some metadata about it
// that is often useful to apprts.
// The text that was read from the terminal.
// The viewport information about this text, if it is visible in
// the viewport.
// The top-left corner of the selection in pixels within the viewport.
// The linear offset of the start of the selection and the length.
// This is "linear" in the sense that it is the offset in the
// flattened viewport as a single array of text.
//
// Note: these values are currently wrong if there is a partially
// visible selection in the viewport (i.e. the top-left or
// bottom-right of the selection is outside the viewport). But the
// apprt usecase we have right now doesn't require these to be
// correct so... let's fix this later. The wrong values will always
// be within the text bounds so we aren't risking an overflow.
// Grab the value of text at the given selection point. Note that the
// selection structure is used as a way to determine the area of the
// screen to read from, it doesn't have to match the user's current
// selection state.
//
// The returned value contains allocated data and must be deinitialized.
// Same as `dumpText` but assumes the renderer state mutex is already
// held.
// Read out the text
// Calculate our viewport info if we can.
// If our bottom right pin is before the viewport, then we can't
// possibly have this text be within the viewport.
// If our top-left pin is after the viewport, then we can't possibly
// have this text be within the viewport.
// I don't think this is possible but I don't want to crash on
// that assertion so let's just break out...
// We established that our top-left somewhere before the viewport
// bottom-right and that our bottom-right is somewhere after
// the top-left. This means that at least some portion of our
// selection is within the viewport.
// Our top-left point. If it doesn't exist in the viewport it must
// be before and we can return (0,0).
// Our bottom-right point. If it doesn't exist in the viewport
// it must be the bottom-right of the viewport.
// Our sizes are all scaled so we need to send the unscaled values back.
// Simple x * cell width gives the left
// Add padding
// Scale
// Simple y * cell height gives the top
// We want the text baseline
// Add padding
// Scale
// Utilize viewport sizing to convert to offsets
// Returns true if the terminal has a selection.
// Returns the selected text. This is allocated.
// Returns the pwd of the terminal, if any. This is always copied because
// the pwd can change at any point from termio. If we are calling from the IO
// thread you should just check the terminal directly.
// Resolves a relative file path to an absolute path using the terminal's pwd.
// Returns the x/y coordinate of where the IME (Input Method Editor)
// keyboard should be rendered.
// TODO: need to handle when scrolling and the cursor is not
// in the visible portion of the screen.
// Our sizes are all scaled so we need to send the unscaled values back.
// Simple x * cell width gives the top-left corner, then add padding offset
// We want the midpoint
// And scale it
// Simple y * cell height gives the top-left corner, then add padding offset
// We want the bottom
// And scale it
// Our height for now is always just the cell height because our preedit
// rendering only renders in a single line.
// Our max width is the remaining screen width after the cursor.
// We don't have to deal with wrapping because the preedit doesn't
// wrap right now.
// Note: we don't apply content scale here because it looks like
// for some reason in macOS its already scaled. I'm not sure why
// that is so I'm going to just leave this comment here so its known
// that I left this out on purpose pending more investigation.
// Build buffer
// Should not be reachable but don't want to risk it.
// Decode
// Ignore this. It is possible to actually have valid data and
// get this error, so we allow it.
// When clipboard-write is "ask" a prompt is displayed to the user asking
// them to confirm the clipboard access. Each app runtime handles this
// differently.
// Create an arena to simplify memory management here.
// The options we'll use for all formatting. We'll just override the
// emit format.
// Note: We don't apply codepoint mappings to VT format since it contains
// escape sequences that should be preserved as-is
// Note: We don't apply codepoint mappings to HTML format since HTML
// has its own character encoding and entity system
// First, generate plain text with codepoint mappings applied
// Second, generate HTML without codepoint mappings
// We purposely don't emit background/foreground for mixed
// mode because the HTML contents is often used for rich text
// input and with trimmed spaces it looks pretty bad.
// Note: We don't apply codepoint mappings to HTML format
// Set the selection contents.
//
// This must be called with the renderer mutex held.
// If copy on select is false then exit early.
// Set our selection clipboard. If the selection is cleared we do not
// clear the clipboard. If the selection is set, we only set the clipboard
// again if it changed, since setting the clipboard can be an expensive
// operation.
// Both standard and selection clipboards are set.
// The selection clipboard is set if supported, otherwise the standard.
// Change the cell size for the terminal grid. This can happen as
// a result of changing the font size at runtime.
// Update our cell size within our size struct
// Notify the terminal
// Update our terminal default size if necessary.
// We don't treat this as a fatal error because not setting
// an initial size shouldn't stop our terminal from working.
// Notify the window
// Change the font size.
//
// This can only be called from the main thread.
// Update our font size so future changes work
// We need to build up a new font stack for this font size.
// Set our cell size
// Notify our render thread of the new font stack. The renderer
// MUST accept the new font grid and deref the old.
// Once we've sent the key we can replace our key
// Schedule render which also drains our mailbox
// This queues a render operation with the renderer thread. The render
// isn't guaranteed to happen immediately but it will happen as soon as
// practical.
// Crash metadata in case we crash in here
// Update our screen size, but only if it actually changed. And if
// the screen size didn't change, then our grid size could not have
// changed, so we just return.
// Save our screen size
// Recalculate our grid size. Because Ghostty supports fluid resizing,
// its possible the grid doesn't change at all even if the screen size changes.
// We have to update the IO thread no matter what because we send
// pixel-level sizing to the subprocess.
// Mail the IO thread
// Recalculate the balanced padding if needed.
// Called to set the preedit state for character input. Preedit is used
// with dead key states, for example, when typing an accent character.
// This should be called with null to reset the preedit state.
//
// The core surface will NOT reset the preedit state on charCallback or
// keyCallback and we rely completely on the apprt implementation to track
// the preedit state correctly.
//
// The preedit input must be UTF-8 encoded.
// log.debug("text preeditCallback value={any}", .{preedit_});
// Crash metadata in case we crash in here
// We clear our selection when ANY OF:
// 1. We have an existing preedit
// 2. We have preedit text
// We always clear our prior preedit
// Mark preedit dirty flag
// If we have no text, we're done. We queue a render in case we cleared
// a prior preedit (likely).
// We convert the UTF-8 text to codepoints.
// Allocate the codepoints slice
// I've never seen a preedit text with a zero-width character. In
// theory its possible but we can't really handle it right now.
// Let's just ignore it.
// If we have no codepoints, then we're done.
// Returns true if the given key event would trigger a keybinding
// if it were to be processed. This is useful for determining if
// a key event should be sent to the terminal or not.
//
// Note that this function does not check if the binding itself
// is performable, only if the key event would trigger a binding.
// If a performable binding is found and the event is not performable,
// then Ghosty will act as though the binding does not exist.
// Apply key remappings for consistency with keyCallback
// Look up our entry
// If we're in a sequence, check the sequence set
// Check active key tables (inner-most to outer-most)
// Check the root set
// Return flags based on the
// Called for any key events. This handles keybindings, encoding and
// sending to the terminal, etc.
// log.warn("text keyCallback event={}", .{event_orig});
// Apply key remappings to transform modifiers before any processing.
// This allows users to remap modifier keys at the app level.
// Crash metadata in case we crash in here
// Setup our inspector event if we have an inspector.
// When we're done processing, we always want to add the event to
// the inspector.
// We have to check for the inspector again because our keybinding
// might close it.
// Handle keybindings first. We need to handle this on all events
// (press, repeat, release) because a press may perform a binding but
// a release should not encode if we consumed the press.
// If we allow KAM and KAM is enabled then we do nothing.
// If this input event has text, then we hide the mouse if configured.
// We only do this on pressed events to avoid hiding the mouse when we
// change focus due to a keybinding (i.e. switching tabs).
// If our mouse modifiers change we may need to change our
// link highlight state.
// Update our modifiers, this will update mouse mods too
// We only refresh links if
// 1. mouse reporting is off
// OR
// 2. mouse reporting is on and we are not reporting shift to the terminal
// Refresh our link state
// If we have mouse reports on and we don't have shift pressed, we reset state
// Process the cursor state logic. This will update the cursor shape if
// needed, depending on the key state.
// We've processed a key event that produced some data so we want to
// track the last pressed key.
// We need to unset the allocated fields that will become invalid
// If we have a previous pressed key and we're releasing it
// then we set it to invalid to prevent repeating the release event.
// if we didn't have a previous event and this is a release
// event then we just want to set it to null.
// If our key is invalid and we have no mods, then we're done!
// This helps catch the state that we naturally released all keys.
// Encode and send our key. If we didn't encode anything, then we
// return the effect as ignored.
// If our process is exited and we press a key that results in
// an encoded value, we close the surface. We want to eventually
// move this behavior to the apprt probably.
// No valid request means that we didn't encode anything.
// If our event is any keypress that isn't a modifier and we generated
// some data to send to the pty, then we move the viewport down to the
// bottom. We also clear the selection for any key other then modifiers.
// Maybe handles a binding for a given event and if so returns the effect.
// Returns null if the event is not handled in any way and processing should
// continue.
// Release events never trigger a binding but we need to check if
// we consumed the press event so we don't encode the release.
// We don't reset the last trigger on release because
// an apprt may send multiple release events for a single
// press event.
// Carry on processing.
// Find an entry in the keybind set that matches our event.
// Handle key sequences first.
// Get our entry from the set for the given event.
// No entry found. We need to encode everything up to this
// point and send to the pty since we're in a sequence.
// We ignore modifiers so that nested sequences such as
// ctrl+a>ctrl+b>c work.
// If we have a catch-all of ignore, then we special case our
// invalid sequence handling to ignore it.
// Encode everything up to this point
// No currently active sequence, move on to tables. For tables,
// we search inner-most table to outer-most. The table stack does
// NOT include the root set.
// If this is a one-shot activation AND its the currently
// active table, then we deactivate it after this.
// Note: we may want to change the semantics here to
// remove this table no matter where it is in the stack,
// maybe.
// No table, use our default set
// Determine if this entry has an action or if its a leader key.
// Setup the next set we'll look at.
// Store this event so that we can drain and encode on invalid.
// We don't need to cap this because it is naturally capped by
// the config validation.
// Start or continue our key sequence
// consumed determines if the input is consumed or if we continue
// encoding the key (if we have a key to encode).
// If the consumed flag is explicitly set, then we are consumed.
// If the global or all flag is set, we always consume.
// We have an action, so at this point we're handling SOMETHING so
// we reset the last trigger to null. We only set this if we actually
// perform an action (below)
// An action also always resets the sequence set.
// Setup our actions
// Attempt to perform the action
// If this is a global or all action, then we perform it on
// the app and it applies to every surface.
// "All" actions are always performed since they are global.
// Perform each action. We are performed if ANY of the chained
// actions perform.
// If we performed an action and it was a closing action,
// our "self" pointer is not safe to use anymore so we need to
// just exit immediately.
// If our action was "ignore" then we return the special input
// effect of "ignored".
// If we have the performable flag and the action was not performed,
// then we act as though a binding didn't exist.
// If we're in a sequence, we treat this as if we pressed a key
// that doesn't exist in the sequence. Reset our sequence and flush
// any queued events.
// If we consume this event, then we are done. If we don't consume
// it, we processed the action but we still want to process our
// encodings, too.
// If we had queued events, we deinit them since we consumed
// Store our last trigger so we don't encode the release event
// If we didn't perform OR we didn't consume, then we want to
// encode any queued events for a sequence.
// No key table active. This does nothing.
// Clear the entire table stack.
// Notify the UI.
// This checks if the current keybinding sets have a catch_all binding
// with `ignore`. This is used to determine some special input cases.
// Get our catch all
// We have a catch-all entry, see if its an ignore
// End a key sequence. Safe to call if no key sequence is active.
//
// Action and mem determine the behavior of the queued inputs up to this
// point.
// Notify apprt key sequence ended
// No matter what we clear our current sequence set. This restores
// the set we look at to the root set.
// If we have no queued data, there is nothing else to do.
// Run the proper action first
// Memory handling of the sequence after the action
// Encodes the key event into a write request. The write request will
// always copy or allocate so the caller can safely free the event.
// Build our encoding options, which requires the lock.
// Try to write the input into a small array. This fits almost
// every scenario. Larger situations can happen due to long
// pre-edits.
// Special-case: we did nothing.
// Means we need to allocate
// We need to allocate. We allocate double the UTF-8 length
// or double the small array size, whichever is larger. That's
// a heuristic that should work. The only scenario I know while
// typing this where we don't have enough space is a long preedit,
// and in that case the size we need is exactly the UTF-8 length,
// so the double is being safe.
// This results in a double allocation but this is such an unlikely
// path the performance impact is unimportant.
// Copy the encoded data into the inspector event if we have one.
// We do this before the mailbox because the IO thread could
// release the memory before we get a chance to copy it.
// If we don't have alt pressed, it doesn't matter what this
// config is so we can just say "false" and break out and avoid
// more expensive checks below.
// Alt is pressed, we're on macOS. We break some encapsulation
// here and assume libwitty for ease...
// Sends text as-is to the terminal without triggering any keyboard
// protocol. This will treat the input text as if it was pasted
// from the clipboard so the same logic will be applied. Namely,
// if bracketed mode is on this will do a bracketed paste. Otherwise,
// this will filter newlines to '\r'.
// Crash metadata in case we crash in here
// Callback for when the surface is fully visible or not, regardless
// of focus state. This is used to pause rendering when the surface
// is not visible, and also re-render when it becomes visible again.
// Crash metadata in case we crash in here
// Crash metadata in case we crash in here
// If our focus state is the same we do nothing.
// Notify our render thread of the new state
// Notify our app if we gained focus.
// If we lost focus and we have a keypress, then we want to send a key
// release event for it. Depending on the apprt, this CAN result in
// duplicate key release events, but that is better than not sending
// a key release event at all.
// All our actions will be releases
// Release the full key first
// Release any modifiers if set
// This is kind of nasty comptime meta programming but all we're doing
// here is going through all the modifiers and if they're set, releasing
// both the left and right sides of the modifier. This may not match
// the exact input event but it ensures a full reset.
// Schedule render which also drains our mailbox
// Whenever our focus changes we unhide the mouse. The mouse will be
// hidden again if the user starts typing. This helps alleviate some
// buggy behavior upstream in macOS with the mouse never becoming visible
// again when tabbing between programs (see #2525).
// Update the focus state and notify the terminal
// Crash metadata in case we crash in here
// The point of this callback is to schedule a render, so do that.
// The amount to scroll. This structure is always normalized so that
// negative is down, left and positive is up, right. Note that INTERNALLY,
// vertical scroll on our terminal uses positive for down (right is not
// supported by our screen since scrollback is only vertical).
// Mouse scroll event. Negative is down, left. Positive is up, right.
//
// "Natural scrolling" is a macOS term for inverting the scroll direction.
// This should be handled by the apprt implementation. At this layer,
// negative is always down, left.
// log.info("SCROLL: xoff={} yoff={} mods={}", .{ xoff, yoff, scroll_mods });
// Crash metadata in case we crash in here
// Always show the mouse again if it is hidden
// We use cell_size to determine if we have accumulated enough to trigger a scroll
// If we have precision scroll, yoff is the number of pixels to scroll. In non-precision
// scroll, yoff is the number of wheel ticks. Some mice are capable of reporting fractional
// wheel ticks, which don't necessarily get reported as precision scrolls. We normalize all
// scroll events to pixels by multiplying the wheel tick value and the cell size. This means
// that a wheel tick of 1 results in single scroll event.
// Round out the yoff to an absolute minimum of 1. macos tries to
// simulate precision scrolling with non precision events by
// ramping up the magnitude of the offsets as it detects faster
// scrolling. Single click (very slow) scrolls are reported with a
// magnitude of 0.1 which would normally require a few clicks
// before we register an actual scroll event (depending on cell
// height and the mouse_scroll_multiplier setting).
// Add our previously saved pending amount to the offset to get the
// new offset value. The signs of the pending and yoff should match
// so that we move further away from zero, but we don't assert
// this because in theory a user could scroll in the opposite
// direction and undo a pending scroll.
// If the new offset is less than a single unit of scroll, we save
// the new pending value and do not scroll yet.
// We scroll by the number of rows in the offset and save the remainder
// Round towards zero.
// For detailed comments see the y calculation above.
// log.info("SCROLL: delta_y={} delta_x={}", .{ y.delta, x.delta });
// If we have an active mouse reporting mode, clear the selection.
// The selection can occur if the user uses the shift mod key to
// override mouse grabbing from the window.
// If we're in alternate screen with alternate scroll enabled, then
// we convert to cursor keys. This only happens if we're:
// (1) alt screen (2) no explicit mouse reporting and (3) alt
// scroll mode enabled.
// When we send mouse events as cursor keys we always
// clear the selection.
// cursor key: application mode
// cursor key: normal mode
// We have mouse events, are not in an alternate scroll buffer,
// or have alternate scroll disabled. In this case, we just run
// the normal logic.
// If we're scrolling up or down, then send a mouse event.
// If mouse reporting is on, we do not want to scroll the
// viewport.
// Modify our viewport, this requires a lock since it affects
// rendering. We have to switch signs here because our delta
// is negative down but our viewport is positive down.
// This is called when the content scale of the surface changes. The surface
// can then update any DPI-sensitive state.
// Crash metadata in case we crash in here
// Calculate the new DPI
// Update our font size which is dependent on the DPI
// If our DPI didn't actually change, save a lot of work by doing nothing.
// Update our padding which is dependent on DPI. We only do this for
// unbalanced padding since balanced padding is not dependent on DPI.
// Force a resize event because the change in padding will affect
// pixel-level changes to the renderer and viewport.
// The type of action to report for a mouse event.
// Returns true if mouse reporting is enabled both in the config and
// the terminal state.
// Mouse reporting must be enabled by both config and terminal state
// Depending on the event, we may do nothing at all.
// X10 only reports clicks with mouse button 1, 2, 3. We verify
// the button later.
// Doesn't report motion
// Button must be pressed
// Everything
// Handle scenarios where the mouse position is outside the viewport.
// We always report release events no matter where they happen.
// If we don't have a motion-tracking event mode, do nothing.
// If any button is pressed, we still do the report. Otherwise,
// we do not do the report.
// This format reports X/Y
// Record our new point. We only want to send a mouse event if the
// cell changed, unless we're tracking raw pixels.
// Get the code we'll actually write
// Determine our initial button value
// Null button means motion without a button pressed
// Release is 3. It is NOT 3 in SGR mode because SGR can tell
// the application what button was released.
// X10 doesn't have modifiers
// Motion adds another bit
// + 1 below is because our x/y is 0-indexed and the protocol wants 1
// Ask our IO thread to write the data
// Maximum of 12 because at most we have 2 fully UTF-8 encoded chars
// The button code will always fit in a single u8
// UTF-8 encode the x/y
// Ask our IO thread to write the data
// Final character to send in the CSI
// Response always is at least 4 chars, so this leaves the
// remainder for numbers which are very large...
// Ask our IO thread to write the data
// Response always is at least 4 chars, so this leaves the
// remainder for numbers which are very large...
// Ask our IO thread to write the data
// Final character to send in the CSI
// The position has to be adjusted to the terminal space.
// Response always is at least 4 chars, so this leaves the
// remainder for numbers which are very large...
// Ask our IO thread to write the data
// Returns true if the shift modifier is allowed to be captured by modifier
// events. It is up to the caller to still verify it is a situation in which
// shift capture makes sense (i.e. left button, mouse click, etc.)
// Handle our never/always case where we don't need a lock.
// If the terminal explicitly requests it then we always allow it
// since we processed never/always at this point.
// Otherwise, go with the user's preference
// Returns true if the mouse is currently captured by the terminal
// (i.e. reporting events).
// Called for mouse button press/release events. This will return true
// if the mouse event was consumed in some way (i.e. the program is capturing
// mouse events). If the event was not consumed, then false is returned.
// Crash metadata in case we crash in here
// log.debug("mouse action={} button={} mods={}", .{ action, button, mods });
// If we have an inspector, we always queue a render
// Always record our latest mouse state
// Always show the mouse again if it is hidden
// Update our modifiers if they changed
// This is set to true if the terminal is allowed to capture the shift
// modifier. Note we can do this more efficiently probably with less
// locking/unlocking but clicking isn't that frequent enough to be a
// bottleneck.
// Shift-click continues the previous mouse state if we have a selection.
// cursorPosCallback will also do a mouse report so we don't need to do any
// of the logic below.
// We could do all the conditionals in one but I find it more
// readable as a human to break this one up.
// We split this conditional out on its own because this is the
// only one that requires a renderer mutex grab which is VERY
// expensive because it could block all our threads.
// If we are within the interval that the click would register
// an increment then we do not extend the selection.
// Click interval very short, we may be increasing
// click counts so we don't extend the selection.
// This is a weird behavior, I think either behavior is actually
// fine. This failure should be exceptionally rare anyways.
// My thinking here is that we can't be sure if we should extend
// the selection or not so we just don't.
// Stop selection scrolling when releasing the left mouse button
// but only when selection scrolling is active.
// The selection clipboard is only updated for left-click drag when
// the left button is released. This is to avoid the clipboard
// being updated on every mouse move which would be noisy.
// Handle link clicking. We want to do this before we do mouse
// reporting or any other mouse handling because a successfully
// clicked link will swallow the event.
// Handle prompt clicking. If we released our mouse on a prompt
// and we support some kind of click events, then we need to
// move to it.
// Report mouse events if enabled
// If we have shift-pressed and we aren't allowed to capture it,
// then we do not do a mouse report.
// In any other mouse button scenario without shift pressed we
// clear the selection since the underlying application can handle
// that in any way (i.e. "scrolling").
// We also set the left click count to 0 so that if mouse reporting
// is disabled in the middle of press (before release) we don't
// suddenly start selecting text.
// If we're doing mouse reporting, we do not support any other
// selection or highlighting.
// For left button clicks we always record some information for
// selection/highlighting purposes.
// Weird... our viewport x/y that we just converted isn't
// found in our pages. This is probably a bug but we don't
// want to crash in releases because its harmless. So, we
// only assert in debug mode.
// If we move our cursor too much between clicks then we reset
// the multi-click state.
// Store it
// Setup our click counter and timer
// If we have mouse clicks, then we check if the time elapsed
// is less than and our interval and if so, increase the count.
// We only support up to triple-clicks.
// In all cases below, we set the selection directly rather than use
// `setSelection` because we want to avoid copying the selection
// to the selection clipboard. For left mouse clicks we only set
// the clipboard on release.
// Single click
// If we have a selection, clear it. This always happens.
// Double click, select the word under our mouse.
// First try to detect if we're clicking on a URL to select the entire URL.
// Try link detection without requiring modifier keys
// Ignore any errors, likely regex errors.
// Triple click, select the line under our mouse
// We should be bounded by 1 to 3
// Middle-click pastes from our selection clipboard
// Right-click down selects word for context menus. If the apprt
// doesn't implement context menus this can be a bit weird but they
// are supported by our two main apprts so we always do this. If we
// want to be careful in the future we can add a function to apprts
// that let's us know.
// Get our viewport pin
// If we already have a selection and the selection contains
// where we clicked then we don't want to modify the selection.
// The selection doesn't contain our pin, so we create a new
// word selection where we clicked.
// If there is a link at this position, we want to
// select the link. Otherwise, select the word.
// Don't consume so that we show the context menu in apprt.
// Pasting can trigger a lock grab in complete clipboard
// request so we need to unlock.
// We don't need to clear selection because we didn't have
// one to begin with.
// Before we yield the lock, clear our selection if we have
// one.
// Pasting can trigger a lock grab in complete clipboard
// request so we need to unlock.
// Consume the event such that the context menu is not displayed.
// If our screen doesn't handle any prompt clicks, then we never
// do anything.
// If our cursor isn't currently at a prompt then we don't handle
// prompt clicks because we can't move if we're not in a prompt!
// If we have a selection currently, then releasing the mouse
// completes the selection and we don't do prompt moving. I don't
// love this logic, I think it should be generalized to "if the
// mouse release was on a different cell than the mouse press" but
// our mouse state at the time of writing this doesn't support that.
// Get the pin for our mouse click.
// See mouseButtonCallback for explanation
// Get our cursor's most current prompt.
// This shouldn't be possible because we asserted we're at
// a prompt above, so we MUST find some prompt in a left_up search.
// If our mouse click is before the prompt, we don't move.
// We DO ALLOW clicks AFTER the prompt, specifically with Kitty's
// click_events=1 since we rely on the shell to validate out of
// bounds clicks. This matches Kitty's logic as best I can tell.
// At this point we've established:
// - Screen supports prompt clicks
// - Cursor is at a prompt
// - Click is at or below our prompt
// Guarded at the start of this function
// For the event, we always send a left-click press event.
// This matches what Kitty sends.
// Not that noisy since this only happens on prompt clicks.
// Ask our IO thread to write the data
// Returns the link at the given cursor position, if any.
//
// Requires the renderer mutex is held.
// Convert our cursor position to a screen point.
// Get our comparison mods
// If we have the proper modifiers set then we can check for OSC8 links.
// Fall back to configured links
// Detects if a link is present at the given pin.
//
// If mouse mods is null then mouse mod requirements are ignored (all
// configured links are checked).
//
// Requires the renderer state mutex is held.
// Skip highlight/mods check when mouse_mods is null (double-click mode)
// This returns the mouse mods to consider for link highlighting or
// other purposes taking into account when shift is pressed for releasing
// the mouse from capture.
//
// The renderer state mutex must be held.
// In any of these scenarios, whatever mods are set (even shift)
// are preserved.
// We have mouse capture, shift set, and we're not allowed to capture
// shift, so we can clear shift.
// Attempt to invoke the action of any link that is under the
// given position.
//
// Requires the renderer state mutex is held.
// If the apprt handles it then we're done.
// apprt didn't handle it, fallback to our simple cross-platform
// URL opener. We log a warning because we want well-behaved
// apprts to handle this themselves.
// Return the URI for an OSC8 hyperlink at the given position or null
// if there is no hyperlink.
// Crash metadata in case we crash in here
// We don't currently use the pressure value for anything. In the
// future, we could report this to applications using new mouse
// events or utilize it for some custom UI.
// If the pressure stage is the same as what we already have do nothing
// Update our pressure stage.
// If our left mouse button is pressed and we're entering a deep
// click then we want to start a selection. We treat this as a
// word selection since that is typical macOS behavior.
// This should always be set in this state but we don't want
// to handle state inconsistency here.
// Cursor position callback.
//
// Send negative x or y values to indicate the cursor is outside the
// viewport. The magnitude of the negative values are meaningless;
// they are only used to indicate the cursor is outside the viewport.
// It's important to do this to ensure hover states are cleared.
//
// The mods parameter is optional because some apprts do not provide
// modifier information on cursor position events. If mods is null then
// we'll use the last known mods. This is usually accurate since mod events
// will trigger key press events but on some platforms we don't get them.
// For example, on macOS, unfocused surfaces don't receive key events but
// do receive mouse events so we have to rely on updated mods.
// Crash metadata in case we crash in here
// log.debug("cursor pos x={} y={} mods={?}", .{ pos.x, pos.y, mods });
// If the position is negative, it is outside our viewport and
// we need to clear any hover states.
// Reset our hyperlink state
// No mouse point so we don't highlight links
// Mark the link's row as dirty, but continue with updating the
// mouse state below so we can scroll when our position is negative.
// Always show the mouse again if it is hidden
// Update our modifiers if they changed
// The mouse position in the viewport
// We always reset the over link status because it will be reprocessed
// below. But we need the old value to know if we need to undo mouse
// shape changes.
// We are reading/writing state for the remainder
// Stop selection scrolling when inside the viewport within a 1px buffer
// for fullscreen windows, but only when selection scrolling is active.
// Update our mouse state. We set this to null initially because we only
// want to set it when we're not selecting or doing any other mouse
// event.
// If we have an inspector, we need to always record position information
// Handle link hovering
// We refresh links when
// 1. we were previously over a link
// OR
// 2. the cursor position has changed (either we have no previous state, or the state has
//    changed)
// AND
// 1. mouse reporting is off
// OR
// 2. mouse reporting is on and we are not reporting shift to the terminal
// If we were previously over a link, we always update. We do this so that if the text
// changed underneath us, even if the mouse didn't move, we update the URL hints and state
// Do a mouse report
// Shift overrides mouse "grabbing" in the window, taken from Kitty.
// This only applies if there is a mouse button pressed so that
// movement reports are not affected.
// We use the first mouse button we find pressed in order to report
// since the spec (afaict) does not say...
// If we're doing mouse motion tracking, we do not support text
// selection.
// Handle cursor position for text selection
// Left click pressed but count zero can happen if mouse reporting is on.
// In this scenario, we mark the click state because we need that to
// properly make some mouse reports, but we don't keep track of the
// count because we don't want to handle selection.
// If our terminal screen changed then we don't process this. We don't
// invalidate our pin or mouse state because if the screen switches
// back then we can continue our selection.
// All roads lead to requiring a re-render at this point.
// If our y is negative, we're above the window. In this case, we scroll
// up. The amount we scroll up is dependent on how negative we are.
// We allow for a 1 pixel buffer at the top and bottom to detect
// scroll even in full screen windows.
// Note: one day, we can change this from distance to time based if we want.
// log.warn("CURSOR POS: {} {}", .{ pos, self.size.screen });
// If the mouse is outside the viewport and we have the left
// mouse button pressed then we need to start the scroll timer.
// Convert to points
// Handle dragging depending on click count
// Double-click dragging moves the selection one "word" at a time.
// Get the word closest to our starting click.
// Get the word closest to our current point.
// If our current mouse position is before the starting position,
// then the selection start is the word nearest our current position.
// Triple-click dragging moves the selection one "line" at a time.
// Get the line selection under our current drag point. If there isn't a
// line, do nothing.
// Get the selection under our click point. We first try to trim
// whitespace if we've selected a word. But if no word exists then
// we select the blank line.
// This logic is in a separate function so that it can be unit tested.
// Calculates the appropriate selection given pins and pixel x positions for
// the click point and the drag point, as well as mouse mods and screen size.
// Explanation:
//
// # Normal selections
//
// ## Left-to-right selections
// - The clicked cell is included if it was clicked to the left of its
//   threshold point and the drag location is right of the threshold point.
// - The cell under the cursor (the "drag cell") is included if the drag
//   location is right of its threshold point.
//
// ## Right-to-left selections
// - The clicked cell is included if it was clicked to the right of its
//   threshold point and the drag location is left of the threshold point.
// - The cell under the cursor (the "drag cell") is included if the drag
//   location is left of its threshold point.
//
// # Rectangular selections
//
// Rectangular selections are handled similarly, except that
// entire columns are considered rather than individual cells.
// We only include cells in the selection if the threshold point lies
// between the start and end points of the selection. A threshold of
// 60% of the cell width was chosen empirically because it felt good.
// We use this to clamp the pixel positions below.
// We need to know how far across in the cell the drag pos is, so
// we subtract the padding and then take it modulo the cell width.
// We figure out the fractional part of the click x position similarly.
// Whether or not this is a rectangular selection.
// Whether the click pin and drag pin are equal.
// Whether or not the end point of our selection is before the start point.
// Special handling for rectangular selections, we only use x position.
// Whether or not the the click pin cell
// should be included in the selection.
// Whether or not the the drag pin cell
// should be included in the selection.
// If the click cell should be included in the selection then it's the
// start, otherwise we get the previous or next cell to it depending on
// the type and direction of the selection.
// Likewise for the end pin with the drag cell.
// If the click cell is the same as the drag cell and the click cell
// shouldn't be included, or if the cells are adjacent such that the
// start or end pin becomes the other cell, and that cell should not
// be included, then we have no selection, so we set it to null.
//
// If in rectangular selection mode, we compare columns as well.
//
// TODO(qwerasd): this can/should probably be refactored, it's a bit
//                repetitive and does excess work in rectangle mode.
// TODO: Clamp selection to the screen area, don't
//       let it extend past the last written row.
// Call to notify Ghostty that the color scheme for the terminal has
// changed.
// Crash metadata in case we crash in here
// If our scheme didn't change, then we don't do anything.
// Setup our conditional state which has the current color theme.
// If mode 2031 is on, then we report the change live.
// Get our grid cell
// Scroll to the bottom of the viewport.
//
// Precondition: the render_state mutex must be held.
// Perform a binding action. A binding is a keybinding. This function
// must be called from the GUI thread.
//
// This function returns true if the binding action was performed. This
// may return false if the binding action is not supported or if the
// binding action would do nothing (i.e. previous tab with no tabs).
//
// NOTE: At the time of writing this comment, only previous/next tab
// will ever return false. We can expand this in the future if it becomes
// useful. We did previous/next tab so we could implement #498.
// Forward app-scoped actions to the app. Some app-scoped actions are
// special-cased here because they do some special things when performed
// from the surface.
// Undo and redo both support both surface and app targeting.
// If we are triggering on a surface then we perform the
// action with the surface target.
// We need to send the CSI/ESC sequence as a single write request.
// If you split it across two then the shell can interpret it
// as two literals.
// CSI/ESC triggers a scroll.
// For text we always allocate just because its easier to
// handle all cases that way.
// Text triggers a scroll.
// We send a different sequence depending on if we're
// in cursor keys mode. We're in "normal" mode if cursor
// keys mode is NOT set.
// With the lock held, we must scroll to the bottom.
// We always scroll to the bottom for these inputs.
// To save resources, we don't actually start a search here,
// we just notify the apprt. The real thread will start when
// the first needles are set.
// We only return that this was performed if we actually
// stopped a search, but we also send the apprt end_search so
// that GUIs can clean up stale stuff.
// If we're stopping the search and we had no prior search,
// then there is nothing to do.
// We need to assign directly to self.search because we need
// a stable pointer back to the thread state.
// Zero-length text means stop searching.
// Clear the selection if configured to do so.
// If the mouse isn't over a link, nothing we can do.
// For regex links, get the text from selection
// For OSC8 links, get the URI directly from hyperlink data
// Max delta is somewhat arbitrary.
// Max point size is somewhat arbitrary.
// Mark that we manually adjusted the font size
// Max delta is somewhat arbitrary.
// Mark that we manually adjusted the font size
// Reset font size also resets the manual adjustment state
// Mark that we manually adjusted the font size
// This is a duplicate of some of the logic in termio.clearScreen
// but we need to do this here so we can know the answer before
// we send the message. If the currently active screen is on the
// alternate screen then clear screen does nothing so we want to
// return false so the keybind can be unconsumed.
// Look up the table in our config
// If this is the same table as is currently active, then
// do nothing.
// If we're already at the max, ignore it.
// Add the table to the stack.
// Notify the UI.
// No key table active. This does nothing.
// Final key table active, clear our state.
// Restore the prior key table. We don't free any memory in
// this case because we assume it will be freed later when
// we finish our key table.
// Notify the UI.
// End the key sequence and flush queued keys to the terminal,
// but don't encode the key that triggered this action. This
// will do that because leaf keys (keys with bindings) aren't
// in the queued encoding list.
// Not a big deal if this fails.
// If we don't have a selection we do not perform this
// action, allowing the keybind to fall through to the
// terminal.
// If the selection endpoint is outside of the current viewpoint,
// scroll it in to view. Note we always specifically use sel.end
// because that is what adjust modifies.
// Our end point is not within the viewport. If the end
// point is after the br then we need to adjust the end so
// that it is at the bottom right of the viewport.
// Queue a render so its shown
// Returns true if performing the given action result in closing
// the surface. This is used to determine if our self pointer is
// still valid after performing some binding action.
// The portion of the screen to write for writeScreenFile.
// Create a temporary directory to store our scrollback.
// Open our scrollback file
// Screen.dumpString writes byte-by-byte, so buffer it
// Write the scrollback contents. This requires a lock.
// We only dump history if we have history. We still keep
// the file and write the empty file to the pty so that this
// command always works on the primary screen.
// We do not support this for alternate screens
// because they don't have scrollback anyways.
// If we have no selection we have no data so we do nothing.
// Get the final path
// Call this to complete a clipboard request sent to apprt. This should
// only be called once for each request. The data is immediately copied so
// it is safe to free the data after this call.
//
// If `confirmed` is true then any clipboard confirmation prompts are skipped:
//
//   - For "regular" pasting this means that unsafe pastes are allowed. Unsafe
//     data is defined as data that contains newlines, though this definition
//     may change later to detect other scenarios.
//
//   - For OSC 52 reads and writes no prompt is shown to the user if
//     `confirmed` is true.
//
// If `confirmed` is false then this may return either an UnsafePaste or
// UnauthorizedPaste error, depending on the type of clipboard request.
// This starts a clipboard request, with some basic validation. For example,
// an OSC 52 request is not actually requested if OSC 52 is disabled.
//
// Returns true if the request was started, false if it was not (e.g., clipboard
// doesn't contain text for paste requests). This allows performable keybinds
// to pass through when the action cannot be performed.
// No clipboard write code paths travel through this function
// If we have paste protection enabled, we detect unsafe pastes and return
// an error. The error approach allows apprt to attempt to complete the paste
// before falling back to requesting confirmation.
//
// We do not do this for bracketed pastes because bracketed pastes are
// by definition safe since they're framed.
// If we've disabled paste protection then we always allow the paste.
// If we're allowed to paste unsafe data then we always allow the paste.
// This is set during confirmation usually.
// If we're bracketed and the paste contains and ending
// bracket then something naughty might be going on and we
// never trust it.
// If we are bracketed and configured to trust that then the
// paste is not unsafe.
// With the lock held, we must scroll to the bottom.
// We always scroll to the bottom for these inputs.
// Encode the data. In most cases this doesn't require any
// copies, so we optimize for that case.
// This code path means the data did require a copy and mutation.
// We must free it.
// We should never get here if clipboard-read is set to deny
// If clipboard-read is set to ask and we haven't confirmed with the user,
// do that now
// Even if the clipboard data is empty we reply, since presumably
// the client app is expecting a reply. We first allocate our buffer.
// This must hold the base64 encoded data PLUS the OSC code surrounding it.
// Wrap our data with the OSC code
// Do the base64 encoding
// Wyhash is used to hash the contents of the desktop notification to limit
// how fast identical notifications can be sent sequentially.
// Set a limit of one desktop notification per second so that the OS
// doesn't kill us when we run out of resources.
// Set a limit of one notification per five seconds for desktop
// notifications with identical content.
// Tell the surface to present itself to the user. This may involve raising the
// window and switching tabs.
// Utility function for the unit tests for mouse selection logic.
//
// Tests a click and drag on a 10x5 cell grid, x positions are given in
// fractional cells, e.g. 3.1 would be 10% through the cell at x = 3.
//
// NOTE: The size tested with has 10px wide cells, meaning only one digit
//       after the decimal place has any meaning, e.g. 3.14 is equal to 3.1.
//
// The provided start_x/y and end_x/y are the expected start and end points
// of the resulting selection.
// Our screen size is 10x5 cells that are
// 10x20 px, with 5px padding on all sides.
// We hold both ctrl and alt for rectangular
// select so that this test is platform agnostic.
// Like `testMouseSelection` but checks that the resulting selection is null.
//
// See `testMouseSelection` for more details.
// Our screen size is 10x5 cells that are
// 10x20 px, with 5px padding on all sides.
// We hold both ctrl and alt for rectangular
// select so that this test is platform agnostic.
// We disable format to make these easier to
// read by pairing sets of coordinates per line.
// zig fmt: off
// -- LTR
// single cell selection
// including click and drag pin cells
// including click pin cell but not drag pin cell
// including drag pin cell but not click pin cell
// including neither click nor drag pin cells
// empty selection (single cell on only left half)
// empty selection (single cell on only right half)
// empty selection (between two cells, not crossing threshold)
// -- RTL
// single cell selection
// including click and drag pin cells
// including click pin cell but not drag pin cell
// including drag pin cell but not click pin cell
// including neither click nor drag pin cells
// empty selection (single cell on only left half)
// empty selection (single cell on only right half)
// empty selection (between two cells, not crossing threshold)
// -- Wrapping
// LTR, wrap excluded cells
// RTL, wrap excluded cells
// We disable format to make these easier to
// read by pairing sets of coordinates per line.
// zig fmt: off
// -- LTR
// single column selection
// including click and drag pin columns
// including click pin column but not drag pin column
// including drag pin column but not click pin column
// including neither click nor drag pin columns
// empty selection (single column on only left half)
// empty selection (single column on only right half)
// empty selection (between two columns, not crossing threshold)
// -- RTL
// single column selection
// including click and drag pin columns
// including click pin column but not drag pin column
// including drag pin column but not click pin column
// including neither click nor drag pin columns
// empty selection (single column on only left half)
// empty selection (single column on only right half)
// empty selection (between two columns, not crossing threshold)
// -- Wrapping
// LTR, do not wrap
// RTL, do not wrap
//
// --- Original Ghostty Comments End: src/Surface.zig

// a minimal "widget" where the terminal is drawn and responds to events
// such as keyboard and mouse. Each surface also creates and owns its pty
// session.
//
// The word "surface" is used because it is left to the higher level
// application runtime to determine if the surface is a window, a tab,
// a split, a preview pane in a larger window, etc. This struct doesn't care:
// it just draws and responds to events. The events come from the application
// runtime so the runtime can determine when and how those are delivered
// (i.e. with focus, without focus, and so on).
module core

import configpkg
import apprt
import datastruct
import font
import input
import log
import math
import time
import os
import encoding.base64
import sync
import search as searchpkg
import osc
import internal_hash
import internal_os
import terminal
import inspector as inspectorpkg
import global_state
import highlight
import renderer as rendererpkg
import simd
import termio as termiopkg
import unicode
import crash
import oniguruma

// Minimum window size in cells.
const min_window_width_cells = u32(10)
const min_window_height_cells = u32(4)

// The maximum number of key tables that can be active at any given time.
const max_active_key_tables = 8

// Default DPI for font scaling.
const default_dpi = f32(font.default_dpi)

// InputEffect (the effect of an input event) lives in the apprt
// interface; core.Surface returns apprt.InputEffect.

// The action to report for a mouse event.
enum MouseReportAction as u8 {
	press
	release
	motion
}

// The portion of the screen to write for write_screen_file.
enum WriteScreenLoc as u8 {
	screen
	history
	selection
}

enum KeySequenceQueued as u8 {
	flush
	drop
}

enum KeySequenceMemory as u8 {
	retain
	free
}

// ScrollAmount keeps track of the scroll delta, normalized so that
// negative is down/left and positive is up/right.
struct ScrollAmount {
mut:
	delta int
}

fn (s ScrollAmount) direction() ScrollDirection {
	return if s.delta < 0 { ScrollDirection.down_left } else { ScrollDirection.up_right }
}

fn (s ScrollAmount) magnitude() uint {
	return if s.delta < 0 { uint(-s.delta) } else { uint(s.delta) }
}

enum ScrollDirection as u8 {
	down_left
	up_right
}

// Coordinate represents x/y in the viewport.
pub type Coordinate = terminal.Coordinate

// FontMetrics holds font measurement data.
pub type FontMetrics = font.Metrics

// DesiredSize represents the desired font size with DPI info.
pub type DesiredSize = font.DesiredSize

// Mouse state for the surface.
pub struct Mouse {
pub mut:
	// Last tracked mouse button state by button.
	click_state [input.mouse_button_max]input.MouseButtonState = [input.mouse_button_max]input.MouseButtonState{init: .release}

	// Last mods state when the last mouse button was pressed/released.
	mods input.Mods

	// Pin at which the left mouse click happened.
	left_click_pin ?&Pin
	// Screen that owns left_click_pin. Selection scrolling stops if the active
	// screen changes while a drag is in progress.
	left_click_screen terminal.ScreenKey

	// Starting xpos/ypos of the left click.
	left_click_xpos f64
	left_click_ypos f64

	// Click count for double/triple clicks.
	left_click_count u8
	left_click_time  u64

	// Last x/y sent for mouse reports.
	event_point ?Coordinate

	// Pressure stage for the mouse.
	pressure_stage input.PressureStage = .none_

	// Pending scroll amounts for high-precision scrolls.
	pending_scroll_x f64
	pending_scroll_y f64

	// True if the mouse is hidden.
	hidden bool

	// True if the mouse position is currently over a link.
	over_link bool

	// Last x/y in the cursor position for links.
	link_point ?Coordinate
}

// Keyboard state for the surface.
pub struct Keyboard {
pub mut:
	// Currently active key sequence set.
	sequence_set ?BindingSet

	// Queued keys when in the middle of a sequenced binding.
	sequence_queued []termiopkg.WriteReq

	// Stack of active key tables.
	table_stack []KeyTableEntry

	// Last handled binding trigger hash.
	last_trigger ?u64
}

struct KeyTableEntry {
	set  BindingSet
	once bool
	// name is the config name of the activated table.
	name string
}

// FontGridSet, FontGridKey, FontGrid are aliases to the real font module types.
pub type FontGridSet = font.SharedGridSet

pub type FontGridKey = font.Key

pub type FontGrid = font.SharedGrid

pub type Renderer = rendererpkg.Renderer

pub type RendererState = rendererpkg.RenderState

pub type RendererMouseState = rendererpkg.RenderMouse

pub type Preedit = rendererpkg.RenderPreedit

pub type PreeditCodepoint = rendererpkg.RenderPreeditCodepoint

pub type RendererThread = rendererpkg.RendererThread

// Keep the public surface names while using the real emulator types.
pub type SurfaceTerminal = terminal.Terminal

pub type TermSelection = terminal.Selection

pub type Pin = terminal.Pin

pub struct TermIO {
pub mut:
	impl     termiopkg.Termio
	messages []termiopkg.Message
	live     bool
}

fn (mut t TermIO) queue_message(msg termiopkg.Message, mutex termiopkg.MutexState) {
	if t.live {
		t.impl.queue_message(msg, mutex)
		return
	}
	// Zero-initialized surfaces used by focused unit tests have no PTY. Retain
	// their messages so the tests can inspect the exact payloads.
	t.messages << msg
}

fn (mut t TermIO) deinit() {
	if t.live {
		t.impl.deinit()
	}
	t.live = false
	t.messages = []
}

pub struct IOThread {
pub mut:
	impl    termiopkg.Thread
	running bool
}

fn (mut t IOThread) deinit() {
	t.impl.deinit()
	t.running = false
}

pub type Inspector = inspectorpkg.Inspector

pub type BindingSet = input.Set

@[heap]
pub struct SurfaceSearch {
pub mut:
	state   &searchpkg.SearchThread = unsafe { nil }
	thread_ ?thread
}

fn (mut s SurfaceSearch) deinit() {
	// Notify the thread to stop
	s.state.stop.notify() or { log.error('error notifying search thread to stop, may stall err=${err}') }

	// Wait for the OS thread to quit
	if worker := s.thread_ {
		worker.wait()
	}
	s.thread_ = none

	// Now it is safe to deinit the state
	s.state.deinit()
}

fn search_callback(event searchpkg.Event, userdata voidptr) {
	// IMPORTANT: This function is run on the SEARCH THREAD! It is NOT SAFE
	// to access anything other than values that never change on the surface.
	// The surface is guaranteed to be valid for the lifetime of the search
	// thread.
	mut surface := unsafe { &Surface(userdata) }
	surface.search_callback_(event) or { log.warn('error in search callback err=${err}') }
}

fn (mut surface Surface) search_callback_(event searchpkg.Event) ! {
	// NOTE: This runs on the search thread.

	match event {
		searchpkg.EventViewportMatches {
			mut matches := []highlight.Flattened{cap: event.matches.len}
			for match_ in event.matches {
				matches << match_.clone()
			}
			_ = surface.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.SearchViewportMatchesMessage{
				matches: matches
			}), datastruct.blocking_queue_forever)
			surface.renderer_thread.wakeup.notify()!
		}
		searchpkg.EventSelectedMatch {
			selected := if value := event.selected { ?uint(value.idx) } else { none }
			match_ := if value := event.selected {
				?highlight.Flattened(value.highlight.clone())
			} else {
				none
			}
			_ = surface.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.SearchSelectedMatchMessage{
				match_: match_
			}), datastruct.blocking_queue_forever)
			surface.surface_mailbox().push(apprt.SurfaceMessageSearchSelected{ selected: selected }, datastruct.blocking_queue_forever)
			surface.renderer_thread.wakeup.notify()!
		}
		searchpkg.EventTotalMatches {
			surface.surface_mailbox().push(apprt.SurfaceMessageSearchTotal{ total: event.total }, datastruct.blocking_queue_forever)
		}
		searchpkg.EventQuit {
			_ = surface.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.SearchSelectedMatchMessage{
				match_: none
			}), datastruct.blocking_queue_forever)
			_ = surface.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.SearchViewportMatchesMessage{
				matches: []highlight.Flattened{}
			}), datastruct.blocking_queue_forever)
			surface.renderer_thread.wakeup.notify()!
			mailbox := surface.surface_mailbox()
			mailbox.push(apprt.SurfaceMessageSearchTotal{ total: none }, datastruct.blocking_queue_forever)
			mailbox.push(apprt.SurfaceMessageSearchSelected{ selected: none }, datastruct.blocking_queue_forever)
		}
		searchpkg.EventComplete {}
	}
}

pub type Config = configpkg.Config

pub type ConditionalState = configpkg.ConditionalState

pub type Theme = configpkg.Theme

// Text represents text read from the terminal with viewport metadata.
pub struct Text {
pub mut:
	text     string
	viewport ?TextViewport
}

pub struct TextViewport {
pub:
	tl_px_x      f64
	tl_px_y      f64
	offset_start u32
	offset_len   u32
}

// deinit releases the owned text returned by dump_text. V's GC owns the
// allocation, so clearing the value is the lifecycle equivalent of Ghostty's
// allocator-backed free.
pub fn (mut self Text) deinit() {
	self.text = ''
	self.viewport = none
}

// Link represents a detected link at a position in the terminal.
struct Link {
	action    input.LinkAction
	selection TermSelection
}

// DerivedConfig holds the configuration derived from the main config.
pub struct DerivedConfig {
pub mut:
	original_font_size               f32
	keybind                          configpkg.Keybinds
	key_remaps                       input.RemapSet
	abnormal_command_exit_runtime_ms u32
	clipboard_read                   configpkg.ClipboardAccess
	clipboard_write                  configpkg.ClipboardAccess
	clipboard_trim_trailing_spaces   bool
	clipboard_paste_protection       bool
	clipboard_paste_bracketed_safe   bool
	clipboard_codepoint_map          configpkg.RepeatableClipboardCodepointMap
	copy_on_select                   configpkg.CopyOnSelect
	confirm_close_surface            configpkg.ConfirmCloseSurface
	cursor_click_to_move             bool
	desktop_notifications            bool
	right_click_action               configpkg.RightClickAction
	mouse_interval                   u64
	mouse_hide_while_typing          bool
	mouse_reporting                  bool
	mouse_scroll_multiplier          configpkg.MouseScrollMultiplier
	mouse_shift_capture              configpkg.MouseShiftCapture
	macos_non_native_fullscreen      configpkg.NonNativeFullscreen
	macos_option_as_alt              ?input.OptionAsAlt
	selection_clear_on_copy          bool
	selection_clear_on_typing        bool
	selection_word_chars             []u32
	vt_kam_allowed                   bool
	wait_after_command               bool
	command                          string
	window_padding_top               u32
	window_padding_bottom            u32
	window_padding_left              u32
	window_padding_right             u32
	window_padding_balance           configpkg.WindowPaddingBalance
	window_height                    u32
	window_width                     u32
	title                            ?string
	title_report                     bool
	links                            []DerivedConfigLink
	link_previews                    configpkg.LinkPreviews
	scroll_to_bottom_keystroke       bool
	font                             DerivedFontConfig
}

pub type DerivedFontConfig = font.DerivedConfig

pub struct DerivedConfigLink {
pub:
	regex     oniguruma.Regex
	action    input.LinkAction
	highlight input.LinkHighlight
}

pub fn DerivedConfig.from_config(config &Config) !DerivedConfig {
	mut links := []DerivedConfigLink{cap: config.link.links.len}
	for link in config.link.links {
		regex := link.oni_regex() or {
			for mut compiled in links {
				compiled.regex.deinit()
			}
			return err
		}
		links << DerivedConfigLink{
			regex:     regex
			action:    link.action
			highlight: link.highlight
		}
	}
	return DerivedConfig{
		original_font_size:               config.font_size
		keybind:                          config.keybind.clone()
		key_remaps:                       config.key_remap.clone()
		abnormal_command_exit_runtime_ms: config.abnormal_command_exit_runtime
		clipboard_read:                   config.clipboard_read
		clipboard_write:                  config.clipboard_write
		clipboard_trim_trailing_spaces:   config.clipboard_trim_trailing_spaces
		clipboard_paste_protection:       config.clipboard_paste_protection
		clipboard_paste_bracketed_safe:   config.clipboard_paste_bracketed_safe
		clipboard_codepoint_map:          config.clipboard_codepoint_map.clone()
		copy_on_select:                   config.copy_on_select
		confirm_close_surface:            config.confirm_close_surface
		cursor_click_to_move:             config.cursor_click_to_move
		desktop_notifications:            config.desktop_notifications
		right_click_action:               config.right_click_action
		mouse_interval:                   u64(config.click_repeat_interval) * u64(time.millisecond)
		mouse_hide_while_typing:          config.mouse_hide_while_typing
		mouse_reporting:                  config.mouse_reporting
		mouse_scroll_multiplier:          config.mouse_scroll_multiplier
		mouse_shift_capture:              config.mouse_shift_capture
		macos_non_native_fullscreen:      config.macos_non_native_fullscreen
		macos_option_as_alt:              config.macos_option_as_alt
		selection_clear_on_copy:          config.selection_clear_on_copy
		selection_clear_on_typing:        config.selection_clear_on_typing
		selection_word_chars:             config.selection_word_chars.codepoints.clone()
		vt_kam_allowed:                   config.vt_kam_allowed
		wait_after_command:               config.wait_after_command
		command:                          if command := config.command {
			command.string_val().clone()
		} else {
			''
		}
		window_padding_top:               config.window_padding_y.top_left
		window_padding_bottom:            config.window_padding_y.bottom_right
		window_padding_left:              config.window_padding_x.top_left
		window_padding_right:             config.window_padding_x.bottom_right
		window_padding_balance:           config.window_padding_balance
		window_height:                    config.window_height
		window_width:                     config.window_width
		title:                            config.title
		title_report:                     config.title_report
		links:                            links
		link_previews:                    config.link_previews
		scroll_to_bottom_keystroke:       config.scroll_to_bottom.keystroke()
		font:                             font.DerivedConfig.init(config)!
	}
}

pub fn (mut self DerivedConfig) deinit() {
	// Cleanup compiled regexes and cloned keybinds.
	for mut link in self.links {
		link.regex.deinit()
	}
	self.links = []
	self.selection_word_chars = []
	self.clipboard_codepoint_map.map.deinit()
	self.key_remaps.deinit()
}

fn (self &DerivedConfig) scaled_padding(x_dpi f32, y_dpi f32) rendererpkg.Padding {
	top := u32(math.floor(f32(self.window_padding_top) * y_dpi / 72.0))
	bottom := u32(math.floor(f32(self.window_padding_bottom) * y_dpi / 72.0))
	left := u32(math.floor(f32(self.window_padding_left) * x_dpi / 72.0))
	right := u32(math.floor(f32(self.window_padding_right) * x_dpi / 72.0))
	return rendererpkg.Padding{
		top:    top
		bottom: bottom
		left:   left
		right:  right
	}
}

pub type SurfaceMessage = apprt.SurfaceMessage

pub type SurfaceMessageKind = apprt.SurfaceMessageKind

// termio_surface_message_push implements apprt.SurfaceMailbox.push for a core
// surface by rewrapping the message for the app thread.
fn termio_surface_message_push(app_ptr voidptr, surface_ptr voidptr, msg apprt.SurfaceMessage, timeout datastruct.BlockingQueueTimeout) u32 {
	app := unsafe { &App(app_ptr) }
	surface := unsafe { &Surface(surface_ptr) }
	app_mailbox := Mailbox{
		rt_app:  surface.rt_app
		mailbox: app.mailbox
	}
	return app_mailbox.push(Message(SurfaceMessageMsg{
		surface: surface
		message: msg
	}), timeout)
}

fn (self &Surface) surface_mailbox() apprt.SurfaceMailbox {
	return apprt.SurfaceMailbox{
		surface: voidptr(self)
		app:     voidptr(self.app)
		push_fn: termio_surface_message_push
	}
}

// surface_renderer_wakeup is the renderer thread's App.Mailbox redraw push.
fn surface_renderer_wakeup(surface_ptr voidptr) {
	surface := unsafe { &Surface(surface_ptr) }
	app_mailbox := Mailbox{
		rt_app:  surface.rt_app
		mailbox: surface.app.mailbox
	}
	_ = app_mailbox.push(Message(RedrawSurfaceMsg{
		surface: surface
	}), datastruct.blocking_queue_instant)
}

fn renderer_surface_event_push(surface_ptr voidptr, event rendererpkg.SurfaceEvent, timeout datastruct.BlockingQueueTimeout) u32 {
	surface := unsafe { &Surface(surface_ptr) }
	message := match event {
		rendererpkg.RendererHealthEvent {
			apprt.SurfaceMessage(apprt.SurfaceMessageRendererHealth{ health: event.health })
		}
		rendererpkg.ScrollbarEvent {
			apprt.SurfaceMessage(event.scrollbar)
		}
	}
	return surface.surface_mailbox().push(message, timeout)
}

pub type KeyEvent = input.KeyEvent

pub type KeyAction = input.KeyAction

// closing_action returns true if performing the given action results in
// closing the surface. This is used to determine if our self pointer is still
// valid after performing some binding action.
fn closing_action(action input.Action) bool {
	return match action {
		input.ActionCloseSurface, input.ActionCloseWindow, input.ActionCloseTab { true }
		else { false }
	}
}

// ---- Surface struct ----

pub struct Surface {
pub mut:
	app        &App                  = unsafe { nil }
	rt_app     &apprt.RuntimeApp     = unsafe { nil }
	rt_surface &apprt.RuntimeSurface = unsafe { nil }

	font_grid_key      FontGridKey
	font_grid          &font.SharedGrid = unsafe { nil }
	font_size          DesiredSize
	font_size_adjusted bool
	font_metrics       FontMetrics

	renderer           Renderer
	renderer_state     RendererState
	renderer_thread    RendererThread
	renderer_os_thread ?thread

	mouse    Mouse
	keyboard Keyboard

	io           TermIO
	io_thread    IOThread
	io_os_thread ?thread

	inspector ?&Inspector

	size   rendererpkg.Size
	config DerivedConfig

	config_conditional_state ConditionalState

	child_exited bool
	focused      bool = true

	selection_scroll_active bool
	readonly                bool

	// The search state for the surface. When none, no search is active.
	search ?&SurfaceSearch

	command_timer  ?u64
	last_bell_time ?u64

	pressed_key          ?KeyEvent
	last_binding_trigger u64
}

// has_terminal returns true if the terminal pointer is initialized.
fn (self &Surface) has_terminal() bool {
	return unsafe { self.renderer_state.terminal_ != nil }
}

// ---- Surface methods ----

pub struct SurfaceInitOptions {
pub:
	command ?configpkg.Command
	title   ?string
}

// init creates a new surface. This must be called from the main thread.
pub fn (mut self Surface) init(config_original &Config, mut app App, rt_app &apprt.RuntimeApp, rt_surface &apprt.RuntimeSurface) ! {
	self.init_with_options(config_original, mut app, rt_app, rt_surface, SurfaceInitOptions{})!
}

// init_with_options applies launch options after resolving conditional config.
pub fn (mut self Surface) init_with_options(config_original &Config, mut app App, rt_app &apprt.RuntimeApp, rt_surface &apprt.RuntimeSurface, options SurfaceInitOptions) ! {
	crash.set_dimensions_reader(crash_surface_dimensions)
	// V has no errdefer. Each source errdefer is a reached defer that runs
	// only while this flag is false, i.e. when initialization fails.
	mut init_ok := false

	// Apply our conditional state. If we fail to apply the conditional state
	// then we log and attempt to move forward with the old config.
	conditional_result := config_original.change_conditional_state(app.config_conditional_state) or {
		log.warn('failed to apply conditional state to config err=${err}')
		configpkg.ConfigChangeResult{}
	}
	mut config_ := &Config(unsafe { nil })
	if c := conditional_result.value {
		config_ = &Config{
			...c
		}
	}
	defer {
		if !isnil(config_) {
			config_.deinit()
		}
	}

	// We want a config pointer for everything so we get that either
	// based on our conditional state or the original config.
	config := if !isnil(config_) {
		// We want to preserve our original working directory. We
		// don't need to dupe memory here because termio will derive
		// it. We preserve this so directory inheritance works.
		config_.working_directory = config_original.working_directory
		config_
	} else {
		config_original
	}

	unsafe {
		self.app = app
		self.rt_app = rt_app
		self.rt_surface = rt_surface
	}

	// The first surface may use initial-command; every later surface uses the
	// regular command. This selection is shared by termio and initial titles.
	command := if override := options.command {
		?configpkg.Command(override)
	} else {
		surface_command(config, app.first)
	}

	// Get our configuration
	mut derived_config := DerivedConfig.from_config(config)!
	derived_config.command = if value := command { value.string_val().clone() } else { '' }
	defer {
		if !init_ok {
			derived_config.deinit()
		}
	}

	// Initialize our renderer with our initialized surface.
	rendererpkg.surface_init()!

	// Determine our DPI configurations so we can properly configure
	// font points to pixels and handle other high-DPI scaling factors.
	content_scale := rt_surface.get_content_scale()!
	x_dpi := content_scale.x * default_dpi
	y_dpi := content_scale.y * default_dpi

	// The font size we desire along with the DPI determined for the surface
	self.font_size = DesiredSize{
		points: derived_config.original_font_size
		xdpi:   u16(x_dpi)
		ydpi:   u16(y_dpi)
	}

	// Setup our font group. This will reuse an existing font group if
	// it was already loaded.
	font_grid_key, font_grid := app.font_grid_set.ref(&derived_config.font, self.font_size)!
	self.font_grid_key = font_grid_key
	self.font_grid = font_grid
	self.font_metrics = font_grid.metrics

	// Build our size struct which has all the sizes we need.
	surface_size := rt_surface.get_size()!
	font_cell_size := font_grid.cell_size()
	self.size = rendererpkg.Size{
		screen: rendererpkg.ScreenSize{
			width:  surface_size.width
			height: surface_size.height
		}
		cell:   rendererpkg.CellSize{
			width:  font_cell_size.width
			height: font_cell_size.height
		}
	}
	explicit := derived_config.scaled_padding(x_dpi, y_dpi)
	self.size.set_padding(explicit, derived_config.window_padding_balance)

	size_limits := apprt.SizeLimit{
		min_width:  self.size.cell.width * min_window_width_cells
		min_height: self.size.cell.height * min_window_height_cells
	}
	initial_size := if derived_config.window_height > 0 && derived_config.window_width > 0 {
		?apprt.InitialSize(derived_config.initial_window_size(self.size, content_scale))
	} else {
		none
	}
	if requested := initial_size {
		if startup := rt_surface.startup_size(requested, size_limits) {
			self.size.screen = rendererpkg.ScreenSize{
				width:  startup.width
				height: startup.height
			}
			self.size.set_padding(explicit, derived_config.window_padding_balance)
		}
	}

	// Create our terminal grid with the initial size
	renderer_config := rendererpkg.DerivedConfig.init(config)!
	self.renderer = Renderer.init(rendererpkg.RendererOpts{
		metal_view:      rt_surface.renderer_view
		metal_shares_gg: rt_surface.renderer_shares_gg
		content_scale:   f64(content_scale.x)
		font_grid:       font_grid
		config:          renderer_config
		size:            self.size
		surface_mailbox: rendererpkg.SurfaceMailbox{
			user_data: voidptr(&self)
			push_fn:   renderer_surface_event_push
		}
	})!
	defer {
		if !init_ok {
			self.renderer.deinit()
		}
	}

	// The mutex used to protect our renderer state.
	self.renderer_state = RendererState{
		mutex: sync.new_mutex()
	}
	defer {
		if !init_ok {
			self.renderer_state.mutex.destroy()
		}
	}

	// Create the renderer thread
	self.renderer_thread = RendererThread.init(config, &self.renderer, &self.renderer_state, rendererpkg.Wakeup{
		user_data: voidptr(&self)
		notify_fn: surface_renderer_wakeup
	})!
	defer {
		if !init_ok {
			self.renderer_thread.deinit()
		}
	}

	// Create the IO thread
	self.io_thread.impl = termiopkg.Thread.init()!
	defer {
		if !init_ok {
			self.io_thread.deinit()
		}
	}

	self.config = derived_config

	// Our conditional state is initialized to the app state. This
	// lets us get the most likely correct color theme and so on.
	self.config_conditional_state = app.config_conditional_state

	// Start our IO implementation
	mut env := rt_surface.default_termio_env() or {
		// If an error occurs, we don't want to block surface startup.
		log.warn('error getting env map for surface err=${err}')
		internal_os.get_env_map() or { map[string]string{} }
	}

	// don't leak GHOSTTY_LOG to any subprocesses
	env.delete('GHOSTTY_LOG')

	// Initialize our IO backend
	mut io_exec := termiopkg.Exec.init(termiopkg.ExecConfig{
		command:                    command
		env:                        env
		env_override:               config.env
		shell_integration:          config.shell_integration
		shell_integration_features: config.shell_integration_features
		working_directory:          config.working_directory
		resources_dir:              global_state.get_state().resources_dir.host()
		term:                       config.term
		linux_cgroup:               rt_surface.linux_cgroup
	})!
	mut io_owned := false
	defer {
		if !io_owned {
			io_exec.deinit()
		}
	}

	// Initialize our IO mailbox
	mut io_mailbox := termiopkg.Mailbox.init_spsc()!
	defer {
		if !io_owned {
			io_mailbox.deinit()
		}
	}

	self.io.impl.init(termiopkg.TermioOpts{
		size:             self.size
		full_config:      unsafe { config }
		config:           termiopkg.DerivedConfig.init(config)!
		backend:          termiopkg.Backend{ exec: io_exec }
		mailbox:          io_mailbox
		renderer_state:   &self.renderer_state
		renderer_wakeup:  self.renderer_thread.wakeup
		renderer_mailbox: self.renderer_thread.mailbox
		surface_mailbox:  apprt.SurfaceMailbox{
			surface: voidptr(&self)
			app:     voidptr(&app)
			push_fn: termio_surface_message_push
		}
	})!
	self.io.live = true
	io_owned = true

	// Outside the block, IO has now taken ownership of our temporary state
	// so we can just defer this and not the subcomponents.
	defer {
		if !init_ok {
			self.io.deinit()
		}
	}

	// Report initial cell size on surface creation
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.cell_size,
		apprt.ActionValue(apprt.CellSize{
			width:  self.size.cell.width
			height: self.size.cell.height
		}),
	)!

	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.size_limit,
		apprt.ActionValue(size_limits),
	)!

	// Call our size callback which handles all our retina setup
	self.resize(self.size.screen)!

	// Give the renderer one more opportunity to finalize any surface
	// setup on the main thread prior to spinning up the rendering thread.
	self.renderer.finalize_surface_init()!

	// Start our renderer thread
	mut render_thread := unsafe { &self.renderer_thread }
	self.renderer_os_thread = spawn render_thread.thread_main()

	// Start our IO thread
	self.io_thread.running = true
	mut writer := unsafe { &self.io_thread.impl }
	mut termio := unsafe { &self.io.impl }
	self.io_os_thread = spawn writer.thread_main(mut termio)

	// Send the initial window size once the renderer is ready.
	if requested := initial_size {
		self.report_initial_window_size(requested) or {
			log.warn('unable to set initial window size: ${err}')
		}
	}

	// Set the configured title, the complete xdg-terminal-exec command, or the
	// argv[0] of a directly supplied command, in that priority order.
	initial_title := if title := options.title { ?string(title) } else { surface_initial_title(config, command) }
	if title := initial_title {
		self.rt_app.perform_action(
			apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
			.set_title,
			apprt.ActionValue(apprt.SetTitle{ title: title }),
		)!
	}

	// We are no longer the first surface
	app.first = false
	init_ok = true
}

fn surface_command(config &Config, first bool) ?configpkg.Command {
	if first {
		if command := config.initial_command {
			return command
		}
	}
	return config.command
}

fn surface_initial_title(config &Config, command ?configpkg.Command) ?string {
	if title := config.title {
		return title
	}

	$if linux {
		if config.xdg_terminal_exec {
			if value := command {
				return value.string_val()
			}
			return none
		}
	}

	if value := command {
		match value {
			configpkg.DirectCmd {
				if value.direct.len > 0 {
					return value.direct[0]
				}
			}
			configpkg.ShellCmd {}
		}
	}
	return none
}

// deinit cleans up the surface and all its resources.
pub fn (mut self Surface) deinit() {
	// Stop search before either consumer of terminal state is torn down.
	if mut search := self.search {
		search.deinit()
		self.search = none
	}

	// Stop rendering thread
	self.renderer_thread.stop.notify() or {
		log.error('error notifying renderer thread to stop, may stall err=${err}')
	}
	renderer_thr := self.renderer_os_thread or { panic('renderer thread was never started') }
	renderer_thr.wait()
	self.renderer_os_thread = none

	// We need to become the active rendering thread again
	self.renderer.thread_enter() or { panic(err) }

	// Stop our IO thread
	self.io_thread.impl.stop.notify() or {
		log.error('error notifying io thread to stop, may stall err=${err}')
	}
	io_thr := self.io_os_thread or { panic('io thread was never started') }
	io_thr.wait()
	self.io_os_thread = none

	// No thread can access shared renderer/terminal state after both joins.
	self.renderer_thread.deinit()
	self.renderer.deinit()
	self.io_thread.deinit()
	self.io.deinit()
	self.renderer_state.terminal_ = unsafe { nil }
	self.renderer_state.mutex.destroy()

	// Clean up inspector
	if mut insp := self.inspector {
		insp.deinit()
		self.inspector = none
	}

	// Clean up keyboard state
	for mut req in self.keyboard.sequence_queued {
		req.deinit()
	}
	self.keyboard.sequence_queued.clear()
	self.keyboard.table_stack.clear()

	// Release font grid
	self.app.font_grid_set.deref(self.font_grid_key)
	self.font_grid = unsafe { nil }

	// Clean up config
	self.config.deinit()
}

// close triggers the runtime to start the close process.
pub fn (mut self Surface) close() {
	self.rt_surface.close(self.needs_confirm_quit())
}

// needs_confirm_quit returns true if the surface requires confirmation to quit.
pub fn (self &Surface) needs_confirm_quit() bool {
	if self.readonly {
		return true
	}
	if self.child_exited {
		return false
	}
	return match self.config.confirm_close_surface {
		.always { true }
		.false_ { false }
		.true_ {
			// Check if cursor is at a shell prompt (process likely idle).
			if !self.has_terminal() {
				true
			} else {
				!self.renderer_state.terminal_.cursor_is_at_prompt()
			}
		}
	}
}

// handle_message handles mailbox messages to this specific surface.
pub fn (mut self Surface) handle_message(msg apprt.SurfaceMessage) ! {
	match msg {
		apprt.SurfaceMessageChangeConfig {
			self.update_config(msg.config)!
		}
		apprt.SurfaceMessageSetTitle {
			if self.config.title != none {
				return
			}
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.set_title,
				apprt.ActionValue(apprt.SetTitle{ title: null_terminated_bytes(msg.title[..]) }),
			)!
		}
		apprt.SurfaceMessageReportTitle {
			if !self.config.title_report {
				return
			}
			title := self.rt_surface.get_title() or { '' }
			data := '\x1b]l${title}\x1b\\'
			self.queue_io(termiopkg.MessageWriteAlloc{ data: data }, .unlocked)
		}
		osc.ColoredTarget {
			if color_change := apprt_color_change(msg) {
				self.rt_app.perform_action(
					apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
					.color_change,
					apprt.ActionValue(color_change),
				)!
			}
		}
		apprt.SurfaceMessageSetMouseShape {
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.mouse_shape,
				apprt.ActionValue(msg.shape),
			)!
		}
		apprt.SurfaceMessageClipboardRead {
			if self.config.clipboard_read == .deny {
				return
			}
			self.start_clipboard_request(.standard, apprt.ClipboardRequestOsc52Read{
				clipboard: msg.clipboard
			})!
		}
		apprt.SurfaceMessageClipboardWrite {
			mut req := msg.req
			defer {
				req.deinit()
			}
			self.clipboard_write(req.slice().bytestr(), msg.clipboard_type)!
		}
		apprt.SurfaceMessagePwdChange {
			mut w := msg.req
			defer {
				w.deinit()
			}

			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.pwd,
				apprt.ActionValue(apprt.PwdValue{ pwd: w.slice().bytestr() }),
			)!
		}
		apprt.SurfaceMessageClose {
			self.close()
		}
		apprt.ChildExited {
			self.child_exited_handler(msg)
		}
		apprt.SurfaceMessageDesktopNotification {
			if !self.config.desktop_notifications {
				return
			}
			self.show_desktop_notification(null_terminated_bytes(msg.title[..]), null_terminated_bytes(msg.body[..]))!
		}
		apprt.SurfaceMessageRendererHealth {
			self.update_renderer_health(msg.health)
		}
		terminal.Scrollbar {
			self.update_scrollbar(msg)
		}
		apprt.SurfaceMessagePresentSurface {
			self.present_surface()!
		}
		apprt.SurfaceMessagePasswordInput {
			self.password_input(msg.value)!
		}
		apprt.SurfaceMessageRingBell {
			now := time.sys_mono_now()
			if last := self.last_bell_time {
				// Rate-limit bell to at most once per 100ms
				if now - last < u64(100 * time.millisecond) {
					return
				}
			}
			self.last_bell_time = now
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.ring_bell,
				apprt.ActionVoid{},
			) or {
				log.warn('apprt failed to ring bell=${err}')
			}
		}
		osc.ProgressReport {
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.progress_report,
				apprt.ActionValue(msg),
			) or {
				log.warn('apprt failed to report progress err=${err}')
			}
		}
		apprt.SurfaceMessageSelectionScrollTick {
			self.selection_scroll_active = msg.value
			self.selection_scroll_tick()!
		}
		apprt.SurfaceMessageStartCommand {
			self.command_timer = time.sys_mono_now()
		}
		apprt.SurfaceMessageStopCommand {
			if started := self.command_timer {
				duration := time.sys_mono_now() - started
				self.command_timer = none
				self.rt_app.perform_action(
					apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
					.command_finished,
					apprt.ActionValue(apprt.CommandFinished{
						exit_code: msg.exit_code
						duration:  configpkg.Duration{ duration: duration }
					}),
				) or {
					log.warn('apprt failed to notify command finish=${err}')
				}
			}
		}
		apprt.SurfaceMessageSearchTotal {
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.search_total,
				apprt.ActionValue(apprt.SearchTotal{ total: msg.total }),
			)!
		}
		apprt.SurfaceMessageSearchSelected {
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.search_selected,
				apprt.ActionValue(apprt.SearchSelected{ selected: msg.selected }),
			)!
		}
	}
}

fn apprt_color_change(value osc.ColoredTarget) ?apprt.ColorChange {
	kind := match value.target {
		osc.ColorTargetPalette { unsafe { apprt.ColorKind(value.target.index) } }
		osc.ColorTargetDynamic {
			match value.target.color {
				.foreground { apprt.ColorKind.foreground }
				.background { apprt.ColorKind.background }
				.cursor { apprt.ColorKind.cursor }
				else {
					return none
				}
			}
		}
		osc.ColorTargetSpecial {
			return none
		}
	}
	return apprt.ColorChange{
		kind: kind
		r:    value.color.r
		g:    value.color.g
		b:    value.color.b
	}
}

fn null_terminated_bytes(data []u8) string {
	mut end := 0
	for end < data.len && data[end] != 0 {
		end++
	}
	return data[..end].bytestr()
}

// draw forces the surface to render a frame.
pub fn (mut self Surface) draw() ! {
	self.renderer.draw_frame(true)!
}

// activate_inspector begins collecting inspection data.
pub fn (mut self Surface) activate_inspector() ! {
	if self.inspector != none {
		return
	}
	mut inspector_value := Inspector.init()!
	mut insp := &inspector_value
	self.inspector = insp

	// Put the inspector onto the render state
	self.renderer_state.inspector = voidptr(insp)

	// Notify components that inspector is active
	_ = self.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.InspectorMessage{
		active: true
	}), datastruct.blocking_queue_forever)
	self.queue_io(termiopkg.MessageInspector{ value: true }, .unlocked)
}

// deactivate_inspector stops collecting inspection data.
pub fn (mut self Surface) deactivate_inspector() {
	mut insp := self.inspector or { return }

	// Remove from render state
	self.renderer_state.inspector = unsafe { nil }

	// Notify components
	_ = self.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.InspectorMessage{
		active: false
	}), datastruct.blocking_queue_forever)
	self.queue_io(termiopkg.MessageInspector{ value: false }, .unlocked)

	// Cleanup
	insp.deinit()
	self.inspector = none
}

// render_inspector draws the inspector into the active Dear ImGui context.
// Windowed runtimes can call this directly. Embedded runtimes reach the same
// implementation through the C bridge. Mirrors the state projection and
// locking performed by Ghostty's inspector widget.
pub fn (mut self Surface) render_inspector(context_handle voidptr) {
	if isnil(context_handle) {
		return
	}
	mut insp := self.inspector or { return }
	self.renderer_state.mutex.lock()

	mut hover_grid_x := u32(0)
	mut hover_grid_y := u32(0)
	pages := &self.renderer_state.terminal_.screens.active.pages
	if point := insp.mouse.last_point {
		if pt := pages.point_from_pin(.active, point) {
			hover_grid_x = u32(pt.coord().x)
			hover_grid_y = pt.coord().y
		}
	}

	mut click_grid_x := u32(0)
	mut click_grid_y := u32(0)
	if point := self.mouse.left_click_pin {
		if pt := pages.point_from_pin(.active, *point) {
			click_grid_x = u32(pt.coord().x)
			click_grid_y = pt.coord().y
		}
	}

	mut click_pressed := [input.mouse_button_max]bool{}
	for index, state in self.mouse.click_state {
		click_pressed[index] = state == .press
	}
	grid := self.size.grid()
	mut term := self.renderer_state.terminal_
	insp.render(context_handle, inspectorpkg.SurfaceInfo{
		screen_width:     self.size.screen.width
		screen_height:    self.size.screen.height
		grid_columns:     grid.columns
		grid_rows:        grid.rows
		cell_width:       self.size.cell.width
		cell_height:      self.size.cell.height
		padding_top:      self.size.padding.top
		padding_bottom:   self.size.padding.bottom
		padding_left:     self.size.padding.left
		padding_right:    self.size.padding.right
		font_points:      self.font_size.points
		font_pixels:      self.font_size.pixels()
		hover_grid_x:     hover_grid_x
		hover_grid_y:     hover_grid_y
		hover_terminal_x: i64(insp.mouse.last_xpos - f64(self.size.padding.left))
		hover_terminal_y: i64(insp.mouse.last_ypos - f64(self.size.padding.top))
		click_pressed:    click_pressed
		click_grid_x:     click_grid_x
		click_grid_y:     click_grid_y
		left_click_xpos:  self.mouse.left_click_xpos
		left_click_ypos:  self.mouse.left_click_ypos
	}, mut term)
	self.renderer_state.mutex.unlock()
	self.queue_render() or {}
}

// update_config updates the surface configuration at runtime.
pub fn (mut self Surface) update_config(config &Config) ! {
	// Each surface evaluates the original configuration using its own
	// conditional state. Keep the resolved value alive through the synchronous
	// runtime notification below; consumers must not retain its pointer.
	mut resolved := config.clone()
	conditional_result := config.change_conditional_state(self.config_conditional_state) or {
		log.warn('failed to apply conditional state to config err=${err}')
		configpkg.ConfigChangeResult{}
	}
	if conditional := conditional_result.value {
		resolved = conditional
	}
	defer {
		resolved.deinit()
	}

	derived := DerivedConfig.from_config(&resolved)!
	termio_config := termiopkg.DerivedConfig.init(&resolved)!
	self.config.deinit()
	self.config = derived

	// If mouse hiding was disabled but mouse is hidden, show it
	if !self.config.mouse_hide_while_typing && self.mouse.hidden {
		self.show_mouse()
	}

	// Clear any active key sequence
	self.end_key_sequence(.drop, .free)

	// Deactivate all key tables (pointers may be stale after config change)
	self.deactivate_all_key_tables() or {
		log.warn('failed to deactivate key tables err=${err}')
	}

	// Update font size (preserving manual adjustments)
	font_size := if self.font_size_adjusted {
		self.font_size
	} else {
		mut s := self.font_size
		s.points = self.config.original_font_size
		s
	}
	self.set_font_size(font_size)!

	// Notify renderer and IO of config change
	renderer_message := rendererpkg.RendererMessage.init_change_config(&resolved)!
	_ = self.renderer_thread.mailbox.push(renderer_message, datastruct.blocking_queue_forever)
	self.queue_io(termiopkg.MessageChangeConfig{ config: termio_config }, .unlocked)

	// With mailbox messages sent, we have to wake them up so they process it.
	self.queue_render() or {
		log.warn('failed to notify renderer of config change err=${err}')
	}

	// Notify runtime of config change
	if _ := self.config.title {
		self.rt_app.perform_action(
			apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
			.set_title,
			apprt.ActionValue(apprt.SetTitle{ title: self.config.title or { '' } }),
		)!
	}
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.config_change,
		apprt.ActionValue(apprt.ConfigChange{ config: &resolved }),
	)!
}

// has_selection returns true if the terminal has a selection.
pub fn (self &Surface) has_selection() bool {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	return self.renderer_state.terminal_.screens.active.selection != none
}

// SelectionStringResult preserves Ghostty's fallible optional selection text.
// V cannot directly return a Result whose success value is an Option.
pub struct SelectionStringResult {
pub:
	value ?string
}

// selection_string returns the selected text.
pub fn (self &Surface) selection_string() !SelectionStringResult {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	sel := self.renderer_state.terminal_.screens.active.selection or {
		return SelectionStringResult{}
	}
	text := self.renderer_state.terminal_.screens.active.selection_string(terminal.SelectionString{
		sel: sel
	})!
	return SelectionStringResult{ value: text }
}

// pwd returns the current working directory of the terminal.
pub fn (self &Surface) pwd() ?string {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	pwd := self.renderer_state.terminal_.get_pwd() or { return none }
	// Termio can replace the terminal-owned value immediately after the lock is
	// released, so callers must receive an independent copy.
	return pwd.clone()
}

// ime_point returns the x/y coordinate of where the IME keyboard should be rendered.
pub fn (self &Surface) ime_point() apprt.IMEPos {
	self.renderer_state.mutex.lock()
	cursor := self.renderer_state.terminal_.screens.active.cursor
	preedit_width := if p := self.renderer_state.preedit {
		u32(p.width())
	} else {
		u32(0)
	}
	self.renderer_state.mutex.unlock()

	content_scale := self.rt_surface.get_content_scale() or {
		apprt.ContentScale{ x: 1.0, y: 1.0 }
	}

	// X: cursor column * cell width + padding, centered in cell, scaled
	mut x := f64(cursor.x * self.size.cell.width + self.size.padding.left)
	x += f64(self.size.cell.width) / 2.0
	x /= content_scale.x

	// Y: cursor row * cell height + padding + full cell height - baseline, scaled
	mut y := f64(cursor.y * self.size.cell.height + self.size.padding.top)
	y += f64(self.size.cell.height)
	y /= content_scale.y

	// Height is one cell
	height := f64(self.size.cell.height) / content_scale.y

	// Width is preedit width clamped to remaining screen space
	mut w := f64(preedit_width * self.size.cell.width)
	term_w := f64(self.size.terminal().width)
	x_offset := f64((cursor.x + 1) * self.size.cell.width)
	max_w := term_w - x_offset
	if w > max_w {
		w = max_w
	}

	return apprt.IMEPos{
		x:      x
		y:      y
		width:  w
		height: height
	}
}

// set_font_size changes the font size. Must be called from the main thread.
pub fn (mut self Surface) set_font_size(size DesiredSize) ! {
	self.font_size = size

	// Get a new font grid for this size
	font_grid_key, font_grid := self.app.font_grid_set.ref(&self.config.font, self.font_size)!

	// Update cell size
	font_cell_size := font_grid.cell_size()
	self.set_cell_size(rendererpkg.CellSize{
		width:  font_cell_size.width
		height: font_cell_size.height
	})!

	// Notify our render thread of the new font stack. The renderer
	// MUST accept the new font grid and deref the old.
	_ = self.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.FontGridMessage{
		grid:    font_grid
		set:     &self.app.font_grid_set
		old_key: self.font_grid_key
		new_key: font_grid_key
	}), datastruct.blocking_queue_forever)

	// Once we've sent the key we can replace our key
	self.font_grid_key = font_grid_key
	self.font_grid = font_grid
	self.font_metrics = font_grid.metrics

	// Schedule render which also drains our mailbox
	self.queue_render()!
}

// This queues a render operation with the renderer thread. The render
// isn't guaranteed to happen immediately but it will happen as soon as
// practical.
fn (mut self Surface) queue_render() ! {
	self.renderer_thread.wakeup.notify()!
}

// size_callback is called when the surface size changes.
pub fn (mut self Surface) size_callback(size apprt.SurfaceSize) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	new_screen := rendererpkg.ScreenSize{
		width:  size.width
		height: size.height
	}
	if self.size.screen.equals(new_screen) {
		return
	}
	self.resize(new_screen)!
}

fn (mut self Surface) resize(size rendererpkg.ScreenSize) ! {
	self.size.screen = size
	self.balance_padding_if_needed()

	grid_size := self.size.grid()
	if grid_size.columns < 5
		&& (self.size.padding.left > 0 || self.size.padding.right > 0) {
		// WARNING: very small terminal grid detected with padding set.
	}
	if grid_size.rows < 2
		&& (self.size.padding.top > 0 || self.size.padding.bottom > 0) {
		// WARNING: very small terminal grid detected with padding set.
	}

	// Notify IO thread of resize
	self.queue_io(termiopkg.Message(self.size), .unlocked)
}

fn (mut self Surface) balance_padding_if_needed() {
	if self.config.window_padding_balance == .false_ {
		return
	}
	content_scale := self.rt_surface.get_content_scale() or {
		return
	}
	x_dpi := content_scale.x * default_dpi
	y_dpi := content_scale.y * default_dpi
	self.size.set_padding(self.config.scaled_padding(x_dpi, y_dpi), self.config.window_padding_balance)
}

// preedit_callback sets the preedit state for character input (dead keys, IME).
pub fn (mut self Surface) preedit_callback(preedit ?string) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}

	// Clear selection when preedit changes (if configured)
	if self.renderer_state.preedit != none || preedit != none {
		if self.config.selection_clear_on_typing {
			self.set_selection(none) or {}
		}
	}

	// Always clear prior preedit
	self.renderer_state.preedit = none

	// Mark preedit dirty
	self.renderer_state.terminal_.flags.set_dirty_preedit(true)

	// If no text, just queue render to clear previous preedit display
	text := preedit or {
		self.queue_render()!
		return
	}

	// Convert UTF-8 text to codepoints
	mut codepoints := []PreeditCodepoint{}
	for ch in text.runes() {
		cp := u32(ch)
		width := unicode.get(cp).width()
		// Ghostty cannot display zero-width preedit codepoints independently,
		// so they are omitted from the renderer preedit buffer.
		if width == 0 {
			continue
		}
		codepoints << PreeditCodepoint{ codepoint: cp, wide: width >= 2 }
	}

	if codepoints.len == 0 {
		self.queue_render()!
		return
	}

	self.renderer_state.preedit = Preedit{ codepoints: codepoints }
	self.queue_render()!
}

// key_event_is_binding returns binding flags if the key event would trigger a keybinding.
pub fn (mut self Surface) key_event_is_binding(event_orig KeyEvent) ?input.Flags {
	// Apply physical modifier remappings before any binding lookup.
	mut event := event_orig
	if self.config.key_remaps.is_remapped(event_orig.mods) {
		event.mods = self.config.key_remaps.apply(event_orig.mods)
	}

	if event.action == .release {
		return none
	}

	// Check active key sequence set
	if seq_set := self.keyboard.sequence_set {
		entry := seq_set.get_event(event) or { return none }
		return binding_flags(entry)
	}

	// Check active key tables (inner to outer)
	for i := self.keyboard.table_stack.len - 1; i >= 0; i-- {
		if entry := self.keyboard.table_stack[i].set.get_event(event) {
			return binding_flags(entry)
		}
	}

	entry := self.config.keybind.set.get_event(event) or { return none }
	return binding_flags(entry)
}

fn binding_flags(entry &input.SetEntry) input.Flags {
	value := entry.value
	return match value {
		input.Leader { input.Flags{} }
		input.Leaf { value.flags }
		input.LeafChained { value.flags }
	}
}

// key_callback handles key events including keybindings, encoding, and sending to terminal.
pub fn (mut self Surface) key_callback(event_orig KeyEvent) !apprt.InputEffect {
	// Modifier remaps affect both keybinding matching and terminal encoding.
	mut event := event_orig
	if self.config.key_remaps.is_remapped(event_orig.mods) {
		event.mods = self.config.key_remaps.apply(event_orig.mods)
	}

	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	// Clone the event before any key processing so the inspector records the
	// remapped event and owns its UTF-8 data independently of the caller.
	inspecting := self.inspector != none
	mut inspector_event := inspectorpkg.KeyEvent{}
	if inspecting {
		inspector_event = inspectorpkg.KeyEvent.init(event)
	}
	defer {
		if inspecting {
			if mut active_inspector := self.inspector {
				if active_inspector.record_key_event(inspector_event) {
					self.queue_render() or {}
				}
			} else {
				inspector_event.deinit()
			}
		}
	}

	// Handle keybindings first (press, repeat, release all checked)
	if v := self.maybe_handle_binding(event, inspecting, mut inspector_event)!.value {
		return v
	}

	// Check if KAM (keyboard action mode) is enabled
	if self.config.vt_kam_allowed {
		self.renderer_state.mutex.lock()
		disabled := self.renderer_state.terminal_.modes.get(.disable_keyboard)
		self.renderer_state.mutex.unlock()
		if disabled {
			return .consumed
		}
	}

	// Hide mouse on typing if configured
	if self.config.mouse_hide_while_typing && event.action == .press
		&& !self.mouse.hidden && event.utf8.len > 0 {
		self.hide_mouse()
	}

	// Update modifiers if changed
	if !self.mouse.mods.equal(event.mods) {
		self.mods_changed(event.mods)

		if self.renderer_state.terminal_.flags.mouse_event() == .none
			|| (self.mouse.mods.shift() && !self.mouse_shift_capture(false)) {
			if pos := self.rt_surface.get_cursor_pos() {
				self.renderer_state.mutex.lock()
				self.mouse_refresh_links(pos, self.pos_to_viewport(f64(pos.x), f64(pos.y)), self.mouse.over_link) or {
					log.warn('failed to refresh links err=${err}')
				}
				self.renderer_state.mutex.unlock()
			}
		} else if !self.mouse.mods.shift() {
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.mouse_shape,
				apprt.ActionValue(self.renderer_state.terminal_.mouse_shape),
			)!
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.mouse_over_link,
				apprt.ActionValue(apprt.MouseOverLink{}),
			)!
			self.queue_render()!
		}
	}

	if shape := (SurfaceMouse{
		physical_key: event.key
		mouse_event:  self.renderer_state.terminal_.flags.mouse_event()
		mouse_shape:  self.renderer_state.terminal_.mouse_shape
		mods:         self.mouse.mods
		over_link:    self.mouse.over_link
		hidden:       self.mouse.hidden
	}).key_to_mouse_shape() {
		self.rt_app.perform_action(
			apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
			.mouse_shape,
			apprt.ActionValue(shape),
		)!
	}

	// Track pressed key for release handling on focus loss
	mut copy := event
	copy.utf8 = ''
	mut next_pressed := ?KeyEvent(copy)
	if event.action == .release {
		if prev_ev := self.pressed_key {
			if prev_ev.key == event.key {
				copy.key = .unidentified
				next_pressed = copy
			}
		} else {
			next_pressed = none
		}
	}
	if pending := next_pressed {
		if pending.key == .unidentified && pending.mods.empty() {
			next_pressed = none
		}
	}
	self.pressed_key = next_pressed

	// Encode and send the key to the terminal
	if write_req := self.encode_key(event, inspecting, mut inspector_event) {
		// If process exited and we got an encoded key, close surface
		if self.child_exited {
			self.close()
			return .closed
		}

		// Queue the encoded key for IO
		self.queue_io(write_req.message(), .unlocked)
	} else {
		return .ignored
	}

	// For non-modifier keys: clear selection and scroll to bottom
	if !event.key.modifier() {
		self.renderer_state.mutex.lock()
		if self.config.selection_clear_on_typing || event.key == .escape {
			self.set_selection(none) or {
				self.renderer_state.mutex.unlock()
				return err
			}
		}
		if self.config.scroll_to_bottom_keystroke {
			self.renderer_state.terminal_.scroll_viewport(terminal.scroll_viewport_bottom) or {
				self.renderer_state.mutex.unlock()
				return err
			}
		}
		self.queue_render() or {
			self.renderer_state.mutex.unlock()
			return err
		}
		self.renderer_state.mutex.unlock()
	}

	return .consumed
}

// text_callback sends text as-is to the terminal (like a paste).
pub fn (mut self Surface) text_callback(text string) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	self.complete_clipboard_paste(text, true)!
}

// occlusion_callback is called when the surface visibility changes.
pub fn (mut self Surface) occlusion_callback(visible bool) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	_ = self.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.VisibleMessage{
		visible: visible
	}), datastruct.blocking_queue_forever)
	self.queue_render()!
}

// focus_callback is called when the surface gains or loses focus.
pub fn (mut self Surface) focus_callback(focused bool) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	if self.focused == focused {
		return
	}
	self.focused = focused

	// Notify our render thread of the new state
	_ = self.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.FocusMessage{
		focused: focused
	}), datastruct.blocking_queue_forever)

	if focused {
		// On focus gain, notify app.
		self.app.focus_surface(self)
	} else {
		// A focus loss may be the last event we receive for a pressed key.
		// Synthesize its release, followed by releases for both sides of every
		// held modifier, so the terminal keyboard protocol cannot retain a
		// logically pressed key.
		if mut pressed_key := self.pressed_key {
			self.pressed_key = none
			pressed_key.action = .release

			original_key := pressed_key.key
			if original_key != .unidentified {
				self.release_key_on_focus_loss(pressed_key)
			}

			if pressed_key.mods.shift() {
				pressed_key.mods.set_shift(false)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .shift_right)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .shift_left)
			}
			if pressed_key.mods.ctrl() {
				pressed_key.mods.set_ctrl(false)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .control_right)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .control_left)
			}
			if pressed_key.mods.alt() {
				pressed_key.mods.set_alt(false)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .alt_right)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .alt_left)
			}
			if pressed_key.mods.super_() {
				pressed_key.mods.set_super(false)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .meta_right)
				self.release_modifier_on_focus_loss(pressed_key, original_key, .meta_left)
			}
		}
	}

	// Schedule render which also drains our mailbox.
	self.queue_render()!

	// Focus changes always reveal the mouse. This also repairs cases where a
	// platform loses the matching mouse-motion event while switching apps.
	self.show_mouse()

	// Update terminal focus flag
	self.renderer_state.mutex.lock()
	self.renderer_state.terminal_.flags.set_focused(focused)
	self.renderer_state.mutex.unlock()

	// Notify IO thread
	self.queue_io(termiopkg.MessageFocused{ value: focused }, .unlocked)
}

fn (mut self Surface) release_key_on_focus_loss(event KeyEvent) {
	effect := self.key_callback(event) or { return }
	assert effect != .closed
}

fn (mut self Surface) release_modifier_on_focus_loss(event KeyEvent, original_key input.Key, key input.Key) {
	if key == original_key {
		return
	}
	mut release := event
	release.key = key
	self.release_key_on_focus_loss(release)
}

// refresh_callback schedules a render.
pub fn (mut self Surface) refresh_callback() ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	self.queue_render()!
}

// scroll_callback handles mouse scroll events.
pub fn (mut self Surface) scroll_callback(xoff f64, yoff f64, scroll_mods input.ScrollMods) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	if self.mouse.hidden {
		self.show_mouse()
	}

	mut y := ScrollAmount{}
	if yoff != 0 {
		cell_size := f64(self.size.cell.height)
		yoff_adjusted := if scroll_mods.precision() {
			yoff * self.config.mouse_scroll_multiplier.precision
		} else {
			yoff_max := if yoff > 0 { math.max(yoff, 1) } else { math.min(yoff, -1) }
			yoff_max * cell_size * self.config.mouse_scroll_multiplier.discrete
		}
		poff := self.mouse.pending_scroll_y + yoff_adjusted
		if math.abs(poff) < cell_size {
			self.mouse.pending_scroll_y = poff
		} else {
			amount := poff / cell_size
			self.mouse.pending_scroll_y = poff - (amount * cell_size)
			y.delta = int(amount)
		}
	}

	mut x := ScrollAmount{}
	if xoff != 0 {
		if !scroll_mods.precision() {
			x.delta = int(math.round(xoff))
		} else {
			poff := self.mouse.pending_scroll_x + xoff
			cell_size := f64(self.size.cell.width)
			if math.abs(poff) < cell_size {
				self.mouse.pending_scroll_x = poff
			} else {
				amount := poff / cell_size
				self.mouse.pending_scroll_x = poff - (amount * cell_size)
				x.delta = int(amount)
			}
		}
	}

	{
		self.renderer_state.mutex.lock()
		defer {
			self.renderer_state.mutex.unlock()
		}

		if self.is_mouse_reporting() {
			self.set_selection(none)!
		}

		mut t := self.renderer_state.terminal_
		if t.screens.active_key == .alternate && t.flags.mouse_event() == .none
			&& t.modes.get(.mouse_alternate_scroll) {
			if y.delta != 0 {
				self.set_selection(none)!
				seq := if t.modes.get(.cursor_keys) {
					if y.direction() == .up_right { '\x1bOA' } else { '\x1bOB' }
				} else {
					if y.direction() == .up_right { '\x1b[A' } else { '\x1b[B' }
				}
				for _ in uint(0) .. y.magnitude() {
					self.queue_io(termiopkg.MessageWriteStable{ data: seq }, .locked)
				}
			}
			return
		}

		if self.is_mouse_reporting() {
			for _ in uint(0) .. y.magnitude() {
				pos := self.rt_surface.get_cursor_pos()!
				button := if y.direction() == .up_right {
					input.MouseButton.four
				} else {
					input.MouseButton.five
				}
				self.mouse_report(button, .press, self.mouse.mods, pos)!
			}
			for _ in uint(0) .. x.magnitude() {
				pos := self.rt_surface.get_cursor_pos()!
				button := if x.direction() == .up_right {
					input.MouseButton.six
				} else {
					input.MouseButton.seven
				}
				self.mouse_report(button, .press, self.mouse.mods, pos)!
			}
			return
		}

		if y.delta != 0 {
			t.scroll_viewport(terminal.ScrollViewport.from_delta(-y.delta))!
		}
	}
	self.queue_render()!
}

// content_scale_callback is called when the DPI content scale changes.
pub fn (mut self Surface) content_scale_callback(content_scale apprt.ContentScale) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	x_dpi := content_scale.x * default_dpi
	y_dpi := content_scale.y * default_dpi

	// Update font size with new DPI
	mut new_size := self.font_size
	new_size.xdpi = u16(x_dpi)
	new_size.ydpi = u16(y_dpi)
	if new_size.xdpi == self.font_size.xdpi && new_size.ydpi == self.font_size.ydpi {
		return
	}
	self.set_font_size(new_size)!

	// Balanced padding is derived from the remaining cell-space and is not
	// DPI-sensitive. Explicit, unbalanced padding is scaled directly.
	if self.config.window_padding_balance == .false_ {
		self.size.padding = self.config.scaled_padding(x_dpi, y_dpi)
	}

	// Trigger resize to recalculate everything
	self.resize(self.size.screen)!
}

// mouse_button_callback handles mouse button press/release events.
pub fn (mut self Surface) mouse_button_callback(button_action input.MouseButtonState, button input.MouseButton, mods input.Mods) !bool {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	// If we have an inspector, we always queue a render.
	if self.inspector != none {
		defer {
			self.queue_render() or {}
		}
	}

	// Always record our latest mouse state.
	self.mouse.click_state[int(button)] = button_action

	// Show mouse on click.
	if self.mouse.hidden {
		self.show_mouse()
	}

	// Update our modifiers if they changed.
	self.mods_changed(mods)

	// This is set to true if the terminal is allowed to capture shift.
	shift_capture := self.mouse_shift_capture(true)

	is_press := button_action == .press

	// Shift-click continues the previous mouse state if we have a selection.
	// cursorPosCallback will also do a mouse report so we don't need to do
	// any of the logic below.
	if button == .left && is_press {
		if mods.shift() && self.mouse.left_click_count > 0 && !shift_capture {
			if self.has_selection() {
				// If we are within the interval that a click would register
				// an increment then we do not extend the selection.
				now := time.sys_mono_now()
				since := now - self.mouse.left_click_time
				if since > self.config.mouse_interval {
					pos := self.rt_surface.get_cursor_pos()!
					self.cursor_pos_callback(pos, none)!
					return true
				}
			}
		}
	}

	if !is_press {
		// Release path.
		if button == .left {
			// Stop selection scrolling when releasing the left button but
			// only when selection scrolling is active.
			if self.selection_scroll_active {
				self.selection_scroll_active = false
				self.queue_io(termiopkg.MessageSelectionScroll{ value: false }, .unlocked)
			}

			// The selection clipboard is only updated for left-click drag
			// when the left button is released. This avoids the clipboard
			// being updated on every mouse move which would be noisy.
			if self.config.copy_on_select != .false_ {
				self.renderer_state.mutex.lock()
				if sel := self.renderer_state.terminal_.screens.active.selection {
					copy := terminal.Selection.init(sel.start(), sel.end(), sel.rectangle)
					self.set_selection(copy) or {
						self.renderer_state.mutex.unlock()
						return err
					}
				}
				self.renderer_state.mutex.unlock()
			}

			// Handle link clicking. We do this before mouse reporting or any
			// other mouse handling because a successfully clicked link will
			// swallow the event.
			if self.mouse.over_link {
				pos := self.rt_surface.get_cursor_pos()!
				self.renderer_state.mutex.lock()
				processed := self.process_links(pos) or {
					self.renderer_state.mutex.unlock()
					false
				}
				self.renderer_state.mutex.unlock()
				if processed {
					return true
				}
			}

			// Handle prompt clicking. If we released on a prompt and support
			// click events, then we move to it.
			if handled := self.maybe_prompt_click() {
				if handled {
					return true
				}
			} else {
				// Log and continue on error.
			}
		}
	}

	// Report mouse events if enabled. Mouse-report state and selection share
	// the renderer mutex with the IO and renderer threads.
	{
		self.renderer_state.mutex.lock()
		defer {
			self.renderer_state.mutex.unlock()
		}
		if self.is_mouse_reporting() {
			// If shift is pressed and we aren't allowed to capture it, then we
			// do not do a mouse report.
			if !(mods.shift() && !shift_capture) {
				// In any other mouse button scenario without shift pressed we
				// clear the selection since the underlying application can handle
				// that in any way (i.e. "scrolling").
				self.set_selection(none)!

				// We also set the left click count to 0 so that if mouse
				// reporting is disabled in the middle of a press (before release)
				// we don't suddenly start selecting text.
				self.mouse.left_click_count = 0

				pos := self.rt_surface.get_cursor_pos()!
				report_action := if is_press {
					MouseReportAction.press
				} else {
					MouseReportAction.release
				}
				self.mouse_report(?input.MouseButton(button), report_action, self.mouse.mods, pos)!

				// If we're doing mouse reporting we don't support other selection
				// or highlighting.
				return true
			}
		}
	}

	// For left button clicks we always record info for selection/highlight.
	if button == .left && is_press {
		self.renderer_state.mutex.lock()
		defer {
			self.renderer_state.mutex.unlock()
		}
		mut screen := self.renderer_state.terminal_.screens.active
		pos := self.rt_surface.get_cursor_pos()!
		vp := self.pos_to_viewport(f64(pos.x), f64(pos.y))
		if pin := screen.pages.pin(terminal.Point.new(.viewport, terminal.Coordinate{
			x: u16(vp.x)
			y: u32(vp.y)
		})) {
			// If we move our cursor too much between clicks then we reset the
			// multi-click state.
			if self.mouse.left_click_count > 0 {
				max_distance := f64(self.size.cell.width)
				dx := pos.x - self.mouse.left_click_xpos
				dy := pos.y - self.mouse.left_click_ypos
				distance := math.sqrt(dx * dx + dy * dy)
				if distance > max_distance {
					self.mouse.left_click_count = 0
				}
			}

			if prev := self.mouse.left_click_pin {
				if mut pin_screen := self.renderer_state.terminal_.screens.get(self.mouse.left_click_screen) {
					pin_screen.pages.untrack_pin(prev)
				}
				self.mouse.left_click_pin = none
			}

			// Store it
			self.mouse.left_click_pin = screen.pages.track_pin(pin)!
			self.mouse.left_click_screen = self.renderer_state.terminal_.screens.active_key
			self.mouse.left_click_xpos = pos.x
			self.mouse.left_click_ypos = pos.y

			// Reset a stale click sequence, then advance it. Counts are always
			// bounded to the single/double/triple-click states.
			now := time.sys_mono_now()
			if self.mouse.left_click_count > 0
				&& now - self.mouse.left_click_time > self.config.mouse_interval {
				self.mouse.left_click_count = 0
			}
			self.mouse.left_click_time = now
			self.mouse.left_click_count++
			if self.mouse.left_click_count > 3 {
				self.mouse.left_click_count = 1
			}

			// Directly update selection here. Clipboard publication for mouse
			// selection happens on release, matching Ghostty.
			match self.mouse.left_click_count {
				1 {
					if screen.selection != none {
						screen.select(none)!
						self.queue_render()!
					}
				}
				2 {
					if link := self.link_at_pin(pin, none) {
						screen.select(link.selection)!
						self.queue_render()!
					} else if selection := screen.select_word(pin, self.config.selection_word_chars) {
						screen.select(selection)!
						self.queue_render()!
					}
				}
				3 {
					sel := if mods.ctrl_or_super() {
						screen.select_output(pin)
					} else {
						screen.select_line(terminal.SelectLine{ pin: pin })
					}
					if selection := sel {
						screen.select(selection)!
						self.queue_render()!
					}
				}
				else {}
			}
		}
	}

	// Middle-click pastes from our selection clipboard.
	if button == .middle && is_press {
		if self.config.copy_on_select != .false_ {
			clipboard := if self.rt_surface.supports_clipboard(.selection) {
				apprt.Clipboard.selection
			} else {
				apprt.Clipboard.standard
			}
			self.start_clipboard_request(clipboard, apprt.ClipboardRequestPaste{})!
		}
	}

	// Right-click behavior is configurable. Context-menu mode prepares a word
	// or link selection but deliberately leaves the event unconsumed so the
	// application runtime can present its native menu.
	if button == .right && is_press {
		self.renderer_state.mutex.lock()
		mut screen := self.renderer_state.terminal_.screens.active
		pos := self.rt_surface.get_cursor_pos() or {
			self.renderer_state.mutex.unlock()
			return err
		}
		vp := self.pos_to_viewport(f64(pos.x), f64(pos.y))
		pin := screen.pages.pin(terminal.Point.new(.viewport, terminal.Coordinate{
			x: u16(vp.x)
			y: u32(vp.y)
		})) or {
			self.renderer_state.mutex.unlock()
			return false
		}

		match self.config.right_click_action {
			.ignore {
				self.renderer_state.mutex.unlock()
				return true
			}
			.context_menu {
				if prev := screen.selection {
					if prev.contains(screen, pin) {
						self.renderer_state.mutex.unlock()
						return false
					}
				}
				if link := self.link_at_pos(pos) {
					selection := terminal.Selection.init(link.selection.start(), link.selection.end(), link.selection.rectangle)
					self.set_selection(selection) or {
						self.renderer_state.mutex.unlock()
						return err
					}
				} else if sel := screen.select_word(pin, self.config.selection_word_chars) {
					selection := terminal.Selection.init(sel.start(), sel.end(), sel.rectangle)
					self.set_selection(selection) or {
						self.renderer_state.mutex.unlock()
						return err
					}
				}
				self.queue_render() or {
					self.renderer_state.mutex.unlock()
					return err
				}
				self.renderer_state.mutex.unlock()
				return false
			}
			.copy, .copy_or_paste {
				if sel := screen.selection {
					self.copy_selection_to_clipboards(sel, [.standard], .mixed) or {
						self.renderer_state.mutex.unlock()
						return err
					}
					self.set_selection(none) or {
						self.renderer_state.mutex.unlock()
						return err
					}
					self.queue_render() or {
						self.renderer_state.mutex.unlock()
						return err
					}
					self.renderer_state.mutex.unlock()
					return true
				}
				if self.config.right_click_action == .copy {
					self.set_selection(none) or {
						self.renderer_state.mutex.unlock()
						return err
					}
					self.queue_render() or {
						self.renderer_state.mutex.unlock()
						return err
					}
					self.renderer_state.mutex.unlock()
					return true
				}
				self.renderer_state.mutex.unlock()
				self.start_clipboard_request(.standard, apprt.ClipboardRequestPaste{})!
				return true
			}
			.paste {
				self.set_selection(none) or {
					self.renderer_state.mutex.unlock()
					return err
				}
				self.queue_render() or {
					self.renderer_state.mutex.unlock()
					return err
				}
				self.renderer_state.mutex.unlock()
				self.start_clipboard_request(.standard, apprt.ClipboardRequestPaste{})!
				return true
			}
		}
	}

	self.queue_render()!
	return false
}

// cursor_pos_callback handles cursor position / mouse move events.
pub fn (mut self Surface) cursor_pos_callback(pos apprt.CursorPos, mods ?input.Mods) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	// Update mods if provided
	if m := mods {
		self.mods_changed(m)
	}

	// Convert to viewport coordinates
	pos_vp := self.pos_to_viewport(f64(pos.x), f64(pos.y))
	if pos.x < 0 || pos.y < 0 {
		self.mouse.link_point = none
		if self.mouse.over_link {
			self.mouse.over_link = false
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.mouse_shape,
				apprt.ActionValue(self.renderer_state.terminal_.mouse_shape),
			)!
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.mouse_over_link,
				apprt.ActionValue(apprt.MouseOverLink{}),
			)!
			self.queue_render()!
		}
	}
	if self.mouse.hidden {
		self.show_mouse()
	}

	over_link := self.mouse.over_link
	self.mouse.over_link = false
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}

	if pos.y >= 1 && self.selection_scroll_active {
		self.queue_io(termiopkg.MessageSelectionScroll{ value: false }, .locked)
	}
	self.renderer_state.mouse.point = none
	if pos.x < 0 || pos.y < 0 {
		self.renderer_state.terminal_.screens.active.dirty.set_hyperlink_hover(true)
	}

	// If we have an inspector, always record position information. The
	// inspector renderer reads this state while holding the same mutex.
	if mut insp := self.inspector {
		insp.mouse.last_xpos = f64(pos.x)
		insp.mouse.last_ypos = f64(pos.y)
		insp.mouse.last_point = self.renderer_state.terminal_.screens.active.pages.pin(terminal.Point.new(.viewport,
			terminal.Coordinate{
				x: u16(pos_vp.x)
				y: u32(pos_vp.y)
			}))
		self.queue_render()!
	}

	// Check for link hover
	if (over_link || self.mouse.link_point == none
		|| !(self.mouse.link_point or { Coordinate{} }).eql(pos_vp))
		&& (self.renderer_state.terminal_.flags.mouse_event() == .none
			|| (self.mouse.mods.shift() && !self.mouse_shift_capture(false))) {
		self.mouse_refresh_links(pos, pos_vp, over_link)!
	}

	// Handle mouse reporting for motion events
	if self.is_mouse_reporting() {
		mut report := true
		if self.mouse.mods.shift() && !self.mouse_shift_capture(false) {
			for state in self.mouse.click_state {
				if state != .release {
					report = false
					break
				}
			}
		}
		if report {
			mut button := ?input.MouseButton(none)
			for i, state in self.mouse.click_state {
				if state == .press {
					button = unsafe { input.MouseButton(i) }
					break
				}
			}
			self.mouse_report(button, .motion, self.mouse.mods, pos)!
			return
		}
	}

	// Handle selection drag (left click held)
	if self.mouse.click_state[int(input.MouseButton.left)] == .press
		&& self.mouse.left_click_count > 0 {
		if self.mouse.left_click_screen != self.renderer_state.terminal_.screens.active_key {
			return
		}
		self.queue_render()!
		max_y := f64(self.size.screen.height)
		if (pos.y <= 1 || pos.y > max_y - 1) && !self.selection_scroll_active {
			self.queue_io(termiopkg.MessageSelectionScroll{ value: true }, .locked)
		}
		if pin := self.renderer_state.terminal_.screens.active.pages.pin(terminal.Point.new(.viewport,
			terminal.Coordinate{
				x: u16(pos_vp.x)
				y: u32(pos_vp.y)
			})) {
			match self.mouse.left_click_count {
				1 { self.drag_left_click_single(pin, f64(pos.x))! }
				2 { self.drag_left_click_double(pin)! }
				else { self.drag_left_click_triple(pin)! }
			}
		}
	}
}

// mouse_pressure_callback handles force touch events.
pub fn (mut self Surface) mouse_pressure_callback(stage input.PressureStage, pressure f64) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	if self.mouse.pressure_stage == stage {
		return
	}
	self.mouse.pressure_stage = stage

	// On deep press with left mouse button, select word under cursor
	if stage == .deep && self.mouse.click_state[int(input.MouseButton.left)] == .press {
		self.renderer_state.mutex.lock()
		defer {
			self.renderer_state.mutex.unlock()
		}
		pin := self.mouse.left_click_pin or { return }
		if sel := self.renderer_state.terminal_.screens.active.select_word(pin, self.config.selection_word_chars) {
			self.renderer_state.terminal_.screens.active.select(sel)!
			self.queue_render()!
		}
	}
	_ = pressure
}

// color_scheme_callback is called when the color scheme changes (light/dark).
pub fn (mut self Surface) color_scheme_callback(scheme apprt.ColorScheme) ! {
	crash.set_thread_state(self.crash_thread_state())
	defer {
		crash.clear_thread_state()
	}

	new_scheme := match scheme {
		.light { Theme.light }
		.dark { Theme.dark }
	}
	if self.config_conditional_state.theme == new_scheme {
		return
	}
	self.config_conditional_state.theme = new_scheme
	self.notify_config_conditional_state()

	// Notify IO thread for mode 2031 DSR report
	self.queue_io(termiopkg.MessageColorSchemeReport{ force: false }, .unlocked)
}

// pos_to_viewport converts surface pixel coordinates to viewport cell coordinates.
pub fn (self &Surface) pos_to_viewport(xpos f64, ypos f64) Coordinate {
	coord := rendererpkg.Coordinate(rendererpkg.SurfaceCoord{ x: xpos, y: ypos })
	grid := coord.convert(.grid, self.size)
	match grid {
		rendererpkg.GridCoord {
			return Coordinate{ x: grid.x, y: grid.y }
		}
		else {
			panic('renderer coordinate conversion returned a non-grid value')
		}
	}
}

// perform_binding_action performs a binding action from a keybinding.
// This is a faithful translation of ghostty's Surface.performBindingAction.
pub fn (mut self Surface) perform_binding_action(action input.Action) !bool {
	// Forward app-scoped actions to the app. Some app-scoped actions are
	// special-cased here because they do some special things when performed
	// from the surface. In ghostty this is `action.scoped(.app)`.
	if app_action := action.scoped(.app) {
		match app_action {
			input.ActionUnbind {
				panic('unbind action reached surface dispatch')
			}
			input.ActionIgnore {}
			input.ActionNewWindow {
				// ghostty: self.app.newWindow(self.rt_app, .{ .parent = self }).
				self.rt_app.perform_action(
					apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
					.new_window,
					apprt.ActionVoid{},
				)!
			}

			// Undo and redo both support both surface and app targeting.
			// If we are triggering on a surface then we perform the action
			// with the surface target.
			input.ActionUndo {
				return self.rt_app.perform_action(
					apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
					.undo,
					apprt.ActionVoid{},
				)!
			}
			input.ActionRedo {
				return self.rt_app.perform_action(
					apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
					.redo,
					apprt.ActionVoid{},
				)!
			}
			input.ActionReloadConfig {
				self.rt_app.perform_action(
					apprt.Target(apprt.AppTarget{}),
					.reload_config,
					apprt.ActionValue(apprt.ReloadConfig{ soft: false }),
				)!
			}
			else {
				// All other app-scoped actions (open_config, close_all_windows,
				// quit, toggle_quick_terminal,
				// toggle_visibility, check_for_updates) are
				// forwarded to the app.
				self.rt_app.perform_action(
					apprt.Target(apprt.AppTarget{}),
					app_action_key(app_action.tag()),
					apprt.ActionVoid{},
				)!
			}
		}
		return true
	}

	match action {
		input.ActionCsi, input.ActionEsc {
			// We need to send the CSI/ESC sequence as a single write request.
			// If you split it across two then the shell can interpret it
			// as two literals.
			prefix := if action is input.ActionCsi { '\x1b[' } else { '\x1b' }
			full_data := (prefix + action.value).bytes()
			// Ghostty formats these into a fixed 128-byte buffer before it
			// constructs the write request. Do not silently truncate it in the
			// small-message representation.
			if full_data.len > 128 {
				return error('binding sequence exceeds 128 bytes')
			}
			self.queue_io(termiopkg.Message.write_req(full_data.bytestr()), .unlocked)

			// CSI/ESC triggers a scroll.
			self.renderer_state.mutex.lock()
			self.scroll_to_bottom() or {
				log.warn('error scrolling to bottom err=${err}')
			}
			self.renderer_state.mutex.unlock()
		}
		input.ActionText {
			// Text actions use Zig string literal escapes, matching the config
			// representation used by Ghostty.
			parsed := configpkg.parse_zig_string(action.value) or { return true }
			self.queue_io(termiopkg.Message.write_req(parsed.bytes().bytestr()), .unlocked)

			// Text triggers a scroll.
			self.renderer_state.mutex.lock()
			self.scroll_to_bottom() or {
				log.warn('error scrolling to bottom err=${err}')
			}
			self.renderer_state.mutex.unlock()
		}
		input.ActionCursorKey {
			// DECCKM selects between the normal and application sequences.
			self.renderer_state.mutex.lock()
			normal := !self.renderer_state.terminal_.modes.get(.cursor_keys)
			self.scroll_to_bottom() or {
				log.warn('error scrolling to bottom err=${err}')
			}
			self.renderer_state.mutex.unlock()
			data := if normal { action.value.normal } else { action.value.application }
			self.queue_io(termiopkg.MessageWriteStable{ data: data }, .unlocked)
		}
		input.ActionReset {
			self.renderer_state.mutex.lock()
			defer {
				self.renderer_state.mutex.unlock()
			}
			self.renderer_state.terminal_.full_reset()
		}
		input.ActionStartSearch {
			// To save resources, we don't actually start a search here, we
			// just notify the apprt. The real thread starts on the first
			// needle.
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.start_search,
				apprt.ActionValue(apprt.StartSearch{}),
			)!
		}
		input.ActionSearchSelection {
			selection_result := self.selection_string()!
			selection := selection_result.value or { return false }
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.start_search,
				apprt.ActionValue(apprt.StartSearch{ needle: selection }),
			)!
		}
		input.ActionEndSearch {
			// We only return that this was performed if we actually stopped a
			// search, but we also send the apprt end_search so GUIs can clean
			// up stale state.
			performed := self.search != none
			if mut s := self.search {
				s.deinit()
				self.search = none
			}
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.end_search,
				apprt.ActionVoid{},
			)!
			return performed
		}
		input.ActionSearch {
			text := action.value
			mut s := self.search or {
				// If we're stopping the search and we had no prior search,
				// then there is nothing to do.
				if text.len == 0 {
					return false
				}

				// We need to assign directly to self.search because we need
				// a stable pointer back to the thread state.
				mut state := searchpkg.SearchThread.init(searchpkg.ThreadOptions{
					mutex:          self.renderer_state.mutex
					terminal:       self.renderer_state.terminal_
					event_cb:       search_callback
					event_userdata: voidptr(&self)
				})!
				mut init_s := &SurfaceSearch{
					state: state
				}
				init_s.thread_ = spawn state.thread_main()
				self.search = init_s
				init_s
			}

			// Zero-length text means stop searching.
			if text.len == 0 {
				s.deinit()
				self.search = none
			} else {
				_ = s.state.mailbox.push(searchpkg.MessageChangeNeedle{
					needle: datastruct.MessageData.init[u8](255, text.bytes())
				}, datastruct.blocking_queue_forever)
				s.state.wakeup.notify() or {}
			}
		}
		input.ActionNavigateSearch {
			mut s := self.search or { return false }
			nav := action.value
			_ = s.state.mailbox.push(searchpkg.MessageSelect{
				select: if nav == .next { .next } else { .prev }
			}, datastruct.blocking_queue_forever)
			s.state.wakeup.notify() or {}
		}
		input.ActionCopyToClipboard {
			self.renderer_state.mutex.lock()
			defer {
				self.renderer_state.mutex.unlock()
			}
			if sel := self.renderer_state.terminal_.screens.active.selection {
				self.copy_selection_to_clipboards(sel, [.standard], action.value)!
				// Clear the selection if configured to do so.
				if self.config.selection_clear_on_copy {
					self.set_selection(none) or {
						log.warn('failed to clear selection after copy err=${err}')
						return true
					}
					self.queue_render() or {
						log.warn('failed to queue render after clear selection err=${err}')
					}
				}
				return true
			}
			return false
		}
		input.ActionCopyUrlToClipboard {
			// If the mouse isn't over a link, nothing we can do.
			if !self.mouse.over_link {
				return false
			}
			pos := self.rt_surface.get_cursor_pos()!
			self.renderer_state.mutex.lock()
			defer {
				self.renderer_state.mutex.unlock()
			}
			link_info := self.link_at_pos(pos) or { return false }
			url_text := match link_info.action {
				.open {
					// For regex links, get the text from the selection.
					self.renderer_state.terminal_.screens.active.selection_string(terminal.SelectionString{
						sel:  link_info.selection
						trim: self.config.clipboard_trim_trailing_spaces
					}) or {
						log.error('error reading url string err=${err}')
						return false
					}
				}
				.open_osc8 {
					// For OSC8 links, get the URI from hyperlink data.
					self.osc8_uri(link_info.selection.start()) or {
						log.warn('failed to get URI for OSC8 hyperlink')
						return false
					}
				}
			}
			self.rt_surface.set_clipboard(.standard, [apprt.ClipboardContent{
				mime: 'text/plain'
				data: url_text
			}], false) or {
				log.error('error copying url to clipboard err=${err}')
				return false
			}
			return true
		}
		input.ActionCopyTitleToClipboard {
			title := self.rt_surface.get_title() or { return false }
			if title.len == 0 {
				return false
			}
			self.rt_surface.set_clipboard(.standard, [apprt.ClipboardContent{
				mime: 'text/plain'
				data: title
			}], false) or {
				log.error('error copying title to clipboard err=${err}')
				return true
			}
			return true
		}
		input.ActionPasteFromClipboard {
			return self.start_clipboard_request(.standard, apprt.ClipboardRequestPaste{})!
		}
		input.ActionPasteFromSelection {
			return self.start_clipboard_request(.selection, apprt.ClipboardRequestPaste{})!
		}
		input.ActionIncreaseFontSize {
			// Max delta is somewhat arbitrary.
			clamped_delta := math.max(f32(0), math.min(f32(255), action.value))
			mut size := self.font_size
			// Max point size is somewhat arbitrary.
			size.points = math.min(size.points + clamped_delta, f32(255))
			self.set_font_size(size)!
			self.font_size_adjusted = true
		}
		input.ActionDecreaseFontSize {
			clamped_delta := math.max(f32(0), math.min(f32(255), action.value))
			mut size := self.font_size
			size.points = math.max(f32(1), size.points - clamped_delta)
			self.set_font_size(size)!
			self.font_size_adjusted = true
		}
		input.ActionResetFontSize {
			mut size := self.font_size
			size.points = self.config.original_font_size
			self.set_font_size(size)!
			self.font_size_adjusted = false
		}
		input.ActionSetFontSize {
			mut size := self.font_size
			points := action.value
			size.points = if points < 1.0 {
				f32(1.0)
			} else if points > 255.0 {
				f32(255.0)
			} else {
				points
			}
			self.set_font_size(size)!
			self.font_size_adjusted = true
		}
		input.ActionPromptSurfaceTitle {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.prompt_title,
				apprt.ActionValue(apprt.PromptTitle.surface),
			)!
		}
		input.ActionPromptTabTitle {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.prompt_title,
				apprt.ActionValue(apprt.PromptTitle.tab),
			)!
		}
		input.ActionClearScreen {
			// If the active screen is the alternate screen then clear screen
			// does nothing, so we return false so the keybind is unconsumed.
			self.renderer_state.mutex.lock()
			alternate := self.renderer_state.terminal_.screens.active_key == .alternate
			self.renderer_state.mutex.unlock()
			if alternate {
				return false
			}
			self.queue_io(termiopkg.MessageClearScreen{ history: true }, .unlocked)
		}
		input.ActionScrollToTop {
			self.queue_io(termiopkg.MessageScrollViewport{ scroll: terminal.scroll_viewport_top }, .unlocked)
		}
		input.ActionScrollToBottom {
			self.queue_io(termiopkg.MessageScrollViewport{ scroll: terminal.scroll_viewport_bottom }, .unlocked)
		}
		input.ActionScrollToRow {
			self.renderer_state.mutex.lock()
			self.renderer_state.terminal_.screens.active.scroll(terminal.ScrollRow{
				n: uint(action.value)
			})
			self.renderer_state.mutex.unlock()
			self.queue_render()!
		}
		input.ActionScrollToSelection {
			self.renderer_state.mutex.lock()
			defer {
				self.renderer_state.mutex.unlock()
			}
			sel := self.renderer_state.terminal_.screens.active.selection or { return false }
			tl := sel.top_left(self.renderer_state.terminal_.screens.active)
			self.renderer_state.terminal_.screens.active.scroll(terminal.ScrollPin{
				pin: tl
			})
			self.queue_render()!
		}
		input.ActionScrollPageUp {
			rows := int(self.size.grid().rows)
			self.queue_io(termiopkg.MessageScrollViewport{ scroll: terminal.ScrollViewport.from_delta(-rows) }, .unlocked)
		}
		input.ActionScrollPageDown {
			rows := int(self.size.grid().rows)
			self.queue_io(termiopkg.MessageScrollViewport{ scroll: terminal.ScrollViewport.from_delta(rows) }, .unlocked)
		}
		input.ActionScrollPageFractional {
			rows := f32(self.size.grid().rows)
			delta := int(action.value * rows)
			self.queue_io(termiopkg.MessageScrollViewport{ scroll: terminal.ScrollViewport.from_delta(delta) }, .unlocked)
		}
		input.ActionScrollPageLines {
			self.queue_io(termiopkg.MessageScrollViewport{ scroll: terminal.ScrollViewport.from_delta(int(action.value)) }, .unlocked)
		}
		input.ActionJumpToPrompt {
			self.queue_io(termiopkg.MessageJumpToPrompt{ delta: int(action.value) }, .unlocked)
		}
		input.ActionWriteScreenFile {
			self.write_screen_file(.screen, action.value)!
		}
		input.ActionWriteScrollbackFile {
			self.write_screen_file(.history, action.value)!
		}
		input.ActionWriteSelectionFile {
			self.write_screen_file(.selection, action.value)!
		}
		input.ActionNewTab {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.new_tab,
				apprt.ActionVoid{},
			)!
		}
		input.ActionCloseTab {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.close_tab,
				apprt.ActionValue(close_tab_mode_from_input(action.value)),
			)!
		}
		input.ActionPreviousTab {
			return self.goto_tab_action(.previous)!
		}
		input.ActionNextTab {
			return self.goto_tab_action(.next)!
		}
		input.ActionLastTab {
			return self.goto_tab_action(.last)!
		}
		input.ActionGotoTab {
			return self.goto_tab_action(unsafe { apprt.GotoTab(int(action.value)) })!
		}
		input.ActionMoveTab {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.move_tab,
				apprt.ActionValue(apprt.MoveTab{ amount: int(action.value) }),
			)!
		}
		input.ActionNewSplit {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.new_split,
				apprt.ActionValue(split_dir_from_input(action.value, self.size.screen)),
			)!
		}
		input.ActionGotoSplit {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.goto_split,
				apprt.ActionValue(goto_split_from_input(action.value)),
			)!
		}
		input.ActionGotoWindow {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.goto_window,
				apprt.ActionValue(goto_window_from_input(action.value)),
			)!
		}
		input.ActionResizeSplit {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.resize_split,
				apprt.ActionValue(apprt.ResizeSplit{
					direction: resize_dir_from_input(action.value.direction)
					amount:    action.value.amount
				}),
			)!
		}
		input.ActionEqualizeSplits {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.equalize_splits,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleSplitZoom {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_split_zoom,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleReadonly {
			self.readonly = !self.readonly
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.readonly,
				apprt.ActionValue(if self.readonly { apprt.Readonly.on } else { apprt.Readonly.off }),
			)!
			return true
		}
		input.ActionResetWindowSize {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.reset_window_size,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleMaximize {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_maximize,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleFullscreen {
			mode := match self.config.macos_non_native_fullscreen {
				.false_ { apprt.Fullscreen.native }
				.true_ { apprt.Fullscreen.macos_non_native }
				.visible_menu { apprt.Fullscreen.macos_non_native_visible_menu }
				.padded_notch { apprt.Fullscreen.macos_non_native_padded_notch }
			}
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_fullscreen,
				apprt.ActionValue(mode),
			)!
		}
		input.ActionToggleWindowDecorations {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_window_decorations,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleTabOverview {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_tab_overview,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleWindowFloatOnTop {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.float_window,
				apprt.ActionValue(apprt.FloatWindow.toggle),
			)!
		}
		input.ActionToggleSecureInput {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.secure_input,
				apprt.ActionValue(apprt.SecureInput.toggle),
			)!
		}
		input.ActionToggleMouseReporting {
			self.config.mouse_reporting = !self.config.mouse_reporting
		}
		input.ActionToggleCommandPalette {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_command_palette,
				apprt.ActionVoid{},
			)!
		}
		input.ActionToggleBackgroundOpacity {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.toggle_background_opacity,
				apprt.ActionVoid{},
			)!
		}
		input.ActionShowOnScreenKeyboard {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.show_on_screen_keyboard,
				apprt.ActionVoid{},
			)!
		}
		input.ActionSelectAll {
			self.renderer_state.mutex.lock()
			defer {
				self.renderer_state.mutex.unlock()
			}
			if sel := self.renderer_state.terminal_.screens.active.select_all() {
				self.set_selection(sel)!
				self.queue_render()!
			}
		}
		input.ActionInspector {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.inspector,
				apprt.ActionValue(inspector_mode_from_input(action.value)),
			)!
		}
		input.ActionCloseSurface {
			self.close()
		}
		input.ActionCloseWindow {
			return self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.close_window,
				apprt.ActionVoid{},
			)!
		}
		input.ActionActivateKeyTable, input.ActionActivateKeyTableOnce {
			return self.activate_key_table(action.value, action is input.ActionActivateKeyTableOnce)!
		}
		input.ActionDeactivateKeyTable {
			match self.keyboard.table_stack.len {
				0 {
					// No key table active. This does nothing.
					return false
				}
				1 {
					// Final key table active, clear our state.
					self.keyboard.table_stack.clear()
				}
				else {
					// Restore the prior key table.
					self.keyboard.table_stack.delete_last()
				}
			}
			self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.key_table,
				apprt.ActionValue(apprt.KeyTable(apprt.KeyTableDeactivate{})),
			) or {
				log.warn('failed to notify app of key table err=${err}')
			}
		}
		input.ActionDeactivateAllKeyTables {
			return self.deactivate_all_key_tables()!
		}
		input.ActionEndKeySequence {
			// End the key sequence and flush queued keys to the terminal,
			// but don't encode the key that triggered this action.
			self.end_key_sequence(.flush, .retain)
		}
		input.ActionAdjustSelection {
			self.renderer_state.mutex.lock()
			defer {
				self.renderer_state.mutex.unlock()
			}
			mut screen := self.renderer_state.terminal_.screens.active
			mut sel := screen.selection or { return false }
			sel.adjust(screen, selection_adjustment_from_input(action.value))
			screen.selection = sel

			// If the selection endpoint is outside of the current viewpoint,
			// scroll it in to view. Note we always specifically use sel.end
			// because that is what adjust modifies.
			viewport_tl := screen.pages.get_top_left(.viewport)
			viewport_br := screen.pages.get_bottom_right(.viewport) or {
				panic('viewport has no bottom-right')
			}
			if !sel.end().is_between(viewport_tl, viewport_br) {
				// Our end point is not within the viewport. If the end
				// point is after the br then we need to adjust the end so
				// that it is at the bottom right of the viewport.
				target := if sel.end().before(viewport_tl) {
					sel.end()
				} else {
					sel.end().up(uint(screen.pages.rows) - 1) or { sel.end() }
				}

				screen.scroll(terminal.ScrollPin{
					pin: target
				})
			}

			// Queue a render so its shown
			screen.dirty.set_selection(true)
			self.queue_render()!
		}
		input.ActionCrash {
			match action.value {
				.main_thread { panic('crash binding action, crashing intentionally') }
				.render {
					_ = self.renderer_thread.mailbox.push(rendererpkg.RendererMessage(rendererpkg.CrashMessage{}),
						datastruct.blocking_queue_forever)
					self.queue_render() or {
						// Not a big deal if this fails.
						log.warn('failed to notify renderer of crash message err=${err}')
					}
				}
				.io { self.queue_io(termiopkg.MessageCrash{}, .unlocked) }
			}
		}
		input.ActionIgnore, input.ActionUnbind, input.ActionNewWindow,
		input.ActionOpenConfig, input.ActionReloadConfig, input.ActionCloseAllWindows,
		input.ActionToggleQuickTerminal, input.ActionToggleVisibility,
		input.ActionCheckForUpdates, input.ActionUndo,
		input.ActionRedo, input.ActionQuit {
			// The scope check above consumes every app-scoped action. Listing
			// them explicitly keeps this switch exhaustive like Ghostty's
			// Scoped(.surface) switch, so a newly added surface action cannot
			// silently fall through as handled.
			panic('app-scoped action reached surface dispatch')
		}
	}

	return true
}

// app_action_key maps an app-scoped input.ActionTag to the corresponding
// apprt.ActionKey so it can be forwarded to the runtime. Only the app-scoped
// tags reach this (see perform_binding_action's scope() == .app branch).
fn app_action_key(tag input.ActionTag) apprt.ActionKey {
	return match tag {
		.open_config { .open_config }
		.reload_config { .reload_config }
		.close_all_windows { .close_all_windows }
		.quit { .quit }
		.toggle_quick_terminal { .toggle_quick_terminal }
		.toggle_visibility { .toggle_visibility }
		.check_for_updates { .check_for_updates }
		else { panic('non-app action reached app action dispatch') }
	}
}

// split_dir_from_input converts an input.SplitDirection
// into the runtime direction, resolving the input-only auto case.
fn split_dir_from_input(e input.SplitDirection, size rendererpkg.ScreenSize) apprt.SplitDirection {
	return match e {
		.right { .right }
		.down { .down }
		.left { .left }
		.up { .up }
		.auto_ {
			if size.width > size.height {
				apprt.SplitDirection.right
			} else {
				apprt.SplitDirection.down
			}
		}
	}
}

// goto_split_from_input converts an input.SplitFocusDirection into the runtime direction.
fn goto_split_from_input(e input.SplitFocusDirection) apprt.GotoSplit {
	return match e {
		.previous { .previous }
		.next { .next }
		.up { .up }
		.left { .left }
		.down { .down }
		.right { .right }
	}
}

// goto_window_from_input converts an input.GotoWindow
// into the runtime direction.
fn goto_window_from_input(e input.GotoWindow) apprt.GotoWindow {
	return match e {
		.previous { .previous }
		.next { .next }
	}
}

// resize_dir_from_input converts an input.SplitResizeDirection into the runtime direction.
fn resize_dir_from_input(e input.SplitResizeDirection) apprt.ResizeSplitDirection {
	return match e {
		.up { .up }
		.down { .down }
		.left { .left }
		.right { .right }
	}
}

// close_tab_mode_from_input converts an input.CloseTabMode into the runtime close mode.
fn close_tab_mode_from_input(e input.CloseTabMode) apprt.CloseTabMode {
	return match e {
		.this { .this }
		.other { .other }
		.right { .right }
	}
}

// inspector_mode_from_input converts an input.InspectorMode into the runtime inspector action.
fn inspector_mode_from_input(e input.InspectorMode) apprt.InspectorAction {
	return match e {
		.toggle { .toggle }
		.show { .show }
		.hide { .hide }
	}
}

fn selection_adjustment_from_input(e input.AdjustSelection) terminal.SelectionAdjustment {
	return match e {
		.left { .left }
		.right { .right }
		.up { .up }
		.down { .down }
		.page_up { .page_up }
		.page_down { .page_down }
		.home { .home }
		.end_ { .end_ }
		.beginning_of_line { .beginning_of_line }
		.end_of_line { .end_of_line }
	}
}

// goto_tab_action forwards a goto_tab action to the runtime.
fn (mut self Surface) goto_tab_action(idx apprt.GotoTab) !bool {
	return self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.goto_tab,
		apprt.ActionValue(idx),
	)!
}

// activate_key_table activates the named key table, pushing it onto the
// table stack. Returns false if the table is unknown, already active, or the
// stack is full.
fn (mut self Surface) activate_key_table(name string, once bool) !bool {
	set := self.config.keybind.tables[name] or { return false }

	// If this is the same table as is currently active, do nothing.
	if self.keyboard.table_stack.len > 0 {
		active := self.keyboard.table_stack[self.keyboard.table_stack.len - 1]
		if active.name == name {
			return false
		}
	}

	// If we're already at the max, ignore it.
	if self.keyboard.table_stack.len >= max_active_key_tables {
		return false
	}

	// Add the table to the stack.
	self.keyboard.table_stack << KeyTableEntry{
		set:  set
		once: once
		name: name
	}

	// Notify the UI.
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.key_table,
		apprt.ActionValue(apprt.KeyTable(apprt.KeyTableActivate{ name: name })),
	) or {
		log.warn('failed to notify app of key table err=${err}')
	}

	return true
}

// ---- Private helper methods ----

fn (mut self Surface) mods_changed(mods input.Mods) {
	if self.mouse.mods.equal(mods) {
		return
	}
	self.mouse.mods = mods.binding()

	// Update renderer mouse mods for link highlighting
	self.renderer_state.mutex.lock()
	self.renderer_state.mouse.mods = self.mouse_mods_with_capture(self.mouse.mods)

	// Force screen rebuild to update link highlight state
	self.renderer_state.terminal_.flags.set_dirty_clear(true)
	self.renderer_state.mutex.unlock()

	self.queue_render() or {
		log.warn('failed to notify renderer of mods change err=${err}')
	}
}

fn (mut self Surface) mouse_refresh_links(pos apprt.CursorPos, pos_vp Coordinate, over_link bool) ! {
	if pos.x < 0 || pos.y < 0 {
		return
	}

	// Update last checked link point
	self.mouse.link_point = pos_vp

	// Check for link at current position
	link := self.link_at_pos(pos) or {
		self.clear_link_hover(over_link)!
		return
	}

	mut url := ''
	mut preview := false
	match link.action {
		.open {
			url = self.renderer_state.terminal_.screens.active.selection_string(terminal.SelectionString{
				sel:  link.selection
				trim: false
			}) or {
				self.clear_link_hover(over_link)!
				return
			}
			preview = self.config.link_previews == .true_
		}
		.open_osc8 {
			url = self.osc8_uri(link.selection.start()) or {
				self.clear_link_hover(over_link)!
				return
			}
			preview = self.config.link_previews != .false_
		}
	}

	// Found a link — update state and notify runtime.
	self.renderer_state.mouse.point = pos_vp
	self.mouse.over_link = true
	self.renderer_state.terminal_.screens.active.dirty.set_hyperlink_hover(true)

	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.mouse_shape,
		apprt.ActionValue(terminal.MouseShape.pointer),
	)!

	if preview {
		self.rt_app.perform_action(
			apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
			.mouse_over_link,
			apprt.ActionValue(apprt.MouseOverLink{ url: url }),
		)!
	}

	self.queue_render()!
}

fn (mut self Surface) clear_link_hover(over_link bool) ! {
	if !over_link {
		return
	}
	self.mouse.over_link = false
	self.renderer_state.mouse.point = none
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.mouse_shape,
		apprt.ActionValue(self.renderer_state.terminal_.mouse_shape),
	)!
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.mouse_over_link,
		apprt.ActionValue(apprt.MouseOverLink{}),
	)!
	self.queue_render()!
}

fn (self &Surface) is_mouse_reporting() bool {
	return self.config.mouse_reporting
		&& self.renderer_state.terminal_.flags.mouse_event() != .none
}

fn (mut self Surface) mouse_report(button ?input.MouseButton, action MouseReportAction, mods input.Mods, pos apprt.CursorPos) ! {
	mouse_event := self.renderer_state.terminal_.flags.mouse_event()
	mouse_format := self.renderer_state.terminal_.flags.mouse_format()

	// Depending on the event, we may do nothing at all.
	match mouse_event {
		.none {
			return
		}
		.x10 {
			// X10 only reports clicks with mouse button 1, 2, 3. We verify
			// the button below. It doesn't report motion, and the button
			// must be pressed.
			if action != .press {
				return
			}
			b := button or { return }
			if b !in [.left, .middle, .right] {
				return
			}
		}
		.normal {
			// Doesn't report motion.
			if action == .motion {
				return
			}
		}
		.button {
			// Button must be pressed.
			if button == none {
				return
			}
		}
		.any {}
	}

	// Handle scenarios where the mouse position is outside the viewport. We
	// always report release events no matter where they happen.
	if action != .release {
		max_x := f32(self.size.screen.width)
		max_y := f32(self.size.screen.height)
		pos_out_viewport := pos.x < 0 || pos.y < 0 || pos.x > max_x || pos.y > max_y
		if pos_out_viewport {
			// If we don't have a motion-tracking event mode, do nothing.
			if mouse_event !in [.button, .any] {
				return
			}
			// If any button is pressed we still report. Otherwise we don't.
			mut any_pressed := false
			for state in self.mouse.click_state {
				if state != .release {
					any_pressed = true
					break
				}
			}
			if !any_pressed {
				return
			}
		}
	}

	// This format reports X/Y.
	viewport_point := self.pos_to_viewport(f64(pos.x), f64(pos.y))

	// Record our new point. We only want to send a mouse event if the cell
	// changed, unless we're tracking raw pixels.
	if action == .motion && mouse_format != .sgr_pixels {
		if last_point := self.mouse.event_point {
			if last_point.eql(viewport_point) {
				return
			}
		}
	}
	self.mouse.event_point = viewport_point

	// Get the code we'll actually write.
	mut button_code := u8(0)
	if button == none {
		// Null button means motion without a button pressed.
		button_code = 3
	} else if action == .release && mouse_format != .sgr && mouse_format != .sgr_pixels {
		// Release is 3. It is NOT 3 in SGR mode because SGR can tell the
		// application what button was released.
		button_code = 3
	} else {
		b := button or { return }
		button_code = match b {
			.left { u8(0) }
			.middle { u8(1) }
			.right { u8(2) }
			.four { u8(64) }
			.five { u8(65) }
			.six { u8(66) }
			.seven { u8(67) }
			.eight { u8(128) }
			.nine { u8(129) }
			else {
				return
			} // unsupported
		}
	}

	// X10 doesn't have modifiers.
	if mouse_event != .x10 {
		if mods.shift() {
			button_code += 4
		}
		if mods.alt() {
			button_code += 8
		}
		if mods.ctrl() {
			button_code += 16
		}
	}

	// Motion adds another bit.
	if action == .motion {
		button_code += 32
	}

	match mouse_format {
		.x10 {
			if viewport_point.x > 222 || viewport_point.y > 222 {
				// X10 mouse format can only encode X/Y up to 223.
				return
			}
			// +1 below is because our x/y is 0-indexed and the protocol wants 1.
			mut data := []u8{cap: 6}
			data << u8(0x1b)
			data << u8(`[`)
			data << u8(`M`)
			data << u8(32 + button_code)
			data << u8(32 + u8(viewport_point.x) + 1)
			data << u8(32 + u8(viewport_point.y) + 1)
			self.queue_io(termiopkg.WriteSmall.from_slice(data), .locked)
		}
		.utf8 {
			mut data := []u8{cap: 12}
			data << u8(0x1b)
			data << u8(`[`)
			data << u8(`M`)
			data << u8(32 + button_code)
			// UTF-8 encode the x/y.
			data << utf8_encode(u32(32 + viewport_point.x + 1))
			data << utf8_encode(u32(32 + viewport_point.y + 1))
			self.queue_io(termiopkg.WriteSmall.from_slice(data), .locked)
		}
		.sgr {
			// Final character to send in the CSI.
			final := if action == .release { `m` } else { `M` }
			resp := '\x1b[<${button_code};${viewport_point.x + 1};${viewport_point.y + 1}${rune(final)}'
			self.queue_io(termiopkg.WriteSmall.from_slice(resp.bytes()), .locked)
		}
		.urxvt {
			resp := '\x1b[${u16(32) + u16(button_code)};${viewport_point.x + 1};${viewport_point.y + 1}M'
			self.queue_io(termiopkg.WriteSmall.from_slice(resp.bytes()), .locked)
		}
		.sgr_pixels {
			// Final character to send in the CSI.
			final := if action == .release { `m` } else { `M` }
			// The position has to be adjusted to the terminal (padding-relative)
			// space and reported in pixels.
			px := i32(math.round(pos.x - f64(self.size.padding.left)))
			py := i32(math.round(pos.y - f64(self.size.padding.top)))
			resp := '\x1b[<${button_code};${px};${py}${rune(final)}'
			self.queue_io(termiopkg.WriteSmall.from_slice(resp.bytes()), .locked)
		}
	}
}

// utf8_encode encodes a single codepoint into UTF-8 bytes.
fn utf8_encode(cp u32) []u8 {
	if cp < 0x80 {
		return [u8(cp)]
	} else if cp < 0x800 {
		return [u8(0xC0 | (cp >> 6)), u8(0x80 | (cp & 0x3F))]
	} else if cp < 0x10000 {
		return [u8(0xE0 | (cp >> 12)), u8(0x80 | ((cp >> 6) & 0x3F)), u8(0x80 | (cp & 0x3F))]
	} else {
		return [u8(0xF0 | (cp >> 18)), u8(0x80 | ((cp >> 12) & 0x3F)), u8(0x80 | ((cp >> 6) & 0x3F)),
			u8(0x80 | (cp & 0x3F))]
	}
}

fn (self &Surface) mouse_shift_capture(do_lock bool) bool {
	// Handle the unconditional cases without taking the renderer lock.
	match self.config.mouse_shift_capture {
		.never {
			return false
		}
		.always {
			return true
		}
		.false_, .true_ {}
	}

	if do_lock {
		self.renderer_state.mutex.lock()
	}
	defer {
		if do_lock {
			self.renderer_state.mutex.unlock()
		}
	}

	// An explicit terminal request wins over the user's conditional default.
	match self.renderer_state.terminal_.flags.mouse_shift_capture() {
		.false_ {
			return false
		}
		.true_ {
			return true
		}
		.null_ {}
	}

	return self.config.mouse_shift_capture == .true_
}

pub fn (mut self Surface) mouse_captured() bool {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	return self.renderer_state.terminal_.flags.mouse_event() != .none
}

fn (self &Surface) mouse_mods_with_capture(mods input.Mods) input.Mods {
	// If the terminal is reporting mouse events and shift is pressed,
	// strip shift from mods if we're not capturing shift
	if self.renderer_state.terminal_.flags.mouse_event() != .none {
		if mods.shift() && !self.mouse_shift_capture(false) {
			return input.Mods.init(false, mods.ctrl(), mods.alt(), mods.super_(), false, false,
				input.SideInfo{})
		}
	}
	return mods
}

fn (mut self Surface) set_selection(sel ?terminal.Selection) ! {
	prev := self.renderer_state.terminal_.screens.active.selection
	self.renderer_state.terminal_.screens.active.select(sel)!

	// If copy_on_select is enabled and selection changed, copy to clipboard
	if self.config.copy_on_select == .false_ {
		return
	}
	new_sel := sel or { return }
	if prev_sel := prev {
		if new_sel.eql(prev_sel) {
			return
		}
	}
	match self.config.copy_on_select {
		.clipboard {
			self.copy_selection_to_clipboards(new_sel, [.standard, .selection], .mixed)!
		}
		.true_ {
			loc := if self.rt_surface.supports_clipboard(.selection) {
				apprt.Clipboard.selection
			} else {
				apprt.Clipboard.standard
			}
			self.copy_selection_to_clipboards(new_sel, [loc], .mixed)!
		}
		.false_ {}
	}
}

fn (mut self Surface) set_cell_size(size rendererpkg.CellSize) ! {
	self.size.cell = size
	self.balance_padding_if_needed()

	// Notify IO thread of new size
	self.queue_io(termiopkg.Message(self.size), .unlocked)

	// Recompute initial window size if configured
	self.recompute_initial_size() or {
		log.warn('unable to recompute initial window size: ${err}')
	}

	// Notify runtime of cell size change
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.cell_size,
		apprt.ActionValue(apprt.CellSize{ width: size.width, height: size.height }),
	)!
}

fn (mut self Surface) queue_io(msg termiopkg.Message, mutex termiopkg.MutexState) {
	// In readonly mode, block write operations
	if self.readonly {
		match msg {
			termiopkg.WriteSmall, termiopkg.MessageWriteStable, termiopkg.MessageWriteAlloc {
				return
			}
			else {}
		}
	}
	self.io.queue_message(msg, mutex)
}

fn (mut self Surface) recompute_initial_size() ! {
	if self.config.window_height <= 0 || self.config.window_width <= 0 {
		return
	}

	content_scale := self.rt_surface.get_content_scale()!
	self.report_initial_window_size(self.config.initial_window_size(self.size, content_scale))!
}

fn (cfg &DerivedConfig) initial_window_size(size rendererpkg.Size, content_scale apprt.ContentScale) apprt.InitialSize {
	height := math.max(cfg.window_height, min_window_height_cells) * size.cell.height
	width := math.max(cfg.window_width, min_window_width_cells) * size.cell.width
	return apprt.InitialSize{
		width:  u32(math.ceil(f64(width) / content_scale.x)) + size.padding.left + size.padding.right
		height: u32(math.ceil(f64(height) / content_scale.y)) + size.padding.top + size.padding.bottom
	}
}

fn (mut self Surface) report_initial_window_size(size apprt.InitialSize) ! {
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.initial_size,
		apprt.ActionValue(size),
	)!
}

fn (mut self Surface) scroll_to_bottom() ! {
	self.renderer_state.terminal_.scroll_viewport(terminal.scroll_viewport_bottom)!
	self.queue_render()!
}

fn (mut self Surface) hide_mouse() {
	if self.mouse.hidden {
		return
	}
	self.mouse.hidden = true
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.mouse_visibility,
		apprt.ActionValue(apprt.MouseVisibility.hidden),
	) or {
		log.warn('apprt failed to set mouse visibility err=${err}')
	}
}

fn (mut self Surface) show_mouse() {
	if !self.mouse.hidden {
		return
	}
	self.mouse.hidden = false
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.mouse_visibility,
		apprt.ActionValue(apprt.MouseVisibility.visible),
	) or {
		log.warn('apprt failed to set mouse visibility err=${err}')
	}
}

// child_exited_handler is Ghostty's `childExited`. V does not allow this
// method to share the `child_exited` field's name.
fn (mut self Surface) child_exited_handler(info apprt.ChildExited) {
	// Mark our flag that we exited immediately
	self.child_exited = true

	// If our runtime was below some threshold then we assume that this
	// was an abnormal exit and we show an error message.
	if info.runtime_ms <= self.config.abnormal_command_exit_runtime_ms {
		// On macOS, our exit code detection doesn't work, possibly
		// because of our `login` wrapper. More investigation required.
		mut good_exit := false
		$if !macos {
			// If the exit code is 0 then it was a good exit.
			good_exit = info.exit_code == 0
		}
		if !good_exit {
			log.warn('abnormal process exit detected, showing error message')

			// Try and show a GUI message. If it returns true, don't do anything else.
			shown := self.rt_app.perform_action(
				apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
				.show_child_exited,
				apprt.ActionValue(info),
			) or {
				log.error('error trying to show native child exited GUI err=${err}')
				false
			}
			if shown {
				return
			}

			// If a native GUI notification was not shown, update our terminal to
			// note the abnormal exit.
			self.child_exited_abnormally(info) or {
				log.error('error handling abnormal child exit err=${err}')
				return
			}

			return
		}
	}

	// We output a message so that the user knows what's going on and
	// doesn't think their terminal just froze. We show this unconditionally
	// on close even if `wait_after_command` is false and the surface closes
	// immediately because if a user does an `undo` to restore a closed
	// surface then they will see this message and know the process has
	// completed. The single-pass loop is the source's labeled block.
	for {
		// First try and show a native GUI message.
		shown := self.rt_app.perform_action(
			apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
			.show_child_exited,
			apprt.ActionValue(info),
		) or {
			log.error('error trying to show native child exited GUI err=${err}')
			false
		}
		if shown {
			break
		}

		// If the native GUI can't be shown, display a text message in the
		// terminal.
		self.renderer_state.mutex.lock()
		mut t := self.renderer_state.terminal_
		t.carriage_return()
		t.linefeed() or {
			self.renderer_state.mutex.unlock()
			break
		}
		t.print_string('Process exited. Press any key to close the terminal.') or {
			self.renderer_state.mutex.unlock()
			break
		}
		t.modes.set(.cursor_visible, false)

		// We also want to ensure that normal keyboard encoding is on
		// so that we can close the terminal. We close the terminal on
		// any key press that encodes a character.
		t.modes.set(.disable_keyboard, false)
		t.screens.active.kitty_keyboard.set(.set_, terminal.key_flags_disabled)
		self.renderer_state.mutex.unlock()
		break
	}

	// Waiting after command we stop here. The terminal is updated, our
	// state is updated, and now its up to the user to decide what to do.
	if self.config.wait_after_command {
		return
	}

	// If we aren't waiting after the command, then we exit immediately
	// with no confirmation.
	self.close()
}

// child_exited_abnormally writes Ghostty's detailed launch-failure report into
// the terminal when the application runtime cannot show a native banner.
fn (mut self Surface) child_exited_abnormally(info apprt.ChildExited) ! {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	mut t := self.renderer_state.terminal_

	// No matter what move the cursor back to the column 0.
	t.carriage_return()

	// Reset styles
	t.set_attribute(terminal.SgrUnset{})!
	viewport := t.plain_string()!
	if viewport.len > 0 {
		t.linefeed()!
		for _ in 0 .. int(t.cols) {
			t.print(0x2501)!
		}
		t.carriage_return()
		t.linefeed()!
		t.linefeed()!
	}

	t.set_attribute(terminal.SgrFg8{ name: .bright_red })!
	t.set_attribute(terminal.SgrBold{})!
	t.print_string('Witty failed to launch the requested command:')!
	t.set_attribute(terminal.SgrUnset{})!
	t.carriage_return()
	t.linefeed()!
	t.linefeed()!
	t.print_string(self.io.impl.backend.exec.subprocess.args.join(' '))!
	t.set_attribute(terminal.SgrUnset{})!
	t.carriage_return()
	t.linefeed()!
	t.linefeed()!
	t.print_string('Runtime: ')!
	t.set_attribute(terminal.SgrFg8{ name: .red })!
	t.print_string('${info.runtime_ms} ms')!
	t.set_attribute(terminal.SgrUnset{})!
	$if !macos {
		t.carriage_return()
		t.linefeed()!
		t.print_string('Exit Code: ')!
		t.set_attribute(terminal.SgrFg8{ name: .red })!
		t.print_string(info.exit_code.str())!
		t.set_attribute(terminal.SgrUnset{})!
	}
	t.carriage_return()
	t.linefeed()!
	t.linefeed()!
	t.print_string('Press any key to close the window.')!
	t.modes.set(.cursor_visible, false)
}

fn (mut self Surface) password_input(v bool) ! {
	self.renderer_state.mutex.lock()
	// Check if state actually changed
	if self.renderer_state.terminal_.flags.password_input() == v {
		self.renderer_state.mutex.unlock()
		return
	}
	self.renderer_state.terminal_.flags.set_password_input(v)
	self.renderer_state.mutex.unlock()

	// Notify runtime for secure input handling (e.g. macOS SecureInput)
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.secure_input,
		apprt.ActionValue(if v { apprt.SecureInput.on } else { apprt.SecureInput.off }),
	) or {
		log.warn('apprt failed to set secure input state err=${err}')
	}

	self.queue_render()!
}

fn (mut self Surface) update_renderer_health(health rendererpkg.Health) {
	log.warn('renderer health status change status=${health}')
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.renderer_health,
		apprt.ActionValue(health),
	) or {
		log.warn('failed to notify app of renderer health change err=${err}')
	}
}

fn (mut self Surface) update_scrollbar(scrollbar terminal.Scrollbar) {
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.scrollbar,
		apprt.ActionValue(scrollbar),
	) or {
		log.warn('failed to notify app of scrollbar change err=${err}')
	}
}

fn (mut self Surface) notify_config_conditional_state() {
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.reload_config,
		apprt.ActionValue(apprt.ReloadConfig{ soft: true }),
	) or {
		log.warn('failed to notify app of config state change err=${err}')
	}
}

fn (self &Surface) crash_thread_state() crash.ThreadState {
	return crash.ThreadState{
		kind:    .main
		surface: voidptr(self)
	}
}

fn (mut self Surface) present_surface() ! {
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.present_terminal,
		apprt.ActionVoid{},
	)!
}

fn (mut self Surface) end_key_sequence(action KeySequenceQueued, mem KeySequenceMemory) {
	// Notify apprt key sequence ended
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.key_sequence,
		apprt.ActionValue(apprt.KeySequence(apprt.KeySequenceEnd{})),
	) or {
		log.warn('failed to notify app of key sequence end err=${err}')
	}

	// No matter what we clear our current sequence set. This restores
	// the set we look at to the root set.
	self.keyboard.sequence_set = none

	if self.keyboard.sequence_queued.len == 0 {
		return
	}

	match action {
		.flush {
			// Send all queued keys to the IO thread
			for write_req in self.keyboard.sequence_queued {
				self.queue_io(write_req.message(), .unlocked)
			}
		}
		.drop {
			// Discard all queued keys
			for mut write_req in self.keyboard.sequence_queued {
				write_req.deinit()
			}
		}
	}

	match mem {
		.free {
			self.keyboard.sequence_queued = []
		}
		.retain { self.keyboard.sequence_queued.clear() }
	}
}

fn (mut self Surface) deactivate_all_key_tables() !bool {
	if self.keyboard.table_stack.len == 0 {
		return false
	}
	self.keyboard.table_stack.clear()

	// Notify the UI.
	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.key_table,
		apprt.ActionValue(apprt.KeyTable(apprt.KeyTableDeactivateAll{})),
	) or {
		log.warn('failed to notify app of key table err=${err}')
	}

	return true
}

fn (self &Surface) catch_all_is_ignore() bool {
	trigger := input.Trigger{
		key: input.TriggerKeyCatchAll{}
	}
	for i := self.keyboard.table_stack.len - 1; i >= 0; i-- {
		if entry := self.keyboard.table_stack[i].set.get(trigger) {
			return binding_entry_has_ignore(entry)
		}
	}
	entry := self.config.keybind.set.get(trigger) or { return false }
	return binding_entry_has_ignore(entry)
}

fn binding_entry_has_ignore(entry &input.SetEntry) bool {
	value := entry.value
	return match value {
		input.Leader { false }
		input.Leaf { value.action is input.ActionIgnore }
		input.LeafChained { value.actions.any(it is input.ActionIgnore) }
	}
}

// MaybeHandleBindingResult preserves Ghostty's error-union-of-optional result.
struct MaybeHandleBindingResult {
	value ?apprt.InputEffect
}

// Maybe handles a binding for a given event and if so returns the effect.
// Returns none if the event is not handled in any way and processing should
// continue.
fn (mut self Surface) maybe_handle_binding(event KeyEvent, inspecting bool, mut inspector_event inspectorpkg.KeyEvent) !MaybeHandleBindingResult {
	match event.action {
		// Release events never trigger a binding but we need to check if
		// we consumed the press event so we don't encode the release.
		.release {
			if last := self.keyboard.last_trigger {
				if last == event.binding_hash() {
					// We don't reset the last trigger on release because
					// an apprt may send multiple release events for a single
					// press event.
					return MaybeHandleBindingResult{
						value: .consumed
					}
				}
			}

			return MaybeHandleBindingResult{}
		}
		// Carry on processing.
		.press, .repeat {}
	}

	// Find an entry in the keybind set that matches our event.
	mut entry := &input.SetEntry(unsafe { nil })
	if set := self.keyboard.sequence_set {
		// Handle key sequences first. Get our entry from the set for the
		// given event.
		entry = set.get_event(event) or {
			// No entry found. We need to encode everything up to this
			// point and send to the pty since we're in a sequence.

			// We ignore modifiers so that nested sequences such as
			// ctrl+a>ctrl+b>c work.
			if event.key.modifier() {
				return MaybeHandleBindingResult{}
			}

			// If we have a catch-all of ignore, then we special case our
			// invalid sequence handling to ignore it.
			if self.catch_all_is_ignore() {
				self.end_key_sequence(.drop, .retain)
				return MaybeHandleBindingResult{
					value: .ignored
				}
			}

			// Encode everything up to this point
			self.end_key_sequence(.flush, .retain)

			return MaybeHandleBindingResult{}
		}
	} else {
		// No currently active sequence, move on to tables. For tables,
		// we search inner-most table to outer-most. The table stack does
		// NOT include the root set.
		table_items := self.keyboard.table_stack
		for i in 0 .. table_items.len {
			rev_i := table_items.len - 1 - i
			table := table_items[rev_i]
			if v := table.set.get_event(event) {
				// If this is a one-shot activation AND its the currently
				// active table, then we deactivate it after this.
				// Note: we may want to change the semantics here to
				// remove this table no matter where it is in the stack,
				// maybe.
				if table.once && i == 0 {
					_ = self.perform_binding_action(input.ActionDeactivateKeyTable{})!
				}

				entry = v
				break
			}
		}

		// No table, use our default set
		if isnil(entry) {
			entry = self.config.keybind.set.get_event(event) or {
				return MaybeHandleBindingResult{}
			}
		}
	}

	// Determine if this entry has an action or if its a leader key.
	leader := entry.value
	if leader is input.Leader {
		// Setup the next set we'll look at.
		self.keyboard.sequence_set = *leader.set

		// Store this event so that we can drain and encode on invalid.
		// We don't need to cap this because it is naturally capped by
		// the config validation.
		if req := self.encode_key(event, inspecting, mut inspector_event) {
			self.keyboard.sequence_queued << req
		}

		// Start or continue our key sequence
		self.rt_app.perform_action(
			apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
			.key_sequence,
			apprt.ActionValue(apprt.KeySequence(entry.trigger)),
		) or {
			log.warn('failed to notify app of key sequence err=${err}')
		}

		return MaybeHandleBindingResult{
			value: .consumed
		}
	}
	leaf := entry.value.generic() or { panic('binding entry is neither a leader nor a leaf') }

	// consumed determines if the input is consumed or if we continue
	// encoding the key (if we have a key to encode). If the consumed flag
	// is explicitly set, or the global or all flag is set, we always consume.
	consumed := leaf.flags.consumed() || leaf.flags.global() || leaf.flags.all()

	// We have an action, so at this point we're handling SOMETHING so
	// we reset the last trigger to none. We only set this if we actually
	// perform an action (below)
	self.keyboard.last_trigger = none

	// An action also always resets the sequence set.
	self.keyboard.sequence_set = none

	// Setup our actions
	actions := leaf.actions_slice()

	// Attempt to perform the action
	mut performed := false
	if leaf.flags.global() || leaf.flags.all() {
		// If this is a global or all action, then we perform it on
		// the app and it applies to every surface.
		mut rt_app := self.rt_app
		self.app.perform_all_chained_action(mut rt_app, actions)

		// "All" actions are always performed since they are global.
		performed = true
	} else {
		// Perform each action. We are performed if ANY of the chained
		// actions perform.
		for action in actions {
			if v := self.perform_binding_action(action) {
				performed = performed || v
			} else {
				log.info('key binding action failed action=${action.tag()} err=${err}')
			}
		}
	}

	if performed {
		// If we performed an action and it was a closing action,
		// our "self" pointer is not safe to use anymore so we need to
		// just exit immediately.
		for action in actions {
			if closing_action(action) {
				return MaybeHandleBindingResult{
					value: .closed
				}
			}
		}

		// If our action was "ignore" then we return the special input
		// effect of "ignored".
		for action in actions {
			if action is input.ActionIgnore {
				return MaybeHandleBindingResult{
					value: .ignored
				}
			}
		}
	}

	// If we have the performable flag and the action was not performed,
	// then we act as though a binding didn't exist.
	if leaf.flags.performable() && !performed {
		// If we're in a sequence, we treat this as if we pressed a key
		// that doesn't exist in the sequence. Reset our sequence and flush
		// any queued events.
		self.end_key_sequence(.flush, .retain)

		return MaybeHandleBindingResult{}
	}

	// If we consume this event, then we are done. If we don't consume
	// it, we processed the action but we still want to process our
	// encodings, too.
	if consumed {
		// If we had queued events, we deinit them since we consumed
		self.end_key_sequence(.drop, .retain)

		// Store our last trigger so we don't encode the release event
		self.keyboard.last_trigger = event.binding_hash()

		if inspecting {
			inspector_event.binding = actions.clone()
		}
		return MaybeHandleBindingResult{
			value: .consumed
		}
	}

	// If we didn't perform OR we didn't consume, then we want to
	// encode any queued events for a sequence.
	self.end_key_sequence(.flush, .retain)

	return MaybeHandleBindingResult{}
}

fn (mut self Surface) encode_key(event KeyEvent, inspecting bool, mut inspector_event inspectorpkg.KeyEvent) ?termiopkg.WriteReq {
	// Build our encoding options, which requires the lock.
	opts := self.encode_key_opts()
	encoded := input.encode(event, opts)

	// Special-case: we did nothing.
	if encoded.len == 0 {
		return none
	}
	write_req := termiopkg.WriteReq.init(encoded.bytes())

	// Copy the encoded data into the inspector event if we have one.
	// We do this before the mailbox because the IO thread could
	// release the memory before we get a chance to copy it.
	if inspecting {
		inspector_event.pty = write_req.slice().clone()
	}

	return write_req
}

fn (mut self Surface) encode_key_opts() input.Options {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	t := self.renderer_state.terminal_
	mut opts := input.Options.from_terminal(t)
	$if macos {
		opts.macos_option_as_alt = self.config.macos_option_as_alt or {
			if !self.mouse.mods.alt() {
				input.OptionAsAlt.false_
			} else {
				self.rt_app.keyboard_layout.detect_option_as_alt()
			}
		}
	}
	return opts
}

fn (mut self Surface) selection_scroll_tick() ! {
	if !self.selection_scroll_active {
		return
	}
	if self.mouse.left_click_count == 0 {
		return
	}

	pos := self.rt_surface.get_cursor_pos()!
	pos_vp := self.pos_to_viewport(f64(pos.x), f64(pos.y))
	delta := if pos.y < 0 { int(-1) } else { int(1) }
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}

	// A stored click pin belongs to the screen it was created for. Stop the
	// selection-scroll loop if an application switched primary/alternate
	// screens during the drag.
	if self.mouse.left_click_screen != self.renderer_state.terminal_.screens.active_key {
		self.queue_io(termiopkg.MessageSelectionScroll{ value: false }, .locked)
		return
	}

	// Scroll the viewport
	self.renderer_state.terminal_.scroll_viewport(terminal.ScrollViewport.from_delta(delta))!

	// Continue drag selection
	if pin := self.renderer_state.terminal_.screens.active.pages.pin(terminal.Point.new(.viewport,
		terminal.Coordinate{
			x: u16(pos_vp.x)
			y: u32(pos_vp.y)
		})) {
		self.drag_left_click_single(pin, f64(pos.x))!
	}

	self.queue_render()!
}

fn (mut self Surface) process_links(pos apprt.CursorPos) !bool {
	link := self.link_at_pos(pos) or { return false }
	match link.action {
		.open {
			url := self.renderer_state.terminal_.screens.active.selection_string(terminal.SelectionString{
				sel:  link.selection
				trim: false
			})!
			// Try resolving as local path first.
			if resolved := self.resolve_path_for_opening(url) {
				self.open_url(apprt.OpenUrl{ kind: .unknown, url: resolved })!
			} else {
				self.open_url(apprt.OpenUrl{ kind: .unknown, url: url })!
			}
			return true
		}
		.open_osc8 {
			if uri := self.osc8_uri(link.selection.start()) {
				self.open_url(apprt.OpenUrl{ kind: .unknown, url: uri })!
				return true
			}
			log.warn('failed to get URI for OSC8 hyperlink')
		}
	}
	return false
}

fn (mut self Surface) open_url(action apprt.OpenUrl) ! {
	handled := self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.open_url,
		apprt.ActionValue(action),
	)!
	if !handled {
		log.warn('apprt did not handle open URL action, falling back to default opener')
		internal_os.open(action.kind, action.url)!
	}
}

// Return the URI for an OSC8 hyperlink at the given position or null
// if there is no hyperlink.
fn (self &Surface) osc8_uri(pin Pin) ?string {
	mut page := &pin.node.data
	cell := pin.row_and_cell().cell
	link_id := page.lookup_hyperlink(cell) or { return none }
	entry := page.hyperlink_set.get(link_id)
	return entry.uri
}

fn (mut self Surface) write_screen_file(loc WriteScreenLoc, write_screen input.WriteScreen) ! {
	self.renderer_state.mutex.lock()
	screen := self.renderer_state.terminal_.screens.active
	pages := &screen.pages
	sel := match loc {
		.history {
			// We do not support this for alternate screens because they
			// don't have scrollback anyways.
			if self.renderer_state.terminal_.screens.active_key == .alternate {
				self.renderer_state.mutex.unlock()
				return
			}
			terminal.Selection.init(pages.get_top_left(.history), pages.get_bottom_right(.history) or {
				self.renderer_state.mutex.unlock()
				return
			}, false)
		}
		.screen {
			terminal.Selection.init(pages.get_top_left(.screen), pages.get_bottom_right(.screen) or {
				self.renderer_state.mutex.unlock()
				return
			}, false)
		}
		.selection {
			self.renderer_state.terminal_.screens.active.selection or {
				// If we have no selection we have no data, do nothing.
				self.renderer_state.mutex.unlock()
				return
			}
		}
	}

	// Format the selection into a temporary file. The extension is chosen
	// based on the emit format.
	ext := match write_screen.emit {
		.plain, .vt { 'txt' }
		.html { 'html' }
	}
	tmp_path := os.join_path(os.temp_dir(), 'witty-${os.getpid()}-${time.sys_mono_now()}-${loc}.${ext}')
	format := match write_screen.emit {
		.plain { terminal.Format.plain }
		.vt { terminal.Format.vt }
		.html { terminal.Format.html }
	}
	mut formatter := terminal.ScreenFormatter.init(screen, terminal.FormatOptions{
		emit:       format
		unwrap:     true
		trim:       false
		background: self.renderer_state.terminal_.colors.background.get()
		foreground: self.renderer_state.terminal_.colors.foreground.get()
		palette:    self.renderer_state.terminal_.colors.palette.current[..]
	})
	formatter.content = terminal.ScreenContent(terminal.ScreenContentSelection{
		sel: sel.ordered(screen, .forward)
	})
	content := formatter.format()
	self.renderer_state.mutex.unlock()
	os.write_file(tmp_path, content)!

	// Act on the written file per the action.
	match write_screen.action {
		.copy {
			self.rt_surface.set_clipboard(.standard, [apprt.ClipboardContent{
				mime: 'text/plain'
				data: tmp_path
			}], false)!
		}
		.open {
			kind := match write_screen.emit {
				.plain, .vt { apprt.OpenUrlKind.text }
				.html { apprt.OpenUrlKind.html }
			}
			self.open_url(apprt.OpenUrl{ kind: kind, url: tmp_path })!
		}
		.paste {
			self.queue_io(termiopkg.MessageWriteAlloc{ data: tmp_path }, .unlocked)
		}
	}
}

fn (mut self Surface) complete_clipboard_paste(data string, allow_unsafe bool) ! {
	if data.len == 0 {
		return
	}

	self.renderer_state.mutex.lock()
	paste_opts := input.PasteOptions.from_terminal(self.renderer_state.terminal_)
	if self.config.clipboard_paste_protection && !allow_unsafe {
		unsafe_paste := if paste_opts.bracketed {
			data.contains('\x1b[201~')
				|| (!self.config.clipboard_paste_bracketed_safe && !input.is_safe(data))
		} else {
			!input.is_safe(data)
		}
		if unsafe_paste {
			self.renderer_state.mutex.unlock()
			log.info('potentially unsafe paste detected, rejecting until confirmation')
			return error('UnsafePaste')
		}
	}

	// Scroll to bottom before pasting
	self.scroll_to_bottom() or {
		log.warn('error scrolling to bottom err=${err}')
	}
	self.renderer_state.mutex.unlock()

	mut encoded := input.PasteEncodeResult{}
	if result := input.paste_encode(data, paste_opts) {
		encoded = result
	} else {
		if err.msg() != 'MutableRequired' {
			return err
		}
		mut mutable_data := data.bytes()
		encoded = input.paste_encode_mut(mut mutable_data, paste_opts)
	}
	for part in encoded.parts() {
		if part.len > 0 {
			self.queue_io(termiopkg.MessageWriteAlloc{ data: part }, .unlocked)
		}
	}
}

// complete_clipboard_request completes exactly one request previously sent to
// the application runtime. The data is copied into the IO queue before return.
pub fn (mut self Surface) complete_clipboard_request(req apprt.ClipboardRequest, data string, confirmed bool) ! {
	match req {
		apprt.ClipboardRequestPaste {
			self.complete_clipboard_paste(data, confirmed)!
		}
		apprt.ClipboardRequestOsc52Read {
			self.complete_clipboard_read_osc52(data, req.clipboard, confirmed)!
		}
		apprt.ClipboardRequestOsc52Write {
			self.rt_surface.set_clipboard(req.clipboard, [apprt.ClipboardContent{
				mime: 'text/plain'
				data: data
			}], !confirmed)!
		}
	}
}

fn (mut self Surface) complete_clipboard_read_osc52(data string, clipboard_type apprt.Clipboard, confirmed bool) ! {
	// We should never get here if clipboard-read is set to deny because a
	// denied request is never started.
	assert self.config.clipboard_read != .deny

	if self.config.clipboard_read == .ask && !confirmed {
		return error('UnauthorizedPaste')
	}

	// Reply even when the clipboard is empty because the requesting client is
	// waiting for the OSC 52 response.
	kind := match clipboard_type {
		.standard { 'c' }
		.selection { 's' }
		.primary { 'p' }
	}
	encoded := base64.encode_str(data)
	response := '\x1b]52;${kind};${encoded}\x1b\\'
	self.queue_io(termiopkg.MessageWriteAlloc{ data: response }, .unlocked)
}

fn (mut self Surface) show_desktop_notification(title string, body string) ! {
	// Wyhash is used to hash the contents of the desktop notification to limit
	// how fast identical notifications can be sent sequentially.
	// Rate limit: at most one notification per second
	now := time.sys_mono_now()
	if last := self.app.last_notification_time {
		if now - last < u64(time.second) {
			log.warn('rate limiting desktop notifications')
			return
		}
	}

	content_hash := desktop_notification_digest(title, body)

	if content_hash == self.app.last_notification_digest {
		if last := self.app.last_notification_time {
			if now - last < u64(5 * time.second) {
				log.warn('suppressing identical desktop notification')
				return
			}
		}
	}

	self.app.last_notification_time = now
	self.app.last_notification_digest = content_hash

	self.rt_app.perform_action(
		apprt.Target(apprt.SurfaceTarget{ surface: voidptr(&self) }),
		.desktop_notification,
		apprt.ActionValue(apprt.DesktopNotificationValue{
			title: title
			body:  body
		}),
	)!
}

fn desktop_notification_digest(title string, body string) u64 {
	mut contents := []u8{cap: title.len + body.len}
	contents << title.bytes()
	contents << body.bytes()
	return internal_hash.wyhash(contents, 0)
}

fn (mut self Surface) copy_selection_to_clipboards(sel TermSelection, clipboards []apprt.Clipboard, format input.CopyToClipboard) ! {
	screen := self.renderer_state.terminal_.screens.active
	base_opts := terminal.FormatOptions{
		emit:          .plain
		unwrap:        true
		trim:          self.config.clipboard_trim_trailing_spaces
		codepoint_map: self.config.clipboard_codepoint_map.map.list
		background:    self.renderer_state.terminal_.colors.background.get()
		foreground:    self.renderer_state.terminal_.colors.foreground.get()
		palette:       self.renderer_state.terminal_.colors.palette.current[..]
	}
	mut contents := []apprt.ClipboardContent{}
	match format {
		.plain {
			mut formatter := terminal.ScreenFormatter.init(screen, base_opts)
			formatter.content = terminal.ScreenContent(terminal.ScreenContentSelection{ sel: sel })
			contents << apprt.ClipboardContent{ mime: 'text/plain', data: formatter.format() }
		}
		.vt {
			mut formatter := terminal.ScreenFormatter.init(screen, terminal.FormatOptions{
				...base_opts
				emit: .vt
			})
			formatter.content = terminal.ScreenContent(terminal.ScreenContentSelection{ sel: sel })

			// Note: We don't apply codepoint mappings to VT format since it contains
			// escape sequences that should be preserved as-is
			contents << apprt.ClipboardContent{ mime: 'text/plain', data: formatter.format() }
		}
		.html {
			mut formatter := terminal.ScreenFormatter.init(screen, terminal.FormatOptions{
				...base_opts
				emit: .html
			})
			formatter.content = terminal.ScreenContent(terminal.ScreenContentSelection{ sel: sel })

			// Note: We don't apply codepoint mappings to HTML format since HTML
			// has its own character encoding and entity system
			contents << apprt.ClipboardContent{ mime: 'text/html', data: formatter.format() }
		}
		.mixed {
			// First, generate plain text with codepoint mappings applied
			mut formatter := terminal.ScreenFormatter.init(screen, base_opts)
			formatter.content = terminal.ScreenContent(terminal.ScreenContentSelection{ sel: sel })
			contents << apprt.ClipboardContent{ mime: 'text/plain', data: formatter.format() }

			// Second, generate HTML without codepoint mappings
			formatter = terminal.ScreenFormatter.init(screen, terminal.FormatOptions{
				...base_opts
				emit:       .html
				// We purposely don't emit background/foreground for mixed
				// mode because the HTML contents is often used for rich text
				// input and with trimmed spaces it looks pretty bad.
				background: none
				foreground: none
			})
			formatter.content = terminal.ScreenContent(terminal.ScreenContentSelection{ sel: sel })

			// Note: We don't apply codepoint mappings to HTML format
			contents << apprt.ClipboardContent{ mime: 'text/html', data: formatter.format() }
		}
	}

	assert contents.len > 0
	for loc in clipboards {
		self.rt_surface.set_clipboard(loc, contents, false) or {
			log.error('error setting clipboard string clipboard=${loc} err=${err}')
		}
	}
}

fn (mut self Surface) clipboard_write(data string, loc apprt.Clipboard) ! {
	if self.config.clipboard_write == .deny {
		log.info("application attempted to write clipboard, but 'clipboard-write' is set to deny")
		return
	}
	decoded := decode_osc52_base64(data) or {
		log.info('application sent invalid base64 data for OSC 52')
		return
	}
	self.rt_surface.set_clipboard(loc, [apprt.ClipboardContent{
		mime: 'text/plain'
		data: decoded
	}], self.config.clipboard_write == .ask) or {
		log.error('error setting clipboard string err=${err}')
		return
	}
}

// decode_osc52_base64 mirrors the standard padded Base64 decoder used by
// Surface.clipboardWrite. Invalid shape/alphabet input is rejected, while
// noncanonical unused trailing bits are accepted just as Ghostty accepts the
// decoder's InvalidPadding result after it has produced the bytes.
fn decode_osc52_base64(data string) ?string {
	if data.len % 4 != 0 {
		return none
	}
	mut padding := 0
	for padding < data.len && data[data.len - 1 - padding] == `=` {
		padding++
	}
	if padding > 2 {
		return none
	}
	for c in data[..data.len - padding] {
		if c == `=` {
			return none
		}
	}
	output_len := data.len / 4 * 3 - padding
	mut output := []u8{len: output_len}
	decoded := simd.decode(data.bytes(), mut output) or { return none }
	if decoded.len != output_len {
		return none
	}
	return decoded.bytestr()
}

fn (mut self Surface) start_clipboard_request(loc apprt.Clipboard, req apprt.ClipboardRequest) !bool {
	match req {
		apprt.ClipboardRequestPaste {}
		apprt.ClipboardRequestOsc52Read {
			if self.config.clipboard_read == .deny {
				log.info("application attempted to read clipboard, but 'clipboard-read' is set to deny")
				return false
			}
		}
		apprt.ClipboardRequestOsc52Write {
			panic('OSC 52 writes do not start clipboard read requests')
		}
	}
	return self.rt_surface.clipboard_request(loc, req)!
}

fn (self &Surface) link_at_pos(pos apprt.CursorPos) ?Link {
	if pos.x < 0 || pos.y < 0 {
		return none
	}

	pos_vp := self.pos_to_viewport(f64(pos.x), f64(pos.y))
	pin := self.renderer_state.terminal_.screens.active.pages.pin(terminal.Point.new(.viewport,
		terminal.Coordinate{
			x: u16(pos_vp.x)
			y: u32(pos_vp.y)
		})) or { return none }
	mouse_mods := self.mouse_mods_with_capture(self.mouse.mods)

	// Check if left click is held and mouse moved (cancel link hover during drag)
	if self.mouse.click_state[int(input.MouseButton.left)] == .press {
		if click_pin := self.mouse.left_click_pin {
			if !click_pin.eql(pin) {
				return none
			}
		}
	}

	if mouse_mods.equal(input.ctrl_or_super_mods(input.Mods{})) {
		if uri := self.osc8_uri(pin) {
			_ = uri
			return Link{
				action:    .open_osc8
				selection: terminal.Selection.init(pin, pin, false)
			}
		}
	}

	return self.link_at_pin(pin, mouse_mods)
}

fn (self &Surface) link_at_pin(pin Pin, mouse_mods ?input.Mods) ?Link {
	if self.config.links.len == 0 {
		return none
	}
	screen := self.renderer_state.terminal_.screens.active
	line := screen.select_line(terminal.SelectLine{
		pin:                      pin
		whitespace:               none
		semantic_prompt_boundary: false
	}) or { return none }
	mut strmap := terminal.StringMap{}
	_ := screen.selection_string(terminal.SelectionString{
		sel:  line
		trim: false
		map:  &strmap
	}) or { return none }
	defer {
		strmap.deinit()
	}
	for link_cfg in self.config.links {
		if mods := mouse_mods {
			match link_cfg.highlight {
				input.LinkHighlightAlways, input.LinkHighlightHover {}
				input.LinkHighlightAlwaysMods, input.LinkHighlightHoverMods {
					if !link_cfg.highlight.mods.equal(mods) {
						continue
					}
				}
			}
		}
		mut it := strmap.search_iterator(link_cfg.regex)
		for {
			next := it.next() or { break }
			mut matched := next.get() or { break }
			sel := matched.selection()
			matched.deinit()
			if sel.contains(screen, pin) {
				return Link{
					action:    link_cfg.action
					selection: sel
				}
			}
		}
	}
	return none
}

fn (mut self Surface) maybe_prompt_click() !bool {
	if !self.config.cursor_click_to_move {
		return false
	}
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	t := self.renderer_state.terminal_
	screen := t.screens.active
	if screen.semantic_prompt.click is terminal.SemanticClickNone || !t.cursor_is_at_prompt()
		|| screen.selection != none {
		return false
	}
	pos := self.rt_surface.get_cursor_pos()!
	pos_vp := self.pos_to_viewport(f64(pos.x), f64(pos.y))
	click_pin := screen.pages.pin(terminal.Point.new(.viewport, terminal.Coordinate{
		x: u16(pos_vp.x)
		y: u32(pos_vp.y)
	})) or { return false }

	// Get our cursor's most current prompt.
	mut prompt_it := screen.cursor.page_pin.prompt_iterator(.left_up, none)
	prompt_pin := prompt_it.next() or {
		// This shouldn't be possible because we asserted we're at
		// a prompt above, so we MUST find some prompt in a left_up search.
		// log.warn: cursor is at prompt but no prompt found
		return false
	}

	// If our mouse click is before the prompt, we don't move.
	// We DO ALLOW clicks AFTER the prompt, specifically with Kitty's
	// click_events=1 since we rely on the shell to validate out of
	// bounds clicks. This matches Kitty's logic as best I can tell.
	if click_pin.before(prompt_pin) {
		return false
	}

	match screen.semantic_prompt.click {
		terminal.SemanticClickNone {
			return false
		}
		terminal.SemanticClickEvents {
			data := '\x1b[<0;${pos_vp.x + 1};${pos_vp.y + 1}M'
			self.queue_io(termiopkg.WriteSmall.from_slice(data.bytes()), .locked)
		}
		terminal.SemanticClickCl {
			left_arrow := if t.modes.get(.cursor_keys) { '\x1bOD' } else { '\x1b[D' }
			right_arrow := if t.modes.get(.cursor_keys) { '\x1bOC' } else { '\x1b[C' }
			move := screen.prompt_click_move(click_pin)
			for _ in 0 .. move.left {
				self.queue_io(termiopkg.MessageWriteStable{ data: left_arrow }, .locked)
			}
			for _ in 0 .. move.right {
				self.queue_io(termiopkg.MessageWriteStable{ data: right_arrow }, .locked)
			}
		}
	}
	return true
}

// Double-click dragging moves the selection one "word" at a time.
fn (mut self Surface) drag_left_click_double(drag_pin Pin) ! {
	mut screen := self.renderer_state.terminal_.screens.active
	click_pin := *(self.mouse.left_click_pin or { return })

	// Get the word closest to our starting click.
	word_start := screen.select_word_between(click_pin, drag_pin, self.config.selection_word_chars) or {
		self.set_selection(none)!
		return
	}

	// Get the word closest to our current point.
	word_current := screen.select_word_between(drag_pin, click_pin, self.config.selection_word_chars) or {
		self.set_selection(none)!
		return
	}

	// If our current mouse position is before the starting position,
	// then the selection start is the word nearest our current position.
	if drag_pin.before(click_pin) {
		screen.select(TermSelection.init(word_current.start(), word_start.end(), false))!
	} else {
		screen.select(TermSelection.init(word_start.start(), word_current.end(), false))!
	}
}

// Triple-click dragging moves the selection one "line" at a time.
fn (mut self Surface) drag_left_click_triple(drag_pin Pin) ! {
	mut screen := self.renderer_state.terminal_.screens.active
	click_pin := *(self.mouse.left_click_pin or { return })

	// Get the line selection under our current drag point. If there isn't a
	// line, do nothing.
	line := screen.select_line(terminal.SelectLine{
		pin: drag_pin
	}) or { return }

	// Get the selection under our click point. We first try to trim
	// whitespace if we've selected a word. But if no word exists then
	// we select the blank line.
	mut sel := screen.select_line(terminal.SelectLine{
		pin: click_pin
	}) or {
		screen.select_line(terminal.SelectLine{
			pin:        click_pin
			whitespace: none
		}) or { return }
	}

	if drag_pin.before(click_pin) {
		mut start := sel.start_ptr()
		unsafe {
			*start = line.start()
		}
	} else {
		mut end := sel.end_ptr()
		unsafe {
			*end = line.end()
		}
	}
	screen.select(sel)!
}

fn (mut self Surface) drag_left_click_single(drag_pin Pin, drag_x f64) ! {
	click_pin := *(self.mouse.left_click_pin or { return })
	// This logic is in a separate function so that it can be unit tested.
	self.renderer_state.terminal_.screens.active.select(mouse_selection(click_pin, drag_pin,
		u32(math.max(0.0, self.mouse.left_click_xpos)), u32(math.max(0.0, drag_x)), self.mouse.mods,
		self.size))!
}

fn (self &Surface) resolve_path_for_opening(path string) ?string {
	if !os.is_abs_path(path) {
		terminal_pwd := self.renderer_state.terminal_.get_pwd() or { return none }
		resolved := os.join_path(terminal_pwd, path)
		if os.exists(resolved) {
			return resolved
		}
		return none
	}
	return none
}

pub fn (mut self Surface) dump_text(sel TermSelection) !Text {
	self.renderer_state.mutex.lock()
	defer {
		self.renderer_state.mutex.unlock()
	}
	return self.dump_text_locked(sel)
}

pub fn (mut self Surface) dump_text_locked(sel TermSelection) !Text {
	// Read out the text
	text := self.renderer_state.terminal_.screens.active.selection_string(terminal.SelectionString{
		sel:  sel
		trim: false
	})!

	return Text{
		text:     text
		viewport: self.dump_text_viewport(sel)
	}
}

// The `viewport:` block of dumpTextLocked: calculate our viewport info if
// we can.
fn (self &Surface) dump_text_viewport(sel TermSelection) ?TextViewport {
	screen := self.renderer_state.terminal_.screens.active

	// If our bottom right pin is before the viewport, then we can't
	// possibly have this text be within the viewport.
	vp_tl_pin := screen.pages.get_top_left(.viewport)
	br_pin := sel.bottom_right(screen)
	if br_pin.before(vp_tl_pin) {
		return none
	}

	// If our top-left pin is after the viewport, then we can't possibly
	// have this text be within the viewport.
	vp_br_pin := screen.pages.get_bottom_right(.viewport) or {
		// I don't think this is possible but I don't want to crash on
		// that assertion so let's just break out...
		// log.warn: viewport bottom-right pin not found, bug?
		return none
	}
	tl_pin := sel.top_left(screen)
	if vp_br_pin.before(tl_pin) {
		return none
	}

	// We established that our top-left somewhere before the viewport
	// bottom-right and that our bottom-right is somewhere after
	// the top-left. This means that at least some portion of our
	// selection is within the viewport.

	// Our top-left point. If it doesn't exist in the viewport it must
	// be before and we can return (0,0).
	tl_pt := screen.pages.point_from_pin(.viewport, tl_pin) or {
		terminal.Point.new(.viewport, terminal.Coordinate{})
	}

	// Our bottom-right point. If it doesn't exist in the viewport
	// it must be the bottom-right of the viewport.
	br_pt := screen.pages.point_from_pin(.viewport, br_pin) or {
		screen.pages.point_from_pin(.viewport, vp_br_pin) or { return none }
	}

	tl_coord := tl_pt.coord()
	br_coord := br_pt.coord()

	// Our sizes are all scaled so we need to send the unscaled values back.
	content_scale := self.rt_surface.get_content_scale() or {
		apprt.ContentScale{
			x: 1.0
			y: 1.0
		}
	}

	// Simple x * cell width gives the left
	mut x := f64(u32(tl_coord.x) * self.size.cell.width)

	// Add padding
	x += f64(self.size.padding.left)

	// Scale
	x /= content_scale.x

	// Simple y * cell height gives the top
	mut y := f64(tl_coord.y * self.size.cell.height)

	// We want the text baseline
	y += f64(self.size.cell.height)
	y -= f64(self.font_metrics.cell_baseline)

	// Add padding
	y += f64(self.size.padding.top)

	// Scale
	y /= content_scale.y

	// Utilize viewport sizing to convert to offsets
	start := tl_coord.y * u32(screen.pages.cols) + u32(tl_coord.x)
	end := br_coord.y * u32(screen.pages.cols) + u32(br_coord.x)

	return TextViewport{
		tl_px_x:      x
		tl_px_y:      y
		offset_start: start
		offset_len:   end - start
	}
}

// mouse_selection calculates the selection given click/drag pins and pixel positions.
fn mouse_selection(click_pin Pin, drag_pin Pin, click_x u32, drag_x u32, mods input.Mods, size rendererpkg.Size) ?TermSelection {
	threshold := u32(math.round(f64(size.cell.width) * 0.6))
	max_x := size.grid().columns * size.cell.width - 1
	drag_relative := if drag_x > size.padding.left { drag_x - size.padding.left } else { u32(0) }
	click_relative := if click_x > size.padding.left { click_x - size.padding.left } else { u32(0) }
	drag_x_frac := math.min(max_x, drag_relative) % size.cell.width
	click_x_frac := math.min(max_x, click_relative) % size.cell.width
	rectangle := is_rectangle_select_state(mods)
	same_pin := drag_pin.eql(click_pin)
	end_before_start := if same_pin {
		drag_x_frac < click_x_frac
	} else if rectangle {
		if drag_pin.x == click_pin.x {
			drag_x_frac < click_x_frac
		} else {
			drag_pin.x < click_pin.x
		}
	} else {
		drag_pin.before(click_pin)
	}
	include_click := if end_before_start {
		click_x_frac >= threshold
	} else {
		click_x_frac < threshold
	}
	include_drag := if end_before_start {
		drag_x_frac < threshold
	} else {
		drag_x_frac >= threshold
	}
	// If the click cell should be included in the selection then it's the
	// start, otherwise we get the previous or next cell to it depending on
	// the type and direction of the selection.
	start_pin := if include_click {
		click_pin
	} else if end_before_start {
		if rectangle { click_pin.left_clamp(1) } else { click_pin.left_wrap(1) or { click_pin } }
	} else if rectangle {
		click_pin.right_clamp(1)
	} else {
		click_pin.right_wrap(1) or { click_pin }
	}

	// Likewise for the end pin with the drag cell.
	end_pin := if include_drag {
		drag_pin
	} else if end_before_start {
		if rectangle { drag_pin.right_clamp(1) } else { drag_pin.right_wrap(1) or { drag_pin } }
	} else if rectangle {
		drag_pin.left_clamp(1)
	} else {
		drag_pin.left_wrap(1) or { drag_pin }
	}
	if (!include_click && same_pin)
		|| (!include_click && rectangle && click_pin.x == drag_pin.x)
		|| (!include_click && end_pin.eql(click_pin))
		|| (!include_click && rectangle && end_pin.x == click_pin.x)
		|| (!include_drag && start_pin.eql(drag_pin))
		|| (!include_drag && rectangle && start_pin.x == drag_pin.x) {
		return none
	}
	return TermSelection.init(start_pin, end_pin, rectangle)
}

fn crash_surface_dimensions(surface_ptr voidptr) crash.Dimensions {
	surface := unsafe { &Surface(surface_ptr) }
	grid := surface.size.grid()
	return crash.Dimensions{
		screen_width: surface.size.screen.width
		screen_height: surface.size.screen.height
		grid_columns: u32(grid.columns)
		grid_rows: u32(grid.rows)
		cell_width: surface.size.cell.width
		cell_height: surface.size.cell.height
	}
}
