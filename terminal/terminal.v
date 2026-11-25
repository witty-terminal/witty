module terminal

import log
import math
import unicode

// --- Original Ghostty Comments Start: src/terminal/Terminal.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/terminal/Terminal.zig
//
// The primary terminal emulation structure. This represents a single
// "terminal" containing a grid of characters and exposes various operations
// on that grid. This also maintains the scrollback buffer.
// Default tabstop interval
// The set of screens behind this terminal (e.g. primary vs alternate).
// Whether we're currently writing to the status line (DECSASD and DECSSDT).
// We don't support a status line currently so we just black hole this
// data so that it doesn't mess up our main display.
// Where the tabstops are.
// The size of the terminal.
// The size of the screen in pixels. This is used for pty events and images
// The current scrolling region.
// The last reported pwd, if any.
// The color state for this terminal.
// The previous printed character. This is used for the repeat previous
// char CSI (ESC [ <n> b).
// The modes that this terminal currently has active.
// The most recently set mouse shape for the terminal.
// These are just a packed set of flags we may set on the terminal.
// This supports a Kitty extension where programs using semantic
// prompts (OSC133) can annotate their new prompts with `redraw=0` to
// disable clearing the prompt on resize.
// This is set via ESC[4;2m. Any other modify key mode just sets
// this to false and we act in mode 1 by default.
// The mouse event mode and format. These are set to the last
// set mode in modes. You can't get the right event/format to use
// based on modes alone because modes don't show you what order
// this was called so we have to track it separately.
// Set via the XTSHIFTESCAPE sequence. If true (XTSHIFTESCAPE = 1)
// then we want to capture the shift key for the mouse protocol
// if the configuration allows it.
// True if the window is focused.
// True if the terminal is in a password entry mode. This is set
// to true based on termios state. This is set
// to true based on termios state.
// True if the terminal should perform selection scrolling.
// Dirty flag used only by the search thread. The renderer is expected
// to set this to true if the viewport was dirty as it was rendering.
// This is used by the search thread to more efficiently re-search the
// viewport and active area.
//
// Since the renderer is going to inspect the viewport/active area ANYWAYS,
// this lets our search thread do less work and hold the lock less time,
// resulting in more throughput for everything.
// Dirty flags for the renderer.
// The various color configurations a terminal maintains and that can
// be set dynamically via OSC, with defaults usually coming from a
// configuration.
// This is a set of dirty flags the renderer can use to determine
// what parts of the screen need to be redrawn. It is up to the renderer
// to clear these flags.
//
// This only contains dirty flags for terminal state, not for the screen
// state. The screen state has its own dirty flags.
// Set when the color palette is modified in any way.
// Set when the reverse colors mode is modified.
// Screen clear of some kind. This can be due to a screen change,
// erase display, etc.
// Set when the pre-edit is modified.
// The event types that can be reported for mouse-related activities.
// These are all mutually exclusive (hence in a single enum).
// Returns true if this event sends motion events.
// The format of mouse events when enabled.
// These are all mutually exclusive (hence in a single enum).
// Scrolling region is the area of the screen designated where scrolling
// occurs. When scrolling the screen, only this viewport is scrolled.
// Top and bottom of the scroll region (0-indexed)
// Precondition: top < bottom
// Left/right scroll regions.
// Precondition: right > left
// Precondition: right <= cols - 1
// The default mode state. When the terminal gets a reset, it
// will revert back to this state.
// Initialize a new terminal.
// Return a terminal.Stream that can process VT streams and update this
// terminal state. The streams will only process read-only data that
// modifies terminal state. Sequences that query or otherwise require
// output will be ignored.
// This is the handler-side only for vtStream.
// The general allocator we should use for this terminal.
// Print UTF-8 encoded string to the terminal.
// Print the previous printed character a repeated amount of times.
// log.debug("print={x} y={} x={}", .{ c, self.screens.active.cursor.y, self.screens.active.cursor.x });
// If we're not on the main display, do nothing for now
// After doing any printing, wrapping, scrolling, etc. we want to ensure
// that our screen remains in a consistent state.
// Our right margin depends where our cursor is now.
// Perform grapheme clustering if grapheme support is enabled (mode 2027).
// This is MUCH slower than the normal path so the conditional below is
// purposely ordered in least-likely to most-likely so we can drop out
// as quickly as possible.
// We need the previous cell to determine if we're at a grapheme
// break or not. If we are NOT, then we are still combining the
// same grapheme. Otherwise, we can stay in this cell.
// If we have wraparound, then we always use the prev col
// If we do not have wraparound, the logic is trickier. If
// we're not on the last column, then we just use the previous
// column. Otherwise, we need to check if there is text to
// figure out if we're attaching to the prev or current.
// If the previous cell is a wide spacer tail, then we actually
// want to use the cell before that because that has the actual
// content.
// If our cell has no content, then this is a new cell and
// necessarily a grapheme break.
// log.debug("cp1={x} cp2={x}", .{ cp1, cp2 });
// log.debug("cp1={x} cp2={x} end", .{ cp1, c });
// If we can NOT break, this means that "c" is part of a grapheme
// with the previous char.
// If this is an emoji variation selector then we need to modify
// the cell width accordingly. VS16 makes the character wide and
// VS15 makes it narrow.
// Check if it is a valid variation sequence in
// emoji-variation-sequences.txt, and if not, ignore the char.
// Move our cursor back to the previous. We'll move
// the cursor within this block to the proper location.
// If we don't have space for the wide char, we need
// to insert spacers and wrap. Then we just print the wide
// char as normal.
// Write our spacer
// Move the cursor again so we're beyond our spacer
// Prev cell is no longer wide
// Remove the wide spacer tail
// Back track the cursor so that we don't end up with
// an extra space after the character. Since xterm is
// not VS aware, it cannot be used as a reference for
// this behavior; but it does follow the principle of
// least surprise, and also matches the behavior that
// can be observed in Kitty, which is one of the only
// other VS aware terminals.
// If we're already at the right edge, we stay
// here and set the pending wrap to false since
// when we pend a wrap, we only move our cursor once
// even for wide chars (tests verify).
// Otherwise, move back.
// Determine the width of this character so we can handle
// non-single-width characters properly. We have a fast-path for
// byte-sized characters since they're so common. We can ignore
// control characters because they're always filtered prior.
// Note: it is possible to have a width of "3" and a width of "-1" from
// uucode.x's wcwidth. We should look into those cases and handle them
// appropriately.
// log.debug("c={x} width={}", .{ c, width });
// Attach zero-width characters to our cell as grapheme data.
// If we have grapheme clustering enabled, we don't blindly attach
// any zero width character to our cells and we instead just ignore
// it.
// If we're at cell zero, then this is malformed data and we don't
// print anything or even store this. Zero-width characters are ALWAYS
// attached to some other non-zero-width character at the time of
// writing.
// Find our previous cell
// If our previous cell has no text, just ignore the zero-width character
// If this is a emoji variation selector, prev must be an emoji
// We have a printable character, save it
// If we're soft-wrapping, then handle that first.
// If we have insert mode enabled then we need to handle that. We
// only do insert mode if we're not at the end of the line.
// Single cell is very easy: just write in the cell
// Wide character requires a spacer. We print this by
// using two cells: the first is flagged "wide" and has the
// wide char. The second is guaranteed to be a spacer if
// we're not at the end of the line.
// If we don't have space for the wide char, we need
// to insert spacers and wrap. Then we just print the wide
// char as normal.
// If we don't have wraparound enabled then we don't print
// this character at all and don't move the cursor. This is
// how xterm behaves.
// We only create a spacer head if we're at the real edge
// of the screen. Otherwise, we clear the space with a narrow.
// This allows soft wrapping to work correctly.
// This is pretty broken, terminals should never be only 1-wide.
// We should prevent this downstream.
// If we're at the column limit, then we need to wrap the next time.
// In this case, we don't move the cursor.
// Move the cursor
// TODO: spacers should use a bgcolor only cell
// TODO: non-utf8 handling, gr
// If we're single shifting, then we use the key exactly once.
// UTF-8 or ASCII is used as-is
// If we're outside of ASCII range this is an invalid value in
// this table so we just return space.
// Get our lookup table and map it
// If the wide property of this cell is the same, then we don't
// need to do the special handling here because the structure will
// be the same. If it is NOT the same, then we may need to clear some
// cells.
// Previous cell was narrow. Do nothing.
// Previous cell was wide. We need to clear the tail and head.
// So integrity checks pass. We fix this up later so we don't
// need to do this without safety checks.
// TODO: this case was not handled in the old terminal implementation
// but it feels like we should do something. investigate other
// terminals (xterm mainly) and see what's up.
// If the prior value had graphemes, clear those
// We don't need to update the style refs unless the
// cell's new style will be different after writing.
// Release the old style.
// Keep track if we had a hyperlink so we can unset it.
// Write
// Use the new style.
// If this is a Kitty unicode placeholder then we need to mark the
// row so that the renderer can lookup rows with these much faster.
// We check for an active hyperlink first because setHyperlink
// handles clearing the old hyperlink and an optimization if we're
// overwriting the same hyperlink.
// If the previous cell had a hyperlink then we need to clear it.
// We only mark that we soft-wrapped if we're at the edge of our
// full screen. We don't mark the row as wrapped if we're in the
// middle due to a right margin.
// Get the old semantic prompt so we can extend it to the next
// line. We need to do this before we index() because we may
// modify memory.
// Move to the next line
// Our pointer should never move
// We always reset our semantic prompt state
// Always mark the row as a continuation
// Assure that our screen is consistent
// Set the charset into the given slot.
// Invoke the charset in slot into the active slot. If single is true,
// then this will only be invoked for a single character.
// Carriage return moves the cursor to the first column.
// Always reset pending wrap state
// In origin mode we always move to the left margin
// Linefeed moves the cursor to the next line.
// Backspace moves the cursor back a column (but not less than 0).
// Move the cursor up amount lines. If amount is greater than the maximum
// move distance then it is internally adjusted to the maximum. If amount is
// 0, adjust it to 1.
// Always resets pending wrap
// The maximum amount the cursor can move up depends on scrolling regions
// We can safely intCast below because of the min/max clamping we did above.
// Move the cursor down amount lines. If amount is greater than the maximum
// move distance then it is internally adjusted to the maximum. This sequence
// will not scroll the screen or scroll region. If amount is 0, adjust it to 1.
// Always resets pending wrap
// The max the cursor can move to depends where the cursor currently is
// Move the cursor right amount columns. If amount is greater than the
// maximum move distance then it is internally adjusted to the maximum.
// This sequence will not scroll the screen or scroll region. If amount is
// 0, adjust it to 1.
// Always resets pending wrap
// The max the cursor can move to depends where the cursor currently is
// Move the cursor to the left amount cells. If amount is 0, adjust it to 1.
// Wrapping behavior depends on various terminal modes
// If we are in no wrap mode, then we move the cursor left and exit
// since this is the fastest and most typical path.
// If we have a pending wrap state and we are in either reverse wrap
// modes then we decrement the amount we move by one to match xterm.
// The margins we can move to.
// Handle some edge cases when our cursor is already on the left margin.
// In reverse mode, if we're already before the top margin
// then we just set our cursor to the top-left and we're done.
// Handled in while loop
// Handled above
// We can move at most to the left margin.
// We want to move at most the number of columns we have left
// or our remaining count. Do the move.
// If we have no more to move, then we're done.
// If we are at the top, then we are done.
// UNDEFINED TERMINAL BEHAVIOR. This situation is not handled in xterm
// and currently results in a crash in xterm. Given no other known
// terminal [to me] implements XTREVWRAP2, I decided to just mimic
// the behavior of xterm up and not including the crash by wrapping
// up to the (0, 0) and stopping there. My reasoning is that for an
// appropriately sized value of "count" this is the behavior that xterm
// would have. This is unit tested.
// If our previous line is not wrapped then we are done.
// Save cursor position and further state.
//
// The primary and alternate screen have distinct save state. One saved state
// is kept per screen (main / alternative). If for the current screen state
// was already saved it is overwritten.
// Restore cursor position and other state.
//
// The primary and alternate screen have distinct save state.
// If no save was done before values are reset to their initial values.
// Set the style first because it can fail
// Regardless of the error here, we revert back to an unstyled
// cursor. It is more important that the restore succeeds in
// other attributes because terminals have no way to communicate
// failure back.
// Ensure our screen is consistent
// Set the character protection mode for the terminal.
// screen.protected_mode is NEVER reset to ".off" because
// logic such as eraseChars depends on knowing what the
// _most recent_ mode was.
// Perform a semantic prompt command.
//
// If there is an error, we do our best to get the terminal into
// some coherent state, since callers typically can't handle errors
// (since they're sending sequences via the pty).
// "First do a fresh-line."
// "Subsequent text (until a OSC "133;B" or OSC "133;I" command)
// is a prompt string (as if followed by OSC 133;P;k=i\007)."
// This is a kitty-specific flag that notes that the shell
// is NOT capable of redraw. Redraw defaults to true so this
// usually just disables it, but either is possible.
// Handle click_events as a priority over cl. click_events
// is another Kitty-specific extension that converts clicks
// within a prompt area to SGR mouse events and defers to the
// shell to handle them.
// If click_events was not set or disabled, fallback to `cl`.
// The "aid" and "cl" options are also valid for this
// command but we don't yet handle these in any meaningful way.
// Spec:
// Same as OSC "133;A" but may first implicitly terminate a
// previous command: if the options specify an aid and there
// is an active (open) command with matching aid, finish the
// innermost such command (as well as any other commands
// nested more deeply). If no aid is specified, treat as an
// aid whose value is the empty string.
// Ghostty:
// We don't currently do explicit command tracking in any way
// so there is no need to terminate prior commands. We just
// perform the `A` action.
// Explicit start of prompt. Optional after an A or N command.
// The k (kind) option specifies the type of prompt:
// regular primary prompt (k=i or default),
// right-side prompts (k=r), or prompts for continuation lines (k=c or k=s).
// End of prompt and start of user input, terminated by a OSC
// "133;C" or another prompt (OSC "133;P").
// End of prompt and start of user input, terminated by end-of-line.
// "End of input, and start of output."
// If our current row is marked as a prompt and we're
// at column zero then we assume we're un-prompting. This
// is a heuristic to deal with fish, mostly. The issue that
// fish brings up is that it has no PS2 equivalent and its
// builtin OSC133 marking doesn't output continuation lines
// as k=s. So, we assume when we get a newline with a prompt
// cursor that the new line is also a prompt. But fish changes
// to output on the newline. So if we're at col 0 we just assume
// we're overwriting the prompt.
// From a terminal state perspective, this doesn't really do
// anything. Other terminals appear to do nothing here. I think
// its reasonable at this point to reset our semantic content
// state but the spec doesn't really say what to do.
// OSC 133;L
// Spec: "If the cursor is the initial column (left, assuming
// left-to-right writing), do nothing" This specification is very under
// specified. We are taking the liberty to assume that in a left/right
// margin context, if the cursor is outside of the left margin, we treat
// it as being at the left margin for the purposes of this command.
// This is arbitrary. If someone has a better reasonable idea we can
// apply it.
// The semantic prompt type. This is used when tracking a line type and
// requires integration with the shell. By default, we mark a line as "none"
// meaning we don't know what type it is.
//
// See: https://gitlab.freedesktop.org/Per_Bothner/specifications/blob/master/proposals/semantic-prompts.md
// Returns true if the cursor is currently at a prompt. Another way to look
// at this is it returns false if the shell is currently outputting something.
// This requires shell integration (semantic prompt integration).
//
// If the shell integration doesn't exist, this will always return false.
// If we're on the secondary screen, we're never at a prompt.
// If our page row is a prompt then we're always at a prompt
// Otherwise, determine our cursor state
// Horizontal tab moves the cursor to the next tabstop, clearing
// the screen to the left the tabstop.
// Move the cursor right
// If the last cursor position was a tabstop we return. We do
// "last cursor position" because we want a space to be written
// at the tabstop unless we're at the end (the while condition).
// Same as horizontalTab but moves to the previous tabstop instead of the next.
// With origin mode enabled, our leftmost limit is the left margin.
// If we're already at the edge of the screen, then we're done.
// Move the cursor left
// Clear tab stops.
// Set a tab stop on the current cursor.
// TODO: test
// TODO: test
// Move the cursor to the next line in the scrolling region, possibly scrolling.
//
// If the cursor is outside of the scrolling region: move the cursor one line
// down if it is not on the bottom-most line of the screen.
//
// If the cursor is inside the scrolling region:
//   If the cursor is on the bottom-most line of the scrolling region:
//     invoke scroll up with amount=1
//   If the cursor is not on the bottom-most line of the scrolling region:
//     move the cursor one line down
//
// This unsets the pending wrap state without wrapping.
// Unset pending wrap state
// We handle our cursor semantic prompt state AFTER doing the
// scrolling, because we may need to apply to new rows.
// Always reset any semantic content clear-eol state.
//
// The specification is not clear what "end-of-line" means. If we
// discover that there are more scenarios we should be unsetting
// this we should document and test it.
// If we aren't clearing our state at EOL and we're not output,
// then we mark the new row as a prompt continuation. This is
// to work around shells that don't send OSC 133 k=s sequences
// for continuations.
//
// This can be a false positive if the shell changes content
// type later and outputs something. We handle that in the
// semanticPrompt function.
// This should never be set in the output mode.
// Outside of the scroll region we move the cursor one line down.
// We only move down if we're not already at the bottom of
// the screen.
// If the cursor is inside the scrolling region and on the bottom-most
// line, then we scroll up. If our scrolling region is the full screen
// we create scrollback.
// Scrolling dirties the images because it updates their placements pins.
// If our scrolling region is at the top, we create scrollback.
// Slow path for left and right scrolling region margins.
// PERF(mitchellh): If we have an SGR background set then
// we need to preserve that background in our erased rows.
// scrollUp does that but eraseRowBounded below does not.
// However, scrollUp is WAY slower. We should optimize this
// case to work in the eraseRowBounded codepath and remove
// this check.
// Otherwise use a fast path function from PageList to efficiently
// scroll the contents of the scrolling region.
// Preserve old cursor just for assertions
// eraseRow and eraseRowBounded will end up moving the cursor pin
// up by 1, so we need to move it back down. A `cursorReload`
// would be better option but this is more efficient and this is
// a super hot path so we do this instead.
// The operations above can prune our cursor style so we need to
// update. This should never fail because the above can only FREE
// memory.
// Increase cursor by 1, maximum to bottom of scroll region
// Move the cursor to the previous line in the scrolling region, possibly
// scrolling.
//
// If the cursor is outside of the scrolling region, move the cursor one
// line up if it is not on the top-most line of the screen.
//
// If the cursor is inside the scrolling region:
//
//   * If the cursor is on the top-most line of the scrolling region:
//     invoke scroll down with amount=1
//   * If the cursor is not on the top-most line of the scrolling region:
//     move the cursor one line up
// Set Cursor Position. Move cursor to the position indicated
// by row and column (1-indexed). If column is 0, it is adjusted to 1.
// If column is greater than the right-most column it is adjusted to
// the right-most column. If row is 0, it is adjusted to 1. If row is
// greater than the bottom-most row it is adjusted to the bottom-most
// row.
// If cursor origin mode is set the cursor row will be moved relative to
// the top margin row and adjusted to be above or at bottom-most row in
// the current scroll region.
//
// If origin mode is set and left and right margin mode is set the cursor
// will be moved relative to the left margin column and adjusted to be on
// or left of the right margin column.
// Unset pending wrap state
// Calculate our new x/y
// If the y is unchanged then this is fast pointer math
// If everything changed we do an absolute change which is slightly slower
// log.info("set cursor position: col={} row={}", .{ self.screens.active.cursor.x, self.screens.active.cursor.y });
// Set Top and Bottom Margins If bottom is not specified, 0 or bigger than
// the number of the bottom-most row, it is adjusted to the number of the
// bottom most row.
//
// If top < bottom set the top and bottom row of the scroll region according
// to top and bottom and move the cursor to the top-left cell of the display
// (when in cursor origin mode is set to the top-left cell of the scroll region).
//
// Otherwise: Set the top and bottom row of the scroll region to the top-most
// and bottom-most line of the screen.
//
// Top and bottom are 1-indexed.
// DECSLRM
// We must have this mode enabled to do anything
// Scroll the text down by one row.
// Preserve our x/y to restore.
// Move to the top of the scroll region
// Removes amount lines from the top of the scroll region. The remaining lines
// to the bottom margin are shifted up and space from the bottom margin up
// is filled with empty lines.
//
// The new lines are created according to the current SGR state.
//
// Does not change the (absolute) cursor position.
// Preserve our x/y to restore.
// If our scroll region is at the top and we have no left/right
// margins then we move the scrolled out text into the scrollback.
// Scrolling dirties the images because it updates their placements pins.
// Clamp count to the scroll region height.
// TODO: Create an optimized version that can scroll N times
// This isn't critical because in most cases, scrollUp is used
// with count=1, but it's still a big optimization opportunity.
// Move our cursor to the bottom of the scroll region so we can
// use the cursorScrollAbove function to create scrollback
// Move to the top of the scroll region
// Options for scrolling the viewport of the terminal grid.
// Scroll to the top of the scrollback
// Scroll to the bottom, i.e. the top of the active area
// Scroll by some delta amount, up is negative.
// Scroll the viewport of the terminal grid.
// To be called before shifting a row (as in insertLines and deleteLines)
//
// Takes care of boundary conditions such as potentially split wide chars
// across scrolling region boundaries and orphaned spacer heads at line
// ends.
// If our scrolling region includes the rightmost column then we
// need to turn any spacer heads in to normal empty cells, since
// once we move them they no longer correspond with soft-wrapped
// wide characters.
//
// If it contains either of the 2 leftmost columns, then the wide
// characters in the first column which may be associated with a
// spacer head will be either moved or cleared, so we also need
// to turn the spacer heads in to empty cells in that case.
// If the leftmost or rightmost cells of our scrolling region
// are parts of wide chars, we need to clear the cells' contents
// since they'd be split by the move.
// TODO(qwerasd): `insertLines` and `deleteLines` are 99% identical,
// the majority of their logic can (and should) be abstracted in to
// a single shared helper function, probably on `Screen` not here.
// I'm just too lazy to do that rn :p
// Insert amount lines at the current cursor row. The contents of the line
// at the current cursor row and below (to the bottom-most line in the
// scrolling region) are shifted down by amount lines. The contents of the
// amount bottom-most lines in the scroll region are lost.
//
// This unsets the pending wrap state without wrapping. If the current cursor
// position is outside of the current scroll region it does nothing.
//
// If amount is greater than the remaining number of lines in the scrolling
// region it is adjusted down (still allowing for scrolling out every remaining
// line in the scrolling region)
//
// In left and right margin mode the margins are respected; lines are only
// scrolled in the scroll region.
//
// All cleared space is colored according to the current SGR state.
//
// Moves the cursor to the left margin.
// Rare, but happens
// If the cursor is outside the scroll region we do nothing.
// Scrolling dirties the images because it updates their placements pins.
// At the end we need to return the cursor to the row it started on.
// Always unset pending wrap
// We have a slower path if we have left or right scroll margins.
// Remaining rows from our cursor to the bottom of the scroll region.
// We can only insert lines up to our remaining lines in the scroll
// region. So we take whichever is smaller.
// Create a new tracked pin which we'll use to navigate the page list
// so that if we need to adjust capacity it will be properly tracked.
// This error scenario means that our GPA is OOM. This is not a
// situation we can gracefully handle. We can't just ignore insertLines
// because it'll result in a corrupted screen. Ideally in the future
// we flag the state as broken and show an error message to the user.
// For now, we panic.
// Our current y position relative to the cursor
// Traverse from the bottom up
// If this is one of the lines we need to shift, do so
// If our scrolling region is full width, then we unset wrap.
// If our page doesn't match, then we need to do a copy from
// one page to another. This is the slow path.
// Adjust our page capacity to make
// room for we didn't have space for
// Rehash the sets
// Increase style memory
// Increase string memory
// Increase hyperlink memory
// Increase grapheme memory
// System OOM. We have no way to recover from this
// currently. We should probably change insertLines
// to raise an error here.
// The page can't accommodate the managed memory required
// for this operation. We previously just corrupted
// memory here so a crash is better. The right long
// term solution is to allocate a new page here
// move this row to the new page, and start over.
// Continue the loop to try handling this row again.
// Swap the src/dst cells. This ensures that our dst gets the
// proper shifted rows and src gets non-garbage cell data that
// we can clear.
// Ensure what we did didn't corrupt the page
// Left/right scroll margins we have to
// copy cells, which is much slower...
// Clear the cells for this row, it has been shifted.
// Mark the row as dirty
// We have successfully processed a line.
// Move our pin up to the next row.
// Removes amount lines from the current cursor row down. The remaining lines
// to the bottom margin are shifted up and space from the bottom margin up is
// filled with empty lines.
//
// If the current cursor position is outside of the current scroll region it
// does nothing. If amount is greater than the remaining number of lines in the
// scrolling region it is adjusted down.
//
// In left and right margin mode the margins are respected; lines are only
// scrolled in the scroll region.
//
// If the cell movement splits a multi cell character that character cleared,
// by replacing it by spaces, keeping its current attributes. All other
// cleared space is colored according to the current SGR state.
//
// Moves the cursor to the left margin.
// Rare, but happens
// If the cursor is outside the scroll region we do nothing.
// Scrolling dirties the images because it updates their placements pins.
// At the end we need to return the cursor to the row it started on.
// Always unset pending wrap
// We have a slower path if we have left or right scroll margins.
// Remaining rows from our cursor to the bottom of the scroll region.
// We can only insert lines up to our remaining lines in the scroll
// region. So we take whichever is smaller.
// Create a new tracked pin which we'll use to navigate the page list
// so that if we need to adjust capacity it will be properly tracked.
// See insertLines
// Our current y position relative to the cursor
// Traverse from the top down
// If this is one of the lines we need to shift, do so
// If our scrolling region is full width, then we unset wrap.
// If our page doesn't match, then we need to do a copy from
// one page to another. This is the slow path.
// Adjust our page capacity to make
// room for we didn't have space for
// Rehash the sets
// Increase style memory
// Increase string memory
// Increase hyperlink memory
// Increase grapheme memory
// See insertLines
// Continue the loop to try handling this row again.
// Swap the src/dst cells. This ensures that our dst gets the
// proper shifted rows and src gets non-garbage cell data that
// we can clear.
// Ensure what we did didn't corrupt the page
// Left/right scroll margins we have to
// copy cells, which is much slower...
// Clear the cells for this row, it's from out of bounds.
// Mark the row as dirty
// We have successfully processed a line.
// Move our pin down to the next row.
// Inserts spaces at current cursor position moving existing cell contents
// to the right. The contents of the count right-most columns in the scroll
// region are lost. The cursor position is not changed.
//
// This unsets the pending wrap state without wrapping.
//
// The inserted cells are colored according to the current SGR state.
// Unset pending wrap state without wrapping. Note: this purposely
// happens BEFORE the scroll region check below, because that's what
// xterm does.
// If our cursor is outside the margins then do nothing. We DO reset
// wrap state still so this must remain below the above logic.
// If our count is larger than the remaining amount, we just erase right.
// We only do this if we can erase the entire line (no right margin).
// if (right_limit == self.cols and
//     count > right_limit - self.screens.active.cursor.x)
// {
//     self.eraseLine(.right, false);
//     return;
// }
// left is just the cursor position but as a multi-pointer
// If our X is a wide spacer tail then we need to erase the
// previous cell too so we don't split a multi-cell character.
// Remaining cols from our cursor to the right margin.
// We can only insert blanks up to our remaining cols
// This is the amount of space at the right of the scroll region
// that will NOT be blank, so we need to shift the correct cols right.
// "scroll_amount" is the number of such cols.
// If our last cell we're shifting is wide, then we need to clear
// it to be empty so we don't split the multi-cell char.
// We work backwards so we don't overwrite data.
// Insert blanks. The blanks preserve the background color.
// Our row is always dirty
// Removes amount characters from the current cursor position to the right.
// The remaining characters are shifted to the left and space from the right
// margin is filled with spaces.
//
// If amount is greater than the remaining number of characters in the
// scrolling region, it is adjusted down.
//
// Does not change the cursor position.
// If our cursor is outside the margins then do nothing. We DO reset
// wrap state still so this must remain below the above logic.
// left is just the cursor position but as a multi-pointer
// Remaining cols from our cursor to the right margin.
// We can only insert blanks up to our remaining cols
// This is the amount of space at the right of the scroll region
// that will NOT be blank, so we need to shift the correct cols right.
// "scroll_amount" is the number of such cols.
// Insert blanks. The blanks preserve the background color.
// Our row's soft-wrap is always reset.
// Our row is always dirty
// If our last cell is a wide char then we need to also clear the
// cell beyond it since we can't just split a wide char.
// Handle any boundary conditions on the edges of the erased area.
//
// TODO(qwerasd): This isn't actually correct if you take in to account
// protected modes. We need to figure out how to make `clearCells` or at
// least `clearUnprotectedCells` handle boundary conditions...
// Reset our row's soft-wrap.
// Mark our cursor row as dirty
// Clear the cells
// If we never had a protection mode, then we can assume no cells
// are protected and go with the fast path. If the last protection
// mode was not ISO we also always ignore protection attributes.
// Erase the line.
// Get our start/end positions depending on mode.
// If our X is a wide spacer tail then we need to erase the
// previous cell too so we don't split a multi-cell character.
// Reset our row's soft-wrap.
// If our x is a wide char we need to delete the tail too.
// Note that it seems like complete should reset the soft-wrap
// state of the line but in xterm it does not.
// All modes will clear the pending wrap state and we know we have
// a valid mode at this point.
// We always mark our row as dirty
// Start of our cells
// We respect protected attributes if explicitly requested (probably
// a DECSEL sequence) or if our last protected mode was ISO even if its
// not currently set.
// If we're not respecting protected attributes, we can use a fast-path
// to fill the entire line.
// Erase the display.
// We respect protected attributes if explicitly requested (probably
// a DECSEL sequence) or if our last protected mode was ISO even if its
// not currently set.
// Unsets pending wrap state
// Clear all Kitty graphics state for this screen
// If we're on the primary screen and our last non-empty row is
// a prompt, then we do a scroll_complete instead. This is a
// heuristic to get the generally desirable behavior that ^L
// at a prompt scrolls the screen contents prior to clearing.
// Most shells send `ESC [ H ESC [ 2 J` so we can't just check
// our current cursor position. See #905
// Go from the bottom of the active up and see if we're
// at a prompt.
// If we're at a prompt or input area, then we are at a prompt.
// If we have command output, then we're most certainly not
// at a prompt.
// If we fail, we just fall back to doing a normal clear
// so we don't worry about the error.
// All active area
// Unsets pending wrap state
// Clear all Kitty graphics state for this screen
// Cleared screen dirty bit
// All lines to the right (including the cursor)
// All lines below
// Unsets pending wrap state. Should be done by eraseLine.
// Erase to the left (including the cursor)
// All lines above
// Unsets pending wrap state
// Resets all margins and fills the whole screen with the character 'E'
//
// Sets the cursor to the top left corner.
// Clear our stylistic attributes. This is the only thing that can
// fail so we do it first so we can undo it.
// Reset margins, also sets cursor to top-left
// Origin mode is disabled
// Move our cursor to the top-left
// Use clearRows instead of eraseDisplay because we must NOT respect
// protected attributes here.
// Fill with Es by moving the cursor but reset it after.
// DECALN does not respect protected state. Verified with xterm.
// If we have a ref-counted style, increase
// We messed with the page so assert its integrity here.
// Reset the cursor to the top-left
// Execute a kitty graphics command. The buf is used to populate with
// the response that should be sent as an APC sequence. The response will
// be a full, valid APC sequence.
//
// If an error occurs, the caller should response to the pty that a
// an error occurred otherwise the behavior of the graphics protocol is
// undefined.
// Set a style attribute.
// Print the active attributes as a string. This is used to respond to DECRQSS
// requests.
//
// Boolean attributes are printed first, followed by foreground color, then
// background color. Each attribute is separated by a semicolon.
// The SGR response always starts with a 0. See https://vt100.net/docs/vt510-rm/DECRPSS
// The modes for DECCOLM.
// DECCOLM changes the terminal width between 80 and 132 columns. This
// function call will do NOTHING unless `setDeccolmSupported` has been
// called with "true".
//
// This breaks the expectation around modern terminals that they resize
// with the window. This will fix the grid at either 80 or 132 columns.
// The rows will continue to be variable.
// If DEC mode 40 isn't enabled, then this is ignored. We also make
// sure that we don't have deccolm set because we want to fully ignore
// set mode.
// Enable it
// Resize to the requested size
// Erase our display and move our cursor.
// Resize the underlying terminal.
// If our cols/rows didn't change then we're done
// Resize our tabstops
// Resize primary screen, which supports reflow
// Alternate screen, if it exists, doesn't reflow
// Whenever we resize we just mark it as a screen clear
// Set our size
// Reset the scrolling region
// Set the pwd for the terminal.
// Returns the pwd for the terminal, if any. The memory is owned by the
// Terminal and is not copied. It is safe until a reset or setPwd.
// Switch to the given screen type (alternate or primary).
//
// This does NOT handle behaviors such as clearing the screen,
// copying the cursor, etc. This should be handled by downstream
// callers.
//
// After calling this function, the `self.screen` field will point
// to the current screen, and the returned value will be the previous
// screen. If the return value is null, then the screen was not
// switched because it was already the active screen.
//
// Note: This is written in a generic way so that we can support
// more than two screens in the future if needed. There isn't
// currently a spec for this, but it is something I think might
// be useful in the future.
// If we're already on the requested screen we do nothing.
// We always end hyperlink state when switching screens.
// We need to do this on the original screen.
// Switch the screens/
// Inherit our Kitty image storage limit from the primary
// screen if we have to initialize.
// The new screen should not have any hyperlinks set
// Bring our charset state with us
// Clear our selection
// Mark kitty images as dirty so they redraw. Without this set
// the images will remain where they were (the dirty bit on
// the screen only tracks the terminal grid, not the images).
// Mark our terminal as dirty to redraw the grid.
// Finalize the switch
// Switch screen via a mode switch (e.g. mode 47, 1047, 1049).
// This is a much more opinionated operation than `switchScreen`
// since it also handles the behaviors of the specific mode,
// such as clearing the screen, saving/restoring the cursor,
// etc.
//
// This should be used for legacy compatibility with VT protocols,
// but more modern usage should use `switchScreen` instead and handle
// details like clearing the screen, cursor saving, etc. manually.
// The behavior in this function is completely based on reading
// the xterm source, specifically "charproc.c" for
// `srm_ALTBUF`, `srm_OPT_ALTBUF`, and `srm_OPT_ALTBUF_CURSOR`.
// We shouldn't touch anything in here without adding a unit
// test AND verifying the behavior with xterm.
// If we're disabling 1047 and we're on alt screen then
// we clear the screen.
// 1049 unconditionally saves the cursor on enabling, even
// if we're already on the alternate screen.
// Switch screens first to whatever we're going to.
// For these modes, we need to copy the cursor. We only copy
// the cursor if the screen actually changed, otherwise the
// cursor is already copied. The cursor is copied regardless
// of destination screen.
// Mode 1049 restores cursor on the primary screen when
// we disable it.
// When we enter alt screen with 1049, we always copy the
// cursor from the primary screen (if we weren't already
// on it).
// Modal screen changes. These map to the literal terminal
// modes to enable or disable alternate screen modes. They each
// have subtle behaviors so we define them as an enum here.
// Legacy alternate screen mode. This goes to the alternate
// screen or primary screen and only copies the cursor. The
// screen is not erased.
// Alternate screen mode where the alternate screen is cleared
// on exit. The primary screen is never cleared. The cursor is
// copied.
// Save primary screen cursor, switch to alternate screen,
// and clear the alternate screen on entry. On exit,
// do not clear the screen, and restore the cursor on the
// primary screen.
// Return the current string value of the terminal. Newlines are
// encoded as "\n". This omits any formatting such as fg/bg.
//
// The caller must free the string.
// Same as plainString, but respects row wrap state when building the string.
// Full reset.
//
// This will attempt to free the existing screen memory but if that fails
// this will reuse the existing memory. In the latter case, memory may
// be wasted (since its unused) but it isn't leaked.
// Ensure we're back on primary screen
// Reset our screens
// Rest our basic state
// Always mark dirty so we redraw everything
// Returns true if the point is dirty, used for testing.
// Clear all dirty bits. Testing only.
// Basic grid writing
// The first row should be dirty
// Basic grid writing
// Old row is dirty because cursor moved from there
// Basic grid writing
// Get our initial grapheme capacity.
// Print glitch text until our capacity changes
// We're testing to make sure that grapheme capacity gets increased.
// This used to crash the terminal. This is not allowed so we should
// just ignore it.
// Should not be dirty since we changed nothing.
// https://github.com/mitchellh/ghostty/issues/1400
// This would crash for issue 1400. So the assertion here is
// that we simply do not crash.
// Our first row just had a spacer head added which does not affect
// rendering so only the place where the wide char was printed
// should be marked.
// BUT old row is dirty because cursor moved from there
// This prints a space so we should be dirty.
// verify we have styles in our style map
// Go back and overwrite with no style
// verify our style is gone
// verify we have styles in our style map
// Go back and overwrite with no style
// verify our style is gone
// https://github.com/mitchellh/ghostty/issues/289
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have 6 cells taken up
// Assert various properties about our screen to verify
// we have all expected cells.
// Disable grapheme clustering
// Disable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/1482
// We should have 1 narrow cell.
// Assert various properties about our screen to verify
// we have all expected cells.
// Disable grapheme clustering
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/289
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have 2 cells taken up. It is one character but "wide".
// Row should be dirty
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// This is: "#︎" (number sign with text presentation selector)
// VS15 should combine with the base character into a single grapheme cluster,
// taking 1 cell (narrow character).
// Row should be dirty
// The base emoji should be in cell 0 with the skin tone as a grapheme
// Enable grapheme clustering
// This is: "#️" (number sign with emoji presentation selector)
// VS16 should combine with the base character into a single grapheme cluster,
// taking 2 cells (wide character).
// Row should be dirty
// The base emoji should be in cell 0 with the skin tone as a grapheme
// Enable grapheme clustering
// This is: "👋🏿" (waving hand with dark skin tone)
// The skin tone should combine with the base emoji into a single grapheme cluster,
// taking 2 cells (wide character).
// Row should be dirty
// The base emoji should be in cell 0 with the skin tone as a grapheme
// Enable grapheme clustering
// This is: "🏿" (which may not render correctly in your editor!)
// We should have 4 cells taken up. Importantly, the skin tone
// should not join with the quotes.
// Row should be dirty
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/289
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have 2 cells taken up. It is one character but "wide".
// Enable grapheme clustering
// We should have 2 cells taken up. It is one character but "wide".
// VS15 should send us back a cell since our char is no longer wide.
// Enable grapheme clustering
// Character takes up one cell
// Enable grapheme clustering
// We should have 2 cells taken up. It is one character but "wide".
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// We should have 2 cells taken up. It is one character but "wide".
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// We only move one because we're in a pending wrap state.
// VS15 should clear the pending wrap state
// Enable grapheme clustering
// Enable grapheme clustering
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/1482
// We should have 1 cells taken up, and narrow.
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/1482
// We should have 2 cells taken up, from two separate narrow characters.
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/1482
// We should have 1 cells taken up, and narrow.
// Assert various properties about our screen to verify
// we have all expected cells.
// Enable grapheme clustering
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/289
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have 2 cells taken up. It is one character but "wide".
// We should have one cell with graphemes
// Move back and overwrite wide
// Enable grapheme clustering
// https://github.com/mitchellh/ghostty/issues/289
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have 2 cells taken up. It is one character but "wide".
// We should have one cell with graphemes
// Move back and overwrite wide
// Make sure we're not at cursor.x == 0 for the next char.
// U+0600 ARABIC NUMBER SIGN (Prepend)
// We should have 3 cells taken up, each narrow. Note that this is
// **incorrect** grapheme break behavior, since a Prepend code point should
// not break with the one following it per UAX #29 GB9b. However, as an
// optimization we assume a grapheme break when c <= 255, and note that
// this deviation only affects these very uncommon scenarios (e.g. the
// Arabic number sign should precede Arabic-script digits).
// This is what we'd expect if we did break correctly:
// try testing.expectEqual(@as(usize, 2), t.screens.active.cursor.x);
// Assert various properties about our screen to verify
// we have all expected cells.
// This is what we'd expect if we did break correctly:
// try testing.expect(cell.hasGrapheme());
// try testing.expectEqualSlices(u21, &.{'1'}, list_cell.node.data.lookupGrapheme(cell).?);
// This is what we'd expect if we did break correctly:
// try testing.expectEqual(@as(u21, 0), cell.content.codepoint);
// Basic grid writing
// Make newlines so we create scrollback
// 3 pushes hello off the screen
// Scroll to the top
// Type
// G1 should have no effect
// No dirty to configure charset
// Basic grid writing
// G1 should have no effect
// No dirty to configure charset
// Basic grid writing
// Invokecharset but should not mark dirty on its own
// Basic grid writing
// Basic grid writing
// Mark our prompt.
// Should not make anything dirty on its own.
// Write and wrap
// This puts our cursor at the end and there is NO SPACE for a
// wide character.
// Make sure we printed nothing
// Should not be dirty since we didn't modify anything
// This puts our cursor at the end and there is NO SPACE for a
// wide character.
// Should not be dirty since we didn't modify anything
// This puts our cursor at the end and there is NO SPACE for a
// wide character.
// Should not be dirty since we didn't modify anything
// Writing our X on the first line should mark only that line dirty.
// Writing our Y should wrap. It marks both rows dirty because the
// cursor moved.
// Both rows dirty because the cursor moved
// Setup our hyperlink and print
// Verify all our cells have a hyperlink
// Setup our hyperlink and print
// Verify all our cells have a hyperlink
// Setup our hyperlink and print
// Verify all our cells have a hyperlink
// Setup our hyperlink and print
// Verify all our cells have a hyperlink
// Setup our hyperlink and print
// Verify all our cells have a hyperlink
// Print and CR.
// CR should not mark row dirty because it doesn't change rendering.
// LF marks row dirty due to cursor movement
// Basic grid writing
// Basic grid writing
// Basic grid writing
// BS
// HT
// HT
// HT at the end
// Edge of screen
// HT
// HT
// HT
// Probably outdated, but dates back to the original terminal implementation.
// Setting it to 0 should keep it zero (1 based)
// Should clamp to size
// Should reset pending wrap
// Origin mode
// No change without a scroll region
// Set the scroll region
// Mark the rows we moved as dirty.
// This is dirty because the cursor moves from this row
// For the line being deleted, create a refcounted style
// verify we have styles in our style map
// verify we have no styles in our style map
// Fill up the first page minus 3 rows
// Add content that will cross a page boundary
// Verify we now have a second page
// Initial value
// Move to row 2
// Insert two lines
// This should do nothing
// Initial value
// Initial value
// Move to row 2
// Insert a bunch of  lines
// Disable grapheme clustering
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// Viewport should have moved. Our entire page should've scrolled!
// The viewport moving will cause our render state to make the full
// frame as dirty.
// This is dirty because the cursor moves from this row
// First row gets some hyperlinks
// Second row preserves hyperlink where we didn't scroll
// This is dirty because the cursor moves from this row
// This is dirty because the cursor moves from this row
// When in primary screen with full-width scroll region at top,
// scrollUp (CSI S) should push lines into scrollback like xterm.
// Fill the screen with content
// Scroll up by 1, which should push "AAAAA" into scrollback
// The cursor row (new empty row) should be dirty
// The active screen should now show BBBBB through EEEEE plus one blank line
// Now scroll to the top to see scrollback - AAAAA should be there
// Should see AAAAA in scrollback
// When max_scrollback is 0, scrollUp should still work but not retain history
// Active screen should show scrolled content
// Scroll to top - should be same as active since no scrollback
// When max_scrollback is 0 and top margin is set, should use deleteLines path
// Set top margin (not at row 0)
// First row preserved, rest scrolled
// When max_scrollback is 0 with left/right margins, uses deleteLines path
// Set left/right margins (columns 2-6, 1-indexed = indices 1-5)
// cols 1-5 scroll, col 0 and cols 6+ preserved
// This is dirty because the cursor moves from this row
// First row preserves hyperlink where we didn't scroll
// Second row gets some hyperlinks
// verify we have styles in our style map
// verify we have no styles in our style map
// This is a test for a bug: https://github.com/ghostty-org/ghostty/issues/2817
// To explain the setup:
// (1) We need our wide characters starting on an even (1-based) column.
// (2) We need our cursor to be in the middle somewhere.
// (3) We need our count to be less than our cursor X and on a split cell.
// The bug was that we split the wrong cell boundaries.
// Initial value
// Initial value
// Set our scroll region
// Fill up the first page minus 3 rows
// Add content that will cross a page boundary
// Verify we now have a second page
// Initial value
// We should be
// Initial value
// We should be
// try testing.expectEqual(@as(usize, 0), t.screens.active.cursor.x);
// try testing.expectEqual(@as(usize, 2), t.screens.active.cursor.y);
// Initial value
// We should be
// try testing.expectEqual(@as(usize, 0), t.screens.active.cursor.x);
// try testing.expectEqual(@as(usize, 2), t.screens.active.cursor.y);
// Initial value
// Initial value
// +-----+
// |AAAAA| < Wrapped
// |BBBB*| < Wrapped     (continued)
// |WWCCC| < Non-wrapped (continued)
// +-----+
// where * represents a spacer head cell
// and WW is the wide character.
// Delete the top line
// +-----+
// |BBBB | < Non-wrapped
// |WWCCC| < Non-wrapped
// |     | < Non-wrapped
// +-----+
// This should convert the spacer head to
// a regular empty cell, and un-set wrap.
// Initial value
// +-----+
// |AAAAA| < Wrapped
// |BBBB*| < Wrapped     (continued)
// |WWCCC| < Non-wrapped (continued)
// +-----+
// where * represents a spacer head cell
// and WW is the wide character.
// Delete the top line
//    ###  <- scrolling region
// +-----+
// |AABB | < Wrapped
// |BBCCC| < Wrapped     (continued)
// |WW   | < Non-wrapped (continued)
// +-----+
// This should convert the spacer head to
// a regular empty cell, but due to the
// left scrolling margin, wrap state should
// remain.
// Initial value
// +-----+
// |AAAAA| < Wrapped
// |BBBB*| < Wrapped     (continued)
// |WWCCC| < Non-wrapped (continued)
// +-----+
// where * represents a spacer head cell
// and WW is the wide character.
// Delete the top line
//  ####   <- scrolling region
// +-----+
// |BBBBA| < Wrapped
// |WWCC | < Wrapped     (continued)
// |    C| < Non-wrapped (continued)
// +-----+
// This should convert the spacer head to
// a regular empty cell, but due to the
// right scrolling margin, wrap state should
// remain.
// Initial value
// +-----+
// |AAAAA| < Wrapped
// |BBBB*| < Wrapped     (continued)
// |WWCCC| < Non-wrapped (continued)
// +-----+
// where * represents a spacer head cell
// and WW is the wide character.
// Delete the top line
//    ##   <- scrolling region
// +-----+
// |AABBA| < Wrapped
// |BBCC*| < Wrapped     (continued)
// |WW  C| < Non-wrapped (continued)
// +-----+
// Because there is both a left scrolling
// margin > 1 and a right scrolling margin
// the spacer head should remain, and the
// wrap state should be untouched.
// Initial value
// +-----+
// |AAAAA| < Wrapped
// |BBBB*| < Wrapped     (continued)
// |WWCCC| < Non-wrapped (continued)
// +-----+
// where * represents a spacer head cell
// and WW is the wide character.
// Delete the top line
//   ###   <- scrolling region
// +-----+
// |ABBBA| < Wrapped
// |B CC | < Wrapped     (continued)
// |    C| < Non-wrapped (continued)
// +-----+
// Because the left margin is 1, the wide
// char is split, and therefore removed,
// along with the spacer head - however,
// wrap state should be untouched.
// Initial value
// +-----+
// |AAAAA|
// |WWBWW|
// +-----+
// where WW represents a wide character
// Delete the top line
//   ###   <- scrolling region
// +-----+
// |A B A|
// |     |
// +-----+
// The two wide chars, because they're
// split by the edge of the scrolling
// region, get removed.
// This should do nothing
// verify we have no styles in our style map
// verify we have no styles in our style map
// Initial value
// Initial value
// Initial value
// Add protected mode. A previous version of DECALN accidentally preserved
// protected mode which left dangling managed memory.
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// NOTE: this is not verified with conformance tests, so these
// tests might actually be verifying wrong behavior.
// NOTE: this is not verified with conformance tests, so these
// tests might actually be verifying wrong behavior.
// NOTE: this is not verified with conformance tests, so these
// tests might actually be verifying wrong behavior.
// Disable grapheme clustering
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have one cell with graphemes
// We should have no graphemes
// Enable grapheme clustering
// This is: 👨‍👩‍👧 (which may or may not render correctly)
// We should have one cell with graphemes
// We should have no graphemes
// osc "8;;http://example.com"
// printf "link"
// printf "\r"
// csi "3@"
// echo
//
// link should be preserved, blanks should not be linked
// Verify all our cells have a hyperlink
// EXPLANATION(qwerasd):
//
// There are 3 or 4 boundaries to be concerned with in deleteChars,
// depending on how you count them. Consider the following terminal:
//
//   +--------+
// 0 |.ABCDEF.|
//   : ^      : (^ = cursor)
//   +--------+
//
// if we DCH 3 we get
//
//   +--------+
// 0 |.DEF....|
//   +--------+
//
// The boundaries exist at the following points then:
//
//   +--------+
// 0 |.ABCDEF.|
//   :11 22 33:
//   +--------+
//
// I'm counting 2 for double since it's both the end of the deleted
// content and the start of the content that is shifted in to place.
//
// Now consider wide characters (represented as `WW`) at these boundaries:
//
//   +--------+
// 0 |WWaWWbWW|
//   : ^      : (^ = cursor)
//   : ^^^    : (^ = deleted by DCH 3)
//   +--------+
//
// -> DCH 3
// -> The first 2 wide characters are split & destroyed (verified in xterm)
//
//   +--------+
// 0 |..bWW...|
//   +--------+
// EXPLANATION(qwerasd):
// (cont. from "Terminal: deleteChars wide char boundary conditions")
//
// Additionally consider soft-wrapped wide chars (`H` = spacer head):
//
//   +--------+
// 0 |.......H…
// 1 …WWabcdeH…
//   : ^      : (^ = cursor)
//   : ^^^    : (^ = deleted by DCH 3)
// 2 …WW......|
//   +--------+
//
// -> DCH 3
// -> First wide character split and destroyed, including spacer head,
//    second spacer head removed (verified in xterm).
// -> Wrap state of row reset
//
//   +--------+
// 0 |........|
// 1 |.cde....|
// 2 |WW......|
//   +--------+
//
// scroll region
//    VVVVVV
//  +-######-+
//  |.abcdeWW|
//  : ^      : (^ = cursor)
//  +--------+
//
// DCH 1
// NOTE: This behavior is slightly inconsistent with xterm. xterm
// _visually_ splits the wide character (half the wide character shows
// up in col 6 and half in col 8). In all other wide char split scenarios,
// xterm clears the cell. Therefore, we've chosen to clear the cell here.
// Given we have space, we also could actually preserve it, but I haven't
// yet found a terminal that behaves that way. We should be open to
// revisiting this behavior but for now we're going with the simpler
// impl.
// Tests that restoreCursor falls back to default style when
// manualStyleUpdate fails with OutOfSpace (can't split a 1-row page
// and styles are at max capacity).
// Use a single row so the page can't be split
// Set a style and save the cursor
// Clear the style
// Fill the style map to max capacity
// Fill all style slots using the StyleSet's layout capacity which accounts
// for the load factor. The capacity in the layout is the actual max number
// of items that can be stored.
// Restore cursor - should fall back to default style since page
// can't be split (1 row) and styles are at max capacity
// The style should be reset to default because OutOfSpace occurred
// Set our cursur
// Erasing the display may detect that our style is no longer in use
// and prune our style, which we don't want because its still our
// active cursor.
// Prompt
// Start input but end it on EOL
// Write some output
// Prompt
// Start input but end it on EOL
// Write some output
// This tests the Fish shell workaround: when in prompt mode and we get
// a newline, assume the new row is a prompt continuation (since Fish
// doesn't emit OSC133 k=s markers for continuation lines).
// Start a prompt
// Verify first row is marked as prompt
// Now do a linefeed while still in prompt mode
// The new row should automatically be marked as prompt continuation
// The cursor semantic content should still be prompt
// Input mode should NOT trigger prompt continuation on newline
// (only prompt mode does, not input mode)
// Start a prompt then switch to input
// Linefeed while in input mode
// The new row should be marked as prompt continuation
// Our cursor should still be in input
// Output mode should NOT trigger prompt continuation
// Complete prompt cycle: prompt -> input -> output
// Linefeed while in output mode
// The new row should NOT be marked as a prompt
// This tests the second Fish heuristic: when Fish emits a newline
// then immediately sends OSC133C (start output) at column 0, we
// should clear the prompt continuation mark we just set.
// Start a prompt
// Simulate Fish behavior: newline first (which marks next row as prompt)
// Verify the new row is marked as prompt continuation
// Now Fish sends OSC133C at column 0 (cursor is still at x=0)
// The prompt continuation should be cleared
// If we're not at column 0, we shouldn't clear the prompt mark
// Start a prompt on a row
// Move to a new line and mark it as prompt continuation manually
// Verify the row is marked as prompt continuation
// Now send OSC133C but cursor is NOT at column 0
// The prompt continuation should NOT be cleared (we're not at x=0)
// Multiple newlines should each mark their row as prompt continuation
// Start a prompt
// Multiple newlines
// First row should be prompt
// Second and third rows should be prompt continuation
// Verify default state is none
// OSC 133;A with click_events=1
// OSC 133;A with click_events=0
// Should remain none since click_events=0 doesn't activate anything
// OSC 133;A with cl=m (multiple)
// OSC 133;A with both click_events=1 and cl=m
// click_events should take priority
// OSC 133;A with click_events=0 and cl=v
// Should fall back to cl since click_events is disabled
// OSC 133;A with no click-related options
// Input is also a prompt
// But once we say we're starting output, we're not a prompt
// (cursor is not at x=0, so the Fish heuristic doesn't trigger)
// Still a prompt because this line has a prompt
// Until we know we're at a prompt again
// Secondary screen is never a prompt
// Origin mode should be reset and the cursor should be moved
// https://github.com/mitchellh/ghostty/issues/1607
// Create a tracked pin
// https://github.com/mitchellh/ghostty/issues/272
// This is also tested in depth in screen resize tests but I want to keep
// this test around to ensure we don't regress at multiple layers.
// https://github.com/mitchellh/ghostty/issues/723
// This was found via fuzzing so its highly specific.
// https://github.com/mitchellh/ghostty/issues/1343
// Verify our cursor is still in the same place
// Pending wrap should be reset
// Print on primary screen
// Go to alt screen with mode 47
// Screen should be empty
// Print on alt screen. This should be off center because
// we copy the cursor over from the primary screen
// Go back to primary
// Primary screen should still have the original content
// Go back to alt screen with mode 47
// Screen should retain content
// Color our cursor red
// Go to alt screen with mode 47
// Verify that our style is set
// Set a new style
// Go back to primary
// Verify that our style is still set
// Print on primary screen
// Go to alt screen with mode 47
// Screen should be empty
// Print on alt screen. This should be off center because
// we copy the cursor over from the primary screen
// Go back to primary
// Primary screen should still have the original content
// Go back to alt screen with mode 1047
// Screen should be empty
// Color our cursor red
// Go to alt screen with mode 47
// Verify that our style is set
// Set a new style
// Go back to primary
// Verify that our style is still set
// Print on primary screen
// Go to alt screen with mode 47
// Screen should be empty
// Print on alt screen. This should be off center because
// we copy the cursor over from the primary screen
// Go back to primary
// Primary screen should still have the original content
// Write, our cursor should be restored back.
// Go back to alt screen with mode 1049
// Screen should be empty
//
// --- Original Ghostty Comments End: src/terminal/Terminal.zig

