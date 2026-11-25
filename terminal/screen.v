module terminal

import osc
import lib_allocator
import tripwire
import unicode

// --- Original Ghostty Comments Start: src/terminal/Screen.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/terminal/Screen.zig
//
// The general purpose allocator to use for all memory allocations.
// Unfortunately some screen operations do require allocation.
// The list of pages in the screen.
// Special-case where we want no scrollback whatsoever. We have to flag
// this because max_size 0 in PageList gets rounded up to two pages so
// we can always have an active screen.
// The current cursor position
// The saved cursor
// The selection for this screen (if any). This MUST be a tracked selection
// otherwise the selection will become invalid. Instead of accessing this
// directly to set it, use the `select` function which will assert and
// automatically setup tracking.
// The charset state
// The current or most recent protected mode. Once a protection mode is
// set, this will never become "off" again until the screen is reset.
// The current state of whether protection attributes should be set is
// set on the Cell pen; this is only used to determine the most recent
// protection mode since some sequences such as ECH depend on this.
// The kitty keyboard settings.
// Kitty graphics protocol state.
// Semantic prompt (OSC133) state.
// Dirty flags for the renderer.
// See Terminal.Dirty. This behaves the same way.
// Set when the selection is set or unset, regardless of if the
// selection is changed or not.
// When an OSC8 hyperlink is hovered, we set the full screen as dirty
// because links can span multiple lines.
// This is flipped to true when any sort of semantic content is
// seen. In particular, this is set to true only when a `prompt` type
// is ever set on our cursor.
//
// This is used to optimize away semantic content operations if we know
// we've never seen them.
// This is set on any `cl` or `click_events` option set on the
// most recent OSC 133 commands to specify how click handling in a
// prompt is handling.
// The cursor position and style.
// The x/y position within the active area.
// The visual style of the cursor. This defaults to block because
// it has to default to something, but users of this struct are
// encouraged to set their own default.
// The "last column flag (LCF)" as its called. If this is set then the
// next character print will force a soft-wrap.
// The protected mode state of the cursor. If this is true then
// all new characters printed will have the protected state set.
// The currently active style. This is the concrete style value
// that should be kept up to date. The style ID to use for cell writing
// is below.
// The currently active style ID. The style is page-specific so when
// we change pages we need to ensure that we update that page with
// our style when used.
// The hyperlink ID that is currently active for the cursor. A value
// of zero means no hyperlink is active. (Implements OSC8, saying that
// so code search can find it.).
// This is the implicit ID to use for hyperlinks that don't specify
// an ID. We do an overflowing add to this so repeats can technically
// happen with carefully crafted inputs but for real workloads its
// highly unlikely -- and the fix is for the TUI program to use explicit
// IDs.
// Heap-allocated hyperlink state so that we can recreate it when
// the cursor page pin changes. We can't get it from the old screen
// state because the page may be cleared. This is heap allocated
// because its most likely null.
// The current semantic content type for the cursor that will be
// applied to any newly written cells.
// The pointers into the page list where the cursor is currently
// located. This makes it faster to move the cursor.
// Saved cursor state.
// State required for all charset operations.
// The list of graphical charsets by slot
// GL is the slot to use when using a 7-bit printable char (up to 127)
// GR used for 8-bit printable chars.
// Single shift where a slot is used for exactly one char.
// An array to map a charset slot to a lookup table.
//
// We use this bespoke struct instead of `std.EnumArray` because
// accessing these slots is very performance critical since it's
// done for every single print. This benchmarks faster.
// The maximum size of scrollback in bytes. Zero means unlimited. Any
// other value will be clamped to support a minimum of the active area.
// The total storage limit for Kitty images in bytes for this
// screen. Kitty image storage is per-screen.
// A simple, default terminal. If you rely on specific dimensions or
// scrollback (or lack of) then do not use this directly. This is just
// for callers that need some defaults.
// Initialize a new screen.
//
// max_scrollback is the amount of scrollback to keep in bytes. This
// will be rounded UP to the nearest page size because our minimum allocation
// size is that anyways.
//
// If max scrollback is 0, then no scrollback is kept at all.
// Initialize our backing pages.
// Create our tracked pin for the cursor.
// This can't fail because the storage is always empty at this point
// and the only fail-able case is that we have to evict images.
// Assert that the screen is in a consistent state. This doesn't check
// all pages in the page list because that is SO SLOW even just for
// tests. This only asserts the screen specific data so callers should
// ensure they're also calling page integrity checks if necessary.
// We don't run integrity checks on Valgrind because its soooooo slow,
// Valgrind is our integrity checker, and we run these during unit
// tests (non-Valgrind) anyways so we're verifying anyways.
// Our cursor x/y should always match the pin. If this doesn't
// match then it indicates that the tracked pin moved and we didn't
// account for it by either calling cursorReload or manually
// adjusting.
// Reset the screen according to the logic of a DEC RIS sequence.
//
// - Clears the screen and attempts to reclaim memory.
// - Moves the cursor to the top-left.
// - Clears any cursor state: style, hyperlink, etc.
// - Resets the charset
// - Clears the selection
// - Deletes all Kitty graphics
// - Resets Kitty Keyboard settings
// - Disables protection mode
//
// Reset our pages
// The above reset preserves tracked pins so we can still use
// our cursor pin, which should be at the top-left already.
// Reset kitty graphics storage
// Reset our basic state
// Clone the screen.
//
// This will copy:
//
//   - Screen dimensions
//   - Screen data (cell state, etc.) for the region
//
// Anything not mentioned above is NOT copied. Some of this is for
// very good reason:
//
//   - Kitty images have a LOT of data. This is not efficient to copy.
//     Use a lock and access the image data. The dirty bit is there for
//     a reason.
//   - Cursor location can be expensive to calculate with respect to the
//     specified region. It is faster to grab the cursor from the old
//     screen and then move it to the new screen.
//   - Current hyperlink cursor state has heap allocations. Since clone
//     is only for read-only operations, it is better to not have any
//     hyperlink state. Note that already-written hyperlinks are cloned.
//
// If not mentioned above, then there isn't a specific reason right now
// to not copy some data other than we probably didn't need it and it
// isn't necessary for screen coherency.
//
// Other notes:
//
//   - The viewport will always be set to the active area of the new
//     screen. This is the bottom "rows" rows.
//   - If the clone region is smaller than a viewport area, blanks will
//     be filled in at the bottom.
//
// Create a tracked pin remapper for our selection and cursor. Note
// that we may want to expose this generally in the future but at the
// time of doing this we don't need to.
// Find our cursor. If the cursor isn't in the cloned area, we move it
// to the top-left arbitrarily because a screen must have SOME cursor.
// Preserve our selection if we have one.
// No start means it is outside the cloned area.
// If we have no end pin then either
// (1) our whole selection is outside the cloned area or
// (2) our cloned area is within the selection
// We check if the selection bottom right pin is above
// the cloned area or if the top left pin is below the
// cloned area, in either of these cases it means that
// the selection is fully out of bounds, so we have no
// selection in the cloned area and break out now.
// We move the top pin back in bounds to the top row.
// If we got to this point it means that the selection is not
// fully out of bounds, so we move the bottom right pin back
// in bounds if it isn't already.
// If the page being modified isn't our cursor page then
// this is a quick operation because we have no additional
// accounting. We have to do this check here BEFORE calling
// increaseCapacity because increaseCapacity will update all
// our tracked pins (including our cursor).
// We're modifying the cursor page. When we increase the
// capacity below it will be short the ref count on our
// current style and hyperlink, so we need to init those.
// Re-add the style, if the page somehow doesn't have enough
// memory to add it, we emit a warning and gracefully degrade
// to the default style for the cursor.
// TODO: Should we increase the capacity further in this case?
// Reset the cursor style.
// Re-add the hyperlink, if the page somehow doesn't have enough
// memory to add it, we emit a warning and gracefully degrade to
// no hyperlink.
// So we don't attempt to free any memory in the replaced page.
// Re-add
// TODO: Should we increase the capacity further in this case?
// Remove our old link
// Reload the cursor information because the pin changed.
// So our page row/cell and so on are all off.
// Move the cursor right. This is a specialized function that is very fast
// if the caller can guarantee we have space to move right (no wrapping).
// Move the cursor left.
// Move the cursor up.
//
// Precondition: The cursor is not at the top of the screen.
// Move the cursor down.
//
// Precondition: The cursor is not at the bottom of the screen.
// We move the offset into our page list to the next row and then
// get the pointers to the row/cell and set all the cursor state up.
// Move the cursor to some absolute horizontal position.
// Move the cursor to some absolute position.
// Reloads the cursor pointer information into the screen. This is expensive
// so it should only be done in cases where the pointers are invalidated
// in such a way that its difficult to recover otherwise.
// Our tracked pin is ALWAYS accurate, so we derive the active
// point from the pin. If this returns null it means our pin
// points outside the active area. In that case, we update the
// pin to be the top-left.
// If we have a style, we need to ensure it is in the page because this
// method may also be called after a page change.
// This failure should not happen because manualStyleUpdate
// handles page splitting, overflow, and more. This should only
// happen if we're out of RAM. In this case, we'll just degrade
// gracefully back to the default style.
// Scroll the active area and keep the cursor at the bottom of the screen.
// This is a very specialized function but it keeps it fast.
// Scrolling dirties the images because it updates their placements pins.
// If we have no scrollback, then we shift all our rows instead.
// If we have a single-row screen, we have no rows to shift
// so our cursor is in the correct place we just have to clear
// the cells.
// The call to `eraseRow` will move the tracked cursor pin up by one
// row, but we don't actually want that, so we keep the old pin and
// put it back after calling `eraseRow`.
// eraseRow will shift everything below it up.
// Note we don't need to mark anything dirty in this branch
// because eraseRow will mark all the rotated rows as dirty
// in the entire page.
// We don't use `cursorChangePin` here because we aren't
// actually changing the pin, we're keeping it the same.
// We do, however, need to refresh the cached page row
// and cell, because `eraseRow` will have moved the row.
// Grow our pages by one row. The PageList will handle if we need to
// allocate, prune scrollback, whatever.
// We do this all in a block here because referencing this pin
// after cursorChangePin is unsafe, and we want to keep it out
// of scope.
// If our pin page change it means that the page that the pin
// was on was pruned. In this case, grow() moves the pin to
// the top-left of the new page. This effectively moves it by
// one already, we just need to fix up the x value.
// These assertions help catch some pagelist math errors. Our
// x/y should be unchanged after the grow.
// Our new row is always dirty
// Clear the new row so it gets our bg color. We only do this
// if we have a bg color at all.
// The newly created line needs to be styled according to
// the bg color if it is set.
// This scrolls the active area at and above the cursor.
// The lines below the cursor are not scrolled.
// We unconditionally mark the cursor row as dirty here because
// the cursor always changes page rows inside this function, and
// when that happens it can mean the text in the old row needs to
// be re-shaped because the cursor splits runs to break ligatures.
// If the cursor is on the bottom of the screen, its faster to use
// our specialized function for that case.
// Logic below assumes we always have at least one row that isn't moving
// Explanation:
//  We don't actually move everything that's at or above the cursor row,
//  since this would require us to shift up our ENTIRE scrollback, which
//  would be ridiculously expensive. Instead, we insert a new row at the
//  end of the pagelist (`grow()`), and move everything BELOW the cursor
//  DOWN by one row. This has the same practical result but it's a whole
//  lot cheaper in 99% of cases.
// In this case, it means grow() didn't allocate a new page.
// If we're on the last page we can do a very fast path because
// all the rows we need to move around are within a single page.
// Note: we don't need to call cursorChangePin here because
// the pin page is the same so there is no accounting to do
// for styles or any of that.
// Rotate the rows so that the newly created empty row is at the
// beginning. e.g. [ 0 1 2 3 ] in to [ 3 0 1 2 ].
// Mark the whole page as dirty.
//
// Technically we only need to mark from the cursor row to the
// end but this is a hot function, so we want to minimize work.
// Setup our cursor caches after the rotation so it points to the
// correct data
// We didn't grow pages but our cursor isn't on the last page.
// In this case we need to do more work because we need to copy
// elements between pages.
//
// An example scenario of this is shown below:
//
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4302 |1A00000000| | 0
// 4303 |2B00000000| | 1
//      :^         : : = PIN 0
// 4304 |3C00000000| | 2
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |4D00000000| | 3
//    1 |5E00000000| | 4
//      +----------+ :
//     +-------------+
// The newly created line needs to be styled according to
// the bg color if it is set.
// Go through each of the pages following our pin, shift all rows
// down by one, and copy the last row of the previous page.
// Rotate the pages down: [ 0 1 2 3 ] => [ 3 0 1 2 ]
// Copy the last row of the previous page to the top of current.
// Mark dirty on the page, since we are dirtying all rows with this.
// Our current is our cursor page, we need to rotate down from
// our cursor and clear our row.
// Mark the whole page as dirty.
//
// Technically we only need to mark from the cursor row to the
// end but this is a hot function, so we want to minimize work.
// Setup cursor cache data after all the rotations so our
// row is valid.
// Move the cursor down if we're not at the bottom of the screen. Otherwise
// scroll. Currently only used for testing.
// Copy another cursor. The cursor can be on any screen but the x/y
// must be within our screen bounds.
// Copy the hyperlink from the other cursor. If not set, this will
// clear our current hyperlink.
// End any currently active hyperlink on our cursor.
// Keep our old style ID so it can be properly cleaned up below.
// Hyperlinks will be managed separately below.
// Keep our old page pin and X/Y because:
// 1. The old style will need to be cleaned up from the page it's from.
// 2. The new position navigated to by `cursorAbsolute` needs to be in our
//    own screen.
// Call manual style update in order to clean up our old style, if we have
// one, and also to load the style from the other cursor, if it had one.
// Move to the correct location to match the other cursor.
// If the other cursor had a hyperlink, add it to ours.
// Get the hyperlink from the other cursor's page.
// And it to our cursor.
// This shouldn't happen because startHyperlink should handle
// resizing. This only happens if we're truly out of RAM. Degrade
// to forgetting the hyperlink.
// Always use this to write to cursor.page_pin.*.
//
// This specifically handles the case when the new pin is on a different
// page than the old AND we have a style or hyperlink set. In that case,
// we must release our old one and insert the new one, since styles are
// stored per-page.
//
// Note that this can change the cursor pin AGAIN if the process of
// setting up our cursor forces a capacity adjustment of the underlying
// cursor page, so any references to the page pin should be re-read
// from `self.cursor.page_pin` after calling this.
// Moving the cursor affects text run splitting (ligatures) so
// we must mark the old and new page dirty. We do this as long
// as the pins are not equal
// If our pin is on the same page, then we can just update the pin.
// We don't need to migrate any state.
// If we have an old style then we need to release it from the old page.
// Release the style directly from the old page instead of going through
// manualStyleUpdate, because the cursor position may have already been
// updated but the pin has not, which would fail integrity checks.
// If we have a hyperlink then we need to release it from the old page.
// Update our pin to the new page
// On the new page, we need to migrate our style
// This failure should not happen because manualStyleUpdate
// handles page splitting, overflow, and more. This should only
// happen if we're out of RAM. In this case, we'll just degrade
// gracefully back to the default style.
// On the new page, we need to migrate our hyperlink
// So we don't attempt to free any memory in the replaced page.
// Re-add
// This shouldn't happen because startHyperlink should handle
// resizing. This only happens if we're truly out of RAM. Degrade
// to forgetting the hyperlink.
// Remove our old link
// Mark the cursor position as dirty.
// TODO: test
// Reset the cursor row's soft-wrap state and the cursor's pending wrap.
// Also handles clearing the spacer head on the cursor row and resetting
// the wrap_continuation flag on the next row if necessary.
//
// NOTE(qwerasd): This method is not scrolling region aware, and cannot be
// since it's on Screen not Terminal. This needs to be addressed down the
// line. Not an extremely urgent issue since it's an edge case of an edge
// case, but not ideal.
// Reset the cursor's pending wrap state
// This row does not wrap and the next row is not wrapped to
// If the last cell in the row is a spacer head we need to clear it.
// Options for scrolling the viewport of the terminal grid. The reason
// we have this in addition to PageList.Scroll is because we have additional
// scroll behaviors that are not part of the PageList.Scroll enum.
// For all of these, see PageList.Scroll.
// Scroll the viewport of the terminal grid.
// No matter what, scrolling marks our image state as dirty since
// it could move placements. If there are no placements or no images
// this is still a very cheap operation.
// See PageList.scrollClear. In addition to that, we reset the cursor
// to be on top.
// No matter what, scrolling marks our image state as dirty since
// it could move placements. If there are no placements or no images
// this is still a very cheap operation.
// Returns true if the viewport is scrolled to the bottom of the screen.
// Erase the region specified by tl and br, inclusive. This will physically
// erase the rows meaning the memory will be reclaimed (if the underlying
// page is empty) and other rows will be shifted up.
// Erase the rows
// Just to be safe, reset our cursor since it is possible depending
// on the points that our active area shifted so our pointers are
// invalid.
// Clear the region specified by tl and bl, inclusive. Cleared cells are
// colored with the current style background color. This will clear all
// cells in the rows.
//
// If protected is true, the protected flag will be respected and only
// unprotected cells will be cleared. Otherwise, all cells will be cleared.
// Clear all cells
// We need to preserve other row attributes since we only
// cleared unprotected cells.
// Clear the cells with the blank cell.
//
// This takes care to handle cleaning up graphemes and styles.
// This whole operation does unsafe things, so we just want to assert
// the end state.
// Our row and cells should be within the page.
// If we have managed memory (styles, graphemes, or hyperlinks)
// in this row then we go cell by cell and clear them if present.
// If we have no left/right scroll region we can be sure
// that we've cleared all the graphemes, so we clear the
// flag, otherwise we ask the page to update the flag.
// If we have no left/right scroll region we can be sure
// that we've cleared all the hyperlinks, so we clear the
// flag, otherwise we ask the page to update the flag.
// If we have no left/right scroll region we can be sure
// that we've cleared all the styles, so we clear the
// flag, otherwise we ask the page to update the flag.
// Clear cells but only if they are not protected.
// Clean up boundary conditions where a cell will become discontiguous with
// a neighboring cell because either one of them will be moved and/or cleared.
//
// For performance reasons this is specialized to operate on the cursor row.
//
// Handles the boundary between the cell at `x` and the cell at `x - 1`.
//
// So, for example, when moving a region of cells [a, b] (inclusive), call this
// function with `x = a` and `x = b + 1`. It is okay if `x` is out of bounds by
// 1, this will be interpreted correctly.
//
// DOES NOT MODIFY ROW WRAP STATE! See `cursorResetWrap` for that.
//
// The following boundary conditions are handled:
//
// - `x - 1` is a wide character and `x` is a spacer tail:
//   o Both cells will be cleared.
//   o If `x - 1` is the start of the row and was wrapped from a previous row
//     then the previous row is checked for a spacer head, which is cleared if
//     present.
//
// - `x == 0` and is a wide character:
//   o If the row is a wrap continuation then the previous row will be checked
//     for a spacer head, which is cleared if present.
//
// - `x == cols` and `x - 1` is a spacer head:
//   o `x - 1` will be cleared.
//
// NOTE(qwerasd): This method is not scrolling region aware, and cannot be
// since it's on Screen not Terminal. This needs to be addressed down the
// line. Not an extremely urgent issue since it's an edge case of an edge
// case, but not ideal.
// `x` may be up to an INCLUDING `cols`, since that signifies splitting
// the boundary to the right of the final cell in the row.
// [ A B C D E F|]
//              ^ Boundary between final cell and row end.
// Spacer head at end of wrapped row.
// [|A B C D E F ]
//  ^ Boundary between first cell and row start.
//
//  OR
//
// [ A|B C D E F ]
//    ^ Boundary between first cell and second cell.
//
// First cell may be a wrapped wide cell with a spacer
// head on the previous row that needs to be cleared.
// If the first cell in a row is wide the previous row
// may have a spacer head which needs to be cleared.
// If x is 0 then we're done.
// [ ... X|Y ... ]
//        ^ Boundary between two cells in the middle of the row.
// There should not be spacer heads in the middle of the row.
// We don't need to do anything for narrow cells or spacer tails.
// A wide char would be split, so must be cleared.
// Returns the blank cell to use when doing terminal operations that
// require preserving the bg color.
// The new size to resize to
// Whether to reflow soft-wrapped text.
//
// This will reflow soft-wrapped text. If the screen size is getting
// smaller and the maximum scrollback size is exceeded, data will be
// lost from the top of the scrollback.
// Set this to enable prompt redraw on resize. This signals
// that the running program can redraw the prompt if the cursor is
// currently at a prompt. This detects OSC133 prompts lines and clears
// them. If set to `.last`, only the most recent prompt line is cleared.
// Resize the screen. The rows or cols can be bigger or smaller.
//
// If this returns an error, the screen is left in a likely garbage state.
// It is very hard to undo this operation without blowing up our memory
// usage. The only way to recover is to reset the screen. The only way
// this really fails is if page allocation is required and fails, which
// probably means the system is in trouble anyways. I'd like to improve this
// in the future but it is not a priority particularly because this scenario
// (resize) is difficult.
// No matter what we mark our image state as dirty
// Release the cursor style while resizing just
// in case the cursor ends up on a different page.
// Restore the cursor style.
// This failure should not happen because manualStyleUpdate
// handles page splitting, overflow, and more. This should only
// happen if we're out of RAM. In this case, we'll just degrade
// gracefully back to the default style.
// If we have a hyperlink, release it from the old page
// and then we need to re-add it to the new page. This needs
// to happen because resize below typically reallocates a
// new page so the old hyperlink is invalid.
// Note we do NOT use endHyperlink because we want to keep
// our allocated self.cursor.hyperlink valid.
// We need to insert a tracked pin for our saved cursor so we can
// modify its X/Y for reflow.
// If our cursor is on a prompt or input line, clear it so the shell can
// redraw it. This works with OSC 133 semantic prompts.
//
// We check cursor.semantic_content rather than page_row.semantic_prompt
// because some shells (e.g., Nu) mark input areas with OSC 133 B but don't
// mark continuation lines with k=s. If the input spans multiple lines and
// continuation lines are unmarked, checking only page_row.semantic_prompt
// would miss them. By checking semantic_content, we assume that if the
// cursor is on anything other than command output, we're at a prompt/input
// line and should clear from there.
// For `.last`, only clear the current line where the cursor is.
// For `.true`, clear all prompt lines starting from the beginning.
// This should never happen because promptIterator should always
// find a prompt if we already verified our row is some kind of
// prompt.
// Clear cells from our start down. We replace it with spaces,
// and do not physically erase the rows (eraseRows) because the
// shell is going to expect this space to be available.
// Perform the resize operation.
// If we have no scrollback and we shrunk our rows, we must explicitly
// erase our history. This is because PageList always keeps at least
// a page size of history.
// If our cursor was updated, we do a full reload so all our cursor
// state is correct.
// If we reflowed a saved cursor, update it.
// This should never fail because a non-null saved_cursor_pin
// implies a non-null saved_cursor.
// If we had pending wrap set and we're no longer at the end of
// the line, we unset the pending wrap and move the cursor to
// reflect the correct next position.
// I think this can happen if the screen is resized to be
// less rows or less cols and our saved cursor moves outside
// the active area. In this case, there isn't anything really
// reasonable we can do so we just move the cursor to the
// top-left. It may be reasonable to also move the cursor to
// match the primary cursor. Any behavior is fine since this is
// totally unspecified.
// Fix up our hyperlink if we had one.
// This shouldn't happen because startHyperlink should handle
// resizing. This only happens if we're truly out of RAM. Degrade
// to forgetting the hyperlink.
// Remove our old link
// Set a style attribute for the current cursor.
//
// If the style can't be set due to any internal errors (memory-related),
// then this will revert back to the existing style and return an error.
// If we fail to set our style for any reason, we should revert
// back to the old style. If we fail to do that, we revert back to
// the default style.
// Bold and faint share the same SGR code for this
// Call this whenever you manually change the cursor style.
//
// This function can NOT fail if the cursor style is changing to the
// default style.
//
// If this returns an error, the style change did not take effect and
// the cursor style is reverted back to the default. The only scenario
// this returns an error is if there is a physical memory allocation failure
// or if there is no possible way to increase style capacity to store
// the style.
//
// This function WILL split pages as necessary to accommodate the new style.
// So if OutOfSpace is returned, it means that even after splitting the page
// there was still no room for the new style.
// std.log.warn("active styles={}", .{page.styles.count()});
// Release our previous style if it was not default.
// If our new style is the default, just reset to that
// Clear the cursor style ID to prevent weird things from happening
// if the page capacity has to be adjusted which would end up calling
// manualStyleUpdate again.
//
// This also ensures that if anything fails below, we fall back to
// clearing our style.
// After setting the style, we need to update our style map.
// Note that we COULD lazily do this in print. We should look into
// if that makes a meaningful difference. Our priority is to keep print
// fast because setting a ton of styles that do nothing is uncommon
// and weird.
// Our style map is full or needs to be rehashed, so we need to
// increase style capacity (or rehash).
// Out of space, we need to split the page. Split wherever
// is using less capacity and hope that works. If it doesn't
// work, we tried.
// This shouldn't happen because increaseCapacity is
// guaranteed to increase our capacity by at least one and
// we only need one space, but again, I don't want to crash
// here so let's log loudly and reset.
// This should be impossible because we rehash above
// and rehashing should never result in a duplicate. But
// we don't want to simply hard crash so log it and
// clear our style.
// Split at the given pin so that the pinned row moves to the page
// with less used capacity after the split.
//
// The primary use case for this is to handle IncreaseCapacityError
// OutOfSpace conditions where we need to split the page in order
// to make room for more managed memory.
//
// If the caller cares about where the pin moves to, they should
// setup a tracked pin before calling this and then check that.
// In many calling cases, the input pin is tracked (e.g. the cursor
// pin).
//
// If this returns OOM then its a system OOM. If this returns OutOfSpace
// then it means the page can't be split further.
// Get our capacities. We include our target row because its
// capacity will be preserved.
// We need to track the old cursor pin because if our split
// moves the cursor pin we need to update our accounting.
// If our bytes above are less than bytes below, we move the pin
// to split down one since splitting includes the pinned row in
// the new node.
// Cursor didn't change nodes, we're done.
// Cursor changed, we need to restore the old pin then use
// cursorChangePin to move to the new pin. The old node is guaranteed
// to still exist, just not the row.
//
// Note that page_row and all that will be invalid, it points to the
// new node, but at the time of writing this we don't need any of that
// to be right in cursorChangePin.
// Append a grapheme to the given cell within the current cursor row.
// We need to determine the actual cell index of the cell so
// that after we adjust the capacity we can reload the cell.
// Adjust our capacity. This will update our cursor page pin and
// force us to reload.
// The cell pointer is now invalid, so we need to get it from
// the reloaded cursor pointers.
// This should never happen because we just increased capacity.
// Log loudly but still return an error so we don't just
// crash.
// Start the hyperlink state. Future cells will be marked as hyperlinks with
// this state. Note that various terminal operations may clear the hyperlink
// state, such as switching screens (alt screen).
// Create our pending entry.
// Loop until we have enough page memory to add the hyperlink
// An actual self.alloc OOM is a fatal error.
// strings table is out of memory, adjust it up
// hyperlink set is out of memory, adjust it up
// hyperlink set is too full, rehash it
// This is like startHyperlink but if we have to adjust page capacities
// this returns error.PageAdjusted. This is useful so that we unwind
// all the previous state and try again.
// End any prior hyperlink
// Allocate our new Hyperlink entry in non-page memory. This
// lets us quickly get access to URI, ID.
// Insert the hyperlink into page memory
// Save it all
// End the hyperlink state so that future cells aren't part of the
// current hyperlink (if any). This is safe to call multiple times.
// If we have no hyperlink state then do nothing
// Release the old hyperlink state. If there are cells using the
// hyperlink this will work because the creation creates a reference
// and all additional cells create a new reference. This release will
// just release our initial reference.
//
// If the ref count reaches zero the set will not delete the item
// immediately; it is kept around in case it is used again (this is
// how RefCountedSet works). This causes some memory fragmentation but
// is fine because if it is ever pruned the context deleted callback
// will be called.
// Set the current hyperlink state on the current cell.
// Success, increase the refcount for the hyperlink.
// hyperlink_map is out of space, realloc the page to be larger
// Attempt to allocate the space that would be required to
// insert a new copy of the cursor hyperlink uri in to the
// string alloc, since right now increaseCapacity always just
// adds an extra copy even if one already exists in the page.
// If this alloc fails then we know we also need to grow our
// string bytes.
//
// FIXME: increaseCapacity should not do this.
// We don't bother freeing because we're
// about to free the entire page anyway.
// We didn't have enough room, let's increase string bytes
// Retry
//
// We check that the cursor hyperlink hasn't been destroyed
// by the capacity adjustment first though- since despite the
// terrible code above, that can still apparently happen ._.
// Modify the semantic content type of the cursor. This should
// be preferred over setting it manually since it handles all the
// proper accounting.
// Set the selection to the given selection. If this is a tracked selection
// then the screen will take ownership of the selection. If this is untracked
// then the screen will convert it to tracked internally. This will automatically
// untrack the prior selection (if any).
//
// Set the selection to null to clear any previous selection.
//
// This is always recommended over setting `selection` directly. Beyond
// managing memory for you, it also performs safety checks that the selection
// is always tracked.
// If this selection is untracked then we track it.
// Untrack prior selection
// Same as select(null) but can't fail.
// The selection to convert to a string.
// If true, trim whitespace around the selection.
// If non-null, a stringmap will be written here. This will use
// the same allocator as the call to selectionString. The string will
// be duplicated here and in the return value so both must be freed.
// Returns the raw text associated with a selection. This will unwrap
// soft-wrapped edges. The returned slice is owned by the caller and allocated
// using alloc, not the allocator associated with the screen (unless they match).
//
// For more flexibility, use a ScreenFormatter directly.
// We'll use this as our buffer to build our string.
// Create a formatter and use that to emit our text.
// If we have a string map, we need to set that up.
// Emit. Since this is an allocating writer, a failed write
// just becomes an OOM.
// Build our final text and if we have a string map set that up.
// The pin of some part of the line to select.
// These are the codepoints to consider whitespace to trim
// from the ends of the selection.
// If true, line selection will consider semantic prompt
// state changing a boundary. State changing is ANY state
// change.
// Select the line under the given point. This will select across soft-wrapped
// lines and will omit the leading and trailing whitespace. If the point is
// over whitespace but the line has non-whitespace characters elsewhere, the
// line will be selected.
// Get the current point semantic prompt state since that determines
// boundary conditions too. This makes it so that line selection can
// only happen within the same prompt state. For example, if you triple
// click output, but the shell uses spaces to soft-wrap to the prompt
// then the selection will stop prior to the prompt. See issue #1329.
// The real start of the row is the first row in the soft-wrap.
// First, check the current row for semantic boundaries before the clicked position.
// Scan backwards from clicked position to find where our content starts
// No boundary found before clicked position on current row.
// If row doesn't wrap from above, start is at column 0.
// Otherwise, continue checking previous rows.
// We need to check every cell in this row in reverse
// order since we're going up and back.
// The real end of the row is the final row in the soft-wrap.
// We need to check every cell in this row
// If this is our pin row we can start from our x because
// the start_pin logic already found the real start.
// Handle the zero case specially because if the first
// col doesn't match then we end at the end of the prior
// row. But if this is the first row, we can't go back,
// so we scan forward to find where our content ends.
// For every other case, we end at the prior cell.
// Go forward from the start to find the first non-whitespace character.
// Non-empty means we found it.
// Go backward from the end to find the first non-whitespace character.
// Non-empty means we found it.
// Return the selection for all contents on the screen. Surrounding
// whitespace is omitted. If there is no selection, this returns null.
// Non-empty means we found it.
// Non-empty means we found it.
// Select the nearest word to start point that is between start_pt and
// end_pt (inclusive). Because it selects "nearest" to start point, start
// point can be before or after end point.
//
// The boundary_codepoints parameter should be a slice of u21 codepoints that
// mark word boundaries, passed through to selectWord.
//
// TODO: test this
// Boundary conditions
// If we found a word, then return it
// Select the word under the given point. A word is any consecutive series
// of characters that are exclusively whitespace or exclusively non-whitespace.
// A selection can span multiple physical lines if they are soft-wrapped.
//
// This will return null if a selection is impossible. The only scenario
// this happens is if the point pt is outside of the written screen space.
//
// The boundary_codepoints parameter should be a slice of u21 codepoints that
// mark word boundaries. This is expected to be pre-parsed from the config.
// If our cell is empty we can't select a word, because we can't select
// areas where the screen is not yet written.
// Determine if we are a boundary or not to determine what our boundary is.
// Go forwards to find our end boundary
// If we reached an empty cell its always a boundary
// If we do not match our expected set, we hit a boundary
// If we are going to the next row and it isn't wrapped, we
// return the previous.
// Go backwards to find our start boundary
// If we are going to the next row and it isn't wrapped, we
// return the previous.
// If we reached an empty cell its always a boundary
// If we do not match our expected set, we hit a boundary
// Select the command output under the given point. The limits of the output
// are determined by semantic prompt information provided by shell integration.
// A selection can span multiple physical lines if they are soft-wrapped.
//
// This will return null if a selection is impossible:
//  - the point pt is outside of the written screen space.
//  - the point pt is on a prompt / input line.
// If our pin right now is not on output, then we return nothing.
// Get the post prior prompt from this pin. This is the prompt whose
// output we'll be capturing.
// If we have a prompt above this point (including this point),
// then thats the prompt we want to capture output from.
// If we don't have a prompt, then we assume that we're
// capturing all the output up to the next prompt.
// We'll capture from the start of the screen to just above
// the prompt and will trim the trailing whitespace.
// Grab our content
// Trim our trailing whitespace
// Returns an iterator to move through the soft-wrapped lines starting
// from pin.
// Determine the inputs necessary to move the cursor to the given
// click location within a prompt input area.
//
// If the cursor isn't currently at a prompt input location, this
// returns no movement.
//
// This feature depends on well-behaved OSC133 shell integration. Specifically,
// this only moves over designated input areas (OSC 133 B). It is assumed
// that the shell will only move the cursor to input cells, so prompt cells
// and other blank cells are ignored as part of the movement calculation.
// If we're not at an input cell with our cursor, no movement will
// ever be possible.
// None doesn't support movement and click_events must use a
// different mechanism (SGR mouse events) that callers must handle.
// All of these currently use dumb line-based navigation.
// But eventually we'll support more.
// Determine the inputs required to move from the cursor to the given
// click location. If the cursor isn't currently at a prompt input
// location, this will return zero.
//
// This currently only supports moving a single line.
// If our click pin is our cursor pin, no movement is needed.
// Do this early so we can assume later that they are different.
// If our cursor is before our click, we're only emitting right inputs.
// We go row-by-row because soft-wrapped rows are still a single
// line to a shell, so we can't just look at our page row.
// Determine if this row is our cursor.
// If this is not the cursor row, verify it's still part of the
// continuation of our starting prompt.
// Determine where our input starts.
// If this is our cursor row then we start after the cursor.
// Otherwise, we start at the first input cell, because
// we expect the shell to properly translate arrows across
// lines to the start of the input. Some shells indent
// where input starts on subsequent lines so we must do
// this.
// We never found an input cell, so we need to move to the
// next row.
// Iterate over the input cells and assume arrow keys only
// jump to input cells.
// Ignore non-input cells, but allow breaks. We assume
// the shell will translate arrow keys to only input
// areas.
// Increment our input count
// If this is our target, we're done.
// If this row isn't soft-wrapped, we need to break out
// because line based moving only handles single lines.
// We're done!
// If we never found our pin, that means we clicked further
// right/beyond it. If we're already on a non-empty input cell
// then we add one so we can move to the newest, empty cell
// at the end, matching typical editor behavior.
// Otherwise, cursor is after click, so we're emitting left inputs.
// We go row-by-row because soft-wrapped rows are still a single
// line to a shell, so we can't just look at our page row.
// Determine the length of the cells we look at in this row.
// If this is our cursor row then we end before the cursor.
// Otherwise, we end at the last cell in the row.
// Iterate backwards over the input cells.
// Ignore non-input cells.
// Increment our input count
// If this is our target, we're done.
// If this row is not a wrap continuation, then break out
// Dump the screen to a string. The writer given should be buffered;
// this function does not attempt to efficiently write and generally writes
// one byte at a time.
// The start and end points of the dump, both inclusive. The x will
// be ignored and the full row will always be dumped.
// If true, this will unwrap soft-wrapped lines. If false, this will
// dump the screen as it is visually seen in a rendered window.
// Create a formatter and use that to emit our text.
// Set up the selection based on the pins
// Emit
// You should use dumpString, this is a restricted version mostly for
// legacy and convenience reasons for unit tests.
// You should use dumpString, this is a restricted version mostly for
// legacy and convenience reasons for unit tests.
// This is basically a really jank version of Terminal.printString. We
// have to reimplement it here because we want a way to print to the screen
// to test it but don't want all the features of Terminal.
// Explicit newline forces a new row
// If we have a ref-counted style, increase.
// If we have a hyperlink, add it to the cell.
// Need a wide spacer head
// If we have a hyperlink, add it to the cell.
// Write our wide char
// If we have a hyperlink, add it to the cell.
// Write our tail
// If we have a hyperlink, add it to the cell.
// If we have a ref-counted style, increase twice.
// Bold should create our style
// Copy default style, should release our style
// We need to get the cursor on a new page.
// Fill the scrollback with blank lines until
// there are only 5 rows left on the first page.
// s2.pages.diagram(...):
//
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4300 |1         | | 0
// 4301 |2         | | 1
// 4302 |3         | | 2
// 4303 |4         | | 3
// 4304 |5         | | 4
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |6         | | 5
//    1 |7         | | 6
//    2 |8         | | 7
//    3 |9         | | 8
//    4 |10        | | 9
//      :  ^       : : = PIN 0
//      +----------+ :
//     +-------------+
// This should be PAGE 1
// It should be the last page in the list.
// It should have a previous page.
// The cursor should be at 2, 9
// Bold should create our style in page 1.
// Copy the cursor for the first screen. This should release
// the style from page 1 and move the cursor back to page 0.
// The page after the page the cursor is now in should be page 1.
// The cursor should be at 0, 0
// Create a hyperlink for the cursor.
// Copy a cursor with no hyperlink, should release our hyperlink.
// We need to get the cursor on a new page.
// Fill the scrollback with blank lines until
// there are only 5 rows left on the first page.
// s2.pages.diagram(...):
//
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4300 |1         | | 0
// 4301 |2         | | 1
// 4302 |3         | | 2
// 4303 |4         | | 3
// 4304 |5         | | 4
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |6         | | 5
//    1 |7         | | 6
//    2 |8         | | 7
//    3 |9         | | 8
//    4 |10        | | 9
//      :  ^       : : = PIN 0
//      +----------+ :
//     +-------------+
// This should be PAGE 1
// It should be the last page in the list.
// It should have a previous page.
// The cursor should be at 2, 9
// Create a hyperlink for the cursor, should be in page 1.
// Copy the cursor for the first screen. This should release
// the hyperlink from page 1 and move the cursor back to page 0.
// The page after the page the cursor is now in should be page 1.
// The cursor should be at 0, 0
// Create a hyperlink for the cursor.
// Copy the cursor with the hyperlink.
// Create a hyperlink for the cursor.
// Copy the cursor with the hyperlink.
// Set a new style
// Set another style, we should still only have one since it was unused
// Set a new style
// Reset to default
// Set a new style
// Reset to default
// We should have one style
// We should have none because active cleared it
// Scroll down enough to go to another page
// We need our page to change for this test o make sense. If this
// assertion fails then the bug is in the test: we should be scrolling
// above enough for a new page to show up.
// Scroll back to the previous page
// Go back up, set a style
// Go back down into the next page and we should have that style
// Scroll down enough to go to another page
// We need our page to change for this test o make sense. If this
// assertion fails then the bug is in the test: we should be scrolling
// above enough for a new page to show up.
// Go back up, set a style
// Go back down into the prev page and we should have that style
// Scroll down enough to go to another page
// We need our page to change for this test o make sense. If this
// assertion fails then the bug is in the test: we should be scrolling
// above enough for a new page to show up.
// Go back up, set a style
// Go back down into the prev page and we should have that style
// This test checks for a very specific edge case
// which previously resulted in memory corruption.
//
// The conditions for this edge case are as such:
// - The cursor has an associated style or other managed memory.
// - The cursor moves to a different page.
// - The new page is at capacity and must have its capacity adjusted.
// Scroll down enough to go to another page
// We need our page to change for this test to make sense. If this
// assertion fails then the bug is in the test: we should be scrolling
// above enough for a new page to show up.
// Add styles to the start page until it reaches capacity.
// Pause integrity checks because they're slow and
// we're not testing this, this is just setup.
// Set a style on the cursor.
// Go back up into the start page and we should still have that style.
// The page we're on now should NOT equal start_page, since its
// capacity should have been adjusted, which invalidates our ptr.
// To make sure we DID change pages we check we're not on new_page.
// Scroll down, should still be bottom
// Everything is dirty because we have no scrollback
// Scrolling to the bottom does nothing
// Scroll down, should still be bottom
// Screen should be dirty
// Scroll down, should still be bottom
// Active should be dirty
// Scrollback also dirty because cursor moved from there
// Scroll down enough to go to another page
// We need our page to change for this test o make sense. If this
// assertion fails then the bug is in the test: we should be scrolling
// above enough for a new page to show up.
// Scrolling up does nothing, but allows it
// Scrolling to the bottom
// Scrolling back should make it visible again
// Scrolling back again should do nothing
// Scrolling to the bottom
// Scrolling forward with no grow should do nothing
// Scrolling to the top should work
// Should be able to easily clear active area only
// Scrolling to the bottom
// Scroll to top
// Scroll down multiple
// First test: we scroll up by 1, so we're not at the bottom anymore.
// Next, we scroll back down by 1, this grows the scrollback but we
// shouldn't move.
// Scroll again, this clears scrollback so we should move viewports
// but still see the same thing since our original view fits.
// Select a single line
// Scroll down, should still be bottom
// Our selection should've moved up
// Test our contents rotated
// Scrolling to the bottom does nothing
// Our selection should've stayed the same
// Test our contents rotated
// Scroll up again
// Test our contents rotated
// Our selection should be null because it left the screen.
// Test our contents rotated
// Write some to create scrollback and move back into our scrollback.
// Our viewport is now somewhere pinned. Create so much scrollback
// that we prune it.
// Move back to top-left
// Write and clear
// Move back to top-left
// At this point:
//  +-------------+ ACTIVE
//   +----------+ : = PAGE 0
// 0 |1ABCD00000| | 0
// 1 |2EFGH00000| | 1
//   :^         : : = PIN 0
// 2 |3IJKL00000| | 2
//   +----------+ :
//  +-------------+
//   +----------+ = PAGE 0
// 0 |1ABCD00000|
//  +-------------+ ACTIVE
// 1 |2EFGH00000| | 0
// 2 |          | | 1
//   :^         : : = PIN 0
// 3 |3IJKL00000| | 2
//   +----------+ :
//  +-------------+
// try s.pages.diagram(std.io.getStdErr().writer());
// Page 0 row 1 (active row 0) is dirty because the cursor moved off of it.
// Page 0 row 2 (active row 1) is dirty because it was cleared.
// Page 0 row 3 (active row 2) is dirty because it's new.
// We need to get the cursor to a new page
// Ensure we're still on the first page and have a second
// At this point:
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4305 |1A00000000| | 0
// 4306 |2B00000000| | 1
//      :^         : : = PIN 0
// 4307 |3C00000000| | 2
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |4D00000000| | 3
//    1 |5E00000000| | 4
//      +----------+ :
//     +-------------+
//      +----------+ = PAGE 0
//  ... :          :
// 4305 |1A00000000|
//     +-------------+ ACTIVE
// 4306 |2B00000000| | 0
// 4307 |          | | 1
//      :^         : : = PIN 0
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |3C00000000| | 2
//    1 |4D00000000| | 3
//    2 |5E00000000| | 4
//      +----------+ :
//     +-------------+
// try s.pages.diagram(std.io.getStdErr().writer());
// Page 0's penultimate row is dirty because the cursor moved off of it.
// The rest of the rows are dirty because they've been modified or are new.
// We need to get the cursor to a new page
// Ensure we're still on the first page and have a second
// At this point:
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4306 |1A00000000| | 0
// 4307 |2B00000000| | 1
//      :^         : : = PIN 0
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |3C00000000| | 2
//    1 |4D00000000| | 3
//    2 |5E00000000| | 4
//      +----------+ :
//     +-------------+
//      +----------+ = PAGE 0
//  ... :          :
// 4306 |1A00000000|
//     +-------------+ ACTIVE
// 4307 |2B00000000| | 0
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |          | | 1
//      :^         : : = PIN 0
//    1 |3C00000000| | 2
//    2 |4D00000000| | 3
//    3 |5E00000000| | 4
//      +----------+ :
//     +-------------+
// try s.pages.diagram(std.io.getStdErr().writer());
// Page 0's final row is dirty because the cursor moved off of it.
// Page 1's rows are all dirty because every row was moved.
// Attempt to clear the style from the cursor and
// then assert the integrity of both of our pages.
//
// This catches a case of memory corruption where the cursor
// is moved between pages without accounting for style refs.
// We need to get the cursor to a new page
// Ensure we're still on the first page
// At this point:
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4305 |1ABCD00000| | 0
// 4306 |2EFGH00000| | 1
//      :^         : : = PIN 0
// 4307 |3IJKL00000| | 2
//      +----------+ :
//     +-------------+
//      +----------+ = PAGE 0
//  ... :          :
// 4305 |1ABCD00000|
//     +-------------+ ACTIVE
// 4306 |2EFGH00000| | 0
// 4307 |          | | 1
//      :^         : : = PIN 0
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |3IJKL00000| | 2
//      +----------+ :
//     +-------------+
// try s.pages.diagram(std.io.getStdErr().writer());
// Page 0's penultimate row is dirty because the cursor moved off of it.
// Page 0's final row is dirty because it was cleared.
// Page 1's row is dirty because it's new.
// Get the cursor to be 2 rows above a new page
// Write 3 lines of text, forcing the last line into the first
// row of a new page. Move our cursor onto the previous page.
// Ensure we're still on the first page. So our cursor is on the first
// page but we have two pages of data.
//      +----------+ = PAGE 0
//  ... :          :
//     +-------------+ ACTIVE
// 4305 |1AB0000000| | 0
// 4306 |2BC0000000| | 1
//      :^         : : = PIN 0
// 4307 |3DE0000000| | 2
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |4FG0000000| | 3
//      +----------+ :
//     +-------------+
//     +----------+ = PAGE 0
//  ... :          :
// 4305 |1AB0000000|
//     +-------------+ ACTIVE
// 4306 |2BC0000000| | 0
// 4307 |          | | 1
//      :^         : : = PIN 0
//      +----------+ :
//      +----------+ : = PAGE 1
//    0 |3DE0000000| | 2
//    1 |4FG0000000| | 3
//      +----------+ :
//     +-------------+
// try s.pages.diagram(std.io.getStdErr().writer());
// Page 0's penultimate row is dirty because the cursor moved off of it.
// Page 0's final row is dirty because it was cleared.
// Page 1's row is dirty because it's new.
// At this point:
//  +-------------+ ACTIVE
//   +----------+ : = PAGE 0
// 0 |1ABCD00000| | 0
// 1 |2EFGH00000| | 1
//   :^         : : = PIN 0
// 2 |3IJKL00000| | 2
//   +----------+ :
//  +-------------+
//   +----------+ = PAGE 0
// 0 |1ABCD00000|
//  +-------------+ ACTIVE
// 1 |2EFGH00000| | 0
// 2 |          | | 1
//   :^         : : = PIN 0
// 3 |3IJKL00000| | 2
//   +----------+ :
//  +-------------+
// try s.pages.diagram(std.io.getStdErr().writer());
// Page 0 row 1 (active row 0) is dirty because the cursor moved off of it.
// Page 0 row 2 (active row 1) is dirty because it was cleared.
// Page 0 row 3 (active row 2) is dirty because it is new.
// Clone
// Write to s1, should not be in s2
// Clone
// Cursor is shifted since we cloned partial
// Clone
// Cursor is shifted since we cloned partial
// Select a single line
// Clone
// Our selection should remain valid
// Select a single line
// Clone
// Our selection should be null
// Select a single line
// Clone
// Our selection should remain valid
// Select a single line
// Clone
// Our selection should remain valid
// Select a single line
// Clone
// Our selection should remain valid
// Select the full screen
// Clone
// Our selection should remain valid
// Select the full screen from x=1 to x=3
// Clone
// Our selection should remain valid and be properly clipped
// preserving the columns of the start and end points of the
// selection.
// Test our contents rotated
// Test our contents rotated
// Test our contents rotated
// Test our contents
// Test our contents rotated
// Test our contents rotated
// Test our contents rotated
// Test our contents rotated
// Scroll to top
// Test our contents rotated
// Test our contents rotated
// Test our contents rotated
// Resize
// Since we shrunk, we should adjust our cursor
// Write only a background color into the remaining rows
// Cursor should not move
// Write only a background color into the remaining rows
// Cursor should not move
// https://github.com/mitchellh/ghostty/issues/1030
// Every second row should be wrapped
// Resize
// Every second row should be wrapped
// Cursor should not move
// Cursor should not move
// Set our cursor to be on the "4"
// Resize
// Cursor should still be on the "4"
// Cursor should not move
// https://github.com/mitchellh/ghostty/issues/272#issuecomment-1676038963
// https://github.com/mitchellh/ghostty/issues/1159
// Cursor at bottom
// Cursor remains at bottom
// https://github.com/mitchellh/ghostty/issues/1159
// Cursor at bottom
// Cursor remains at bottom
// Old implementation doesn't do this but it makes sense to me:
// {
//     const contents = try s.dumpStringAlloc(alloc, .{ .viewport = .{} });
//     defer alloc.free(contents);
//     try testing.expectEqualStrings("2\n3\n4", contents);
// }
// Set one of the rows to be a prompt
// Our one row should still be a semantic prompt, the others should not.
// Verify we soft wrapped
// Let's put our cursor on row 2, where the soft wrap is
// Resize and verify we undid the soft wrap because we have space now
// Our cursor should've moved
// Verify we soft wrapped
// Let's put our cursor on the last row
// Resize and verify we undid the soft wrap because we have space now
// Our cursor should still be on the 3
// Let's put our cursor on row 2, where the soft wrap is
// Verify we soft wrapped
// Resize and verify we undid the soft wrap because we have space now
// Our cursor should've moved
// Let's put our cursor on row 2, where the soft wrap is
// Verify we soft wrapped
// Resize and verify we undid the soft wrap because we have space now
// Our cursor should've moved
// // Set our cursor to be on the "5"
// Resize
// Cursor should still be on the "5"
// Let's put our cursor on row 2, where the soft wrap is
// Verify we soft wrapped
// Resize and verify we undid the soft wrap because we have space now
// Our cursor should've moved
// Cursor should move due to wrapping
// Cursor should not move
// Put our cursor on the last line
// Resize
// Cursor should be on the last line
// Resize
// Resize
// Cursor should stay in the same relative place (bottom of the
// screen, same character).
// Cursor should not move
// Put our cursor on the end
// Cursor should be on the last line
// Check
// {
//     const contents = try s.testString(alloc, .viewport);
//     defer alloc.free(contents);
//     const expected = "CD\n5EF\nGH";
//     try testing.expectEqualStrings(expected, contents);
// }
// Put our cursor on the end
// Cursor should be on the last line
// Check
// Put our cursor on the end
// Cursor should be on the last line
// Lets do a scroll and clear operation
// Move our cursor to the beginning
// Cursor should be on the last line
// This seems like it should work fine but for some reason in practice
// in the initial implementation I found this bug! This is a regression
// test for that.
// Grow
// Shrink
// Grow again
// Resize to 1 column can't fit a wide char. So it should be deleted.
// So this is the key point: we end up with a wide spacer head at
// the end of row 1, then the emoji, then a wide spacer tail on row 2.
// We should expect that if we resize to more cols, the wide spacer
// head is replaced with the emoji.
// Similar to the "wide spacer head" test, but this time we'er going
// to increase our columns such that multiple rows are unwrapped.
// This resizes to 3 columns, which isn't enough space for our wide
// char to enter row 1. But we need to mark the wide spacer head on the
// end of the first row since we're wrapping to the next row.
// zig fmt: off
// zig fmt: on
// Cursor should not move
// zig fmt: off
// zig fmt: on
// Cursor should not move
// zig fmt: off
// zig fmt: on
// Cursor is at end of "world" line with semantic_content = .input
// With .last, only the current line where cursor is should be cleared
// Create a 3-line prompt: 1 initial + 2 continuation lines
// zig fmt: off
// zig fmt: on
// Cursor is at end of line3 (the last continuation line)
// With .last, only line3 (where cursor is) should be cleared
// Outside of active area
// try testing.expect(s.selectLine(.{ .x = 13, .y = 0 }) == null);
// try testing.expect(s.selectLine(.{ .x = 0, .y = 5 }) == null);
// Going forward
// Going backward
// Going forward and backward
// Outside active area
// Going forward
// Going forward
// Going backward
// Going forward and backward
// Going forward
// Non-wrapped
// Selecting first line
// Selecting last line
// https://github.com/mitchellh/ghostty/issues/1329
// Selecting output stops at the prompt even if soft-wrapped
// Write prompt followed by user input on same row: "$>command"
// Using non-whitespace to avoid whitespace trimming affecting the test
// Selecting from prompt should only select prompt
// Selecting from input should only select input
// Row 0: user input
// Row 1: command output
// Selecting from input should only select input
// Selecting from output should only select output
// Single row with output then prompt then input: "out$>cmd"
// Using non-whitespace to avoid whitespace trimming affecting the test
// Selecting from output should stop at prompt
// Selecting from prompt should only select prompt
// Selecting from input should only select input
// Row 0: prompt "$ " + input "cmd" (soft-wraps)
// Row 1: input continues "12" + output "out"
// Verify layout
// Selecting from input on row 0 should get all input across soft-wrap
// Selecting from input on row 1 should get all input across soft-wrap
// Selecting from output should only get output
// Write prompt followed by input
// With semantic_prompt_boundary = false, should select entire line
// Row 0: input that soft-wraps
// Row 1: output starts at first cell
// Verify soft-wrap happened
// Selecting from input should stop before output on row 1
// Selecting from output should only get output
// All prompt content that soft-wraps
// Verify soft-wrap
// Should select all prompt content across soft-wraps
// Default boundary codepoints for word selection
// Outside of active area
// try testing.expect(s.selectWord(.{ .x = 9, .y = 0 }) == null);
// try testing.expect(s.selectWord(.{ .x = 0, .y = 5 }) == null);
// Going forward
// Going backward
// Going forward and backward
// Whitespace
// Whitespace single char
// End of screen
// Default boundary codepoints for word selection
// Going forward
// Going backward
// Going forward and backward
// Default boundary codepoints for word selection
// Going forward
// Going backward
// Going forward and backward
// Default boundary codepoints for word selection
// Inside character forward
// Inside character backward
// Inside character bidirectional
// On quote
// NOTE: this behavior is not ideal, so we can change this one day,
// but I think its also not that important compared to the above.
// Build content with cell-level semantic content:
// Row 0-1: output1 (output)
// Row 2: prompt2 (prompt)
// Row 3: input2 (input)
// Row 4-7: output2 (output, with overflow causing wrap)
// Row 8: "$ " (prompt) + "input3" (input)
// Row 9-11: output3 (output)
// First output block (rows 0-1), should select those rows
// Second output block (rows 4-7)
// Third output block (rows 9-11)
// Click on prompt should return null
// Click on input should return null
// No trim
// No trim
// https://github.com/mitchellh/ghostty/issues/289
// Let me describe the situation that caused this because this
// test is not obvious. By writing an emoji below, we introduce
// one cell with the emoji and one cell as a "wide char spacer".
// We then soft wrap the line by writing spaces.
//
// By selecting only the tail, we'd select nothing and we had
// a logic error that would cause a crash.
// Integrity check
// The real test
// Lazy way to seek to the first page boundary.
// Test the line iterator
// Test the line iterator
// try testing.expect(iter.next() == null);
// Use it for the first time
// Reuse the same hyperlink, expect we have the same ID
// This test depends on underlying PageList implementation so
// it may be invalid one day. It's here to document/verify the
// current behavior.
// Start a hyperlink
// Resize. Any column growth will trigger a page to be reallocated.
// Start a hyperlink with a URI that just barely fits in the string alloc.
// This will ensure that additional string alloc space is needed for the
// redundant copy of the URI when the page is re-alloced.
// Figure out how many cells should can have hyperlinks in this page,
// and write twice that number, to guarantee the capacity needs to be
// increased at some point.
// Make sure the capacity really did increase.
// And that our string_bytes increased as well.
// We should have one page and it should be our cursor page
// 5 chars + cursor = 6 refs
// This forces the page to change via increaseCapacity.
// Cursor's page_pin should now point to the new node
// Verify cursor's page_cell and page_row are correctly reloaded from the pin
// Style should be preserved
// After increaseCapacity, the 5 chars are cloned (5 refs) and
// the cursor's style is re-added (1 ref) = 6 total.
// We should have one page and it should be our cursor page
// Cursor has the hyperlink active = 1 count in hyperlink_set
// This forces the page to change via increaseCapacity.
// Hyperlink should be preserved with correct URI
// After increaseCapacity, the hyperlink is re-added to the new page.
// Set both a non-default style AND an active hyperlink.
// Write one character first with bold to mark the row as styled,
// then start the hyperlink and write more characters.
// We should have one page and it should be our cursor page
// 5 chars + cursor = 6 refs for bold style
// Cursor has the hyperlink active = 1 count in hyperlink_set
// This forces the page to change via increaseCapacity.
// Style should be preserved
// Hyperlink should be preserved with correct URI
// After increaseCapacity, both style and hyperlink are re-added to the new page.
// Test that calling increaseCapacity on a page that is NOT the cursor's
// page properly delegates to pages.increaseCapacity without doing the
// extra cursor accounting (style/hyperlink re-adding).
// Set up a custom style and hyperlink on the cursor
// Store cursor state before growing pages
// The cursor is on the first (and only) page
// Grow pages until we have multiple pages. The cursor's pin stays on
// the first page since we're just adding rows.
// Now we have two pages
// Cursor should still be on the first page (where it was created)
// Call increaseCapacity on the second page (NOT the cursor's page)
// The second page should have increased capacity
// The cursor's page (first page) should be unchanged
// Cursor state should be completely unchanged since we didn't touch its page
// Verify hyperlink is still valid
// Regression test for https://github.com/ghostty-org/ghostty/issues/10282
//
// This test exposes a use-after-realloc bug in cursorDown (and similar
// cursor movement functions). The bug pattern:
//
// 1. cursorDown creates a by-value copy of the pin via page_pin.down(n)
// 2. cursorChangePin is called, which may trigger adjustCapacity
//    if the target page's style map is full
// 3. adjustCapacity frees the old page and creates a new one
// 4. The local pin copy still points to the freed page
// 5. rowAndCell() on the stale pin accesses freed memory
// Small screen to make page boundary crossing easy to set up
// Scroll down enough to create a second page
// Cursor should now be on a new page
// Fill new_page's style map to capacity. When we move INTO this page
// with a style set, adjustCapacity will be triggered.
// Move cursor to start of active area and set a style
// Find the row just before the page boundary
// Cursor is at 'row', moving down crosses to new_page
// This cursorDown triggers the bug: the local page_pin copy
// becomes stale after adjustCapacity, causing rowAndCell()
// to access freed memory.
// If the fix is applied, verify correct state
// Didn't find boundary
// Tests that setAttribute succeeds when the style map is full by
// increasing page capacity. When capacity is at max and increaseCapacity
// returns OutOfSpace, manualStyleUpdate will split the page instead.
// Use a small screen with multiple rows
// Write content to multiple rows
// Get the page and fill its style map to capacity
// Fill the style map to capacity using the StyleSet's layout capacity
// which accounts for the load factor
// Now try to set a new unique attribute that would require a new style slot
// This should succeed by increasing capacity (or splitting if at max capacity)
// The style should have been applied (bold flag set)
// The cursor should have a valid non-default style_id
// Either the capacity increased or the page was split/changed
// Write content to multiple rows so we have something to split
// Remember the original node
// Increase the page's style capacity to max by repeatedly calling increaseCapacity
// Use Screen.increaseCapacity to properly maintain cursor state
// Get the page reference after increaseCapacity - cursor may have moved
// Fill the style map to capacity using the StyleSet's layout capacity
// which accounts for the load factor
// Track the node before setAttribute
// Now try to set a new unique attribute that would require a new style slot
// At max capacity, increaseCapacity will return OutOfSpace, triggering page split
// The style should have been applied (bold flag set)
// The cursor should have a valid non-default style_id
// The page should have been split
// This test verifies that if toOwnedSlice fails when building
// the StringMap, we don't leak the already-allocated map.string.
// Get a selection
// Trigger allocation failure on toOwnedSlice
// If this test passes without memory leaks (when run with testing.allocator),
// it means the errdefer properly cleaned up map.string when toOwnedSlice failed.
// Enable line click mode
// Write a prompt and input
// Move cursor back to start of input (column 2, the 'h')
// Click on first 'l' (column 4), should require 2 right movements (h->e->l)
// Enable line click mode
// Write a prompt and input
// Move cursor back to prompt area (column 0, the '>')
// Cursor is on prompt, not input - should return zero
// Enable line click mode
// Write a prompt and input
// Move cursor to column 4
// Click on same position - no movement needed
// Enable line click mode
// Write: "> h" then output "X" then input "llo"
// Move cursor to column 2 (the 'h')
// Click on 'l' at column 5 - should skip the 'X' output cell
// Movement: h (start) -> l (col 4) -> l (col 5) = 2 right movements
// Enable line click mode
// Write a prompt and input that wraps
// Write 8 chars of input, first row has 2 for prompt + 8 input = 10 cols
// Continue on next row (soft-wrapped)
// Verify soft wrap occurred
// Move cursor to column 2 (the 'a')
// Click on 'j' at column 1, row 1 - should count all input cells
// Movement: a->b->c->d->e->f->g->h->i->j = 9 right movements
// Click mode is .none by default (disabled)
// Write a prompt and input
// Move cursor to start of input
// Click should return zero since click mode is disabled
// Enable line click mode
// Write prompt and input on first line
// Hard wrap (newline)
// Move cursor to column 2 (the 'h')
// Click on 'w' at column 0, row 1 - but line mode stops at hard wrap
// Should only move to end of first line: h->e->l->l->o = 4 movements
// Should stop at end of first line, not cross hard wrap
// Enable line click mode
// Row 0: PROMPT "> hello"
// Row 1: CONTINUATION "world"
// Row 2: NEW PROMPT "> again"
// Verify content
// Move cursor to 'w' at column 0, row 1
// Click on 'a' at column 2, row 2 - but row 2 is a new prompt
// Should stop at end of "world": w->o->r->l->d = 4 movements
// Should stop at 'd' (end of world), not cross to new prompt
// Enable line click mode
// Write a prompt and input
// Cursor is at column 7 (after 'o'), move it to column 6 (the 'o')
// Click on 'h' (column 2), should require 4 left movements (o->l->l->e->h)
// Enable line click mode
// Write: "> h" then output "X" then input "llo"
// Move cursor to column 6 (the 'o')
// Click on 'h' at column 2 - should skip the 'X' output cell
// Movement: o->l->l->h = 3 left movements (skipping X)
// Enable line click mode
// Write a prompt and input that wraps
// Write 8 chars of input, first row has 2 for prompt + 8 input = 10 cols
// Continue on next row (soft-wrapped)
// Verify soft wrap occurred
// Cursor is at column 2, row 1 (after 'j'). Move to 'j' at column 1.
// Click on 'a' at column 2, row 0 - should count all input cells backwards
// Movement: j->i->h->g->f->e->d->c->b->a = 9 left movements
// Enable line click mode
// Write prompt and input on first line, then hard wrap
// Hard wrap (newline)
// Move cursor to 'd' at column 4, row 1 (an actual input cell)
// Click on 'h' at column 2, row 0 - but line mode stops at hard wrap
// Should only move to start of second line, not cross to row 0
// Should stop at start of second line: d->l->r->o->w = 4 movements
// Set up: "> hello" where "> " is prompt and "hello" is input
// Clicking to the right of the 'o' should move cursor past the input
// Enable line click mode
// Write a prompt and input
// Move cursor to start of input (column 2, the 'h')
// Click beyond the input (column 15) - should move to one past the 'o'
// Enable line click mode
// Write a prompt and input
// Cursor is already at column 7 (one past 'o') after writing
// Click beyond the input (column 15) - no movement needed since
// cursor is already at the end position
// Enable line click mode
// Write a prompt and input
// Move cursor to start of input (column 2, the 'h')
// Click on a lower line (row 1) - should move to end of input
// This is outside the prompt area so should clamp to end
// From 'h', we need to pass e, l, l, o (4 cells) + 1 past end = 5
// Enable line click mode
// Write a prompt and input
// Cursor is at column 7 after writing (one past 'o')
// Click on a lower line (row 1) - cursor already at end, no movement needed
// Enable line click mode
// Write a prompt and input
// Move cursor to last input char (column 6, the 'o')
// Click beyond the input (column 15)
//
// --- Original Ghostty Comments End: src/terminal/Screen.zig