// The primary terminal emulation structure. This represents a single
// "terminal" containing a grid of characters and exposes various operations
// on that grid. This also maintains the scrollback buffer.

import osc
import strings

// Default tabstop interval
const tabstop_interval = 8

// ============================================================
// Terminal struct
// ============================================================

pub struct Terminal {
pub mut:
	// The set of screens behind this terminal (e.g. primary vs alternate).
	screens ScreenSet

	// Whether we're currently writing to the status line (DECSASD and DECSSDT).
	// We don't support a status line currently so we just black hole this
	// data so that it doesn't mess up our main display.
	status_display StatusDisplay = .main

	// Where the tabstops are.
	tabstops Tabstops

	// The size of the terminal.
	rows u16
	cols u16

	// The size of the screen in pixels. This is used for pty events and images.
	width_px  u32
	height_px u32

	// The current scrolling region.
	scrolling_region ScrollingRegion

	// The last reported pwd, if any.
	pwd string

	// The color state for this terminal.
	colors Colors

	// The previous printed character. This is used for the repeat previous
	// char CSI (ESC [ <n> b).
	previous_char ?u32

	// The modes that this terminal currently has active.
	modes ModeState

	// The most recently set mouse shape for the terminal.
	mouse_shape MouseShape = .text

	// These are just a packed set of flags we may set on the terminal.
	flags TerminalFlags
}

// ============================================================
// Nested types
// ============================================================

// The various color configurations a terminal maintains and that can
// be set dynamically via OSC, with defaults usually coming from a
// configuration.
pub struct Colors {
pub mut:
	background DynamicRGB
	foreground DynamicRGB
	cursor     DynamicRGB
	palette    DynamicPalette
}

// colors_default provides the default Colors value.
// DynamicRGB and DynamicPalette are defined in color.v.
pub const colors_default = Colors{
	palette: dynamic_palette_default_val
}

@[aligned: 4]
pub struct RGB {
pub:
	r u8
	g u8
	b u8
}

// This is a set of dirty flags the renderer can use to determine
// what parts of the screen need to be redrawn. It is up to the renderer
// to clear these flags.
//
// This only contains dirty flags for terminal state, not for the screen
// state. The screen state has its own dirty flags.
pub struct Dirty {
mut:
	value u8
}

pub fn Dirty.init(palette bool, reverse_colors bool, clear bool, preedit bool) Dirty {
	return Dirty{
		value: u8(palette) | (u8(reverse_colors) << 1) | (u8(clear) << 2) | (u8(preedit) << 3)
	}
}

pub fn Dirty.from_int(value u8) Dirty {
	return Dirty{
		value: value & 0b1111
	}
}