// Screen represents a single terminal screen with cursor, selection,
// and cell data. Translated from ghostty's Screen.zig.

// ScreenDirty tracks what parts of the screen need redrawing.
//
// See Terminal.Dirty. This behaves the same way.
pub struct ScreenDirty {
mut:
	value u8
}

pub fn ScreenDirty.init(selection bool, hyperlink_hover bool) ScreenDirty {
	return ScreenDirty{
		value: u8(selection) | (u8(hyperlink_hover) << 1)
	}
}

// Set when the selection is set or unset, regardless of if the
// selection is changed or not.
pub fn (self ScreenDirty) selection() bool {
	return self.value & 0b01 != 0
}

pub fn (mut self ScreenDirty) set_selection(value bool) {
	self.set_bit(0b01, value)
}

// When an OSC8 hyperlink is hovered, we set the full screen as dirty
// because links can span multiple lines.
pub fn (self ScreenDirty) hyperlink_hover() bool {
	return self.value & 0b10 != 0
}

pub fn (mut self ScreenDirty) set_hyperlink_hover(value bool) {
	self.set_bit(0b10, value)
}

pub fn (self ScreenDirty) int() u8 {
	return self.value
}

fn (mut self ScreenDirty) set_bit(mask u8, enabled bool) {
	if enabled {
		self.value |= mask
	} else {
		self.value &= ~mask
	}
}