// Set when the color palette is modified in any way.
pub fn (self Dirty) palette() bool {
	return self.value & 0b0001 != 0
}

pub fn (mut self Dirty) set_palette(value bool) {
	self.set_bit(0b0001, value)
}

// Set when the reverse colors mode is modified.
pub fn (self Dirty) reverse_colors() bool {
	return self.value & 0b0010 != 0
}

pub fn (mut self Dirty) set_reverse_colors(value bool) {
	self.set_bit(0b0010, value)
}

// Screen clear of some kind. This can be due to a screen change,
// erase display, etc.
pub fn (self Dirty) clear() bool {
	return self.value & 0b0100 != 0
}

pub fn (mut self Dirty) set_clear(value bool) {
	self.set_bit(0b0100, value)
}

// Set when the pre-edit is modified.
pub fn (self Dirty) preedit() bool {
	return self.value & 0b1000 != 0
}

pub fn (mut self Dirty) set_preedit(value bool) {
	self.set_bit(0b1000, value)
}

pub fn (self Dirty) int() u8 {
	return self.value
}

fn (mut self Dirty) set_bit(mask u8, enabled bool) {
	if enabled {
		self.value |= mask
	} else {
		self.value &= ~mask
	}
}

// The event types that can be reported for mouse-related activities.
// These are all mutually exclusive (hence in a single enum).
pub enum MouseEvents as u8 {
	none   = 0
	x10    = 1 // 9
	normal = 2 // 1000
	button = 3 // 1002
	any    = 4 // 1003
}

// Returns true if this event sends motion events.
pub fn (self MouseEvents) motion() bool {
	return self == .button || self == .any
}

// The format of mouse events when enabled.
// These are all mutually exclusive (hence in a single enum).
pub enum MouseFormat as u8 {
	x10        = 0
	utf8       = 1 // 1005
	sgr        = 2 // 1006
	urxvt      = 3 // 1015
	sgr_pixels = 4 // 1016
}

// Scrolling region is the area of the screen designated where scrolling
// occurs. When scrolling the screen, only this viewport is scrolled.
pub struct ScrollingRegion {
pub mut:
	// Top and bottom of the scroll region (0-indexed)
	// Precondition: top < bottom
	top    u16
	bottom u16

	// Left/right scroll regions.
	// Precondition: right > left
	// Precondition: right <= cols - 1
	left  u16
	right u16
}

pub struct Options {
pub:
	cols           u16
	rows           u16
	max_scrollback uint  = 10_000
	colors         Colors = terminal.colors_default

	// The default mode state. When the terminal gets a reset, it
	// will revert back to this state.
	// The default mode state includes wraparound (bit 0) and
	// cursor visible (bit 2), matching DEC mode defaults.
	default_modes ModePacked = build_default_modes()
}

pub struct TerminalFlags {
mut:
	value u32 = 1 << 11
}

// This supports a Kitty extension where programs using semantic prompts
// (OSC133) can annotate prompt redraw behavior.
pub fn (self TerminalFlags) shell_redraws_prompt() osc.Redraw {
	return unsafe { osc.Redraw(u8(self.value & 0b11)) }
}

pub fn (mut self TerminalFlags) set_shell_redraws_prompt(value osc.Redraw) {
	self.set_field(0b11, u32(value))
}

// This is set via ESC[4;2m.
pub fn (self TerminalFlags) modify_other_keys_2() bool {
	return self.value & (1 << 2) != 0
}

pub fn (mut self TerminalFlags) set_modify_other_keys_2(value bool) {
	self.set_bit(1 << 2, value)
}

pub fn (self TerminalFlags) mouse_event() MouseEvents {
	return unsafe { MouseEvents(u8((self.value >> 3) & 0b111)) }
}

pub fn (mut self TerminalFlags) set_mouse_event(value MouseEvents) {
	self.set_field(0b111 << 3, u32(value) << 3)
}

pub fn (self TerminalFlags) mouse_format() MouseFormat {
	return unsafe { MouseFormat(u8((self.value >> 6) & 0b111)) }
}

pub fn (mut self TerminalFlags) set_mouse_format(value MouseFormat) {
	self.set_field(0b111 << 6, u32(value) << 6)
}

pub fn (self TerminalFlags) mouse_shift_capture() MouseShiftCaptureState {
	return unsafe { MouseShiftCaptureState(u8((self.value >> 9) & 0b11)) }
}

pub fn (mut self TerminalFlags) set_mouse_shift_capture(value MouseShiftCaptureState) {
	self.set_field(0b11 << 9, u32(value) << 9)
}

pub fn (self TerminalFlags) focused() bool {
	return self.value & (1 << 11) != 0
}

pub fn (mut self TerminalFlags) set_focused(value bool) {
	self.set_bit(1 << 11, value)
}

pub fn (self TerminalFlags) password_input() bool {
	return self.value & (1 << 12) != 0
}

pub fn (mut self TerminalFlags) set_password_input(value bool) {
	self.set_bit(1 << 12, value)
}

pub fn (self TerminalFlags) selection_scroll() bool {
	return self.value & (1 << 13) != 0
}

pub fn (mut self TerminalFlags) set_selection_scroll(value bool) {
	self.set_bit(1 << 13, value)
}

// Dirty flag used only by the search thread.
pub fn (self TerminalFlags) search_viewport_dirty() bool {
	return self.value & (1 << 14) != 0
}

pub fn (mut self TerminalFlags) set_search_viewport_dirty(value bool) {
	self.set_bit(1 << 14, value)
}

pub fn (self TerminalFlags) dirty() Dirty {
	return Dirty.from_int(u8((self.value >> 15) & 0b1111))
}

pub fn (mut self TerminalFlags) set_dirty(value Dirty) {
	self.set_field(0b1111 << 15, u32(value.int()) << 15)
}

pub fn (mut self TerminalFlags) set_dirty_palette(value bool) {
	self.set_bit(1 << 15, value)
}

pub fn (mut self TerminalFlags) set_dirty_reverse_colors(value bool) {
	self.set_bit(1 << 16, value)
}

pub fn (mut self TerminalFlags) set_dirty_clear(value bool) {
	self.set_bit(1 << 17, value)
}

pub fn (mut self TerminalFlags) set_dirty_preedit(value bool) {
	self.set_bit(1 << 18, value)
}

pub fn (self TerminalFlags) int() u32 {
	return self.value
}

fn (mut self TerminalFlags) set_bit(mask u32, enabled bool) {
	if enabled {
		self.value |= mask
	} else {
		self.value &= ~mask
	}
}

fn (mut self TerminalFlags) set_field(mask u32, value u32) {
	self.value = (self.value & ~mask) | (value & mask)
}

pub enum MouseShiftCaptureState as u8 {
	null_
	false_
	true_
}

// Options for scrolling the viewport of the terminal grid.
pub struct ScrollViewportTop {}

pub struct ScrollViewportBottom {}

pub struct ScrollViewportDelta {
pub:
	delta int
}

pub type ScrollViewport = ScrollViewportBottom | ScrollViewportDelta | ScrollViewportTop

pub const scroll_viewport_top = ScrollViewport(ScrollViewportTop{})
pub const scroll_viewport_bottom = ScrollViewport(ScrollViewportBottom{})

pub fn ScrollViewport.from_delta(delta int) ScrollViewport {
	return ScrollViewportDelta{
		delta: delta
	}
}

// The modes for DECCOLM.
pub enum DeccolmMode as u8 {
	cols_80  = 0
	cols_132 = 1
}

// Modal screen changes. These map to the literal terminal
// modes to enable or disable alternate screen modes.
pub enum SwitchScreenMode as u8 {
	// Legacy alternate screen mode. This goes to the alternate
	// screen or primary screen and only copies the cursor. The
	// screen is not erased.
	mode_47

	// Alternate screen mode where the alternate screen is cleared
	// on exit. The primary screen is never cleared. The cursor is
	// copied.
	mode_1047

	// Save primary screen cursor, switch to alternate screen,
	// and clear the alternate screen on entry. On exit,
	// do not clear the screen, and restore the cursor on the
	// primary screen.
	mode_1049
}

// ============================================================
// Initialize a new terminal.
// ============================================================

pub fn Terminal.init(opts Options) !Terminal {
	cols := opts.cols
	rows := opts.rows

	mut screen_set := ScreenSet.init(ScreenOptions{
		cols:           u32(cols)
		rows:           u32(rows)
		max_scrollback: opts.max_scrollback
	})!

	tabstops := Tabstops.init(uint(cols), terminal.tabstop_interval) or {
		screen_set.deinit()
		return err
	}

	return Terminal{
		cols:             cols
		rows:             rows
		screens:          screen_set
		tabstops:         tabstops
		scrolling_region: ScrollingRegion{
			top:    0
			bottom: rows - 1
			left:   0
			right:  cols - 1
		}
		colors:           opts.colors
		modes:            ModeState{
			values:  opts.default_modes
			default: opts.default_modes
		}
	}
}

pub fn (mut self Terminal) deinit() {
	self.tabstops.deinit()
	self.screens.deinit()
}

// Return a terminal.Stream that can process VT streams and update this
// terminal state. The streams will only process read-only data that
// modifies terminal state. Sequences that query or otherwise require
// output will be ignored.
// vt_stream creates a ReadonlyStream that wraps this terminal.
// The stream parses VT sequences and applies them to the terminal.
pub fn (mut self Terminal) vt_stream() ReadonlyStream {
	return Stream.init_alloc[ReadonlyHandler](voidptr(1), self.vt_handler())
}

// vt_handler creates just the handler portion (without stream parser).
pub fn (mut self Terminal) vt_handler() ReadonlyHandler {
	return ReadonlyHandler.init(mut self)
}

// ============================================================
// Print functions
// ============================================================

// Print UTF-8 encoded string to the terminal.
pub fn (mut self Terminal) print_string(str string) ! {
	for c in str.runes() {
		if c == `\n` {
			self.carriage_return()
			self.linefeed()!
		} else {
			self.print(u32(c))!
		}
	}
}

// Print the previous printed character a repeated amount of times.
pub fn (mut self Terminal) print_repeat(count_req uint) ! {
	if c := self.previous_char {
		count := if count_req < 1 { uint(1) } else { count_req }
		for _ in uint(0) .. count {
			self.print(c)!
		}
	}
}

// Print a single codepoint to the terminal.
pub fn (mut self Terminal) print(c u32) ! {
	// If we're not on the main display, do nothing for now
	if self.status_display != .main {
		return
	}

	// After doing any printing, wrapping, scrolling, etc. we want to ensure
	// that our screen remains in a consistent state.
	defer { self.screens.active.assert_integrity() }

	// Our right margin depends where our cursor is now.
	right_limit := if self.screens.active.cursor.x > self.scrolling_region.right {
		self.cols
	} else {
		self.scrolling_region.right + 1
	}

	// Perform grapheme clustering if grapheme support is enabled (mode 2027).
	// This is MUCH slower than the normal path so the conditional below is
	// purposely ordered in least-likely to most-likely so we can drop out
	// as quickly as possible.
	if c > 255 && self.modes.get(.grapheme_cluster) && self.screens.active.cursor.x > 0 {
		if self.print_grapheme_cluster(c, right_limit)! {
			return
		}
	}

	// Determine the width of this character so we can handle
	// non-single-width characters properly. We have a fast-path for
	// byte-sized characters since they're so common. We can ignore
	// control characters because they're always filtered prior.
	width := if c <= 0xFF { u32(1) } else { u32(unicode.get(c).width()) }

	// Note: it is possible to have a width of "3" and a width of "-1" from
	// uucode.x's wcwidth. We should look into those cases and handle them
	// appropriately.
	assert width <= 2

	// Attach zero-width characters to our cell as grapheme data.
	if width == 0 {
		// If we have grapheme clustering enabled, we don't blindly attach
		// any zero width character to our cells and we instead just ignore
		// it.
		if self.modes.get(.grapheme_cluster) {
			return
		}

		// If we're at cell zero, then this is malformed data and we don't
		// print anything or even store this. Zero-width characters are ALWAYS
		// attached to some other non-zero-width character at the time of
		// writing.
		if self.screens.active.cursor.x == 0 {
			// log.warn: zero-width character with no prior character, ignoring
			return
		}

		// Find our previous cell
		immediate := self.screens.active.cursor_cell_left(1)
		prev := if immediate.wide != .spacer_tail {
			immediate
		} else {
			self.screens.active.cursor_cell_left(2)
		}

		// If our previous cell has no text, just ignore the zero-width character
		if !prev.has_text() {
			// log.warn: zero-width character with no prior character, ignoring
			return
		}

		// If this is a emoji variation selector, prev must be an emoji
		if c == 0xFE0F || c == 0xFE0E {
			prev_props := unicode.get(prev.codepoint)
			emoji := prev_props.grapheme_break() == .extended_pictographic
			if !emoji {
				return
			}
		}

		self.screens.active.append_grapheme(prev, c)!
		return
	}

	// We have a printable character, save it
	self.previous_char = c

	// If we're soft-wrapping, then handle that first.
	if self.screens.active.cursor.pending_wrap && self.modes.get(.wraparound) {
		self.print_wrap()!
	}

	// If we have insert mode enabled then we need to handle that. We
	// only do insert mode if we're not at the end of the line.
	if self.modes.get(.insert) && self.screens.active.cursor.x + width < self.cols {
		self.insert_blanks(uint(width))
	}

	match width {
		// Single cell is very easy: just write in the cell
		1 {
			self.screens.active.cursor_mark_dirty()
			self.print_cell(c, .narrow)
		}
		// Wide character requires a spacer. We print this by
		// using two cells: the first is flagged "wide" and has the
		// wide char. The second is guaranteed to be a spacer if
		// we're not at the end of the line.
		2 {
			if (right_limit - self.scrolling_region.left) > 1 {
				// If we don't have space for the wide char, we need
				// to insert spacers and wrap. Then we just print the wide
				// char as normal.
				if self.screens.active.cursor.x == right_limit - 1 {
					// If we don't have wraparound enabled then we don't print
					// this character at all and don't move the cursor. This is
					// how xterm behaves.
					if !self.modes.get(.wraparound) {
						return
					}

					// We only create a spacer head if we're at the real edge
					// of the screen. Otherwise, we clear the space with a narrow.
					// This allows soft wrapping to work correctly.
					self.print_cell(0, if right_limit == self.cols {
						CellWide.spacer_head
					} else {
						CellWide.narrow
					})
					self.print_wrap()!
				}

				self.screens.active.cursor_mark_dirty()
				self.print_cell(c, .wide)
				self.screens.active.cursor_right(1)
				self.print_cell(0, .spacer_tail)
			} else {
				// This is pretty broken, terminals should never be only 1-wide.
				// We should prevent this downstream.
				self.screens.active.cursor_mark_dirty()
				self.print_cell(0, .narrow)
			}
		}
		else {
			panic('unreachable character width')
		}
	}

	// If we're at the column limit, then we need to wrap the next time.
	// In this case, we don't move the cursor.
	if self.screens.active.cursor.x == right_limit - 1 {
		self.screens.active.cursor.pending_wrap = true
		return
	}

	// Move the cursor
	self.screens.active.cursor_right(1)
}

// The `grapheme:` block of Terminal.print. Returns true when `c` was
// consumed by the previous grapheme, which ends print; false breaks out of
// the block and continues with the normal width path.
fn (mut self Terminal) print_grapheme_cluster(c u32, right_limit u32) !bool {
	// We need the previous cell to determine if we're at a grapheme
	// break or not. If we are NOT, then we are still combining the
	// same grapheme. Otherwise, we can stay in this cell.
	//
	// If we have wraparound, then we always use the prev col.
	// If we do not have wraparound, the logic is trickier. If
	// we're not on the last column, then we just use the previous
	// column. Otherwise, we need to check if there is text to
	// figure out if we're attaching to the prev or current.
	left := if self.modes.get(.wraparound) {
		u32(1)
	} else if self.screens.active.cursor.x != right_limit - 1 {
		u32(1)
	} else {
		u32(self.screens.active.cursor.page_cell.codepoint() == 0)
	}

	// If the previous cell is a wide spacer tail, then we actually
	// want to use the cell before that because that has the actual
	// content.
	immediate := self.screens.active.cursor_cell_left(left)
	mut prev_cell := unsafe { immediate }
	mut prev_left := left
	if immediate.wide == .spacer_tail {
		prev_cell = self.screens.active.cursor_cell_left(left + 1)
		prev_left = left + 1
	}

	// If our cell has no content, then this is a new cell and
	// necessarily a grapheme break.
	if prev_cell.codepoint() == 0 {
		return false
	}

	grapheme_break := grapheme_break_after(&self.screens.active.cursor.page_pin.node.data,
		prev_cell, c)

	// If we can NOT break, this means that "c" is part of a grapheme
	// with the previous char.
	if grapheme_break {
		return false
	}

	// If this is an emoji variation selector then we need to modify
	// the cell width accordingly. VS16 makes the character wide and
	// VS15 makes it narrow.
	if c == 0xFE0F || c == 0xFE0E {
		prev_props := unicode.get(prev_cell.codepoint)
		// Check if it is a valid variation sequence in
		// emoji-variation-sequences.txt, and if not, ignore the char.
		if !prev_props.emoji_vs_base() {
			return true
		}

		match c {
			0xFE0F {
				if prev_cell.wide != .wide {
					// Move our cursor back to the previous. We'll move
					// the cursor within this block to the proper location.
					self.screens.active.cursor_left(prev_left)

					// If we don't have space for the wide char, we need
					// to insert spacers and wrap. Then we just print the wide
					// char as normal.
					if self.screens.active.cursor.x == right_limit - 1 {
						if !self.modes.get(.wraparound) {
							return true
						}
						self.print_cell(0, if right_limit == self.cols {
							CellWide.spacer_head
						} else {
							CellWide.narrow
						})
						self.print_wrap()!
					}

					self.print_cell(prev_cell.codepoint, .wide)

					// Write our spacer
					self.screens.active.cursor_right(1)
					self.print_cell(0, .spacer_tail)

					// Move the cursor again so we're beyond our spacer
					if self.screens.active.cursor.x == right_limit - 1 {
						self.screens.active.cursor.pending_wrap = true
					} else {
						self.screens.active.cursor_right(1)
					}
				}
			}
			0xFE0E {
				// Prev cell is no longer wide
				if prev_cell.wide == .wide {
					mut prev_mut := unsafe { prev_cell }
					prev_mut.wide = .narrow

					// Remove the wide spacer tail
					mut cell := self.screens.active.cursor_cell_left(prev_left - 1)
					cell.wide = .narrow

					// Back track the cursor so that we don't end up with
					// an extra space after the character. Since xterm is
					// not VS aware, it cannot be used as a reference for
					// this behavior; but it does follow the principle of
					// least surprise, and also matches the behavior that
					// can be observed in Kitty, which is one of the only
					// other VS aware terminals.
					if self.screens.active.cursor.x == right_limit - 1 {
						// If we're already at the right edge, we stay
						// here and set the pending wrap to false since
						// when we pend a wrap, we only move our cursor once
						// even for wide chars (tests verify).
						self.screens.active.cursor.pending_wrap = false
					} else {
						// Otherwise, move back.
						self.screens.active.cursor_left(1)
					}
				}
			}
			else {
				panic('unreachable variation selector')
			}
		}
	}

	// log.debug: grapheme attach to left
	self.screens.active.cursor_mark_dirty()
	self.screens.active.append_grapheme(prev_cell, c)!
	return true
}

// The `grapheme_break:` block of Terminal.print: replay the cell's
// existing grapheme to rebuild the break state, then test `cp`.
fn grapheme_break_after(page &Page, prev &CellData, cp u32) bool {
	mut state := unicode.BreakState.default
	mut cp1 := prev.codepoint
	if prev.has_grapheme() {
		cps := page.lookup_grapheme(prev) or { panic('grapheme cell has no grapheme data') }
		for cp2 in cps {
			// log.debug: cp1 cp2
			assert !unicode.grapheme_break(cp1, cp2, &state)
			cp1 = cp2
		}
	}

	// log.debug: cp1 cp2 end
	return unicode.grapheme_break(cp1, cp, &state)
}

fn (mut self Terminal) print_cell(unmapped_c u32, wide CellWide) {
	defer { self.screens.active.assert_integrity() }

	// TODO: spacers should use a bgcolor only cell

	c := self.map_charset(unmapped_c)

	mut cell := self.screens.active.cursor.page_cell

	// If the wide property of this cell is the same, then we don't
	// need to do the special handling here because the structure will
	// be the same. If it is NOT the same, then we may need to clear some
	// cells.
	if cell.wide != wide {
		match cell.wide {
			// Previous cell was narrow. Do nothing.
			.narrow {}
			// Previous cell was wide. We need to clear the tail and head.
			.wide {
				if self.screens.active.cursor.x < self.cols - 1 {
					spacer_cell := self.screens.active.cursor_cell_right(1)
					mut page := &self.screens.active.cursor.page_pin.node.data
					mut spacer := row_cells_at(self.screens.active.cursor.page_row, spacer_cell, 1)
					self.screens.active.clear_cells(mut page, mut self.screens.active.cursor.page_row, mut
						spacer)
					if self.screens.active.cursor.y > 0 && self.screens.active.cursor.x <= 1 {
						mut head_cell := self.screens.active.cursor_cell_end_of_prev()
						head_cell.wide = .narrow
					}
				}
			}
			.spacer_tail {
				assert self.screens.active.cursor.x > 0

				// So integrity checks pass. We fix this up later so we don't
				// need to do this without safety checks.
				$if !prod {
					cell.wide = .narrow
				}

				wide_cell := self.screens.active.cursor_cell_left(1)
				mut page := &self.screens.active.cursor.page_pin.node.data
				mut wide_cells := row_cells_at(self.screens.active.cursor.page_row, wide_cell, 1)
				self.screens.active.clear_cells(mut page, mut self.screens.active.cursor.page_row, mut
					wide_cells)
				if self.screens.active.cursor.y > 0 && self.screens.active.cursor.x <= 1 {
					mut head_cell := self.screens.active.cursor_cell_end_of_prev()
					head_cell.wide = .narrow
				}
			}
			// TODO: this case was not handled in the old terminal implementation
			// but it feels like we should do something. investigate other
			// terminals (xterm mainly) and see what's up.
			.spacer_head {}
		}
	}

	// If the prior value had graphemes, clear those
	if cell.has_grapheme() {
		mut page := &self.screens.active.cursor.page_pin.node.data
		row_idx := page.row_index(self.screens.active.cursor.page_row)
		page.clear_grapheme(row_idx, cell_index(self.screens.active.cursor.page_row, cell))
		page.update_row_grapheme_flag(self.screens.active.cursor.page_row)
	}

	// We don't need to update the style refs unless the
	// cell's new style will be different after writing.
	style_changed := cell.style_id != self.screens.active.cursor.style_id
	if style_changed {
		mut page := &self.screens.active.cursor.page_pin.node.data

		// Release the old style.
		if cell.style_id != default_style_id {
			assert self.screens.active.cursor.page_row.header.styled
			page.styles.release(cell.style_id)
		}
	}

	// Keep track if we had a hyperlink so we can unset it.
	had_hyperlink := cell.has_hyperlink

	// Write
	unsafe {
		*cell = CellData{
			content_tag:      .codepoint
			codepoint:        c
			style_id:         self.screens.active.cursor.style_id
			wide:             wide
			is_protected:     self.screens.active.cursor.is_protected
			semantic_content: self.screens.active.cursor.semantic_content
			// The page's hyperlink map still holds the prior link until
			// it is replaced or cleared below.
			has_hyperlink:    had_hyperlink
		}
	}

	if style_changed {
		mut page := &self.screens.active.cursor.page_pin.node.data

		// Use the new style.
		if cell.style_id != default_style_id {
			page.styles.use_style(cell.style_id)
			self.screens.active.cursor.page_row.header.styled = true
		}
	}

	// If this is a Kitty unicode placeholder then we need to mark the
	// row so that the renderer can lookup rows with these much faster.
	if c == kitty_unicode_placeholder {
		self.screens.active.cursor.page_row.header.kitty_virtual_placeholder = true
	}

	// We check for an active hyperlink first because setHyperlink
	// handles clearing the old hyperlink and an optimization if we're
	// overwriting the same hyperlink.
	if self.screens.active.cursor.hyperlink_id > 0 {
		self.screens.active.cursor_set_hyperlink() or {
			// log.warn: error reallocating for more hyperlink space, ignoring hyperlink
			assert !cell.has_hyperlink
		}
	} else if had_hyperlink {
		// If the previous cell had a hyperlink then we need to clear it.
		mut page := &self.screens.active.cursor.page_pin.node.data
		row_idx := page.row_index(self.screens.active.cursor.page_row)
		page.clear_hyperlink(row_idx, cell_index(self.screens.active.cursor.page_row, cell))
		page.update_row_hyperlink_flag(self.screens.active.cursor.page_row)
	}
}

// The `c:` block of Terminal.printCell: map the codepoint through the
// active charset.
fn (mut self Terminal) map_charset(unmapped_c u32) u32 {
	// TODO: non-utf8 handling, gr

	// If we're single shifting, then we use the key exactly once.
	key := if key_once := self.screens.active.charset.single_shift {
		self.screens.active.charset.single_shift = none
		key_once
	} else {
		self.screens.active.charset.gl
	}

	set := self.screens.active.charset.charsets.get(key)

	// UTF-8 or ASCII is used as-is
	if set == .utf8 || set == .ascii {
		return unmapped_c
	}

	// If we're outside of ASCII range this is an invalid value in
	// this table so we just return space.
	if unmapped_c > 0xff {
		return u32(` `)
	}

	// Get our lookup table and map it
	return u32(charset_table(set)[int(unmapped_c)])
}

fn (mut self Terminal) print_wrap() ! {
	// We only mark that we soft-wrapped if we're at the edge of our
	// full screen. We don't mark the row as wrapped if we're in the
	// middle due to a right margin.
	mark_wrap := self.screens.active.cursor.x == self.cols - 1
	if mark_wrap {
		self.screens.active.cursor.page_row.header.wrap = true
	}

	// Get the old semantic prompt so we can extend it to the next
	// line. We need to do this before we index() because we may
	// modify memory.
	old_semantic := self.screens.active.cursor.semantic_content
	old_semantic_clear := self.screens.active.cursor.semantic_content_clear_eol

	// Move to the next line
	self.index()!
	self.screens.active.cursor_horizontal_absolute(self.scrolling_region.left)

	// We always reset our semantic prompt state
	self.screens.active.cursor.semantic_content = old_semantic
	self.screens.active.cursor.semantic_content_clear_eol = old_semantic_clear
	match old_semantic {
		.output, .input {}
		.prompt {
			self.screens.active.cursor.page_row.header.semantic_prompt = .prompt_continuation
		}
	}

	if mark_wrap {
		mut row := self.screens.active.cursor.page_row
		// Always mark the row as a continuation
		row.header.wrap_continuation = true
	}

	// Assure that our screen is consistent
	self.screens.active.assert_integrity()
}

// Set the charset into the given slot.
pub fn (mut self Terminal) configure_charset(slot CharsetSlot, set Charset) {
	self.screens.active.charset.charsets.set(slot, set)
}

// Invoke the charset in slot into the active slot. If single is true,
// then this will only be invoked for a single character.
pub fn (mut self Terminal) invoke_charset(active ActiveSlot, slot CharsetSlot, single bool) {
	if single {
		self.screens.active.charset.single_shift = slot
		return
	}
	match active {
		.gl {
			self.screens.active.charset.gl = slot
		}
		.gr {
			self.screens.active.charset.gr = slot
		}
	}
}

// ============================================================
// Basic cursor movement
// ============================================================

// Carriage return moves the cursor to the first column.
pub fn (mut self Terminal) carriage_return() {
	// Always reset pending wrap state
	self.screens.active.cursor.pending_wrap = false

	// In origin mode we always move to the left margin
	target := if self.modes.get(.origin) {
		self.scrolling_region.left
	} else if self.screens.active.cursor.x >= self.scrolling_region.left {
		self.scrolling_region.left
	} else {
		u16(0)
	}
	self.screens.active.cursor_horizontal_absolute(target)
}

// Linefeed moves the cursor to the next line.
pub fn (mut self Terminal) linefeed() ! {
	self.index()!
	if self.modes.get(.linefeed) {
		self.carriage_return()
	}
}

// Backspace moves the cursor back a column (but not less than 0).
pub fn (mut self Terminal) backspace() {
	self.cursor_left(1)
}

// Move the cursor up amount lines. If amount is greater than the maximum
// move distance then it is internally adjusted to the maximum. If amount is
// 0, adjust it to 1.
pub fn (mut self Terminal) cursor_up(count_req uint) {
	// Always resets pending wrap
	self.screens.active.cursor.pending_wrap = false

	// The maximum amount the cursor can move up depends on scrolling regions
	max := if self.screens.active.cursor.y >= self.scrolling_region.top {
		self.screens.active.cursor.y - self.scrolling_region.top
	} else {
		self.screens.active.cursor.y
	}
	requested := if count_req < 1 { uint(1) } else { count_req }
	count := if uint(max) < requested { max } else { u16(requested) }

	if count > 0 {
		self.screens.active.cursor_up(u32(count))
	}
}

// Move the cursor down amount lines. If amount is greater than the maximum
// move distance then it is internally adjusted to the maximum. This sequence
// will not scroll the screen or scroll region. If amount is 0, adjust it to 1.
pub fn (mut self Terminal) cursor_down(count_req uint) {
	// Always resets pending wrap
	self.screens.active.cursor.pending_wrap = false

	// The max the cursor can move to depends where the cursor currently is
	max := if self.screens.active.cursor.y <= self.scrolling_region.bottom {
		self.scrolling_region.bottom - self.screens.active.cursor.y
	} else {
		u16(self.rows - self.screens.active.cursor.y - 1)
	}
	requested := if count_req < 1 { uint(1) } else { count_req }
	count := if uint(max) < requested { max } else { u16(requested) }

	if count > 0 {
		self.screens.active.cursor_down(u32(count))
	}
}

// Move the cursor right amount columns. If amount is greater than the
// maximum move distance then it is internally adjusted to the maximum.
// This sequence will not scroll the screen or scroll region. If amount is
// 0, adjust it to 1.
pub fn (mut self Terminal) cursor_right(count_req uint) {
	// Always resets pending wrap
	self.screens.active.cursor.pending_wrap = false

	// The max the cursor can move to depends where the cursor currently is
	max := if self.screens.active.cursor.x <= self.scrolling_region.right {
		self.scrolling_region.right - self.screens.active.cursor.x
	} else {
		u16(self.cols - self.screens.active.cursor.x - 1)
	}
	requested := if count_req < 1 { uint(1) } else { count_req }
	count := if uint(max) < requested { max } else { u16(requested) }

	if count > 0 {
		self.screens.active.cursor_right(u32(count))
	}
}

// Move the cursor to the left amount cells. If amount is 0, adjust it to 1.
pub fn (mut self Terminal) cursor_left(count_req uint) {
	// Wrapping behavior depends on various terminal modes
	wrap_mode := if !self.modes.get(.wraparound) {
		WrapMode.none
	} else if self.modes.get(.reverse_wrap_extended) {
		WrapMode.reverse_extended
	} else if self.modes.get(.reverse_wrap) {
		WrapMode.reverse
	} else {
		WrapMode.none
	}

	mut count := if count_req < 1 { uint(1) } else { count_req }

	// If we are in no wrap mode, then we move the cursor left and exit
	// since this is the fastest and most typical path.
	if wrap_mode == .none {
		move_amt := if count < uint(self.screens.active.cursor.x) {
			u32(count)
		} else {
			u32(self.screens.active.cursor.x)
		}
		if move_amt > 0 {
			self.screens.active.cursor_left(move_amt)
		}
		self.screens.active.cursor.pending_wrap = false
		return
	}

	// If we have a pending wrap state and we are in either reverse wrap
	// modes then we decrement the amount we move by one to match xterm.
	if self.screens.active.cursor.pending_wrap {
		count -= 1
		self.screens.active.cursor.pending_wrap = false
	}

	// The margins we can move to.
	top := self.scrolling_region.top
	bottom := self.scrolling_region.bottom
	right_margin := self.scrolling_region.right
	left_margin := if self.screens.active.cursor.x < self.scrolling_region.left {
		u16(0)
	} else {
		self.scrolling_region.left
	}

	// Handle some edge cases when our cursor is already on the left margin.
	if self.screens.active.cursor.x == left_margin {
		match wrap_mode {
			// In reverse mode, if we're already before the top margin
			// then we just set our cursor to the top-left and we're done.
			.reverse {
				if self.screens.active.cursor.y <= top {
					self.screens.active.cursor_absolute(u32(left_margin), u32(top))
					return
				}
			}

			// Handled in while loop
			.reverse_extended {}
			// Handled above
			.none {}
		}
		// unreachable
	}

	for {
		// We can move at most to the left margin.
		max := uint(self.screens.active.cursor.x - left_margin)

		// We want to move at most the number of columns we have left
		// or our remaining count.
		amount := if max < count { max } else { count }
		count -= amount
		if amount > 0 {
			self.screens.active.cursor_left(u32(amount))
		}

		// If we have no more to move, then we're done.
		if count == 0 {
			break
		}

		// If we are at the top, then we are done.
		if self.screens.active.cursor.y == top {
			if wrap_mode != .reverse_extended {
				break
			}
			self.screens.active.cursor_absolute(u32(right_margin), u32(bottom))
			count -= 1
			continue
		}

		// UNDEFINED TERMINAL BEHAVIOR - wrap up to (0, 0) and stop
		if self.screens.active.cursor.y == 0 {
			break
		}

		// If our previous line is not wrapped then we are done.
		if wrap_mode != .reverse_extended {
			prev_row := self.screens.active.cursor_row_up(1)
			if !prev_row.header.wrap {
				break
			}
		}

		self.screens.active.cursor_absolute(u32(right_margin), u32(self.screens.active.cursor.y - 1))
		count -= 1
	}
}

enum WrapMode as u8 {
	none
	reverse
	reverse_extended
}

// ============================================================
// Cursor save/restore
// ============================================================

// Save cursor position and further state.
//
// The primary and alternate screen have distinct save state. One saved state
// is kept per screen (main / alternative). If for the current screen state
// was already saved it is overwritten.
pub fn (mut self Terminal) save_cursor() {
	self.screens.active.saved_cursor = SavedCursor{
		x:            self.screens.active.cursor.x
		y:            self.screens.active.cursor.y
		style:        self.screens.active.cursor.style
		is_protected: self.screens.active.cursor.is_protected
		pending_wrap: self.screens.active.cursor.pending_wrap
		origin:       self.modes.get(.origin)
		charset:      self.screens.active.charset
	}
}