pub struct SemanticPrompt {
pub mut:
	// This is flipped to true when any sort of semantic content is
	// seen. In particular, this is set to true only when a `prompt` type
	// is ever set on our cursor.
	//
	// This is used to optimize away semantic content operations if we know
	// we've never seen them.
	seen bool
	// This is set on any `cl` or `click_events` option set on the
	// most recent OSC 133 commands to specify how click handling in a
	// prompt is handling.
	click SemanticClick
}

pub const semantic_prompt_disabled = SemanticPrompt{
	seen:  false
	click: semantic_click_none
}

pub struct SemanticClickNone {}

pub struct SemanticClickEvents {}

pub struct SemanticClickCl {
pub:
	cl osc.Click
}

pub type SemanticClick = SemanticClickCl | SemanticClickEvents | SemanticClickNone

pub const semantic_click_none = SemanticClick(SemanticClickNone{})
pub const semantic_click_click_events = SemanticClick(SemanticClickEvents{})

pub fn SemanticClick.from_cl(cl osc.Click) SemanticClick {
	return SemanticClickCl{
		cl: cl
	}
}

// The cursor position and style.
pub struct Cursor {
pub mut:
	// The x/y position within the active area.
	x u32
	y u32
	// The visual style of the cursor. This defaults to block because
	// it has to default to something, but users of this struct are
	// encouraged to set their own default.
	cursor_style CursorStyle = .block
	// The "last column flag (LCF)" as its called. If this is set then the
	// next character print will force a soft-wrap.
	pending_wrap bool
	// The protected mode state of the cursor. If this is true then
	// all new characters printed will have the protected state set.
	is_protected bool
	// The currently active style. This is the concrete style value
	// that should be kept up to date. The style ID to use for cell writing
	// is below.
	style CellStyle
	// The currently active style ID. The style is page-specific so when
	// we change pages we need to ensure that we update that page with
	// our style when used.
	style_id u32 = default_style_id
	// The hyperlink ID that is currently active for the cursor. A value
	// of zero means no hyperlink is active. (Implements OSC8, saying that
	// so code search can find it.).
	hyperlink_id u32
	// This is the implicit ID to use for hyperlinks that don't specify
	// an ID. We do an overflowing add to this so repeats can technically
	// happen with carefully crafted inputs but for real workloads its
	// highly unlikely -- and the fix is for the TUI program to use explicit
	// IDs.
	hyperlink_implicit_id u32
	// The hyperlink state so that we can recreate it when the cursor page
	// pin changes. We can't get it from the old screen state because the
	// page may be cleared. Ghostty heap-allocates this because it is most
	// likely null; V stores the optional value directly.
	hyperlink_state ?Hyperlink
	// The current semantic content type for the cursor that will be
	// applied to any newly written cells.
	semantic_content           SemanticContent = .output
	semantic_content_clear_eol bool
	// The pointers into the page list where the cursor is currently
	// located. This makes it faster to move the cursor.
	page_pin  &Pin      = unsafe { nil }
	page_row  &RowData  = unsafe { nil }
	page_cell &CellData = unsafe { nil }
}