// Restore cursor position and other state.
//
// The primary and alternate screen have distinct save state.
// If no save was done before values are reset to their initial values.
pub fn (mut self Terminal) restore_cursor() {
	saved := self.screens.active.saved_cursor or {
		SavedCursor{
			x: 0
			y: 0
		}
	}

	// Set the style first because it can fail
	self.screens.active.cursor.style = saved.style
	self.screens.active.manual_style_update() or {
		self.screens.active.cursor.style = CellStyle{}
		self.screens.active.manual_style_update() or {}
	}

	self.screens.active.charset = saved.charset
	self.modes.set(.origin, saved.origin)
	self.screens.active.cursor.pending_wrap = saved.pending_wrap
	self.screens.active.cursor.is_protected = saved.is_protected

	x := if saved.x < self.cols { saved.x } else { self.cols - 1 }
	y := if saved.y < self.rows { saved.y } else { self.rows - 1 }
	self.screens.active.cursor_absolute(u32(x), u32(y))

	// Ensure our screen is consistent
	self.screens.active.assert_integrity()
}

// ============================================================
// Protection mode
// ============================================================

// Set the character protection mode for the terminal.
pub fn (mut self Terminal) set_protected_mode(mode ProtectedMode) {
	match mode {
		.off {
			self.screens.active.cursor.is_protected = false
			// screen.protected_mode is NEVER reset to ".off" because
			// logic such as eraseChars depends on knowing what the
			// _most recent_ mode was.
		}
		.iso {
			self.screens.active.cursor.is_protected = true
			self.screens.active.protected_mode = .iso
		}
		.dec {
			self.screens.active.cursor.is_protected = true
			self.screens.active.protected_mode = .dec
		}
	}
}

// ============================================================
// Semantic prompt
// ============================================================

// Returns true if the cursor is currently at a prompt. Another way to look
// at this is it returns false if the shell is currently outputting something.
// This requires shell integration (semantic prompt integration).
//
// If the shell integration doesn't exist, this will always return false.
pub fn (self &Terminal) cursor_is_at_prompt() bool {
	// If we're on the secondary screen, we're never at a prompt.
	if self.screens.active_key == .alternate {
		return false
	}

	// If our page row is a prompt then we're always at a prompt
	cursor := &self.screens.active.cursor
	if cursor.page_row.header.semantic_prompt != .unknown {
		return true
	}

	// Otherwise, determine our cursor state
	return match self.screens.active.cursor.semantic_content {
		.input, .prompt { true }
		.output { false }
	}
}

// ============================================================
// Tab functions
// ============================================================

// Horizontal tab moves the cursor to the next tabstop.
pub fn (mut self Terminal) horizontal_tab() {
	for self.screens.active.cursor.x < self.scrolling_region.right {
		// Move the cursor right
		self.screens.active.cursor_right(1)

		// If the last cursor position was a tabstop we return.
		if self.tabstops.get(uint(self.screens.active.cursor.x)) {
			return
		}
	}
}

// Same as horizontal_tab but moves to the previous tabstop instead of the next.
pub fn (mut self Terminal) horizontal_tab_back() {
	// With origin mode enabled, our leftmost limit is the left margin.
	left_limit := if self.modes.get(.origin) {
		self.scrolling_region.left
	} else {
		u16(0)
	}

	for {
		// If we're already at the edge of the screen, then we're done.
		if self.screens.active.cursor.x <= left_limit {
			return
		}

		// Move the cursor left
		self.screens.active.cursor_left(1)
		if self.tabstops.get(uint(self.screens.active.cursor.x)) {
			return
		}
	}
}

// Clear tab stops.
pub fn (mut self Terminal) tab_clear(cmd TabClear) {
	match cmd {
		.current { self.tabstops.unset(uint(self.screens.active.cursor.x)) }
		.all { self.tabstops.reset(0) }
	}
}

// Set a tab stop on the current cursor.
pub fn (mut self Terminal) tab_set() {
	self.tabstops.set(uint(self.screens.active.cursor.x))
}

// Reset tab stops to default interval.
pub fn (mut self Terminal) tab_reset() {
	self.tabstops.reset(terminal.tabstop_interval)
}

// ============================================================
// Index / Reverse Index
// ============================================================

// Move the cursor to the next line in the scrolling region, possibly scrolling.
//
// If the cursor is outside of the scrolling region: move the cursor one line
// down if it is not on the bottom-most line of the screen.
//
// If the cursor is inside the scrolling region:
//   If the cursor is on the bottom-most line of the scrolling region:
//     invoke scroll up with amount=1
//   If the cursor is not on the bottom-most line of the scrolling region:
//     move the cursor one line down
//
// This unsets the pending wrap state without wrapping.
pub fn (mut self Terminal) index() ! {
	mut screen := self.screens.active

	// Unset pending wrap state
	screen.cursor.pending_wrap = false

	// We handle our cursor semantic prompt state AFTER doing the
	// scrolling, because we may need to apply to new rows.
	defer {
		if screen.cursor.semantic_content != .output {
			// Always reset any semantic content clear-eol state.
			//
			// The specification is not clear what "end-of-line" means. If we
			// discover that there are more scenarios we should be unsetting
			// this we should document and test it.
			if screen.cursor.semantic_content_clear_eol {
				screen.cursor.semantic_content = .output
				screen.cursor.semantic_content_clear_eol = false
			} else {
				// If we aren't clearing our state at EOL and we're not output,
				// then we mark the new row as a prompt continuation. This is
				// to work around shells that don't send OSC 133 k=s sequences
				// for continuations.
				//
				// This can be a false positive if the shell changes content
				// type later and outputs something. We handle that in the
				// semanticPrompt function.
				screen.cursor.page_row.header.semantic_prompt = .prompt_continuation
			}
		} else {
			// This should never be set in the output mode.
			assert !screen.cursor.semantic_content_clear_eol
		}
	}

	// Outside of the scroll region we move the cursor one line down.
	if screen.cursor.y < self.scrolling_region.top || screen.cursor.y > self.scrolling_region.bottom {
		// We only move down if we're not already at the bottom of
		// the screen.
		if screen.cursor.y < self.rows - 1 {
			screen.cursor_down(1)
		}

		return
	}

	// If the cursor is inside the scrolling region and on the bottom-most
	// line, then we scroll up. If our scrolling region is the full screen
	// we create scrollback.
	if screen.cursor.y == self.scrolling_region.bottom
		&& screen.cursor.x >= self.scrolling_region.left
		&& screen.cursor.x <= self.scrolling_region.right {
		// Scrolling dirties the images because it updates their placements pins.
		screen.kitty_images.dirty = true

		// If our scrolling region is at the top, we create scrollback.
		if self.scrolling_region.top == 0 && self.scrolling_region.left == 0
			&& self.scrolling_region.right == self.cols - 1 {
			placements := self.prepare_kitty_scroll(-1, true)
			defer { self.restore_kitty_scroll(placements) }
			screen.cursor_scroll_above()!
			return
		}

		// Slow path for left and right scrolling region margins.
		if self.scrolling_region.left != 0 || self.scrolling_region.right != self.cols - 1 || 
		// PERF(mitchellh): If we have an SGR background set then
		// we need to preserve that background in our erased rows.
		// scrollUp does that but eraseRowBounded below does not.
		// However, scrollUp is WAY slower. We should optimize this
		// case to work in the eraseRowBounded codepath and remove
		// this check.
		!screen.blank_cell().is_zero() {
			self.scroll_up(1)!
			return
		}

		// Otherwise use a fast path function from PageList to efficiently
		// scroll the contents of the scrolling region.
		placements := self.prepare_kitty_scroll(-1, false)
		defer { self.restore_kitty_scroll(placements) }

		// Preserve old cursor just for assertions
		old_cursor := screen.cursor

		screen.pages.erase_row_bounded(Point.new(.active, Coordinate{
			y: self.scrolling_region.top
		}), uint(self.scrolling_region.bottom - self.scrolling_region.top))!

		// eraseRow and eraseRowBounded will end up moving the cursor pin
		// up by 1, so we need to move it back down. A `cursorReload`
		// would be better option but this is more efficient and this is
		// a super hot path so we do this instead.
		assert screen.cursor.x == old_cursor.x
		assert screen.cursor.y == old_cursor.y
		screen.cursor.y -= 1
		screen.cursor_down(1)

		// The operations above can prune our cursor style so we need to
		// update. This should never fail because the above can only FREE
		// memory.
		screen.manual_style_update() or {
			// log.warn: deleteLines manualStyleUpdate
			screen.cursor.style = CellStyle{}
			screen.manual_style_update() or { panic('the default style cannot fail') }
		}

		return
	}

	// Increase cursor by 1, maximum to bottom of scroll region
	if screen.cursor.y < self.scrolling_region.bottom {
		screen.cursor_down(1)
	}
}

// Move the cursor to the previous line in the scrolling region, possibly
// scrolling.
//
// If the cursor is outside of the scrolling region, move the cursor one
// line up if it is not on the top-most line of the screen.
//
// If the cursor is inside the scrolling region:
//   * If the cursor is on the top-most line: invoke scroll down with amount=1
//   * Otherwise: move the cursor one line up
pub fn (mut self Terminal) reverse_index() {
	if self.screens.active.cursor.y != self.scrolling_region.top
		|| self.screens.active.cursor.x < self.scrolling_region.left
		|| self.screens.active.cursor.x > self.scrolling_region.right {
		self.cursor_up(1)
		return
	}
	self.scroll_down(1)
}

// ============================================================
// Cursor positioning
// ============================================================

// Set Cursor Position. Move cursor to the position indicated
// by row and column (1-indexed). If column is 0, it is adjusted to 1.
// If column is greater than the right-most column it is adjusted to
// the right-most column. If row is 0, it is adjusted to 1. If row is
// greater than the bottom-most row it is adjusted to the bottom-most row.
pub fn (mut self Terminal) set_cursor_pos(row_req uint, col_req uint) {
	// If cursor origin mode is set the cursor row will be moved relative to
	// the top margin row.
	x_offset, y_offset, x_max, y_max := if self.modes.get(.origin) {
		self.scrolling_region.left, self.scrolling_region.top, self.scrolling_region.right + 1, self.scrolling_region.bottom + 1
	} else {
		u16(0), u16(0), self.cols, self.rows
	}

	// Unset pending wrap state
	self.screens.active.cursor.pending_wrap = false

	// Calculate our new x/y
	row := if row_req == 0 { 1 } else { row_req }
	col := if col_req == 0 { 1 } else { col_req }

	x_with_offset := if col > uint(x_max - x_offset) {
		x_max
	} else {
		u16(col) + x_offset
	}
	y_with_offset := if row > uint(y_max - y_offset) {
		y_max
	} else {
		u16(row) + y_offset
	}
	x := x_with_offset - 1
	y := y_with_offset - 1

	// If the y is unchanged then this is fast pointer math.
	if u32(y) == self.screens.active.cursor.y {
		if u32(x) > self.screens.active.cursor.x {
			self.screens.active.cursor_right(u32(x) - self.screens.active.cursor.x)
		} else {
			self.screens.active.cursor_left(self.screens.active.cursor.x - u32(x))
		}
		return
	}

	// If everything changed, perform an absolute change.
	self.screens.active.cursor_absolute(u32(x), u32(y))
}

// ============================================================
// Margin setting
// ============================================================

// Set Top and Bottom Margins. Top and bottom are 1-indexed.
pub fn (mut self Terminal) set_top_and_bottom_margin(top_req uint, bottom_req uint) {
	top := if top_req < 1 { uint(1) } else { top_req }
	bottom_limit := if bottom_req == 0 { uint(self.rows) } else { bottom_req }
	bottom := if bottom_limit > uint(self.rows) { uint(self.rows) } else { bottom_limit }
	if top >= bottom {
		return
	}
	self.scrolling_region.top = u16(top - 1)
	self.scrolling_region.bottom = u16(bottom - 1)
	self.set_cursor_pos(1, 1)
}

// DECSLRM - Set Left and Right Margin
pub fn (mut self Terminal) set_left_and_right_margin(left_req uint, right_req uint) {
	// We must have this mode enabled to do anything
	if !self.modes.get(.enable_left_and_right_margin) {
		return
	}

	left := if left_req < 1 { uint(1) } else { left_req }
	right_limit := if right_req == 0 { uint(self.cols) } else { right_req }
	right := if right_limit > uint(self.cols) { uint(self.cols) } else { right_limit }
	if left >= right {
		return
	}
	self.scrolling_region.left = u16(left - 1)
	self.scrolling_region.right = u16(right - 1)
	self.set_cursor_pos(1, 1)
}

// ============================================================
// Scrolling
// ============================================================

// Scroll the scrolling region down by count rows.
pub fn (mut self Terminal) scroll_down(count uint) {
	region_height := uint(self.scrolling_region.bottom - self.scrolling_region.top) + 1
	placements := self.prepare_kitty_scroll(int(math.min(count, region_height)), false)
	defer { self.restore_kitty_scroll(placements) }

	// Preserve our x/y to restore.
	old_x := self.screens.active.cursor.x
	old_y := self.screens.active.cursor.y
	old_wrap := self.screens.active.cursor.pending_wrap

	// Move to the top of the scroll region
	self.screens.active.cursor_absolute(u32(self.scrolling_region.left), u32(self.scrolling_region.top))
	self.insert_lines(count)

	// Restore cursor
	self.screens.active.cursor_absolute(u32(old_x), u32(old_y))
	self.screens.active.cursor.pending_wrap = old_wrap
}

// Removes amount lines from the top of the scroll region. The remaining lines
// to the bottom margin are shifted up and space from the bottom margin up
// is filled with empty lines.
//
// The new lines are created according to the current SGR state.
//
// Does not change the (absolute) cursor position.
pub fn (mut self Terminal) scroll_up(count uint) ! {
	region := self.scrolling_region
	adjusted_count := math.min(count, uint(region.bottom - region.top) + 1)
	shifts_window := region.top == 0 && region.left == 0 && region.right == self.cols - 1
	placements := self.prepare_kitty_scroll(-int(adjusted_count), shifts_window)
	defer { self.restore_kitty_scroll(placements) }

	// Preserve our x/y to restore.
	old_x := self.screens.active.cursor.x
	old_y := self.screens.active.cursor.y
	old_wrap := self.screens.active.cursor.pending_wrap

	// If our scroll region is at the top and we have no left/right
	// margins then we move the scrolled out text into the scrollback.
	if shifts_window {
		self.screens.active.kitty_images.dirty = true
		// Move cursor to bottom and scroll
		self.screens.active.cursor_absolute(0, u32(self.scrolling_region.bottom))
		for _ in uint(0) .. adjusted_count {
			self.screens.active.cursor_scroll_above()!
		}

		// Restore cursor
		self.screens.active.cursor_absolute(u32(old_x), u32(old_y))
		self.screens.active.cursor.pending_wrap = old_wrap
		return
	}

	// Move to the top of the scroll region
	self.screens.active.cursor_absolute(u32(self.scrolling_region.left), u32(self.scrolling_region.top))
	self.delete_lines(count)

	// Restore cursor
	self.screens.active.cursor_absolute(u32(old_x), u32(old_y))
	self.screens.active.cursor.pending_wrap = old_wrap
}

// Scroll the viewport of the terminal grid.
pub fn (mut self Terminal) scroll_viewport(behavior ScrollViewport) ! {
	match behavior {
		ScrollViewportTop { self.screens.active.scroll(ScrollTop{}) }
		ScrollViewportBottom { self.screens.active.scroll(ScrollActive{}) }
		ScrollViewportDelta {
			self.screens.active.scroll(ScrollDeltaRow{
				delta: behavior.delta
			})
		}
	}
}

// ============================================================
// Insert / Delete lines
// ============================================================

// To be called before shifting a row (as in insertLines and deleteLines).
//
// Takes care of boundary conditions such as potentially split wide chars
// across scrolling region boundaries and orphaned spacer heads at line ends.
fn (mut self Terminal) row_will_be_shifted(mut page Page, mut row RowData) {
	mut cells := unsafe { row.cells }

	// If our scrolling region includes the rightmost column then we
	// need to turn any spacer heads in to normal empty cells, since
	// once we move them they no longer correspond with soft-wrapped
	// wide characters.
	//
	// If it contains either of the 2 leftmost columns, then the wide
	// characters in the first column which may be associated with a
	// spacer head will be either moved or cleared, so we also need
	// to turn the spacer heads in to empty cells in that case.
	if self.scrolling_region.right == self.cols - 1 || self.scrolling_region.left < 2 {
		end := int(page.size.cols) - 1
		if cells[end].wide == .spacer_head {
			cells[end].wide = .narrow
		}
	}

	// If the leftmost or rightmost cells of our scrolling region
	// are parts of wide chars, we need to clear the cells' contents
	// since they'd be split by the move.
	left := int(self.scrolling_region.left)
	right := int(self.scrolling_region.right)

	if cells[left].wide == .spacer_tail {
		wide := left - 1
		if cells[wide].has_grapheme() {
			page.clear_grapheme(page.row_index(row), uint(wide))
			page.update_row_grapheme_flag(row)
		}
		cells[wide].codepoint = 0
		cells[wide].wide = .narrow
		cells[left].wide = .narrow
	}

	if cells[right].wide == .wide {
		tail := right + 1
		if cells[right].has_grapheme() {
			page.clear_grapheme(page.row_index(row), uint(right))
			page.update_row_grapheme_flag(row)
		}
		cells[right].codepoint = 0
		cells[right].wide = .narrow
		cells[tail].wide = .narrow
	}
}

// Map a failed partial-row clone to the capacity that must grow, as the
// error switch in insertLines and deleteLines does.
fn clone_error_capacity(err PageCloneError) ?IncreaseCapacity {
	return match err {
		// Rehash the sets
		.hyperlink_set_needs_rehash { none }
		// Increase style memory
		.style_set_out_of_memory { .styles }
		// Increase string memory
		.string_alloc_out_of_memory { .string_bytes }
		// Increase hyperlink memory
		.hyperlink_set_out_of_memory, .hyperlink_map_out_of_memory { .hyperlink_bytes }
		// Increase grapheme memory
		.grapheme_map_out_of_memory, .grapheme_alloc_out_of_memory { .grapheme_bytes }
	}
}

// TODO(qwerasd): `insertLines` and `deleteLines` are 99% identical,
// the majority of their logic can (and should) be abstracted in to
// a single shared helper function, probably on `Screen` not here.
// I'm just too lazy to do that rn :p