// Release cursor-owned state. Ghostty frees the heap-allocated pending
// hyperlink here; V owns that memory through GC, so dropping the retained
// value is the equivalent lifecycle operation.
pub fn (mut self Cursor) deinit() {
	self.hyperlink_state = none
}

// CursorCopyOptions controls which cursor-owned state is migrated when a
// cursor is copied between screens.
pub struct CursorCopyOptions {
pub:
	// Copy the hyperlink from the other cursor. If not set, this will
	// clear our current hyperlink.
	hyperlink bool = true
}

// Saved cursor state.
pub struct SavedCursor {
pub mut:
	x            u32
	y            u32
	style        CellStyle
	is_protected bool
	pending_wrap bool
	origin       bool
	charset      CharsetState
}

// State required for all charset operations.
pub struct CharsetState {
pub mut:
	// The list of graphical charsets by slot
	charsets CharsetArray
	// GL is the slot to use when using a 7-bit printable char (up to 127)
	// GR used for 8-bit printable chars.
	gl CharsetSlot = .g0
	gr CharsetSlot = .g2
	// Single shift where a slot is used for exactly one char.
	single_shift ?CharsetSlot
}

// An array to map a charset slot to a lookup table.
//
// We use this bespoke struct instead of `std.EnumArray` because
// accessing these slots is very performance critical since it's
// done for every single print. This benchmarks faster.
pub struct CharsetArray {
pub mut:
	g0 Charset = .utf8
	g1 Charset = .utf8
	g2 Charset = .utf8
	g3 Charset = .utf8
}

pub fn (self CharsetArray) get(slot CharsetSlot) Charset {
	return match slot {
		.g0 { self.g0 }
		.g1 { self.g1 }
		.g2 { self.g2 }
		.g3 { self.g3 }
	}
}

pub fn (mut self CharsetArray) set(slot CharsetSlot, charset Charset) {
	match slot {
		.g0 {
			self.g0 = charset
		}
		.g1 {
			self.g1 = charset
		}
		.g2 {
			self.g2 = charset
		}
		.g3 {
			self.g3 = charset
		}
	}
}

pub struct ScreenOptions {
pub:
	cols u32 = 80
	rows u32 = 24
	// The maximum size of scrollback in bytes. Zero means unlimited. Any
	// other value will be clamped to support a minimum of the active area.
	max_scrollback uint
	// The total storage limit for Kitty images in bytes for this
	// screen. Kitty image storage is per-screen.
	kitty_image_storage_limit uint = 320 * 1000 * 1000 // 320MB
}

// Options for scrolling the viewport of the terminal grid. The reason
// we have this in addition to PageList.Scroll is because we have additional
// scroll behaviors that are not part of the PageList.Scroll enum.
pub struct ScrollActive {}

pub struct ScrollTop {}

pub struct ScrollPin {
pub:
	pin Pin
}

pub struct ScrollRow {
pub:
	n uint
}

pub struct ScrollDeltaRow {
pub:
	delta int
}

pub struct ScrollDeltaPrompt {
pub:
	delta int
}

// For all of these, see PageList.Scroll.
pub type Scroll = ScrollActive
	| ScrollTop
	| ScrollPin
	| ScrollRow
	| ScrollDeltaRow
	| ScrollDeltaPrompt

pub struct ScreenResize {
pub:
	// The new size to resize to
	cols u32
	rows u32
	// Whether to reflow soft-wrapped text.
	//
	// This will reflow soft-wrapped text. If the screen size is getting
	// smaller and the maximum scrollback size is exceeded, data will be
	// lost from the top of the scrollback.
	reflow bool = true
	// Set this to enable prompt redraw on resize. This signals
	// that the running program can redraw the prompt if the cursor is
	// currently at a prompt. This detects OSC133 prompts lines and clears
	// them. If set to `.last`, only the most recent prompt line is cleared.
	prompt_redraw osc.Redraw = .redraw_false
}

pub struct SelectionString {
pub:
	// The selection to convert to a string.
	sel Selection
	// If true, trim whitespace around the selection.
	trim bool = true
	// If non-nil, a stringmap will be written here. The string will be
	// duplicated here and in the return value.
	map &StringMap = unsafe { nil }
}

enum SelectionStringFailPoint as u8 {
	copy_map
}

struct SelectionStringTripwire {
mut:
	value tripwire.TripwireModule[SelectionStringFailPoint]
}

const selection_string_tw_singleton = &SelectionStringTripwire{}

fn selection_string_tripwire() &tripwire.TripwireModule[SelectionStringFailPoint] {
	return unsafe { &selection_string_tw_singleton.value }
}

pub struct SelectLine {
pub:
	// The pin of some part of the line to select.
	pin Pin
	// These are the codepoints to consider whitespace to trim
	// from the ends of the selection.
	whitespace ?[]u32 = [u32(0), u32(` `), u32(`\t`)]
	// If true, line selection will consider semantic prompt
	// state changing a boundary. State changing is ANY state
	// change.
	semantic_prompt_boundary bool = true
}

pub struct LineIterator {
pub mut:
	screen  &Screen = unsafe { nil }
	current ?Pin
}

pub fn (mut self LineIterator) next() ?Selection {
	current := self.current or { return none }
	result := self.screen.select_line(SelectLine{
		pin:                      current
		whitespace:               none
		semantic_prompt_boundary: false
	}) or {
		self.current = none
		return none
	}

	self.current = result.end().down(1)
	return result
}

pub struct PromptClickMove {
pub:
	left  uint
	right uint
}

pub const prompt_click_move_zero = PromptClickMove{
	left:  0
	right: 0
}

// The terminal package owns screen lifecycle while the kitty package owns the
// concrete storage type. Operation-specific hooks preserve the direct source
// calls without introducing a terminal -> kitty -> terminal import cycle.

// ============================================================
// Screen struct
// ============================================================

@[heap]
pub struct Screen {
pub mut:
	// The list of pages in the screen.
	pages PageList
	// Special-case where we want no scrollback whatsoever. We have to flag
	// this because max_size 0 in PageList gets rounded up to two pages so
	// we can always have an active screen.
	no_scrollback bool
	// The current cursor position
	cursor Cursor
	// The saved cursor
	saved_cursor ?SavedCursor
	// The selection for this screen (if any). This MUST be a tracked selection
	// otherwise the selection will become invalid. Instead of accessing this
	// directly to set it, use the `select` function which will assert and
	// automatically setup tracking.
	selection ?Selection
	// The charset state
	charset CharsetState
	// The current or most recent protected mode. Once a protection mode is
	// set, this will never become "off" again until the screen is reset.
	// The current state of whether protection attributes should be set is
	// set on the Cell pen; this is only used to determine the most recent
	// protection mode since some sequences such as ECH depend on this.
	protected_mode ProtectedMode = .off
	// The kitty keyboard settings.
	kitty_keyboard KeyFlagStack
	// Kitty graphics protocol state.
	kitty_images ImageStorage
	// Semantic prompt (OSC133) state.
	semantic_prompt SemanticPrompt
	// Dirty flags for the renderer.
	dirty ScreenDirty
}

// Initialize a new screen.
//
// max_scrollback is the amount of scrollback to keep in bytes. This
// will be rounded UP to the nearest page size because our minimum allocation
// size is that anyways.
//
// If max scrollback is 0, then no scrollback is kept at all.
pub fn Screen.init(cols u32, rows u32, max_scrollback uint) !Screen {
	return Screen.init_alloc(lib_allocator.c_allocator_value(), cols, rows, max_scrollback)
}

pub fn Screen.init_alloc(allocator lib_allocator.Allocator, cols u32, rows u32, max_scrollback uint) !Screen {
	// Initialize our backing pages.
	mut pages := PageList.init_alloc(allocator, page_list_page_allocator(), u16(cols), u16(rows), max_scrollback)!

	// Create our tracked pin for the cursor.
	first := pages.pages.first or { panic('page list has no pages') }
	page_pin := pages.track_pin(Pin{
		node: first
	}) or {
		pages.deinit()
		return err
	}
	page_rac := page_pin.row_and_cell()

	return Screen{
		pages:           pages
		no_scrollback:   max_scrollback == 0
		cursor:          Cursor{
			x:         0
			y:         0
			page_pin:  page_pin
			page_row:  page_rac.row
			page_cell: page_rac.cell
		}
		semantic_prompt: semantic_prompt_disabled
	}
}

pub fn (mut self Screen) deinit() {
	self.kitty_images.deinit(mut self)
	self.cursor.deinit()
	self.pages.deinit()
}

// Assert that the screen is in a consistent state. This doesn't check
// all pages in the page list because that is SO SLOW even just for
// tests. This only asserts the screen specific data so callers should
// ensure they're also calling page integrity checks if necessary.
pub fn (self &Screen) assert_integrity() {
	$if !prod {
		assert self.cursor.x < u32(self.pages.cols)
		assert self.cursor.y < u32(self.pages.rows)

		// Our cursor x/y should always match the pin. If this doesn't
		// match then it indicates that the tracked pin moved and we didn't
		// account for it by either calling cursorReload or manually
		// adjusting.
		pt := self.pages.point_from_pin(.active, *self.cursor.page_pin) or {
			panic('cursor pin is outside the active area')
		}
		assert self.cursor.x == u32(pt.coord().x)
		assert self.cursor.y == pt.coord().y
	}
}

// Reset the screen according to the logic of a DEC RIS sequence.
//
// - Clears the screen and attempts to reclaim memory.
// - Moves the cursor to the top-left.
// - Clears any cursor state: style, hyperlink, etc.
// - Resets the charset
// - Clears the selection
// - Deletes all Kitty graphics
// - Resets Kitty Keyboard settings
// - Disables protection mode
//
pub fn (mut self Screen) reset() {
	// Reset our pages
	self.pages.reset()

	// The above reset preserves tracked pins so we can still use
	// our cursor pin, which should be at the top-left already.
	cursor_pin := self.cursor.page_pin
	first := self.pages.pages.first or { panic('page list has no pages') }
	assert voidptr(cursor_pin.node) == voidptr(first)
	assert cursor_pin.x == 0
	assert cursor_pin.y == 0
	cursor_rac := cursor_pin.row_and_cell()
	self.cursor.deinit()
	self.cursor = Cursor{
		page_pin:  cursor_pin
		page_row:  cursor_rac.row
		page_cell: cursor_rac.cell
	}

	// Reset kitty graphics storage
	self.kitty_images.deinit(mut self)
	self.kitty_images = ImageStorage{
		dirty: true
	}

	// Reset our basic state
	self.saved_cursor = none
	self.charset = CharsetState{}
	self.kitty_keyboard = KeyFlagStack{}
	self.protected_mode = .off
	self.semantic_prompt = semantic_prompt_disabled
	self.clear_selection()
}

// Clone the screen.
//
// This will copy:
//
//   - Screen dimensions
//   - Screen data (cell state, etc.) for the region
//
// Anything not mentioned above is NOT copied. Some of this is for
// very good reason:
//
//   - Kitty images have a LOT of data. This is not efficient to copy.
//     Use a lock and access the image data. The dirty bit is there for
//     a reason.
//   - Cursor location can be expensive to calculate with respect to the
//     specified region. It is faster to grab the cursor from the old
//     screen and then move it to the new screen.
//   - Current hyperlink cursor state has heap allocations. Since clone
//     is only for read-only operations, it is better to not have any
//     hyperlink state. Note that already-written hyperlinks are cloned.
//
// If not mentioned above, then there isn't a specific reason right now
// to not copy some data other than we probably didn't need it and it
// isn't necessary for screen coherency.
//
// Other notes:
//
//   - The viewport will always be set to the active area of the new
//     screen. This is the bottom "rows" rows.
//   - If the clone region is smaller than a viewport area, blanks will
//     be filled in at the bottom.
//
pub fn (self &Screen) clone(top Point, bot ?Point) !Screen {
	return self.clone_alloc(self.pages.pool.alloc, top, bot)
}

pub fn (self &Screen) clone_alloc(allocator lib_allocator.Allocator, top Point, bot ?Point) !Screen {
	// Create a tracked pin remapper for our selection and cursor. Note
	// that we may want to expose this generally in the future but at the
	// time of doing this we don't need to.
	mut pin_remap := PageTrackedPinsRemap.init_alloc(allocator)
	defer { pin_remap.deinit() }

	mut pages := self.pages.clone_alloc(allocator, PageCloneOpts{
		top:          top
		bot:          bot
		tracked_pins: &pin_remap
	})!

	// Find our cursor. If the cursor isn't in the cloned area, we move it
	// to the top-left arbitrarily because a screen must have SOME cursor.
	mut cursor := Cursor{}
	mut found_cursor := false
	if remapped := pin_remap.get(self.cursor.page_pin) {
		mut p := unsafe { remapped }
		page_rac := p.row_and_cell()
		if pt := pages.point_from_pin(.active, *p) {
			cursor = Cursor{
				x:         u32(pt.coord().x)
				y:         pt.coord().y
				page_pin:  p
				page_row:  page_rac.row
				page_cell: page_rac.cell
			}
			found_cursor = true
		}
	}
	if !found_cursor {
		first := pages.pages.first or { panic('cloned page list has no pages') }
		mut page_pin := pages.track_pin(Pin{
			node: first
		}) or {
			pages.deinit()
			return err
		}
		page_rac := page_pin.row_and_cell()
		cursor = Cursor{
			x:         0
			y:         0
			page_pin:  page_pin
			page_row:  page_rac.row
			page_cell: page_rac.cell
		}
	}

	// Preserve our selection if we have one.
	mut sel := ?Selection(none)
	if existing := self.selection {
		sel = (self.clone_selection(existing, top, mut pages, pin_remap) or {
			pages.deinit()
			return err
		}).selection
	}

	result := Screen{
		pages:         pages
		no_scrollback: self.no_scrollback
		cursor:        cursor
		selection:     sel
		dirty:         self.dirty
	}
	result.assert_integrity()
	return result
}

// Remap a tracked selection into a cloned page list. This is the selection
// block of Ghostty's Screen.clone, split out because V has no labeled
// block expressions.
struct SelectionCloneOption {
	selection ?Selection
}

fn (self &Screen) clone_selection(sel Selection, top Point, mut pages PageList, pin_remap &PageTrackedPinsRemap) !SelectionCloneOption {
	assert sel.tracked()
	bounds := sel.bounds as SelectionTrackedBounds

	tl, br := match sel.order(self) {
		.forward, .mirrored_forward { bounds.start, bounds.end }
		.reverse, .mirrored_reverse { bounds.end, bounds.start }
	}

	start_pin := pin_remap.get(tl) or {
		// No start means it is outside the cloned area.

		// If we have no end pin then either
		// (1) our whole selection is outside the cloned area or
		// (2) our cloned area is within the selection
		if pin_remap.get(br) == none {
			// We check if the selection bottom right pin is above
			// the cloned area or if the top left pin is below the
			// cloned area, in either of these cases it means that
			// the selection is fully out of bounds, so we have no
			// selection in the cloned area and break out now.
			clone_top := self.pages.pin(top) or { return SelectionCloneOption{} }
			clone_top_y := (self.pages.point_from_pin(.screen, clone_top) or { return SelectionCloneOption{} }).coord().y
			br_y := (self.pages.point_from_pin(.screen, *br) or { return SelectionCloneOption{} }).coord().y
			if br_y < clone_top_y {
				return SelectionCloneOption{}
			}
			tl_y := (self.pages.point_from_pin(.screen, *tl) or { return SelectionCloneOption{} }).coord().y
			if tl_y > clone_top_y {
				return SelectionCloneOption{}
			}
		}

		// We move the top pin back in bounds to the top row.
		first := pages.pages.first or { panic('cloned page list has no pages') }
		pages.track_pin(Pin{
			node: first
			x:    if sel.rectangle { tl.x } else { 0 }
		})!
	}

	// If we got to this point it means that the selection is not
	// fully out of bounds, so we move the bottom right pin back
	// in bounds if it isn't already.
	end_pin := pin_remap.get(br) or {
		last := pages.pages.last or { panic('cloned page list has no pages') }
		pages.track_pin(Pin{
			node: last
			x:    if sel.rectangle { br.x } else { pages.cols - 1 }
			y:    last.data.size.rows - 1
		})!
	}

	return SelectionCloneOption{
		selection: Selection{
			bounds:    SelectionTrackedBounds{
				start: start_pin
				end:   end_pin
			}
			rectangle: sel.rectangle
		}
	}
}