// Insert amount lines at the current cursor row. The contents of the line
// at the current cursor row and below (to the bottom-most line in the
// scrolling region) are shifted down by amount lines. The contents of the
// amount bottom-most lines in the scroll region are lost.
//
// This unsets the pending wrap state without wrapping. If the current cursor
// position is outside of the current scroll region it does nothing.
//
// If amount is greater than the remaining number of lines in the scrolling
// region it is adjusted down (still allowing for scrolling out every remaining
// line in the scrolling region)
//
// In left and right margin mode the margins are respected; lines are only
// scrolled in the scroll region.
//
// All cleared space is colored according to the current SGR state.
//
// Moves the cursor to the left margin.
pub fn (mut self Terminal) insert_lines(count uint) {
	// Rare, but happens
	if count == 0 {
		return
	}

	// If the cursor is outside the scroll region we do nothing.
	if self.screens.active.cursor.y < self.scrolling_region.top
		|| self.screens.active.cursor.y > self.scrolling_region.bottom
		|| self.screens.active.cursor.x < self.scrolling_region.left
		|| self.screens.active.cursor.x > self.scrolling_region.right {
		return
	}

	// Scrolling dirties the images because it updates their placements pins.
	self.screens.active.kitty_images.dirty = true

	// At the end we need to return the cursor to the row it started on.
	start_y := self.screens.active.cursor.y
	defer {
		self.screens.active.cursor_absolute(self.scrolling_region.left, start_y)

		// Always unset pending wrap
		self.screens.active.cursor.pending_wrap = false
	}

	// We have a slower path if we have left or right scroll margins.
	left_right := self.scrolling_region.left > 0 || self.scrolling_region.right < self.cols - 1

	// Remaining rows from our cursor to the bottom of the scroll region.
	rem := uint(self.scrolling_region.bottom - self.screens.active.cursor.y + 1)

	// We can only insert lines up to our remaining lines in the scroll
	// region. So we take whichever is smaller.
	adjusted_count := if count < rem { count } else { rem }

	// Create a new tracked pin which we'll use to navigate the page list
	// so that if we need to adjust capacity it will be properly tracked.
	mut cur_p := self.screens.active.pages.track_pin(self.screens.active.cursor.page_pin.down(rem - 1) or {
		panic('insertLines region extends past the page list')
	}) or {
		eprintln('insertLines trackPin error err=${err}')
		panic('insertLines trackPin OOM')
	}
	defer { self.screens.active.pages.untrack_pin(cur_p) }

	// Our current y position relative to the cursor
	mut y := rem

	// Traverse from the bottom up
	for y > 0 {
		cur_rac := cur_p.row_and_cell()
		mut cur_row := cur_rac.row

		// If this is one of the lines we need to shift, do so
		if y > adjusted_count {
			off_p := cur_p.up(adjusted_count) or { panic('insertLines source row is missing') }
			off_rac := off_p.row_and_cell()
			mut off_row := off_rac.row

			mut cur_page := &cur_p.node.data
			mut off_page := &off_p.node.data
			self.row_will_be_shifted(mut cur_page, mut cur_row)
			self.row_will_be_shifted(mut off_page, mut off_row)

			// If our scrolling region is full width, then we unset wrap.
			if !left_right {
				off_row.header.wrap = false
				cur_row.header.wrap = false
				off_row.header.wrap_continuation = false
				cur_row.header.wrap_continuation = false
			}

			if !self.shift_row(off_p, off_row, *cur_p, cur_row, left_right) {
				// Continue the loop to try handling this row again.
				continue
			}
		} else {
			// Clear the cells for this row, it has been shifted.
			mut page := &cur_p.node.data
			mut cells := unsafe { page.get_cells(cur_row)[int(self.scrolling_region.left)..int(self.scrolling_region.right) + 1] }
			self.screens.active.clear_cells(mut page, mut cur_row, mut cells)
		}

		// Mark the row as dirty
		cur_p.mark_dirty()

		// We have successfully processed a line.
		y -= 1
		// Move our pin up to the next row.
		if p := cur_p.up(1) {
			unsafe {
				*cur_p = p
			}
		}
	}
}

// Move one shifted row from src to dst, the part of insertLines and
// deleteLines after the rows are prepared. Returns false when the
// destination page had to grow, meaning the caller retries this row.
fn (mut self Terminal) shift_row(src_p Pin, src_row &RowData, dst_p Pin, dst_row &RowData, left_right bool) bool {
	// If our page doesn't match, then we need to do a copy from
	// one page to another. This is the slow path.
	if voidptr(src_p.node) != voidptr(dst_p.node) {
		mut dst_page := &dst_p.node.data
		src_page := &src_p.node.data
		if err := dst_page.try_clone_partial_row_from(src_page, dst_page.row_index(dst_row),
			src_page.row_index(src_row), uint(self.scrolling_region.left), uint(self.scrolling_region.right) + 1)
		{
			// Adjust our page capacity to make
			// room for we didn't have space for
			self.screens.active.increase_capacity(dst_p.node, clone_error_capacity(err)) or {
				// System OOM. We have no way to recover from this
				// currently. We should probably change insertLines
				// to raise an error here.
				//
				// Or the page can't accommodate the managed memory required
				// for this operation. We previously just corrupted
				// memory here so a crash is better. The right long
				// term solution is to allocate a new page here
				// move this row to the new page, and start over.
				panic('increaseCapacity ${err}')
			}
			return false
		}
		return true
	}

	if !left_right {
		// Swap the src/dst cells. This ensures that our dst gets the
		// proper shifted rows and src gets non-garbage cell data that
		// we can clear.
		mut dst_mut := unsafe { dst_row }
		mut src_mut := unsafe { src_row }
		dst := *dst_row
		unsafe {
			*dst_mut = *src_row
			*src_mut = dst
		}

		// Ensure what we did didn't corrupt the page
		dst_p.node.data.assert_integrity()
	} else {
		// Left/right scroll margins we have to
		// copy cells, which is much slower...
		mut page := &dst_p.node.data
		page.move_cells(page.row_index(src_row), uint(self.scrolling_region.left), page.row_index(dst_row),
			uint(self.scrolling_region.left), uint(self.scrolling_region.right - self.scrolling_region.left) + 1)
	}
	return true
}

// Removes amount lines from the current cursor row down. The remaining lines
// to the bottom margin are shifted up and space from the bottom margin up is
// filled with empty lines.
//
// If the current cursor position is outside of the current scroll region it
// does nothing. If amount is greater than the remaining number of lines in the
// scrolling region it is adjusted down.
//
// In left and right margin mode the margins are respected; lines are only
// scrolled in the scroll region.
//
// If the cell movement splits a multi cell character that character cleared,
// by replacing it by spaces, keeping its current attributes. All other
// cleared space is colored according to the current SGR state.
//
// Moves the cursor to the left margin.
pub fn (mut self Terminal) delete_lines(count uint) {
	// Rare, but happens
	if count == 0 {
		return
	}

	// If the cursor is outside the scroll region we do nothing.
	if self.screens.active.cursor.y < self.scrolling_region.top
		|| self.screens.active.cursor.y > self.scrolling_region.bottom
		|| self.screens.active.cursor.x < self.scrolling_region.left
		|| self.screens.active.cursor.x > self.scrolling_region.right {
		return
	}

	// Scrolling dirties the images because it updates their placements pins.
	self.screens.active.kitty_images.dirty = true

	// At the end we need to return the cursor to the row it started on.
	start_y := self.screens.active.cursor.y
	defer {
		self.screens.active.cursor_absolute(self.scrolling_region.left, start_y)
		// Always unset pending wrap
		self.screens.active.cursor.pending_wrap = false
	}

	// We have a slower path if we have left or right scroll margins.
	left_right := self.scrolling_region.left > 0 || self.scrolling_region.right < self.cols - 1

	// Remaining rows from our cursor to the bottom of the scroll region.
	rem := uint(self.scrolling_region.bottom - self.screens.active.cursor.y + 1)

	// We can only insert lines up to our remaining lines in the scroll
	// region. So we take whichever is smaller.
	adjusted_count := if count < rem { count } else { rem }

	// Create a new tracked pin which we'll use to navigate the page list
	// so that if we need to adjust capacity it will be properly tracked.
	mut cur_p := self.screens.active.pages.track_pin(*self.screens.active.cursor.page_pin) or {
		eprintln('deleteLines trackPin error err=${err}')
		panic('deleteLines trackPin OOM')
	}
	defer { self.screens.active.pages.untrack_pin(cur_p) }

	// Our current y position relative to the cursor
	mut y := uint(0)

	// Traverse from the top down
	for y < rem {
		cur_rac := cur_p.row_and_cell()
		mut cur_row := cur_rac.row

		// If this is one of the lines we need to shift, do so
		if y < rem - adjusted_count {
			off_p := cur_p.down(adjusted_count) or { panic('deleteLines source row is missing') }
			off_rac := off_p.row_and_cell()
			mut off_row := off_rac.row

			mut cur_page := &cur_p.node.data
			mut off_page := &off_p.node.data
			self.row_will_be_shifted(mut cur_page, mut cur_row)
			self.row_will_be_shifted(mut off_page, mut off_row)

			// If our scrolling region is full width, then we unset wrap.
			if !left_right {
				off_row.header.wrap = false
				cur_row.header.wrap = false
				off_row.header.wrap_continuation = false
				cur_row.header.wrap_continuation = false
			}

			if !self.shift_row(off_p, off_row, *cur_p, cur_row, left_right) {
				// Continue the loop to try handling this row again.
				continue
			}
		} else {
			// Clear the cells for this row, it's from out of bounds.
			mut page := &cur_p.node.data
			mut cells := unsafe { page.get_cells(cur_row)[int(self.scrolling_region.left)..int(self.scrolling_region.right) + 1] }
			self.screens.active.clear_cells(mut page, mut cur_row, mut cells)
		}

		// Mark the row as dirty
		cur_p.mark_dirty()

		// We have successfully processed a line.
		y += 1
		// Move our pin down to the next row.
		if p := cur_p.down(1) {
			unsafe {
				*cur_p = p
			}
		}
	}
}

// ============================================================
// Insert / Delete / Erase characters
// ============================================================

// Inserts spaces at current cursor position moving existing cell contents
// to the right. The contents of the count right-most columns in the scroll
// region are lost. The cursor position is not changed.
//
// This unsets the pending wrap state without wrapping.
//
// The inserted cells are colored according to the current SGR state.
pub fn (mut self Terminal) insert_blanks(count uint) {
	// Unset pending wrap state without wrapping. Note: this purposely
	// happens BEFORE the scroll region check below, because that's what
	// xterm does.
	self.screens.active.cursor.pending_wrap = false

	// If our cursor is outside the margins then do nothing. We DO reset
	// wrap state still so this must remain below the above logic.
	if self.screens.active.cursor.x < self.scrolling_region.left
		|| self.screens.active.cursor.x > self.scrolling_region.right {
		return
	}

	// If our count is larger than the remaining amount, we just erase right.
	// We only do this if we can erase the entire line (no right margin).
	// if (right_limit == self.cols and
	//     count > right_limit - self.screens.active.cursor.x)
	// {
	//     self.eraseLine(.right, false);
	//     return;
	// }

	// left is just the cursor position but as a multi-pointer
	left := int(self.screens.active.cursor.x)
	mut page := &self.screens.active.cursor.page_pin.node.data
	mut row := self.screens.active.cursor.page_row
	row_idx := page.row_index(row)

	// If our X is a wide spacer tail then we need to erase the
	// previous cell too so we don't split a multi-cell character.
	if self.screens.active.cursor.page_cell.wide == .spacer_tail {
		assert self.screens.active.cursor.x > 0
		mut pair := unsafe { row.cells[left - 1..left + 1] }
		self.screens.active.clear_cells(mut page, mut row, mut pair)
	}

	// Remaining cols from our cursor to the right margin.
	rem := uint(self.scrolling_region.right - self.screens.active.cursor.x + 1)

	// We can only insert blanks up to our remaining cols
	adjusted_count := if count < rem { count } else { rem }

	// This is the amount of space at the right of the scroll region
	// that will NOT be blank, so we need to shift the correct cols right.
	// "scroll_amount" is the number of such cols.
	scroll_amount := rem - adjusted_count
	if scroll_amount > 0 {
		page.pause_integrity_checks(true)
		defer { page.pause_integrity_checks(false) }

		mut x := left + int(scroll_amount) - 1

		// If our last cell we're shifting is wide, then we need to clear
		// it to be empty so we don't split the multi-cell char.
		if row.cells[x].wide == .wide {
			assert row.cells[x + 1].wide == .spacer_tail
			mut end_pair := unsafe { row.cells[x..x + 2] }
			self.screens.active.clear_cells(mut page, mut row, mut end_pair)
		}

		// We work backwards so we don't overwrite data.
		for x >= left {
			page.swap_cells(row_idx, uint(x), uint(x) + adjusted_count)
			x -= 1
		}
	}

	// Insert blanks. The blanks preserve the background color.
	mut blanks := unsafe { row.cells[left..left + int(adjusted_count)] }
	self.screens.active.clear_cells(mut page, mut row, mut blanks)

	// Our row is always dirty
	self.screens.active.cursor_mark_dirty()
}

// Removes amount characters from the current cursor position to the right.
// The remaining characters are shifted to the left and space from the right
// margin is filled with spaces.
//
// If amount is greater than the remaining number of characters in the
// scrolling region, it is adjusted down.
//
// Does not change the cursor position.
pub fn (mut self Terminal) delete_chars(count_req uint) {
	if count_req == 0 {
		return
	}

	// If our cursor is outside the margins then do nothing. We DO reset
	// wrap state still so this must remain below the above logic.
	if self.screens.active.cursor.x < self.scrolling_region.left
		|| self.screens.active.cursor.x > self.scrolling_region.right {
		return
	}

	// left is just the cursor position but as a multi-pointer
	left := int(self.screens.active.cursor.x)
	mut page := &self.screens.active.cursor.page_pin.node.data
	mut row := self.screens.active.cursor.page_row
	row_idx := page.row_index(row)

	// Remaining cols from our cursor to the right margin.
	rem := uint(self.scrolling_region.right - self.screens.active.cursor.x + 1)

	// We can only insert blanks up to our remaining cols
	count := if count_req < rem { count_req } else { rem }

	self.screens.active.split_cell_boundary(self.screens.active.cursor.x)
	self.screens.active.split_cell_boundary(self.screens.active.cursor.x + u32(count))
	self.screens.active.split_cell_boundary(self.scrolling_region.right + 1)

	// This is the amount of space at the right of the scroll region
	// that will NOT be blank, so we need to shift the correct cols right.
	// "scroll_amount" is the number of such cols.
	scroll_amount := rem - count
	mut x := left
	if scroll_amount > 0 {
		page.pause_integrity_checks(true)
		defer { page.pause_integrity_checks(false) }

		right := left + int(scroll_amount) - 1

		for x <= right {
			page.swap_cells(row_idx, uint(x) + count, uint(x))
			x += 1
		}
	}

	// Insert blanks. The blanks preserve the background color.
	mut blanks := unsafe { row.cells[x..x + int(rem - scroll_amount)] }
	self.screens.active.clear_cells(mut page, mut row, mut blanks)

	// Our row's soft-wrap is always reset.
	self.screens.active.cursor_reset_wrap()

	// Our row is always dirty
	self.screens.active.cursor_mark_dirty()
}

pub fn (mut self Terminal) erase_chars(count_req uint) {
	remaining := uint(self.cols - self.screens.active.cursor.x)
	mut count := if remaining < count_req { remaining } else { count_req }
	if count < 1 {
		count = if remaining < 1 { remaining } else { 1 }
	}

	// If our last cell is a wide char then we need to also clear the
	// cell beyond it since we can't just split a wide char.
	if count != remaining {
		last := self.screens.active.cursor_cell_right(u32(count) - 1)
		if last.wide == .wide {
			count += 1
		}
	}

	// Handle any boundary conditions on the edges of the erased area.
	//
	// TODO(qwerasd): This isn't actually correct if you take in to account
	// protected modes. We need to figure out how to make `clearCells` or at
	// least `clearUnprotectedCells` handle boundary conditions...
	self.screens.active.split_cell_boundary(self.screens.active.cursor.x)
	self.screens.active.split_cell_boundary(self.screens.active.cursor.x + u32(count))

	// Reset our row's soft-wrap.
	self.screens.active.cursor_reset_wrap()

	// Mark our cursor row as dirty
	self.screens.active.cursor_mark_dirty()

	// Clear the cells
	mut page := &self.screens.active.cursor.page_pin.node.data
	mut row := self.screens.active.cursor.page_row
	mut cells := row_cells_at(row, self.screens.active.cursor.page_cell, int(count))

	// If we never had a protection mode, then we can assume no cells
	// are protected and go with the fast path. If the last protection
	// mode was not ISO we also always ignore protection attributes.
	if self.screens.active.protected_mode != .iso {
		self.screens.active.clear_cells(mut page, mut row, mut cells)
		return
	}

	self.screens.active.clear_unprotected_cells(mut page, mut row, mut cells)
}

// Erase the line.
pub fn (mut self Terminal) erase_line(mode EraseLine, protected_req bool) {
	// Get our start/end positions depending on mode.
	mut start := u32(0)
	mut end := u32(0)
	match mode {
		.right {
			mut x := self.screens.active.cursor.x

			// If our X is a wide spacer tail then we need to erase the
			// previous cell too so we don't split a multi-cell character.
			if x > 0 && self.screens.active.cursor.page_cell.wide == .spacer_tail {
				x -= 1
			}

			// Reset our row's soft-wrap.
			self.screens.active.cursor_reset_wrap()

			start = x
			end = self.cols
		}
		.left {
			mut x := self.screens.active.cursor.x

			// If our x is a wide char we need to delete the tail too.
			if self.screens.active.cursor.page_cell.wide == .wide {
				x += 1
			}

			start = 0
			end = x + 1
		}
		// Note that it seems like complete should reset the soft-wrap
		// state of the line but in xterm it does not.
		.complete {
			start = 0
			end = self.cols
		}
		else {
			log.error('unimplemented erase line mode: ${mode}')
			return
		}
	}

	// All modes will clear the pending wrap state and we know we have
	// a valid mode at this point.
	self.screens.active.cursor.pending_wrap = false

	// We always mark our row as dirty
	self.screens.active.cursor_mark_dirty()

	// Start of our cells
	mut page := &self.screens.active.cursor.page_pin.node.data
	mut row := self.screens.active.cursor.page_row
	mut cells := unsafe { row.cells[int(start)..int(end)] }

	// We respect protected attributes if explicitly requested (probably
	// a DECSEL sequence) or if our last protected mode was ISO even if its
	// not currently set.
	protected := self.screens.active.protected_mode == .iso || protected_req

	// If we're not respecting protected attributes, we can use a fast-path
	// to fill the entire line.
	if !protected {
		self.screens.active.clear_cells(mut page, mut row, mut cells)
		return
	}

	self.screens.active.clear_unprotected_cells(mut page, mut row, mut cells)
}