pub fn (mut self Screen) increase_capacity(node &PageNode, adjustment ?IncreaseCapacity) !&PageNode {
	// If the page being modified isn't our cursor page then
	// this is a quick operation because we have no additional
	// accounting. We have to do this check here BEFORE calling
	// increaseCapacity because increaseCapacity will update all
	// our tracked pins (including our cursor).
	if voidptr(node) != voidptr(self.cursor.page_pin.node) {
		return self.pages.increase_capacity(node, adjustment)!
	}

	// We're modifying the cursor page. When we increase the
	// capacity below it will be short the ref count on our
	// current style and hyperlink, so we need to init those.
	new_node := self.pages.increase_capacity(node, adjustment)!
	mut new_page := &new_node.data

	// Re-add the style, if the page somehow doesn't have enough
	// memory to add it, we emit a warning and gracefully degrade
	// to the default style for the cursor.
	if self.cursor.style_id != default_style_id {
		self.cursor.style_id = new_page.styles.add(self.cursor.style) or {
			// TODO: Should we increase the capacity further in this case?
			// log.warn: failed to add cursor style back to page

			// Reset the cursor style.
			self.cursor.style = CellStyle{}
			default_style_id
		}
	}

	// Re-add the hyperlink, if the page somehow doesn't have enough
	// memory to add it, we emit a warning and gracefully degrade to
	// no hyperlink.
	if link := self.cursor.hyperlink_state {
		// So we don't attempt to free any memory in the replaced page.
		self.cursor.hyperlink_id = 0
		self.cursor.hyperlink_state = none

		// Re-add
		self.start_hyperlink_once(link) or {
			// TODO: Should we increase the capacity further in this case?
			// log.warn: failed to add cursor hyperlink back to page
		}
	}

	// Reload the cursor information because the pin changed.
	// So our page row/cell and so on are all off.
	self.cursor_reload()

	return new_node
}

pub fn (mut self Screen) cursor_cell_right(n u32) &CellData {
	assert self.cursor.x + n < u32(self.pages.cols)
	return unsafe { &CellData(&u8(self.cursor.page_cell) + uint(n) * sizeof(CellData)) }
}

pub fn (mut self Screen) cursor_cell_left(n u32) &CellData {
	assert self.cursor.x >= n
	return unsafe { &CellData(&u8(self.cursor.page_cell) - uint(n) * sizeof(CellData)) }
}

pub fn (mut self Screen) cursor_cell_end_of_prev() &CellData {
	assert self.cursor.y > 0

	mut page_pin := self.cursor.page_pin.up(1) or { panic('cursor has no previous row') }
	page_pin.x = self.pages.cols - 1
	page_rac := page_pin.row_and_cell()
	return page_rac.cell
}

// Move the cursor right. This is a specialized function that is very fast
// if the caller can guarantee we have space to move right (no wrapping).
pub fn (mut self Screen) cursor_right(n u32) {
	assert self.cursor.x + n < u32(self.pages.cols)
	defer { self.assert_integrity() }

	self.cursor.page_cell = unsafe { &CellData(&u8(self.cursor.page_cell) + uint(n) * sizeof(CellData)) }
	self.cursor.page_pin.x += u16(n)
	self.cursor.x += n
}

// Move the cursor left.
pub fn (mut self Screen) cursor_left(n u32) {
	assert self.cursor.x >= n
	defer { self.assert_integrity() }

	self.cursor.page_cell = unsafe { &CellData(&u8(self.cursor.page_cell) - uint(n) * sizeof(CellData)) }
	self.cursor.page_pin.x -= u16(n)
	self.cursor.x -= n
}

// Move the cursor up.
//
// Precondition: The cursor is not at the top of the screen.
pub fn (mut self Screen) cursor_up(n u32) {
	assert self.cursor.y >= n
	defer { self.assert_integrity() }

	self.cursor.y -= n // Must be set before cursorChangePin
	self.cursor_change_pin(self.cursor.page_pin.up(n) or { panic('cursor up is outside the page list') })
	page_rac := self.cursor.page_pin.row_and_cell()
	self.cursor.page_row = page_rac.row
	self.cursor.page_cell = page_rac.cell
}

pub fn (mut self Screen) cursor_row_up(n u32) &RowData {
	assert self.cursor.y >= n
	defer { self.assert_integrity() }

	page_pin := self.cursor.page_pin.up(n) or { panic('cursor row up is outside the page list') }
	page_rac := page_pin.row_and_cell()
	return page_rac.row
}

// Move the cursor down.
//
// Precondition: The cursor is not at the bottom of the screen.
pub fn (mut self Screen) cursor_down(n u32) {
	assert self.cursor.y + n < u32(self.pages.rows)
	defer { self.assert_integrity() }

	self.cursor.y += n // Must be set before cursorChangePin

	// We move the offset into our page list to the next row and then
	// get the pointers to the row/cell and set all the cursor state up.
	self.cursor_change_pin(self.cursor.page_pin.down(n) or {
		panic('cursor down is outside the page list')
	})
	page_rac := self.cursor.page_pin.row_and_cell()
	self.cursor.page_row = page_rac.row
	self.cursor.page_cell = page_rac.cell
}

// Move the cursor to some absolute horizontal position.
pub fn (mut self Screen) cursor_horizontal_absolute(x u32) {
	assert x < u32(self.pages.cols)
	defer { self.assert_integrity() }

	self.cursor.page_pin.x = u16(x)
	page_rac := self.cursor.page_pin.row_and_cell()
	self.cursor.page_cell = page_rac.cell
	self.cursor.x = x
}

// Move the cursor to some absolute position.
pub fn (mut self Screen) cursor_absolute(x u32, y u32) {
	assert x < u32(self.pages.cols)
	assert y < u32(self.pages.rows)
	defer { self.assert_integrity() }

	mut page_pin := if y < self.cursor.y {
		self.cursor.page_pin.up(self.cursor.y - y) or { panic('cursor absolute is outside the page list') }
	} else if y > self.cursor.y {
		self.cursor.page_pin.down(y - self.cursor.y) or {
			panic('cursor absolute is outside the page list')
		}
	} else {
		*self.cursor.page_pin
	}
	page_pin.x = u16(x)
	self.cursor.x = x // Must be set before cursorChangePin
	self.cursor.y = y
	self.cursor_change_pin(page_pin)
	page_rac := self.cursor.page_pin.row_and_cell()
	self.cursor.page_row = page_rac.row
	self.cursor.page_cell = page_rac.cell
}

// Reloads the cursor pointer information into the screen. This is expensive
// so it should only be done in cases where the pointers are invalidated
// in such a way that its difficult to recover otherwise.
pub fn (mut self Screen) cursor_reload() {
	defer { self.assert_integrity() }

	// Our tracked pin is ALWAYS accurate, so we derive the active
	// point from the pin. If this returns null it means our pin
	// points outside the active area. In that case, we update the
	// pin to be the top-left.
	pt := self.pages.point_from_pin(.active, *self.cursor.page_pin) or {
		pin := self.pages.pin(Point.new(.active, Coordinate{})) or {
			panic('page list has no active area')
		}
		unsafe {
			*self.cursor.page_pin = pin
		}
		self.pages.point_from_pin(.active, pin) or { panic('active pin is not active') }
	}

	self.cursor.x = u32(pt.coord().x)
	self.cursor.y = pt.coord().y
	page_rac := self.cursor.page_pin.row_and_cell()
	self.cursor.page_row = page_rac.row
	self.cursor.page_cell = page_rac.cell

	// If we have a style, we need to ensure it is in the page because this
	// method may also be called after a page change.
	if self.cursor.style_id != default_style_id {
		self.manual_style_update() or {
			// This failure should not happen because manualStyleUpdate
			// handles page splitting, overflow, and more. This should only
			// happen if we're out of RAM. In this case, we'll just degrade
			// gracefully back to the default style.
			// log.err: failed to update style on cursor reload
			self.cursor.style = CellStyle{}
			self.cursor.style_id = 0
		}
	}
}

// Scroll the active area and keep the cursor at the bottom of the screen.
// This is a very specialized function but it keeps it fast.
pub fn (mut self Screen) cursor_down_scroll() ! {
	assert self.cursor.y == u32(self.pages.rows) - 1
	defer { self.assert_integrity() }

	// Scrolling dirties the images because it updates their placements pins.
	self.kitty_images.dirty = true

	// If we have no scrollback, then we shift all our rows instead.
	if self.no_scrollback {
		// If we have a single-row screen, we have no rows to shift
		// so our cursor is in the correct place we just have to clear
		// the cells.
		if self.pages.rows == 1 {
			mut page := &self.cursor.page_pin.node.data
			mut cells := page.get_cells(self.cursor.page_row)
			self.clear_cells(mut page, mut self.cursor.page_row, mut cells)
			self.cursor_mark_dirty()
		} else {
			// The call to `eraseRow` will move the tracked cursor pin up by one
			// row, but we don't actually want that, so we keep the old pin and
			// put it back after calling `eraseRow`.
			old_pin := *self.cursor.page_pin

			// eraseRow will shift everything below it up.
			self.pages.erase_row(Point.new(.active, Coordinate{}))!

			// Note we don't need to mark anything dirty in this branch
			// because eraseRow will mark all the rotated rows as dirty
			// in the entire page.

			// We don't use `cursorChangePin` here because we aren't
			// actually changing the pin, we're keeping it the same.
			unsafe {
				*self.cursor.page_pin = old_pin
			}

			// We do, however, need to refresh the cached page row
			// and cell, because `eraseRow` will have moved the row.
			page_rac := self.cursor.page_pin.row_and_cell()
			self.cursor.page_row = page_rac.row
			self.cursor.page_cell = page_rac.cell
		}
	} else {
		old_pin := *self.cursor.page_pin

		// Grow our pages by one row. The PageList will handle if we need to
		// allocate, prune scrollback, whatever.
		_ = self.pages.grow()!.node

		// If our pin page change it means that the page that the pin
		// was on was pruned. In this case, grow() moves the pin to
		// the top-left of the new page. This effectively moves it by
		// one already, we just need to fix up the x value.
		page_pin := if voidptr(old_pin.node) == voidptr(self.cursor.page_pin.node) {
			self.cursor.page_pin.down(1) or { panic('grown page list has no row below the cursor') }
		} else {
			mut pin := *self.cursor.page_pin
			pin.x = u16(self.cursor.x)
			pin
		}

		// These assertions help catch some pagelist math errors. Our
		// x/y should be unchanged after the grow.
		$if !prod {
			active := self.pages.point_from_pin(.active, page_pin) or {
				panic('grown cursor pin is not active')
			}
			assert u32(active.coord().x) == self.cursor.x
			assert active.coord().y == self.cursor.y
		}

		self.cursor_change_pin(page_pin)
		page_rac := self.cursor.page_pin.row_and_cell()
		self.cursor.page_row = page_rac.row
		self.cursor.page_cell = page_rac.cell

		// Our new row is always dirty
		self.cursor_mark_dirty()

		// Clear the new row so it gets our bg color. We only do this
		// if we have a bg color at all.
		if self.cursor.style.bg_color !is StyleColorNone {
			mut page := &self.cursor.page_pin.node.data
			mut cells := page.get_cells(self.cursor.page_row)
			self.clear_cells(mut page, mut self.cursor.page_row, mut cells)
		}
	}

	if self.cursor.style_id != default_style_id {
		// The newly created line needs to be styled according to
		// the bg color if it is set.
		if blank_cell := self.cursor.style.bg_cell() {
			self.cursor_row_memset(blank_cell)
		}
	}
}

// @memset(cells[0..cols], blank_cell) over the cursor row, starting from
// the cursor cell minus the cursor x as the source does.
fn (mut self Screen) cursor_row_memset(blank_cell CellData) {
	cells := unsafe { &CellData(&u8(self.cursor.page_cell) - uint(self.cursor.x) * sizeof(CellData)) }
	for x in 0 .. u32(self.pages.cols) {
		unsafe {
			*(&CellData(&u8(cells) + uint(x) * sizeof(CellData))) = blank_cell
		}
	}
}

// This scrolls the active area at and above the cursor.
// The lines below the cursor are not scrolled.
pub fn (mut self Screen) cursor_scroll_above() ! {
	// We unconditionally mark the cursor row as dirty here because
	// the cursor always changes page rows inside this function, and
	// when that happens it can mean the text in the old row needs to
	// be re-shaped because the cursor splits runs to break ligatures.
	self.cursor_mark_dirty()

	// If the cursor is on the bottom of the screen, its faster to use
	// our specialized function for that case.
	if self.cursor.y == u32(self.pages.rows) - 1 {
		return self.cursor_down_scroll()
	}

	defer { self.assert_integrity() }

	// Logic below assumes we always have at least one row that isn't moving
	assert self.cursor.y < u32(self.pages.rows) - 1

	// Explanation:
	//  We don't actually move everything that's at or above the cursor row,
	//  since this would require us to shift up our ENTIRE scrollback, which
	//  would be ridiculously expensive. Instead, we insert a new row at the
	//  end of the pagelist (`grow()`), and move everything BELOW the cursor
	//  DOWN by one row. This has the same practical result but it's a whole
	//  lot cheaper in 99% of cases.

	old_pin := *self.cursor.page_pin
	if _ := self.pages.grow()!.node {
		self.cursor_scroll_above_rotate()!
	} else {
		// In this case, it means grow() didn't allocate a new page.

		last := self.pages.pages.last or { panic('page list has no pages') }
		if voidptr(self.cursor.page_pin.node) == voidptr(last) {
			// If we're on the last page we can do a very fast path because
			// all the rows we need to move around are within a single page.

			// Note: we don't need to call cursorChangePin here because
			// the pin page is the same so there is no accounting to do
			// for styles or any of that.
			assert voidptr(old_pin.node) == voidptr(self.cursor.page_pin.node)
			unsafe {
				*self.cursor.page_pin = self.cursor.page_pin.down(1) or {
					panic('grown page has no row below the cursor')
				}
			}

			pin := self.cursor.page_pin
			mut page := &self.cursor.page_pin.node.data

			// Rotate the rows so that the newly created empty row is at the
			// beginning. e.g. [ 0 1 2 3 ] in to [ 3 0 1 2 ].
			mut rows := unsafe { page.rows[int(pin.y)..int(page.size.rows)] }
			rotate_row_views(mut rows, true)

			// Mark the whole page as dirty.
			//
			// Technically we only need to mark from the cursor row to the
			// end but this is a hot function, so we want to minimize work.
			page.dirty = true

			// Setup our cursor caches after the rotation so it points to the
			// correct data
			page_rac := self.cursor.page_pin.row_and_cell()
			self.cursor.page_row = page_rac.row
			self.cursor.page_cell = page_rac.cell
		} else {
			// We didn't grow pages but our cursor isn't on the last page.
			// In this case we need to do more work because we need to copy
			// elements between pages.
			//
			// An example scenario of this is shown below:
			//
			//      +----------+ = PAGE 0
			//  ... :          :
			//     +-------------+ ACTIVE
			// 4302 |1A00000000| | 0
			// 4303 |2B00000000| | 1
			//      :^         : : = PIN 0
			// 4304 |3C00000000| | 2
			//      +----------+ :
			//      +----------+ : = PAGE 1
			//    0 |4D00000000| | 3
			//    1 |5E00000000| | 4
			//      +----------+ :
			//     +-------------+
			self.cursor_scroll_above_rotate()!
		}
	}

	if self.cursor.style_id != default_style_id {
		// The newly created line needs to be styled according to
		// the bg color if it is set.
		if blank_cell := self.cursor.style.bg_cell() {
			self.cursor_row_memset(blank_cell)
		}
	}
}

fn (mut self Screen) cursor_scroll_above_rotate() ! {
	self.cursor_change_pin(self.cursor.page_pin.down(1) or {
		panic('page list has no row below the cursor')
	})

	// Go through each of the pages following our pin, shift all rows
	// down by one, and copy the last row of the previous page.
	mut current := self.pages.pages.last or { panic('page list has no pages') }
	for voidptr(current) != voidptr(self.cursor.page_pin.node) {
		mut prev := current.prev or { panic('page before the cursor page is missing') }
		mut prev_page := &prev.data
		mut cur_page := &current.data

		// Rotate the pages down: [ 0 1 2 3 ] => [ 3 0 1 2 ]
		mut cur_rows := unsafe { cur_page.rows[..int(cur_page.size.rows)] }
		rotate_row_views(mut cur_rows, true)

		// Copy the last row of the previous page to the top of current.
		cur_page.clone_row_from(prev_page, 0, prev_page.size.rows - 1)!

		// Mark dirty on the page, since we are dirtying all rows with this.
		cur_page.dirty = true

		current = prev
	}

	// Our current is our cursor page, we need to rotate down from
	// our cursor and clear our row.
	assert voidptr(current) == voidptr(self.cursor.page_pin.node)
	mut cur_page := &current.data
	y := int(self.cursor.page_pin.y)
	mut cur_rows := unsafe { cur_page.rows[y..int(cur_page.size.rows)] }
	rotate_row_views(mut cur_rows, true)
	mut row := unsafe { &cur_page.rows[y] }
	mut cells := cur_page.get_cells(row)
	self.clear_cells(mut cur_page, mut row, mut cells)

	// Mark the whole page as dirty.
	//
	// Technically we only need to mark from the cursor row to the
	// end but this is a hot function, so we want to minimize work.
	cur_page.dirty = true

	// Setup cursor cache data after all the rotations so our
	// row is valid.
	page_rac := self.cursor.page_pin.row_and_cell()
	self.cursor.page_row = page_rac.row
	self.cursor.page_cell = page_rac.cell
}

// Move the cursor down if we're not at the bottom of the screen. Otherwise
// scroll. Currently only used for testing.
fn (mut self Screen) cursor_down_or_scroll() ! {
	if self.cursor.y + 1 < u32(self.pages.rows) {
		self.cursor_down(1)
	} else {
		self.cursor_down_scroll()!
	}
}

// Copy another cursor. The cursor can be on any screen but the x/y
// must be within our screen bounds.
pub fn (mut self Screen) cursor_copy(other Cursor, opts CursorCopyOptions) ! {
	assert other.x < u32(self.pages.cols)
	assert other.y < u32(self.pages.rows)

	// End any currently active hyperlink on our cursor.
	self.end_hyperlink()

	old := self.cursor
	self.cursor = other

	// Keep our old style ID so it can be properly cleaned up below.
	self.cursor.style_id = old.style_id

	// Hyperlinks will be managed separately below.
	self.cursor.hyperlink_id = 0
	self.cursor.hyperlink_state = none

	// Keep our old page pin and X/Y because:
	// 1. The old style will need to be cleaned up from the page it's from.
	// 2. The new position navigated to by `cursorAbsolute` needs to be in our
	//    own screen.
	self.cursor.page_pin = old.page_pin
	self.cursor.x = old.x
	self.cursor.y = old.y

	// Call manual style update in order to clean up our old style, if we have
	// one, and also to load the style from the other cursor, if it had one.
	self.manual_style_update() or {
		self.cursor = old
		return err
	}

	// Move to the correct location to match the other cursor.
	self.cursor_absolute(other.x, other.y)

	// If the other cursor had a hyperlink, add it to ours.
	if opts.hyperlink && other.hyperlink_id != 0 {
		// Get the hyperlink from the other cursor's page.
		other_page := &other.page_pin.node.data
		other_link := other_page.hyperlink_set.get(HyperlinkId(other.hyperlink_id))

		uri := other_link.uri
		id_ := match other_link.id {
			HyperlinkExplicitId { ?string(other_link.id.value) }
			HyperlinkImplicitId { ?string(none) }
		}

		// And it to our cursor.
		self.start_hyperlink(uri, id_) or {
			// This shouldn't happen because startHyperlink should handle
			// resizing. This only happens if we're truly out of RAM. Degrade
			// to forgetting the hyperlink.
			// log.err: failed to update hyperlink on cursor change
		}
	}
}

// Always use this to write to cursor.page_pin.*.
//
// This specifically handles the case when the new pin is on a different
// page than the old AND we have a style or hyperlink set. In that case,
// we must release our old one and insert the new one, since styles are
// stored per-page.
//
// Note that this can change the cursor pin AGAIN if the process of
// setting up our cursor forces a capacity adjustment of the underlying
// cursor page, so any references to the page pin should be re-read
// from `self.cursor.page_pin` after calling this.
fn (mut self Screen) cursor_change_pin(new Pin) {
	// Moving the cursor affects text run splitting (ligatures) so
	// we must mark the old and new page dirty. We do this as long
	// as the pins are not equal
	if !self.cursor.page_pin.eql(new) {
		self.cursor_mark_dirty()
		new.mark_dirty()
	}

	// If our pin is on the same page, then we can just update the pin.
	// We don't need to migrate any state.
	if voidptr(self.cursor.page_pin.node) == voidptr(new.node) {
		unsafe {
			*self.cursor.page_pin = new
		}
		return
	}

	// If we have an old style then we need to release it from the old page.
	old_style_ := if self.cursor.style_id == default_style_id {
		?CellStyle(none)
	} else {
		?CellStyle(self.cursor.style)
	}
	if old_style_ != none {
		// Release the style directly from the old page instead of going through
		// manualStyleUpdate, because the cursor position may have already been
		// updated but the pin has not, which would fail integrity checks.
		mut old_page := &self.cursor.page_pin.node.data
		old_page.styles.release(self.cursor.style_id)
		self.cursor.style = CellStyle{}
		self.cursor.style_id = default_style_id
	}

	// If we have a hyperlink then we need to release it from the old page.
	if self.cursor.hyperlink_state != none {
		mut old_page := &self.cursor.page_pin.node.data
		old_page.hyperlink_set.release(HyperlinkId(self.cursor.hyperlink_id))
	}

	// Update our pin to the new page
	unsafe {
		*self.cursor.page_pin = new
	}

	// On the new page, we need to migrate our style
	if old_style := old_style_ {
		self.cursor.style = old_style
		self.manual_style_update() or {
			// This failure should not happen because manualStyleUpdate
			// handles page splitting, overflow, and more. This should only
			// happen if we're out of RAM. In this case, we'll just degrade
			// gracefully back to the default style.
			// log.err: failed to update style on cursor change
			self.cursor.style = CellStyle{}
			self.cursor.style_id = 0
		}
	}

	// On the new page, we need to migrate our hyperlink
	if link := self.cursor.hyperlink_state {
		// So we don't attempt to free any memory in the replaced page.
		self.cursor.hyperlink_id = 0
		self.cursor.hyperlink_state = none

		// Re-add
		self.start_hyperlink(link.uri, match link.id {
			HyperlinkExplicitId { ?string(link.id.value) }
			HyperlinkImplicitId { ?string(none) }
		}) or {
			// This shouldn't happen because startHyperlink should handle
			// resizing. This only happens if we're truly out of RAM. Degrade
			// to forgetting the hyperlink.
			// log.err: failed to update hyperlink on cursor change
		}
	}
}

// Mark the cursor position as dirty.
// TODO: test
pub fn (mut self Screen) cursor_mark_dirty() {
	self.cursor.page_row.header.dirty = true
}

// Reset the cursor row's soft-wrap state and the cursor's pending wrap.
// Also handles clearing the spacer head on the cursor row and resetting
// the wrap_continuation flag on the next row if necessary.
//
// NOTE(qwerasd): This method is not scrolling region aware, and cannot be
// since it's on Screen not Terminal. This needs to be addressed down the
// line. Not an extremely urgent issue since it's an edge case of an edge
// case, but not ideal.
pub fn (mut self Screen) cursor_reset_wrap() {
	// Reset the cursor's pending wrap state
	self.cursor.pending_wrap = false

	mut page_row := self.cursor.page_row

	if !page_row.header.wrap {
		return
	}

	// This row does not wrap and the next row is not wrapped to
	page_row.header.wrap = false

	if next_row := self.cursor.page_pin.down(1) {
		mut row := next_row.row_and_cell().row
		row.header.wrap_continuation = false
	}

	// If the last cell in the row is a spacer head we need to clear it.
	mut cells := self.cursor.page_pin.cells(.all)
	cols := int(self.cursor.page_pin.node.data.size.cols)
	cell := cells[cols - 1]
	if cell.wide == .spacer_head {
		mut page := &self.cursor.page_pin.node.data
		mut last := unsafe { cells[cols - 1..cols] }
		self.clear_cells(mut page, mut page_row, mut last)
	}
}

// Scroll the viewport of the terminal grid.
pub fn (mut self Screen) scroll(behavior Scroll) {
	defer { self.assert_integrity() }

	// No matter what, scrolling marks our image state as dirty since
	// it could move placements. If there are no placements or no images
	// this is still a very cheap operation.
	self.kitty_images.dirty = true

	match behavior {
		ScrollActive { self.pages.scroll(PageScrollActive{}) }
		ScrollTop { self.pages.scroll(PageScrollTop{}) }
		ScrollPin { self.pages.scroll(PageScrollPin{ pin: behavior.pin }) }
		ScrollRow { self.pages.scroll(PageScrollRow{ n: behavior.n }) }
		ScrollDeltaRow { self.pages.scroll(PageScrollDeltaRow{ delta: behavior.delta }) }
		ScrollDeltaPrompt { self.pages.scroll(PageScrollDeltaPrompt{ delta: behavior.delta }) }
	}
}

// See PageList.scrollClear. In addition to that, we reset the cursor
// to be on top.
pub fn (mut self Screen) scroll_clear() ! {
	defer { self.assert_integrity() }

	self.pages.scroll_clear()!
	self.cursor_reload()

	// No matter what, scrolling marks our image state as dirty since
	// it could move placements. If there are no placements or no images
	// this is still a very cheap operation.
	self.kitty_images.dirty = true
}

// Returns true if the viewport is scrolled to the bottom of the screen.
pub fn (self &Screen) viewport_is_bottom() bool {
	return self.pages.viewport == .active
}

// Erase the region specified by tl and br, inclusive. This will physically
// erase the rows meaning the memory will be reclaimed (if the underlying
// page is empty) and other rows will be shifted up.
pub fn (mut self Screen) erase_rows(tl Point, bl ?Point) {
	defer { self.assert_integrity() }

	// Erase the rows
	self.pages.erase_rows(tl, bl)

	// Just to be safe, reset our cursor since it is possible depending
	// on the points that our active area shifted so our pointers are
	// invalid.
	self.cursor_reload()
}

fn (mut self Screen) erase_history() {
	// PageList remaps pins in removed rows to the surviving rows.
	self.kitty_images.reap_placements(mut self, true)
	self.erase_rows(Point.new(.history, Coordinate{}), none)
	// Erasing history can change the viewport even with no removed placement.
	self.kitty_images.dirty = true
}

// Clear the region specified by tl and bl, inclusive. Cleared cells are
// colored with the current style background color. This will clear all
// cells in the rows.
//
// If protected is true, the protected flag will be respected and only
// unprotected cells will be cleared. Otherwise, all cells will be cleared.
pub fn (mut self Screen) clear_rows(tl Point, bl ?Point, protected bool) {
	defer { self.assert_integrity() }

	mut it := self.pages.page_iterator(.right_down, tl, bl)
	for {
		chunk := it.next() or { break }
		mut page := &chunk.node.data
		for y in int(chunk.start) .. int(chunk.end) {
			mut row := unsafe { &page.rows[y] }
			cells_offset := row.header.cells_offset
			row_cells := row.cells
			mut cells := unsafe { row.cells[..int(self.pages.cols)] }

			// Clear all cells
			if protected {
				self.clear_unprotected_cells(mut page, mut row, mut cells)
				// We need to preserve other row attributes since we only
				// cleared unprotected cells.
				row.cells = row_cells
				row.header.cells_offset = cells_offset
			} else {
				self.clear_cells(mut page, mut row, mut cells)
				unsafe {
					*row.header = PageRowHeader{ cells_offset: cells_offset }
				}
			}

			row.header.dirty = true
		}
	}
}

// Clear the cells with the blank cell.
//
// This takes care to handle cleaning up graphemes and styles.
pub fn (mut self Screen) clear_cells(mut page Page, mut row RowData, mut cells []CellData) {
	// This whole operation does unsafe things, so we just want to assert
	// the end state.
	page.pause_integrity_checks(true)
	defer {
		page.pause_integrity_checks(false)
		page.assert_integrity()
		self.assert_integrity()
	}

	if cells.len == 0 {
		return
	}

	row_idx := page.row_index(row)
	left := cell_index(row, unsafe { &cells[0] })

	$if !prod {
		// Our row and cells should be within the page.
		assert row_idx < uint(page.size.rows)
		assert left + uint(cells.len) <= uint(page.get_cells(row).len)
	}

	// If we have managed memory (styles, graphemes, or hyperlinks)
	// in this row then we go cell by cell and clear them if present.
	if row.header.grapheme {
		for i, cell in cells {
			if cell.has_grapheme() {
				page.clear_grapheme(row_idx, left + uint(i))
			}
		}

		// If we have no left/right scroll region we can be sure
		// that we've cleared all the graphemes, so we clear the
		// flag, otherwise we ask the page to update the flag.
		if cells.len == int(self.pages.cols) {
			row.header.grapheme = false
		} else {
			page.update_row_grapheme_flag(row)
		}
	}

	if row.header.hyperlink {
		for i, cell in cells {
			if cell.has_hyperlink {
				page.clear_hyperlink(row_idx, left + uint(i))
			}
		}

		// If we have no left/right scroll region we can be sure
		// that we've cleared all the hyperlinks, so we clear the
		// flag, otherwise we ask the page to update the flag.
		if cells.len == int(self.pages.cols) {
			row.header.hyperlink = false
		} else {
			page.update_row_hyperlink_flag(row)
		}
	}

	if row.header.styled {
		for cell in cells {
			if cell.has_styling() {
				page.styles.release(cell.style_id)
			}
		}

		// If we have no left/right scroll region we can be sure
		// that we've cleared all the styles, so we clear the
		// flag, otherwise we ask the page to update the flag.
		if cells.len == int(self.pages.cols) {
			row.header.styled = false
		} else {
			page.update_row_styled_flag(row)
		}
	}

	if row.header.kitty_virtual_placeholder && cells.len == int(self.pages.cols) {
		mut found := false
		for c in cells {
			if c.codepoint() == kitty_unicode_placeholder {
				found = true
				break
			}
		}
		if !found {
			row.header.kitty_virtual_placeholder = false
		}
	}

	blank := self.blank_cell()
	for i in 0 .. cells.len {
		cells[i] = blank
	}
}

// Clear cells but only if they are not protected.
pub fn (mut self Screen) clear_unprotected_cells(mut page Page, mut row RowData, mut cells []CellData) {
	mut x0 := 0
	mut x1 := 0

	for x0 < cells.len {
		for cells[x0].is_protected {
			x0 += 1
			if x0 >= cells.len {
				break
			}
		}
		if x0 >= cells.len {
			break
		}
		x1 = x0 + 1
		for x1 < cells.len && !cells[x1].is_protected {
			x1 += 1
		}
		mut range := unsafe { cells[x0..x1] }
		self.clear_cells(mut page, mut row, mut range)
		x0 = x1
	}

	page.assert_integrity()
	self.assert_integrity()
}

// Clean up boundary conditions where a cell will become discontiguous with
// a neighboring cell because either one of them will be moved and/or cleared.
//
// For performance reasons this is specialized to operate on the cursor row.
//
// Handles the boundary between the cell at `x` and the cell at `x - 1`.
//
// So, for example, when moving a region of cells [a, b] (inclusive), call this
// function with `x = a` and `x = b + 1`. It is okay if `x` is out of bounds by
// 1, this will be interpreted correctly.
//
// DOES NOT MODIFY ROW WRAP STATE! See `cursorResetWrap` for that.
//
// The following boundary conditions are handled:
//
// - `x - 1` is a wide character and `x` is a spacer tail:
//   o Both cells will be cleared.
//   o If `x - 1` is the start of the row and was wrapped from a previous row
//     then the previous row is checked for a spacer head, which is cleared if
//     present.
//
// - `x == 0` and is a wide character:
//   o If the row is a wrap continuation then the previous row will be checked
//     for a spacer head, which is cleared if present.
//
// - `x == cols` and `x - 1` is a spacer head:
//   o `x - 1` will be cleared.
//
// NOTE(qwerasd): This method is not scrolling region aware, and cannot be
// since it's on Screen not Terminal. This needs to be addressed down the
// line. Not an extremely urgent issue since it's an edge case of an edge
// case, but not ideal.
pub fn (mut self Screen) split_cell_boundary(x u32) {
	mut page := &self.cursor.page_pin.node.data

	page.pause_integrity_checks(true)
	defer { page.pause_integrity_checks(false) }

	cols := u32(self.cursor.page_pin.node.data.size.cols)

	// `x` may be up to an INCLUDING `cols`, since that signifies splitting
	// the boundary to the right of the final cell in the row.
	assert x <= cols

	// [ A B C D E F|]
	//              ^ Boundary between final cell and row end.
	if x == cols {
		if !self.cursor.page_row.header.wrap {
			return
		}

		mut cells := self.cursor.page_pin.cells(.all)

		// Spacer head at end of wrapped row.
		if cells[cols - 1].wide == .spacer_head {
			mut last := unsafe { cells[int(cols) - 1..int(cols)] }
			self.clear_cells(mut page, mut self.cursor.page_row, mut last)
		}

		return
	}

	// [|A B C D E F ]
	//  ^ Boundary between first cell and row start.
	//
	//  OR
	//
	// [ A|B C D E F ]
	//    ^ Boundary between first cell and second cell.
	//
	// First cell may be a wrapped wide cell with a spacer
	// head on the previous row that needs to be cleared.
	if (x == 0 || x == 1) && self.cursor.page_row.header.wrap_continuation {
		cells := self.cursor.page_pin.cells(.all)

		// If the first cell in a row is wide the previous row
		// may have a spacer head which needs to be cleared.
		if cells[0].wide == .wide {
			if p_row := self.cursor.page_pin.up(1) {
				p_rac := p_row.row_and_cell()
				mut p_cells := p_row.cells(.all)
				p_cols := int(p_row.node.data.size.cols)
				p_cell := p_cells[p_cols - 1]
				if p_cell.wide == .spacer_head {
					mut p_page := &p_row.node.data
					mut p_row_data := p_rac.row
					mut last := unsafe { p_cells[p_cols - 1..p_cols] }
					self.clear_cells(mut p_page, mut p_row_data, mut last)
				}
			}
		}
	}

	// If x is 0 then we're done.
	if x == 0 {
		return
	}

	// [ ... X|Y ... ]
	//        ^ Boundary between two cells in the middle of the row.
	{
		assert x > 0
		assert x < cols

		mut cells := self.cursor.page_pin.cells(.all)

		left := cells[x - 1]
		match left.wide {
			// There should not be spacer heads in the middle of the row.
			.spacer_head {
				panic('spacer head in the middle of a row')
			}
			// We don't need to do anything for narrow cells or spacer tails.
			.narrow, .spacer_tail {}
			// A wide char would be split, so must be cleared.
			.wide {
				mut pair := unsafe { cells[int(x) - 1..int(x) + 1] }
				self.clear_cells(mut page, mut self.cursor.page_row, mut pair)
			}
		}
	}
}

// Returns the blank cell to use when doing terminal operations that
// require preserving the bg color.
pub fn (self &Screen) blank_cell() CellData {
	if self.cursor.style_id == default_style_id {
		return CellData{}
	}
	return self.cursor.style.bg_cell() or { CellData{} }
}

// Resize the screen. The rows or cols can be bigger or smaller.
//
// If this returns an error, the screen is left in a likely garbage state.
// It is very hard to undo this operation without blowing up our memory
// usage. The only way to recover is to reset the screen. The only way
// this really fails is if page allocation is required and fails, which
// probably means the system is in trouble anyways. I'd like to improve this
// in the future but it is not a priority particularly because this scenario
// (resize) is difficult.
pub fn (mut self Screen) resize(opts ScreenResize) ! {
	defer { self.assert_integrity() }

	// No matter what we mark our image state as dirty
	self.kitty_images.dirty = true

	// Release the cursor style while resizing just
	// in case the cursor ends up on a different page.
	cursor_style := self.cursor.style
	self.cursor.style = CellStyle{}
	self.manual_style_update() or { panic('releasing the cursor style cannot fail') }
	defer {
		// Restore the cursor style.
		self.cursor.style = cursor_style
		self.manual_style_update() or {
			// This failure should not happen because manualStyleUpdate
			// handles page splitting, overflow, and more. This should only
			// happen if we're out of RAM. In this case, we'll just degrade
			// gracefully back to the default style.
			// log.err: failed to update style on cursor reload
			self.cursor.style = CellStyle{}
			self.cursor.style_id = 0
		}
	}

	// If we have a hyperlink, release it from the old page
	// and then we need to re-add it to the new page. This needs
	// to happen because resize below typically reallocates a
	// new page so the old hyperlink is invalid.
	hyperlink_ := self.cursor.hyperlink_state
	if self.cursor.hyperlink_id != 0 {
		// Note we do NOT use endHyperlink because we want to keep
		// our allocated self.cursor.hyperlink valid.
		mut page := &self.cursor.page_pin.node.data
		page.hyperlink_set.release(HyperlinkId(self.cursor.hyperlink_id))
		self.cursor.hyperlink_id = 0
		self.cursor.hyperlink_state = none
	}

	// We need to insert a tracked pin for our saved cursor so we can
	// modify its X/Y for reflow.
	mut saved_cursor_pin := &Pin(unsafe { nil })
	if sc := self.saved_cursor {
		if pin := self.pages.pin(Point.new(.active, Coordinate{
			x: u16(sc.x)
			y: sc.y
		}))
		{
			saved_cursor_pin = self.pages.track_pin(pin)!
		}
	}
	defer {
		if !isnil(saved_cursor_pin) {
			self.pages.untrack_pin(saved_cursor_pin)
		}
	}

	// Perform the resize operation.
	self.pages.resize(PageResizeOpts{
		rows:   u16(opts.rows)
		cols:   u16(opts.cols)
		reflow: opts.reflow
		cursor: PageResizeCursor{
			x: u16(self.cursor.x)
			y: u16(self.cursor.y)
			pin: self.cursor.page_pin
		}
	})!

	// If we have no scrollback and we shrunk our rows, we must explicitly
	// erase our history. This is because PageList always keeps at least
	// a page size of history.
	if self.no_scrollback {
		self.erase_history()
	} else {
		// The resize can move the cursor and invalidate its caches.
		self.cursor_reload()
	}

	// A cursor left in the middle of a row by reflow can advance normally.
	if self.cursor.pending_wrap && self.cursor.x != opts.cols - 1 {
		self.cursor.pending_wrap = false
		self.cursor_right(1)
	}

	// Clear the prompt on the resized grid while the cursor style is still
	// reset. The cursor's semantic content also covers unmarked continuations.
	if opts.prompt_redraw != .redraw_false && self.cursor.semantic_content != .output {
		self.resize_clear_prompt(opts.prompt_redraw)
	}

	// If we reflowed a saved cursor, update it.
	if !isnil(saved_cursor_pin) {
		// This should never fail because a non-null saved_cursor_pin
		// implies a non-null saved_cursor.
		mut sc := self.saved_cursor or { panic('saved cursor pin without a saved cursor') }
		if pt := self.pages.point_from_pin(.active, *saved_cursor_pin) {
			sc.x = u32(pt.coord().x)
			sc.y = pt.coord().y

			// If we had pending wrap set and we're no longer at the end of
			// the line, we unset the pending wrap and move the cursor to
			// reflect the correct next position.
			if sc.pending_wrap && sc.x != opts.cols - 1 {
				sc.pending_wrap = false
				sc.x += 1
			}
		} else {
			// I think this can happen if the screen is resized to be
			// less rows or less cols and our saved cursor moves outside
			// the active area. In this case, there isn't anything really
			// reasonable we can do so we just move the cursor to the
			// top-left. It may be reasonable to also move the cursor to
			// match the primary cursor. Any behavior is fine since this is
			// totally unspecified.
			sc.x = 0
			sc.y = 0
			sc.pending_wrap = false
		}
		self.saved_cursor = sc
	}

	// Fix up our hyperlink if we had one.
	if link := hyperlink_ {
		self.start_hyperlink(link.uri, match link.id {
			HyperlinkExplicitId { ?string(link.id.value) }
			HyperlinkImplicitId { ?string(none) }
		}) or {
			// This shouldn't happen because startHyperlink should handle
			// resizing. This only happens if we're truly out of RAM. Degrade
			// to forgetting the hyperlink.
			// log.err: failed to update hyperlink on resize
		}
	}
}

// The prompt-clearing block of Screen.resize. V has no labeled blocks, so
// the `break :prompt` exit becomes a return from this helper.
fn (mut self Screen) resize_clear_prompt(redraw osc.Redraw) {
	match redraw {
		.redraw_false {
			panic('prompt redraw is disabled')
		}
		// For `.last`, only clear the current line where the cursor is.
		// For `.true`, clear all prompt lines starting from the beginning.
		.last {
			mut page := &self.cursor.page_pin.node.data
			mut row := self.cursor.page_row
			mut cells := page.get_cells(row)
			self.clear_cells(mut page, mut row, mut cells)
		}
		.redraw_true {
			mut prompt_it := self.cursor.page_pin.prompt_iterator(.left_up, none)
			start := prompt_it.next() or {
				// This should never happen because promptIterator should always
				// find a prompt if we already verified our row is some kind of
				// prompt.
				// log.warn: cursor on prompt line but promptIterator found no prompt
				return
			}

			// Clear cells from our start down. We replace it with spaces,
			// and do not physically erase the rows (eraseRows) because the
			// shell is going to expect this space to be available.
			mut it := start.row_iterator(.right_down, none)
			for {
				pin := it.next() or { break }
				mut page := &pin.node.data
				mut row := pin.row_and_cell().row
				mut cells := page.get_cells(row)
				self.clear_cells(mut page, mut row, mut cells)
			}
		}
	}
}