// Erase the display.
pub fn (mut self Terminal) erase_display(mode EraseDisplay, protected_req bool) {
	// We respect protected attributes if explicitly requested or if our
	// last protected mode was ISO.
	is_protected := self.screens.active.protected_mode == .iso || protected_req

	match mode {
		.scroll_complete {
			self.screens.active.scroll_clear() or {
				self.erase_display(.complete, protected_req)
				return
			}
			// Unsets pending wrap state
			self.screens.active.cursor.pending_wrap = false
			// Clear all Kitty graphics state for this screen
			self.screens.active.kitty_images.delete(mut self, DeleteAll{ delete: true })
		}
		.complete {
			// If we're on the primary screen and our last non-empty row is
			// a prompt, then we do a scroll_complete instead. (Heuristic for ^L)
			if self.screens.active_key == .primary {
				// Check for prompt at bottom of active area
				at_prompt := self.check_at_prompt_for_clear()
				if at_prompt {
					self.screens.active.scroll_clear() or {}
				}
			}

			// All active area
			self.screens.active.clear_rows(Point.new(.active, Coordinate{}), ?Point(none), is_protected)
			self.screens.active.cursor.pending_wrap = false
			// Clear all Kitty graphics state for this screen
			self.screens.active.kitty_images.delete(mut self, DeleteAll{ delete: true })
			self.flags.set_dirty_clear(true)
		}
		.below {
			// All lines to the right (including the cursor)
			self.erase_line(.right, protected_req)

			// All lines below
			if self.screens.active.cursor.y + 1 < self.rows {
				self.screens.active.clear_rows(Point.new(.active, Coordinate{
					y: self.screens.active.cursor.y + 1
				}), ?Point(none), is_protected)
			}
		}
		.above {
			// Erase to the left (including the cursor)
			self.erase_line(.left, protected_req)

			// All lines above
			if self.screens.active.cursor.y > 0 {
				self.screens.active.clear_rows(Point.new(.active, Coordinate{}), Point.new(.active, Coordinate{ y: self.screens.active.cursor.y - 1 }), is_protected)
			}
		}
		.scrollback {
			self.screens.active.erase_history()
		}
	}
}

// The `at_prompt:` block of eraseDisplay's complete mode: go from the bottom
// of the active area up and see if we're at a prompt.
fn (self &Terminal) check_at_prompt_for_clear() bool {
	active_br := self.screens.active.pages.get_bottom_right(.active) or { return false }
	mut it := active_br.row_iterator(.left_up, self.screens.active.pages.get_top_left(.active))
	for {
		p := it.next() or { break }
		row := p.row_and_cell().row
		match row.header.semantic_prompt {
			// If we're at a prompt or input area, then we are at a prompt.
			.prompt, .prompt_continuation {
				return true
			}
			// If we have command output, then we're most certainly not
			// at a prompt.
			.unknown {
				return false
			}
		}
	}
	return false
}

// ============================================================
// DECALN - Screen Alignment Pattern
// ============================================================

// Resets all margins and fills the whole screen with the character 'E'.
// Sets the cursor to the top left corner.
pub fn (mut self Terminal) decaln() ! {
	// Clear all stylistic attributes except the foreground and background
	// colors. Ghostty does this before any other mutation because updating the
	// page-local cursor style is the only fallible part of DECALN.
	old_style := self.screens.active.cursor.style
	self.screens.active.cursor.style = CellStyle{
		fg_color: old_style.fg_color
		bg_color: old_style.bg_color
	}
	self.screens.active.manual_style_update() or {
		self.screens.active.cursor.style = old_style
		return err
	}

	// Reset margins, also sets cursor to top-left
	self.scrolling_region = ScrollingRegion{
		top:    0
		bottom: self.rows - 1
		left:   0
		right:  self.cols - 1
	}

	// Origin mode is disabled
	self.modes.set(.origin, false)

	// Move our cursor to the top-left
	self.set_cursor_pos(1, 1)

	// Use clearRows instead of eraseDisplay because we must NOT respect
	// protected attributes here.
	self.screens.active.clear_rows(Point.new(.active, Coordinate{}), none, false)

	// Fill with Es by moving the cursor but reset it after.
	for {
		mut page := &self.screens.active.cursor.page_pin.node.data
		mut row := self.screens.active.cursor.page_row
		cols := int(page.size.cols)
		for x in 0 .. cols {
			row.cells[x] = CellData{
				content_tag:  .codepoint
				codepoint:    u32(`E`)
				style_id:     self.screens.active.cursor.style_id
				// DECALN does not respect protected state. Verified with xterm.
				is_protected: false
			}
		}

		// If we have a ref-counted style, increase
		if self.screens.active.cursor.style_id != default_style_id {
			page.styles.use_multiple(self.screens.active.cursor.style_id, u16(cols))
			row.header.styled = true
		}

		// We messed with the page so assert its integrity here.
		page.assert_integrity()

		self.screens.active.cursor_mark_dirty()
		if self.screens.active.cursor.y == self.rows - 1 {
			break
		}
		self.screens.active.cursor_down(1)
	}

	// Reset the cursor to the top-left
	self.set_cursor_pos(1, 1)
}

// ============================================================
// Style attributes
// ============================================================

// Set a style attribute.
// Execute a kitty graphics command. The buf is used to populate with
// the response that should be sent as an APC sequence. The response will
// be a full, valid APC sequence.
//
// If an error occurs, the caller should response to the pty that a
// an error occurred otherwise the behavior of the graphics protocol is
// undefined.
pub fn (mut self Terminal) kitty_graphics(cmd &Command) ?Response {
	return kitty_graphics_execute(mut self, cmd)
}

pub fn (mut self Terminal) set_attribute(attr SgrAttribute) ! {
	self.screens.active.set_attribute(attr)!
}

// Print the active attributes as a string. This is used to respond to DECRQSS.
pub fn (mut self Terminal) print_attributes() !string {
	mut result := strings.new_builder(64)

	// The SGR response always starts with a 0.
	result.write_string('0')

	pen := self.screens.active.cursor.style

	if pen.flags.bold() {
		result.write_string(';1')
	}
	if pen.flags.faint() {
		result.write_string(';2')
	}
	if pen.flags.italic() {
		result.write_string(';3')
	}
	if pen.flags.underline() != .none {
		result.write_string(';4')
	}
	if pen.flags.blink() {
		result.write_string(';5')
	}
	if pen.flags.inverse() {
		result.write_string(';7')
	}
	if pen.flags.invisible() {
		result.write_string(';8')
	}
	if pen.flags.strikethrough() {
		result.write_string(';9')
	}

	match pen.fg_color {
		StyleColorNone {}
		StyleColorPalette {
			idx := (pen.fg_color as StyleColorPalette).index
			if idx >= 16 {
				result.write_string(';38:5:${idx}')
			} else if idx >= 8 {
				result.write_string(';9${idx - 8}')
			} else {
				result.write_string(';3${idx}')
			}
		}
		StyleColorRgb {
			rgb := (pen.fg_color as StyleColorRgb).rgb
			result.write_string(';38:2::${rgb.r}:${rgb.g}:${rgb.b}')
		}
	}
	match pen.bg_color {
		StyleColorNone {}
		StyleColorPalette {
			idx := (pen.bg_color as StyleColorPalette).index
			if idx >= 16 {
				result.write_string(';48:5:${idx}')
			} else if idx >= 8 {
				result.write_string(';10${idx - 8}')
			} else {
				result.write_string(';4${idx}')
			}
		}
		StyleColorRgb {
			rgb := (pen.bg_color as StyleColorRgb).rgb
			result.write_string(';48:2::${rgb.r}:${rgb.g}:${rgb.b}')
		}
	}

	return result.str()
}

// ============================================================
// DECCOLM
// ============================================================

// DECCOLM changes the terminal width between 80 and 132 columns.
// This will do NOTHING unless enable_mode_3 has been set.
pub fn (mut self Terminal) deccolm(mode DeccolmMode) ! {
	// If DEC mode 40 isn't enabled, then this is ignored.
	if !self.modes.get(.enable_mode_3) {
		self.modes.set(.column_132, false)
		return
	}

	// Enable it
	self.modes.set(.column_132, mode == .cols_132)

	// Resize to the requested size
	new_cols := match mode {
		.cols_132 { u16(132) }
		.cols_80 { u16(80) }
	}
	self.resize(new_cols, self.rows)!

	// Erase our display and move our cursor.
	self.erase_display(.complete, false)
	self.set_cursor_pos(1, 1)
}

// ============================================================
// Resize
// ============================================================

// Resize the underlying terminal.
pub fn (mut self Terminal) resize(cols u16, rows u16) ! {
	// If our cols/rows didn't change then we're done
	if self.cols == cols && self.rows == rows {
		return
	}

	// Resize our tabstops
	if self.cols != cols {
		self.tabstops.deinit()
		self.tabstops = Tabstops.init(uint(cols), 8)!
	}

	// Resize primary screen, which supports reflow.
	mut primary := self.screens.get(.primary) or { panic('primary screen must be initialized') }
	primary.resize(ScreenResize{
		cols:          u32(cols)
		rows:          u32(rows)
		reflow:        self.modes.get(.wraparound)
		prompt_redraw: self.flags.shell_redraws_prompt()
	})!

	// Alternate screen, if it exists, doesn't reflow.
	if mut alternate := self.screens.get(.alternate) {
		alternate.resize(ScreenResize{
			cols:   u32(cols)
			rows:   u32(rows)
			reflow: false
		})!
	}

	// Whenever we resize we just mark it as a screen clear
	self.flags.set_dirty_clear(true)

	// Set our size
	self.cols = cols
	self.rows = rows

	// Reset the scrolling region
	self.scrolling_region = ScrollingRegion{
		top:    0
		bottom: rows - 1
		left:   0
		right:  cols - 1
	}
}

// ============================================================
// PWD
// ============================================================

// Set the pwd for the terminal.
pub fn (mut self Terminal) set_pwd(pwd_str string) ! {
	self.pwd = pwd_str
}

// Returns the pwd for the terminal, if any.
pub fn (self &Terminal) get_pwd() ?string {
	if self.pwd.len == 0 {
		return none
	}
	return self.pwd
}

// ============================================================
// Screen switching
// ============================================================

// SwitchScreenResult preserves Ghostty's !?*Screen return contract. V cannot
// directly nest a fallible result and an optional, so the optional previous
// screen is carried in an explicit result value.
pub struct SwitchScreenResult {
pub:
	previous ?&Screen
}

// Switch to the given screen type (alternate or primary).
//
// This does NOT handle behaviors such as clearing the screen,
// copying the cursor, etc.
pub fn (mut self Terminal) switch_screen(key ScreenKey) !SwitchScreenResult {
	// If we're already on the requested screen we do nothing.
	if self.screens.active_key == key {
		return SwitchScreenResult{}
	}
	mut old := self.screens.active

	// We always end hyperlink state when switching screens.
	old.end_hyperlink()

	// Get or initialize the new screen.
	mut new := self.screens.get(key) or {
		self.screens.get_init(key, ScreenOptions{
			cols:                      u32(self.cols)
			rows:                      u32(self.rows)
			max_scrollback:            if key == .primary {
				primary := self.screens.get(.primary) or {
					panic('primary screen must be initialized')
				}
				primary.pages.explicit_max_size
			} else {
				0
			}
			// Inherit our Kitty image storage limit from the primary
			// screen if we have to initialize.
			kitty_image_storage_limit: (self.screens.get(.primary) or {
				panic('primary screen must be initialized')
			}).kitty_images.total_limit
		})!
	}

	// The new screen should not have any hyperlinks set.
	assert new.cursor.hyperlink_id == 0

	// Bring charset state with us.
	new.charset = old.charset

	// Clear selection and redraw Kitty images on the new screen.
	new.clear_selection()
	new.kitty_images.dirty = true

	// Mark terminal as dirty.
	self.flags.set_dirty_clear(true)

	// Finalize the switch.
	self.screens.switch_to(key)

	return SwitchScreenResult{ previous: old }
}

// Switch screen via a mode switch (e.g. mode 47, 1047, 1049).
pub fn (mut self Terminal) switch_screen_mode(mode SwitchScreenMode, enabled bool) ! {
	match mode {
		.mode_47 {}
		// If we're disabling 1047 and we're on alt screen then
		// we clear the screen.
		.mode_1047 {
			if !enabled && self.screens.active_key == .alternate {
				self.erase_display(.complete, false)
			}
		}

		// 1049 unconditionally saves the cursor on enabling.
		.mode_1049 {
			if enabled {
				self.save_cursor()
			}
		}
	}

	// Switch screens first to whatever we're going to.
	to := if enabled { ScreenKey.alternate } else { ScreenKey.primary }
	old_ := self.switch_screen(to)!

	match mode {
		// For these modes, we need to copy the cursor. We only copy the
		// cursor if the screen actually changed, otherwise the cursor is
		// already copied. The cursor is copied regardless of destination
		// screen.
		.mode_47, .mode_1047 {
			if old := old_.previous {
				old_cursor := old.cursor
				self.screens.active.cursor_copy(old_cursor, CursorCopyOptions{
					hyperlink: false
				}) or {
					// cursor copy failed entering alt screen
				}
			}
		}

		// Mode 1049 restores cursor on the primary screen when disabled.
		.mode_1049 {
			if enabled {
				self.erase_display(.complete, false)

				// When we enter alt screen with 1049, we always copy the
				// cursor from the primary screen (if we weren't already
				// on it).
				if old := old_.previous {
					old_cursor := old.cursor
					self.screens.active.cursor_copy(old_cursor, CursorCopyOptions{
						hyperlink: false
					}) or {
						// cursor copy failed entering alt screen
					}
				}
			} else {
				self.restore_cursor()
			}
		}
	}
}

// ============================================================
// Plain string output
// ============================================================

// Return the current string value of the terminal. Newlines are
// encoded as "\n". This omits any formatting such as fg/bg.
pub fn (mut self Terminal) plain_string() !string {
	return self.screens.active.dump_string_alloc(.viewport)!
}

// Same as plain_string, but respects row wrap state when building the string.
pub fn (mut self Terminal) plain_string_unwrapped() !string {
	return self.screens.active.dump_string_alloc_unwrapped(.viewport)!
}

// ============================================================
// Full reset
// ============================================================

// Full reset.
//
// This will attempt to free the existing screen memory but if that fails
// this will reuse the existing memory. In the latter case, memory may
// be wasted (since its unused) but it isn't leaked.
pub fn (mut self Terminal) full_reset() {
	// Ensure we're back on primary screen
	self.screens.switch_to(.primary)
	self.screens.remove(.alternate)

	// Reset our screens
	self.screens.active.reset()

	// Reset our basic state
	self.modes.reset()
	self.flags = TerminalFlags{}
	self.tabstops.reset(terminal.tabstop_interval)
	self.previous_char = none
	self.pwd = ''
	self.status_display = .main
	self.scrolling_region = ScrollingRegion{
		top:    0
		bottom: self.rows - 1
		left:   0
		right:  self.cols - 1
	}

	// Always mark dirty so we redraw everything
	self.flags.set_dirty_clear(true)
}

// Perform a semantic prompt command (OSC 133).
//
// If there is an error, we do our best to get the terminal into some
// coherent state, since callers typically can't handle errors (since
// they're sending sequences via the pty).
//
pub fn (mut self Terminal) semantic_prompt(cmd osc.SemanticPrompt) {
	options := cmd.options_unvalidated
	match cmd.action {
		.fresh_line {
			self.semantic_prompt_fresh_line()
		}
		.fresh_line_new_prompt {
			self.semantic_prompt_fresh_line()
			self.screens.active.cursor_set_semantic_content(CursorSemanticPrompt{
				kind: prompt_kind_from_osc(options)
			})

			if redraw := osc.read_redraw(options) {
				self.flags.set_shell_redraws_prompt(redraw)
			}

			if click_events := osc.read_click_events(options) {
				if click_events {
					self.screens.active.semantic_prompt.click = semantic_click_click_events
					return
				}
			}
			if click := osc.read_click(options) {
				self.screens.active.semantic_prompt.click = SemanticClick.from_cl(click)
			}
		}
		.new_command {
			// Spec:
			// Same as OSC "133;A" but may first implicitly terminate a
			// previous command: if the options specify an aid and there
			// is an active (open) command with matching aid, finish the
			// innermost such command (as well as any other commands
			// nested more deeply). If no aid is specified, treat as an
			// aid whose value is the empty string.

			// Ghostty:
			// We don't currently do explicit command tracking in any way
			// so there is no need to terminate prior commands. We just
			// perform the `A` action.
			self.semantic_prompt(osc.SemanticPrompt{
				action:              .fresh_line_new_prompt
				options_unvalidated: cmd.options_unvalidated
			})
		}
		.prompt_start {
			self.screens.active.cursor_set_semantic_content(CursorSemanticPrompt{
				kind: prompt_kind_from_osc(options)
			})
		}
		.end_prompt_start_input {
			self.screens.active.cursor_set_semantic_content(CursorSemanticInput{
				clear: .clear_explicit
			})
		}
		.end_prompt_start_input_terminate_eol {
			self.screens.active.cursor_set_semantic_content(CursorSemanticInput{
				clear: .clear_eol
			})
		}
		.end_input_start_output {
			self.screens.active.cursor_set_semantic_content(CursorSemanticOutput{})

			// If our current row is marked as a prompt and we're at column
			// zero then we assume we're un-prompting. This is a heuristic to
			// deal with fish, mostly (it has no PS2 equivalent and its OSC133
			// marking doesn't output continuation lines as k=s). So we assume
			// when we get a newline with a prompt cursor that the new line is
			// also a prompt. But fish changes to output on the newline, so if
			// we're at col 0 we just assume we're overwriting the prompt.
			if self.screens.active.cursor.page_row.header.semantic_prompt != .unknown
				&& self.screens.active.cursor.x == 0 {
				self.screens.active.cursor.page_row.header.semantic_prompt = .unknown
			}
		}
		.end_command {
			self.screens.active.cursor_set_semantic_content(CursorSemanticOutput{})
		}
	}
}

fn prompt_kind_from_osc(options string) PromptKind {
	kind := osc.read_prompt_kind(options) or { return .initial }
	return match kind {
		.initial { .initial }
		.right { .right }
		.continuation { .continuation }
		.secondary { .secondary }
	}
}

// OSC 133;L: do a fresh-line.
fn (mut self Terminal) semantic_prompt_fresh_line() {
	// Spec: "If the cursor is the initial column (left, assuming
	// left-to-right writing), do nothing." We take the liberty to assume
	// that in a left/right margin context, if the cursor is outside of the
	// left margin, we treat it as being at the left margin for the purposes
	// of this command.
	left_margin := if self.screens.active.cursor.x < self.scrolling_region.left {
		u32(0)
	} else {
		self.scrolling_region.left
	}

	if self.screens.active.cursor.x == left_margin {
		return
	}

	self.carriage_return()
	self.index() or {}
}

// ============================================================
// Testing helpers
// ============================================================

// Returns true if the point is dirty, used for testing.
pub fn (self &Terminal) is_dirty(pt Point) bool {
	cell := self.screens.active.pages.get_cell(pt) or { panic('dirty point is outside the page list') }
	return cell.is_dirty()
}

// Clear all dirty bits. Testing only.
pub fn (mut self Terminal) clear_dirty() {
	self.screens.active.pages.clear_dirty()
}