// Set a style attribute for the current cursor.
//
// If the style can't be set due to any internal errors (memory-related),
// then this will revert back to the existing style and return an error.
pub fn (mut self Screen) set_attribute(attr SgrAttribute) ! {
	// If we fail to set our style for any reason, we should revert
	// back to the old style. If we fail to do that, we revert back to
	// the default style.
	old_style := self.cursor.style

	match attr {
		SgrUnset {
			self.cursor.style = CellStyle{}
		}
		SgrBold {
			self.cursor.style.flags.set_bold(true)
		}
		SgrResetBold {
			// Bold and faint share the same SGR code for this
			self.cursor.style.flags.set_bold(false)
			self.cursor.style.flags.set_faint(false)
		}
		SgrItalic {
			self.cursor.style.flags.set_italic(true)
		}
		SgrResetItalic {
			self.cursor.style.flags.set_italic(false)
		}
		SgrFaint {
			self.cursor.style.flags.set_faint(true)
		}
		SgrUnderline {
			self.cursor.style.flags.set_underline(attr.style)
		}
		SgrUnderlineColor {
			self.cursor.style.underline_color = StyleColorRgb{ rgb: attr.rgb }
		}
		SgrUnderlineColor256 {
			self.cursor.style.underline_color = StyleColorPalette{ index: attr.idx }
		}
		SgrResetUnderlineColor {
			self.cursor.style.underline_color = StyleColorNone{}
		}
		SgrOverline {
			self.cursor.style.flags.set_overline(true)
		}
		SgrResetOverline {
			self.cursor.style.flags.set_overline(false)
		}
		SgrBlink {
			self.cursor.style.flags.set_blink(true)
		}
		SgrResetBlink {
			self.cursor.style.flags.set_blink(false)
		}
		SgrInverse {
			self.cursor.style.flags.set_inverse(true)
		}
		SgrResetInverse {
			self.cursor.style.flags.set_inverse(false)
		}
		SgrInvisible {
			self.cursor.style.flags.set_invisible(true)
		}
		SgrResetInvisible {
			self.cursor.style.flags.set_invisible(false)
		}
		SgrStrikethrough {
			self.cursor.style.flags.set_strikethrough(true)
		}
		SgrResetStrikethrough {
			self.cursor.style.flags.set_strikethrough(false)
		}
		SgrDirectColorFg {
			self.cursor.style.fg_color = StyleColorRgb{ rgb: attr.rgb }
		}
		SgrDirectColorBg {
			self.cursor.style.bg_color = StyleColorRgb{ rgb: attr.rgb }
		}
		SgrFg8 {
			self.cursor.style.fg_color = StyleColorPalette{ index: u8(attr.name) }
		}
		SgrBg8 {
			self.cursor.style.bg_color = StyleColorPalette{ index: u8(attr.name) }
		}
		SgrResetFg {
			self.cursor.style.fg_color = StyleColorNone{}
		}
		SgrResetBg {
			self.cursor.style.bg_color = StyleColorNone{}
		}
		SgrBrightFg8 {
			self.cursor.style.fg_color = StyleColorPalette{ index: u8(attr.name) }
		}
		SgrBrightBg8 {
			self.cursor.style.bg_color = StyleColorPalette{ index: u8(attr.name) }
		}
		SgrFg256 {
			self.cursor.style.fg_color = StyleColorPalette{ index: attr.idx }
		}
		SgrBg256 {
			self.cursor.style.bg_color = StyleColorPalette{ index: attr.idx }
		}
		SgrUnknown {
			return
		}
	}

	self.manual_style_update() or {
		self.cursor.style = old_style
		self.manual_style_update() or {
			// log.warn: setAttribute error restoring old style after failure
			self.cursor.style = CellStyle{}
			self.manual_style_update() or { panic('the default style cannot fail') }
		}
		return err
	}
}

// Call this whenever you manually change the cursor style.
//
// This function can NOT fail if the cursor style is changing to the
// default style.
//
// If this returns an error, the style change did not take effect and
// the cursor style is reverted back to the default. The only scenario
// this returns an error is if there is a physical memory allocation failure
// or if there is no possible way to increase style capacity to store
// the style.
//
// This function WILL split pages as necessary to accommodate the new style.
// So if OutOfSpace is returned, it means that even after splitting the page
// there was still no room for the new style.
pub fn (mut self Screen) manual_style_update() ! {
	defer { self.assert_integrity() }
	mut page := &self.cursor.page_pin.node.data

	// Release our previous style if it was not default.
	if self.cursor.style_id != default_style_id {
		page.styles.release(self.cursor.style_id)
	}

	// If our new style is the default, just reset to that
	if self.cursor.style.default() {
		self.cursor.style_id = default_style_id
		return
	}

	// Clear the cursor style ID to prevent weird things from happening
	// if the page capacity has to be adjusted which would end up calling
	// manualStyleUpdate again.
	//
	// This also ensures that if anything fails below, we fall back to
	// clearing our style.
	self.cursor.style_id = default_style_id

	// After setting the style, we need to update our style map.
	// Note that we COULD lazily do this in print. We should look into
	// if that makes a meaningful difference. Our priority is to keep print
	// fast because setting a ton of styles that do nothing is uncommon
	// and weird.
	id := page.styles.add(self.cursor.style) or {
		// Our style map is full or needs to be rehashed, so we need to
		// increase style capacity (or rehash).
		mut adjustment := ?IncreaseCapacity(none)
		if err.msg() != 'needs rehash' {
			adjustment = .styles
		}
		node := self.increase_capacity(self.cursor.page_pin.node, adjustment) or {
			if err.msg() != 'OutOfSpace' {
				return err
			}
			// Out of space, we need to split the page. Split wherever
			// is using less capacity and hope that works. If it doesn't
			// work, we tried.
			self.split_for_capacity(*self.cursor.page_pin)!
			self.cursor.page_pin.node
		}

		page = &node.data
		page.styles.add(self.cursor.style) or {
			if err.msg() == 'needs rehash' {
				// This should be impossible because we rehash above
				// and rehashing should never result in a duplicate. But
				// we don't want to simply hard crash so log it and
				// clear our style.
				// log.err: style rehash resulted in needs rehash
				return
			}
			// This shouldn't happen because increaseCapacity is
			// guaranteed to increase our capacity by at least one and
			// we only need one space, but again, I don't want to crash
			// here so let's log loudly and reset.
			// log.err: style addition failed after capacity increase
			return error('OutOfMemory')
		}
	}

	self.cursor.style_id = id
}

// Split at the given pin so that the pinned row moves to the page
// with less used capacity after the split.
//
// The primary use case for this is to handle IncreaseCapacityError
// OutOfSpace conditions where we need to split the page in order
// to make room for more managed memory.
//
// If the caller cares about where the pin moves to, they should
// setup a tracked pin before calling this and then check that.
// In many calling cases, the input pin is tracked (e.g. the cursor
// pin).
//
// If this returns OOM then its a system OOM. If this returns OutOfSpace
// then it means the page can't be split further.
fn (mut self Screen) split_for_capacity(pin Pin) ! {
	// Get our capacities. We include our target row because its
	// capacity will be preserved.
	bytes_above := Page.layout(pin.node.data.exact_row_capacity(0, uint(pin.y) + 1)).total_size
	bytes_below := Page.layout(pin.node.data.exact_row_capacity(uint(pin.y), uint(pin.node.data.size.rows))).total_size

	// We need to track the old cursor pin because if our split
	// moves the cursor pin we need to update our accounting.
	old_cursor := *self.cursor.page_pin

	// If our bytes above are less than bytes below, we move the pin
	// to split down one since splitting includes the pinned row in
	// the new node.
	mut split_pin := pin
	if bytes_above < bytes_below {
		split_pin = pin.down(1) or { pin }
	}
	self.pages.split(split_pin)!

	// Cursor didn't change nodes, we're done.
	if voidptr(self.cursor.page_pin.node) == voidptr(old_cursor.node) {
		return
	}

	// Cursor changed, we need to restore the old pin then use
	// cursorChangePin to move to the new pin. The old node is guaranteed
	// to still exist, just not the row.
	//
	// Note that page_row and all that will be invalid, it points to the
	// new node, but at the time of writing this we don't need any of that
	// to be right in cursorChangePin.
	new_cursor := *self.cursor.page_pin
	unsafe {
		*self.cursor.page_pin = old_cursor
	}
	self.cursor_change_pin(new_cursor)
}

// Append a grapheme to the given cell within the current cursor row.
pub fn (mut self Screen) append_grapheme(cell &CellData, cp u32) ! {
	defer { self.cursor.page_pin.node.data.assert_integrity() }
	row_idx := self.cursor.page_pin.node.data.row_index(self.cursor.page_row)
	col_idx := cell_index(self.cursor.page_row, cell)
	self.cursor.page_pin.node.data.append_grapheme(row_idx, col_idx, cp) or {
		// We need to determine the actual cell index of the cell so
		// that after we adjust the capacity we can reload the cell.
		cell_idx := col_idx

		// Adjust our capacity. This will update our cursor page pin and
		// force us to reload.
		_ = self.increase_capacity(self.cursor.page_pin.node, .grapheme_bytes)!

		// The cell pointer is now invalid, so we need to get it from
		// the reloaded cursor pointers.
		reloaded_cell := if cell_idx == uint(self.cursor.x) {
			self.cursor.page_cell
		} else if cell_idx < uint(self.cursor.x) {
			self.cursor_cell_left(self.cursor.x - u32(cell_idx))
		} else {
			self.cursor_cell_right(u32(cell_idx) - self.cursor.x)
		}

		reloaded_row := self.cursor.page_pin.node.data.row_index(self.cursor.page_row)
		self.cursor.page_pin.node.data.append_grapheme(reloaded_row, cell_index(self.cursor.page_row,
			reloaded_cell), cp) or {
			// This should never happen because we just increased capacity.
			// Log loudly but still return an error so we don't just
			// crash.
			// log.err: grapheme append failed after capacity increase
			return err
		}
	}
}

// Start the hyperlink state. Future cells will be marked as hyperlinks with
// this state. Note that various terminal operations may clear the hyperlink
// state, such as switching screens (alt screen).
pub fn (mut self Screen) start_hyperlink(uri string, id_ ?string) ! {
	// Create our pending entry.
	mut implicit := false
	link := Hyperlink{
		uri: uri
		id:  if id := id_ {
			HyperlinkIdKind(HyperlinkExplicitId{
				value: id
			})
		} else {
			implicit = true
			offset := self.cursor.hyperlink_implicit_id
			self.cursor.hyperlink_implicit_id += 1
			HyperlinkIdKind(HyperlinkImplicitId{
				offset: offset
			})
		}
	}

	// Loop until we have enough page memory to add the hyperlink
	for {
		self.start_hyperlink_once(link) or {
			match err.msg() {
				// strings table is out of memory, adjust it up
				'strings out of memory' {
					self.increase_capacity(self.cursor.page_pin.node, .string_bytes) or {
						if implicit {
							self.cursor.hyperlink_implicit_id -= 1
						}
						return err
					}
				}
				// hyperlink set is out of memory, adjust it up
				'set out of memory' {
					self.increase_capacity(self.cursor.page_pin.node, .hyperlink_bytes) or {
						if implicit {
							self.cursor.hyperlink_implicit_id -= 1
						}
						return err
					}
				}
				// hyperlink set is too full, rehash it
				'set needs rehash' {
					self.increase_capacity(self.cursor.page_pin.node, none) or {
						if implicit {
							self.cursor.hyperlink_implicit_id -= 1
						}
						return err
					}
				}
				// An actual self.alloc OOM is a fatal error.
				else {
					if implicit {
						self.cursor.hyperlink_implicit_id -= 1
					}
					return err
				}
			}

			self.assert_integrity()
			continue
		}
		return
	}
}

// This is like startHyperlink but if we have to adjust page capacities
// this returns error.PageAdjusted. This is useful so that we unwind
// all the previous state and try again.
fn (mut self Screen) start_hyperlink_once(source Hyperlink) ! {
	// End any prior hyperlink
	self.end_hyperlink()

	// Allocate our new Hyperlink entry in non-page memory. This
	// lets us quickly get access to URI, ID.
	link := source.dupe()

	// Insert the hyperlink into page memory
	mut page := &self.cursor.page_pin.node.data
	id := page.insert_hyperlink(link)!

	// Save it all
	self.cursor.hyperlink_state = link
	self.cursor.hyperlink_id = id
}

// End the hyperlink state so that future cells aren't part of the
// current hyperlink (if any). This is safe to call multiple times.
pub fn (mut self Screen) end_hyperlink() {
	// If we have no hyperlink state then do nothing
	if self.cursor.hyperlink_id == 0 {
		assert self.cursor.hyperlink_state == none
		return
	}

	// Release the old hyperlink state. If there are cells using the
	// hyperlink this will work because the creation creates a reference
	// and all additional cells create a new reference. This release will
	// just release our initial reference.
	//
	// If the ref count reaches zero the set will not delete the item
	// immediately; it is kept around in case it is used again (this is
	// how RefCountedSet works). This causes some memory fragmentation but
	// is fine because if it is ever pruned the context deleted callback
	// will be called.
	mut page := &self.cursor.page_pin.node.data
	page.hyperlink_set.release(HyperlinkId(self.cursor.hyperlink_id))
	self.cursor.hyperlink_id = 0
	self.cursor.hyperlink_state = none
}

// Set the current hyperlink state on the current cell.
pub fn (mut self Screen) cursor_set_hyperlink() ! {
	assert self.cursor.hyperlink_id != 0

	mut page := &self.cursor.page_pin.node.data
	row_idx := page.row_index(self.cursor.page_row)
	col_idx := cell_index(self.cursor.page_row, self.cursor.page_cell)
	page.set_hyperlink(row_idx, col_idx, HyperlinkId(self.cursor.hyperlink_id)) or {
		if err.msg() != 'HyperlinkMapOutOfMemory' {
			return err
		}
		// hyperlink_map is out of space, realloc the page to be larger

		// Attempt to allocate the space that would be required to
		// insert a new copy of the cursor hyperlink uri in to the
		// string alloc, since right now increaseCapacity always just
		// adds an extra copy even if one already exists in the page.
		// If this alloc fails then we know we also need to grow our
		// string bytes.
		//
		// FIXME: increaseCapacity should not do this.
		for {
			link := self.cursor.hyperlink_state or { break }
			if page.hyperlink_set.can_allocate_string_bytes(uint(link.uri.len)) {
				break
			}

			// We didn't have enough room, let's increase string bytes
			new_node := self.increase_capacity(self.cursor.page_pin.node, .string_bytes)!
			assert voidptr(new_node) == voidptr(self.cursor.page_pin.node)
			page = &new_node.data
		}

		_ = self.increase_capacity(self.cursor.page_pin.node, .hyperlink_bytes)!

		// Retry
		//
		// We check that the cursor hyperlink hasn't been destroyed
		// by the capacity adjustment first though- since despite the
		// terrible code above, that can still apparently happen ._.
		if self.cursor.hyperlink_id > 0 {
			return self.cursor_set_hyperlink()
		}
		return
	}

	// Success, increase the refcount for the hyperlink.
	page.hyperlink_set.use_link(HyperlinkId(self.cursor.hyperlink_id))
}

pub enum SemanticInputClear as u8 {
	clear_explicit
	clear_eol
}

pub struct CursorSemanticPrompt {
pub:
	kind PromptKind
}

pub struct CursorSemanticOutput {}

pub struct CursorSemanticInput {
pub:
	clear SemanticInputClear
}

pub type CursorSemanticContent = CursorSemanticInput | CursorSemanticOutput | CursorSemanticPrompt

// Modify the semantic content type of the cursor. This should
// be preferred over setting it manually since it handles all the
// proper accounting.
pub fn (mut self Screen) cursor_set_semantic_content(t CursorSemanticContent) {
	match t {
		CursorSemanticOutput {
			self.cursor.semantic_content = .output
			self.cursor.semantic_content_clear_eol = false
		}
		CursorSemanticInput {
			self.cursor.semantic_content = .input
			self.cursor.semantic_content_clear_eol = match t.clear {
				.clear_explicit { false }
				.clear_eol { true }
			}
		}
		CursorSemanticPrompt {
			self.semantic_prompt.seen = true
			self.cursor.semantic_content = .prompt
			self.cursor.semantic_content_clear_eol = false
			self.cursor.page_row.header.semantic_prompt = match t.kind {
				.initial, .right { SemanticPromptType.prompt }
				.continuation, .secondary { SemanticPromptType.prompt_continuation }
			}
		}
	}
}

// Set the selection to the given selection. If this is a tracked selection
// then the screen will take ownership of the selection. If this is untracked
// then the screen will convert it to tracked internally. This will automatically
// untrack the prior selection (if any).
//
// Set the selection to null to clear any previous selection.
//
// This is always recommended over setting `selection` directly. Beyond
// managing memory for you, it also performs safety checks that the selection
// is always tracked.
pub fn (mut self Screen) select(sel_ ?Selection) ! {
	sel := sel_ or {
		self.clear_selection()
		return
	}

	// If this selection is untracked then we track it.
	tracked_sel := if sel.tracked() { sel } else { sel.track(mut self)! }

	// Untrack prior selection
	if old := self.selection {
		old.deinit(mut self)
	}
	self.selection = tracked_sel
	self.dirty.set_selection(true)
}

// Same as select(null) but can't fail.
pub fn (mut self Screen) clear_selection() {
	if sel := self.selection {
		sel.deinit(mut self)
		self.dirty.set_selection(true)
	}
	self.selection = none
}

// Returns the raw text associated with a selection. This will unwrap
// soft-wrapped edges. The returned slice is owned by the caller and allocated
// using alloc, not the allocator associated with the screen (unless they match).
//
// For more flexibility, use a ScreenFormatter directly.
pub fn (mut self Screen) selection_string(opts SelectionString) !string {
	// Create a formatter and use that to emit our text.
	mut formatter := ScreenFormatter.init(self, FormatOptions{
		emit:   .plain
		unwrap: true
		trim:   opts.trim
	})
	formatter.content = ScreenContentSelection{
		sel: opts.sel
	}

	// If we have a string map, we need to set that up.
	mut pins := PinMap{}
	if opts.map != unsafe { nil } {
		formatter.pin_map = &pins
	}

	// Emit.
	text := formatter.format()

	// Build our final text and if we have a string map set that up.
	if opts.map != unsafe { nil } {
		// Match Ghostty's fallible map-pin ownership boundary. V's GC-backed
		// array transfer itself cannot report allocation failure, so this typed
		// test checkpoint represents that source error path.
		map_string := text.clone()
		mut tw := selection_string_tripwire()
		tw.check(.copy_map)!
		mut map_out := opts.map
		unsafe {
			*map_out = StringMap{
				string: map_string
				map:    pins.pins
			}
		}
	}

	return text
}

// Select the line under the given point. This will select across soft-wrapped
// lines and will omit the leading and trailing whitespace. If the point is
// over whitespace but the line has non-whitespace characters elsewhere, the
// line will be selected.
pub fn (self &Screen) select_line(opts SelectLine) ?Selection {
	// Get the current point semantic prompt state since that determines
	// boundary conditions too. This makes it so that line selection can
	// only happen within the same prompt state. For example, if you triple
	// click output, but the shell uses spaces to soft-wrap to the prompt
	// then the selection will stop prior to the prompt. See issue #1329.
	mut semantic_prompt_state := ?SemanticContent(none)
	if opts.semantic_prompt_boundary {
		rac := opts.pin.row_and_cell()
		semantic_prompt_state = rac.cell.semantic_content
	}

	// The real start of the row is the first row in the soft-wrap.
	start_pin := select_line_start_pin(opts, semantic_prompt_state)

	// The real end of the row is the final row in the soft-wrap.
	end_pin := select_line_end_pin(opts, semantic_prompt_state)?

	// Go forward from the start to find the first non-whitespace character.
	start := if whitespace := opts.whitespace {
		first_non_whitespace(start_pin, .right_down, end_pin, whitespace)?
	} else {
		start_pin
	}

	// Go backward from the end to find the first non-whitespace character.
	end := if whitespace := opts.whitespace {
		first_non_whitespace(end_pin, .left_up, start_pin, whitespace)?
	} else {
		end_pin
	}

	return Selection.init(start, end, false)
}

// The `start_pin` block of selectLine.
fn select_line_start_pin(opts SelectLine, semantic_prompt_state ?SemanticContent) Pin {
	mut it := opts.pin.row_iterator(.left_up, none)
	mut it_prev := it.next() or { panic('row iterator yields its own row') } // skip self

	// First, check the current row for semantic boundaries before the clicked position.
	if v := semantic_prompt_state {
		row := it_prev.row_and_cell().row
		cells := it_prev.node.data.get_cells(row)
		// Scan backwards from clicked position to find where our content starts
		for i in 0 .. int(opts.pin.x) + 1 {
			x_rev := int(opts.pin.x) - i
			if cells[x_rev].semantic_content != v {
				mut copy := it_prev
				copy.x = u16(x_rev + 1)
				return copy
			}
		}

		// No boundary found before clicked position on current row.
		// If row doesn't wrap from above, start is at column 0.
		// Otherwise, continue checking previous rows.
	}

	for {
		p := it.next() or { break }
		row := p.row_and_cell().row

		if !row.header.wrap {
			mut copy := it_prev
			copy.x = 0
			return copy
		}

		if v := semantic_prompt_state {
			// We need to check every cell in this row in reverse
			// order since we're going up and back.
			cells := p.node.data.get_cells(row)
			for x in 0 .. cells.len {
				x_rev := cells.len - 1 - x
				cell := cells[x_rev]
				if cell.semantic_content != v {
					return it_prev
				}
				it_prev = p
				it_prev.x = u16(x_rev)
			}

			continue
		}

		it_prev = p
	}

	mut copy := it_prev
	copy.x = 0
	return copy
}

// The `end_pin` block of selectLine.
fn select_line_end_pin(opts SelectLine, semantic_prompt_state ?SemanticContent) ?Pin {
	mut it := opts.pin.row_iterator(.right_down, none)
	for {
		p := it.next() or { break }
		row := p.row_and_cell().row

		if v := semantic_prompt_state {
			// We need to check every cell in this row
			cells := p.node.data.get_cells(row)

			// If this is our pin row we can start from our x because
			// the start_pin logic already found the real start.
			start_offset := if voidptr(p.node) == voidptr(opts.pin.node) && p.y == opts.pin.y {
				int(opts.pin.x)
			} else {
				0
			}

			// Handle the zero case specially because if the first
			// col doesn't match then we end at the end of the prior
			// row. But if this is the first row, we can't go back,
			// so we scan forward to find where our content ends.
			if start_offset == 0 && cells[0].semantic_content != v {
				mut prev := p.up(1) or { panic('selected row has no previous row') }
				prev.x = p.node.data.size.cols - 1
				return prev
			}

			// For every other case, we end at the prior cell.
			for x in start_offset .. cells.len {
				if cells[x].semantic_content != v {
					mut copy := p
					copy.x = u16(x - 1)
					return copy
				}
			}
		}

		if !row.header.wrap {
			mut copy := p
			copy.x = p.node.data.size.cols - 1
			return copy
		}
	}

	return none
}

// Iterate cells from `from` towards `limit` and return the first one whose
// text is not in `whitespace`. Shared by selectLine, selectAll, and friends.
fn first_non_whitespace(from Pin, direction IterDirection, limit ?Pin, whitespace []u32) ?Pin {
	mut it := from.cell_iterator(direction, limit)
	for {
		p := it.next() or { break }
		cell := p.row_and_cell().cell
		if !cell.has_text() {
			continue
		}

		// Non-empty means we found it.
		this_whitespace := cell.codepoint in whitespace
		if this_whitespace {
			continue
		}

		return p
	}

	return none
}

// Return the selection for all contents on the screen. Surrounding
// whitespace is omitted. If there is no selection, this returns null.
pub fn (mut self Screen) select_all() ?Selection {
	whitespace := [u32(0), u32(` `), u32(`\t`)]

	start := first_non_whitespace_in(self.pages.cell_iterator(.right_down, Point.new(.screen,
		Coordinate{}), none), whitespace)?

	end := first_non_whitespace_in(self.pages.cell_iterator(.left_up, Point.new(.screen,
		Coordinate{}), none), whitespace)?

	return Selection.init(start, end, false)
}

fn first_non_whitespace_in(iterator CellIterator, whitespace []u32) ?Pin {
	mut it := iterator
	for {
		p := it.next() or { break }
		cell := p.row_and_cell().cell
		if !cell.has_text() {
			continue
		}

		// Non-empty means we found it.
		this_whitespace := cell.codepoint in whitespace
		if this_whitespace {
			continue
		}

		return p
	}

	return none
}

// Select the nearest word to start point that is between start_pt and
// end_pt (inclusive). Because it selects "nearest" to start point, start
// point can be before or after end point.
//
// The boundary_codepoints parameter should be a slice of u21 codepoints that
// mark word boundaries, passed through to selectWord.
//
// TODO: test this
pub fn (mut self Screen) select_word_between(start Pin, end Pin, boundary_codepoints []u32) ?Selection {
	dir := if start.before(end) { IterDirection.right_down } else { IterDirection.left_up }
	mut it := start.cell_iterator(dir, end)
	for {
		pin := it.next() or { break }
		// Boundary conditions
		match dir {
			.right_down {
				if end.before(pin) {
					return none
				}
			}
			.left_up {
				if pin.before(end) {
					return none
				}
			}
		}

		// If we found a word, then return it
		if sel := self.select_word(pin, boundary_codepoints) {
			return sel
		}
	}

	return none
}

// Select the word under the given point. A word is any consecutive series
// of characters that are exclusively whitespace or exclusively non-whitespace.
// A selection can span multiple physical lines if they are soft-wrapped.
//
// This will return null if a selection is impossible. The only scenario
// this happens is if the point pt is outside of the written screen space.
//
// The boundary_codepoints parameter should be a slice of u21 codepoints that
// mark word boundaries. This is expected to be pre-parsed from the config.
pub fn (self &Screen) select_word(pin Pin, boundary_codepoints []u32) ?Selection {
	// If our cell is empty we can't select a word, because we can't select
	// areas where the screen is not yet written.
	start_cell := pin.row_and_cell().cell
	if !start_cell.has_text() {
		return none
	}

	// Determine if we are a boundary or not to determine what our boundary is.
	expect_boundary := start_cell.codepoint in boundary_codepoints

	// Go forwards to find our end boundary
	end := select_word_end(pin, boundary_codepoints, expect_boundary)

	// Go backwards to find our start boundary
	start := select_word_start(pin, boundary_codepoints, expect_boundary)

	return Selection.init(start, end, false)
}

// The `end` block of selectWord.
fn select_word_end(pin Pin, boundary_codepoints []u32, expect_boundary bool) Pin {
	mut it := pin.cell_iterator(.right_down, none)
	mut prev := it.next() or { panic('cell iterator yields its own cell') } // Consume one, our start
	for {
		p := it.next() or { break }
		rac := p.row_and_cell()
		cell := rac.cell

		// If we reached an empty cell its always a boundary
		if !cell.has_text() {
			return prev
		}

		// If we do not match our expected set, we hit a boundary
		this_boundary := cell.codepoint in boundary_codepoints
		if this_boundary != expect_boundary {
			return prev
		}

		// If we are going to the next row and it isn't wrapped, we
		// return the previous.
		if p.x == p.node.data.size.cols - 1 && !rac.row.header.wrap {
			return p
		}

		prev = p
	}

	return prev
}

// The `start` block of selectWord.
fn select_word_start(pin Pin, boundary_codepoints []u32, expect_boundary bool) Pin {
	mut it := pin.cell_iterator(.left_up, none)
	mut prev := it.next() or { panic('cell iterator yields its own cell') } // Consume one, our start
	for {
		p := it.next() or { break }
		rac := p.row_and_cell()
		cell := rac.cell

		// If we are going to the next row and it isn't wrapped, we
		// return the previous.
		if p.x == p.node.data.size.cols - 1 && !rac.row.header.wrap {
			return prev
		}

		// If we reached an empty cell its always a boundary
		if !cell.has_text() {
			return prev
		}

		// If we do not match our expected set, we hit a boundary
		this_boundary := cell.codepoint in boundary_codepoints
		if this_boundary != expect_boundary {
			return prev
		}

		prev = p
	}

	return prev
}

// Select the command output under the given point. The limits of the output
// are determined by semantic prompt information provided by shell integration.
// A selection can span multiple physical lines if they are soft-wrapped.
//
// This will return null if a selection is impossible:
//  - the point pt is outside of the written screen space.
//  - the point pt is on a prompt / input line.
pub fn (mut self Screen) select_output(pin Pin) ?Selection {
	// If our pin right now is not on output, then we return nothing.
	if pin.row_and_cell().cell.semantic_content != .output {
		return none
	}

	// Get the post prior prompt from this pin. This is the prompt whose
	// output we'll be capturing.
	mut prompt_it := pin.prompt_iterator(.left_up, none)

	// If we have a prompt above this point (including this point),
	// then thats the prompt we want to capture output from.
	prompt_pin := prompt_it.next() or {
		// If we don't have a prompt, then we assume that we're
		// capturing all the output up to the next prompt.
		prompt_it = pin.prompt_iterator(.right_down, none)
		next := prompt_it.next() or { return none }

		// We'll capture from the start of the screen to just above
		// the prompt and will trim the trailing whitespace.
		start_pin := self.pages.get_top_left(.screen)
		mut end_pin := next.up(1) or { return none }
		end_pin.x = end_pin.node.data.size.cols - 1
		mut cell_it := end_pin.cell_iterator(.left_up, start_pin)
		for {
			p := cell_it.next() or { break }
			cell := p.row_and_cell().cell
			end_pin = p
			if cell.has_text() {
				break
			}
		}

		return Selection.init(start_pin, end_pin, false)
	}

	// Grab our content
	mut hl := self.pages.highlight_semantic_content(prompt_pin, .output) or { return none }

	// Trim our trailing whitespace
	mut cell_it := hl.end.cell_iterator(.left_up, hl.start)
	for {
		p := cell_it.next() or { break }
		cell := p.row_and_cell().cell
		hl.end = p
		if cell.has_text() {
			break
		}
	}

	return Selection.init(hl.start, hl.end, false)
}

// Returns an iterator to move through the soft-wrapped lines starting
// from pin.
pub fn (self &Screen) line_iterator(start Pin) LineIterator {
	return LineIterator{
		screen:  unsafe { self }
		current: start
	}
}

// Determine the inputs necessary to move the cursor to the given
// click location within a prompt input area.
//
// If the cursor isn't currently at a prompt input location, this
// returns no movement.
//
// This feature depends on well-behaved OSC133 shell integration. Specifically,
// this only moves over designated input areas (OSC 133 B). It is assumed
// that the shell will only move the cursor to input cells, so prompt cells
// and other blank cells are ignored as part of the movement calculation.
pub fn (mut self Screen) prompt_click_move(click_pin Pin) PromptClickMove {
	// If we're not at an input cell with our cursor, no movement will
	// ever be possible.
	if self.cursor.semantic_content != .input && self.cursor.page_cell.semantic_content != .input {
		return prompt_click_move_zero
	}

	return match self.semantic_prompt.click {
		// None doesn't support movement and click_events must use a
		// different mechanism (SGR mouse events) that callers must handle.
		SemanticClickNone, SemanticClickEvents {
			prompt_click_move_zero
		}
		SemanticClickCl {
			match self.semantic_prompt.click.cl {
				// All of these currently use dumb line-based navigation.
				// But eventually we'll support more.
				.line, .multiple, .conservative_vertical, .smart_vertical {
					self.prompt_click_line(click_pin)
				}
			}
		}
	}
}

// Determine the inputs required to move from the cursor to the given
// click location. If the cursor isn't currently at a prompt input
// location, this will return zero.
//
// This currently only supports moving a single line.
fn (mut self Screen) prompt_click_line(click_pin Pin) PromptClickMove {
	// If our click pin is our cursor pin, no movement is needed.
	// Do this early so we can assume later that they are different.
	cursor_pin := *self.cursor.page_pin
	if cursor_pin.eql(click_pin) {
		return prompt_click_move_zero
	}

	// If our cursor is before our click, we're only emitting right inputs.
	if cursor_pin.before(click_pin) {
		mut count := uint(0)

		// We go row-by-row because soft-wrapped rows are still a single
		// line to a shell, so we can't just look at our page row.
		mut row_it := cursor_pin.row_iterator(.right_down, click_pin)
		row_loop: for {
			row_pin := row_it.next() or { break }
			rac := row_pin.row_and_cell()
			cells := row_pin.node.data.get_cells(rac.row)

			// Determine if this row is our cursor.
			is_cursor_row := voidptr(row_pin.node) == voidptr(cursor_pin.node)
				&& row_pin.y == cursor_pin.y

			// If this is not the cursor row, verify it's still part of the
			// continuation of our starting prompt.
			if !is_cursor_row && rac.row.header.semantic_prompt != .prompt_continuation {
				break
			}

			// Determine where our input starts.
			start_x := prompt_input_start_x(is_cursor_row, cursor_pin, cells)

			// Iterate over the input cells and assume arrow keys only
			// jump to input cells.
			for x in start_x .. cells.len {
				cell := cells[x]
				// Ignore non-input cells, but allow breaks. We assume
				// the shell will translate arrow keys to only input
				// areas.
				if cell.semantic_content != .input {
					continue
				}

				// Increment our input count
				count += 1

				// If this is our target, we're done.
				if voidptr(row_pin.node) == voidptr(click_pin.node) && row_pin.y == click_pin.y
					&& x == int(click_pin.x) {
					break row_loop
				}
			}

			// If this row isn't soft-wrapped, we need to break out
			// because line based moving only handles single lines.
			// We're done!
			if !rac.row.header.wrap {
				// If we never found our pin, that means we clicked further
				// right/beyond it. If we're already on a non-empty input cell
				// then we add one so we can move to the newest, empty cell
				// at the end, matching typical editor behavior.
				if self.cursor.page_cell.semantic_content == .input {
					count += 1
				}

				break
			}
		}

		return PromptClickMove{
			left:  0
			right: count
		}
	}

	// Otherwise, cursor is after click, so we're emitting left inputs.
	mut count := uint(0)

	// We go row-by-row because soft-wrapped rows are still a single
	// line to a shell, so we can't just look at our page row.
	mut row_it := cursor_pin.row_iterator(.left_up, click_pin)
	row_loop_left: for {
		row_pin := row_it.next() or { break }
		rac := row_pin.row_and_cell()
		cells := row_pin.node.data.get_cells(rac.row)

		// Determine the length of the cells we look at in this row.
		end_len := if voidptr(row_pin.node) == voidptr(cursor_pin.node) && row_pin.y == cursor_pin.y {
			// If this is our cursor row then we end before the cursor.
			int(cursor_pin.x)
		} else {
			// Otherwise, we end at the last cell in the row.
			cells.len
		}

		// Iterate backwards over the input cells.
		for rev_x in 0 .. end_len {
			x := end_len - 1 - rev_x
			cell := cells[x]

			// Ignore non-input cells.
			if cell.semantic_content != .input {
				continue
			}

			// Increment our input count
			count += 1

			// If this is our target, we're done.
			if voidptr(row_pin.node) == voidptr(click_pin.node) && row_pin.y == click_pin.y
				&& x == int(click_pin.x) {
				break row_loop_left
			}
		}

		// If this row is not a wrap continuation, then break out
		if !rac.row.header.wrap_continuation {
			break
		}
	}

	return PromptClickMove{
		left:  count
		right: 0
	}
}

// The `start_x` block of promptClickLine.
fn prompt_input_start_x(is_cursor_row bool, cursor_pin Pin, cells []CellData) int {
	// If this is our cursor row then we start after the cursor.
	if is_cursor_row {
		return int(cursor_pin.x) + 1
	}

	// Otherwise, we start at the first input cell, because
	// we expect the shell to properly translate arrows across
	// lines to the start of the input. Some shells indent
	// where input starts on subsequent lines so we must do
	// this.
	for x, cell in cells {
		if cell.semantic_content == .input {
			return x
		}
	}

	// We never found an input cell, so we need to move to the
	// next row.
	return cells.len
}

// Options for dumping an inclusive screen region.
pub struct DumpStringOptions {
pub:
	// The start and end points of the dump, both inclusive. The x will
	// be ignored and the full row will always be dumped.
	tl Pin
	br ?Pin
	// If true, this will unwrap soft-wrapped lines. If false, this will
	// dump the screen as it is visually seen in a rendered window.
	unwrap bool = true
}

// Dump the screen to a string.
pub fn (self &Screen) dump_string(opts DumpStringOptions) !string {
	// Create a formatter and use that to emit our text.
	mut formatter := ScreenFormatter.init(self, FormatOptions{
		emit:   .plain
		unwrap: opts.unwrap
		trim:   false
	})

	// Set up the selection based on the pins
	tl := opts.tl
	br := opts.br or {
		self.pages.get_bottom_right(.screen) or { return error('UnknownPoint') }
	}

	formatter.content = ScreenContentSelection{
		sel: Selection.init(tl, br, false) // not rectangle
	}

	// Emit
	return formatter.format()
}

// You should use dumpString, this is a restricted version mostly for
// legacy and convenience reasons for unit tests.
pub fn (self &Screen) dump_string_alloc(tl PointTag) !string {
	return self.dump_string(DumpStringOptions{
		tl:     self.pages.get_top_left(tl)
		br:     self.pages.get_bottom_right(tl) or { return error('UnknownPoint') }
		unwrap: false
	})
}

// You should use dumpString, this is a restricted version mostly for
// legacy and convenience reasons for unit tests.
pub fn (self &Screen) dump_string_alloc_unwrapped(tl PointTag) !string {
	return self.dump_string(DumpStringOptions{
		tl:     self.pages.get_top_left(tl)
		br:     self.pages.get_bottom_right(tl) or { return error('UnknownPoint') }
		unwrap: true
	})
}

// This is basically a really jank version of Terminal.printString. We
// have to reimplement it here because we want a way to print to the screen
// to test it but don't want all the features of Terminal.
pub fn (mut self Screen) test_write_string(text string) ! {
	for c in text.runes() {
		cp := u32(c)
		// Explicit newline forces a new row
		if cp == `\n` {
			self.cursor_down_or_scroll()!
			self.cursor_horizontal_absolute(0)
			self.cursor.pending_wrap = false
			if self.cursor.semantic_content_clear_eol {
				self.cursor_set_semantic_content(CursorSemanticOutput{})
			} else {
				match self.cursor.semantic_content {
					.output {}
					.prompt, .input {
						self.cursor.page_row.header.semantic_prompt = .prompt_continuation
					}
				}
			}
			continue
		}

		width := if cp <= 0xFF { 1 } else { int(unicode.get(cp).width()) }
		if width == 0 {
			mut cell := self.cursor_cell_left(1)
			match cell.wide {
				.narrow {}
				.wide {}
				.spacer_head {
					panic('spacer head before a zero-width codepoint')
				}
				.spacer_tail {
					cell = self.cursor_cell_left(2)
				}
			}

			row_idx := self.cursor.page_pin.node.data.row_index(self.cursor.page_row)
			self.cursor.page_pin.node.data.append_grapheme(row_idx, cell_index(self.cursor.page_row,
				cell), cp)!
			continue
		}

		if self.cursor.pending_wrap {
			assert self.cursor.x == u32(self.pages.cols) - 1
			self.cursor.pending_wrap = false
			self.cursor.page_row.header.wrap = true
			self.cursor_down_or_scroll()!
			self.cursor_horizontal_absolute(0)
			self.cursor.page_row.header.wrap_continuation = true
			match self.cursor.semantic_content {
				.output {}
				.input, .prompt {
					self.cursor.page_row.header.semantic_prompt = .prompt_continuation
				}
			}
		}

		assert width == 1 || width == 2
		match width {
			1 {
				unsafe {
					*self.cursor.page_cell = CellData{
						content_tag:      .codepoint
						codepoint:        cp
						style_id:         self.cursor.style_id
						is_protected:     self.cursor.is_protected
						semantic_content: self.cursor.semantic_content
					}
				}

				// If we have a ref-counted style, increase.
				if self.cursor.style_id != default_style_id {
					mut page := &self.cursor.page_pin.node.data
					page.styles.use_style(self.cursor.style_id)
					self.cursor.page_row.header.styled = true
				}

				// If we have a hyperlink, add it to the cell.
				if self.cursor.hyperlink_id > 0 {
					self.cursor_set_hyperlink()!
				}
			}
			2 {
				// Need a wide spacer head
				if self.cursor.x == u32(self.pages.cols) - 1 {
					unsafe {
						*self.cursor.page_cell = CellData{
							content_tag:      .codepoint
							codepoint:        0
							wide:             .spacer_head
							is_protected:     self.cursor.is_protected
							semantic_content: self.cursor.semantic_content
						}
					}

					// If we have a hyperlink, add it to the cell.
					if self.cursor.hyperlink_id > 0 {
						self.cursor_set_hyperlink()!
					}

					self.cursor.page_row.header.wrap = true
					self.cursor_down_or_scroll()!
					self.cursor_horizontal_absolute(0)
					self.cursor.page_row.header.wrap_continuation = true
				}

				// Write our wide char
				unsafe {
					*self.cursor.page_cell = CellData{
						content_tag:      .codepoint
						codepoint:        cp
						style_id:         self.cursor.style_id
						wide:             .wide
						is_protected:     self.cursor.is_protected
						semantic_content: self.cursor.semantic_content
					}
				}

				// If we have a hyperlink, add it to the cell.
				if self.cursor.hyperlink_id > 0 {
					self.cursor_set_hyperlink()!
				}

				// Write our tail
				self.cursor_right(1)
				unsafe {
					*self.cursor.page_cell = CellData{
						content_tag:      .codepoint
						codepoint:        0
						wide:             .spacer_tail
						is_protected:     self.cursor.is_protected
						semantic_content: self.cursor.semantic_content
					}
				}

				// If we have a hyperlink, add it to the cell.
				if self.cursor.hyperlink_id > 0 {
					self.cursor_set_hyperlink()!
				}

				// If we have a ref-counted style, increase twice.
				if self.cursor.style_id != default_style_id {
					mut page := &self.cursor.page_pin.node.data
					page.styles.use_style(self.cursor.style_id)
					page.styles.use_style(self.cursor.style_id)
					self.cursor.page_row.header.styled = true
				}
			}
			else {
				panic('unsupported codepoint width')
			}
		}

		if self.cursor.x + 1 < u32(self.pages.cols) {
			self.cursor_right(1)
		} else {
			self.cursor.pending_wrap = true
		}
	}
}
