module terminal

import buildcfg
import strings
import tripwire
import lib_allocator

// --- Original Ghostty Comments Start: src/terminal/PageList.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/terminal/PageList.zig
//
// Maintains a linked list of pages to make up a terminal screen
// and provides higher level operations on top of those pages to
// make it slightly easier to work with.
// The number of PageList.Nodes we preheat the pool with. A node is
// a very small struct so we can afford to preheat many, but the exact
// number is uncertain. Any number too large is wasting memory, any number
// too small will cause the pool to have to allocate more memory later.
// This should be set to some reasonable minimum that we expect a terminal
// window to scroll into quickly.
// The list of pages in the screen. These are expected to be in order
// where the first page is the topmost page (scrollback) and the last is
// the bottommost page (the current active page).
// A single node within the PageList linked list.
//
// This isn't pub because you can access the type via List.Node.
// The memory pool we get page nodes from.
// The standard page capacity that we use as a starting point for
// all pages. This is chosen as a sane default that fits most terminal
// usage to support using our pool.
// The byte size required for a standard page.
// The memory pool we use for page memory buffers. We use a separate pool
// so we can allocate these with a page allocator. We have to use a page
// allocator because we need memory that is zero-initialized and page-aligned.
// List of pins, known as "tracked" pins. These are pins that are kept
// up to date automatically through page-modifying operations.
// The pool of memory used for a pagelist. This can be shared between
// multiple pagelists but it is not threadsafe.
// The memory pool we get page nodes, pages from.
// The list of pages in the screen.
// A monotonically increasing serial number that is incremented each
// time a page is allocated or reused as new. The serial is assigned to
// the Node.
//
// The serial number can be used to detect whether the page is identical
// to the page that was originally referenced by a pointer. Since we reuse
// and pool memory, pointer stability is not guaranteed, but the serial
// will always be different for different allocations.
//
// Developer note: we never do overflow checking on this. If we created
// a new page every second it'd take 584 billion years to overflow. We're
// going to risk it.
// The lowest still valid serial number that could exist. This allows
// for quick comparisons to find invalid pages in references.
// Byte size of the total amount of allocated pages. Note this does
// not include the total allocated amount in the pool which may be more
// than this due to preheating.
// Maximum size of the page allocation in bytes. This only includes pages
// that are used ONLY for scrollback. If the active area is still partially
// in a page that also includes scrollback, then that page is not included.
// This is the minimum max size that we will respect due to the rows/cols
// of the PageList. We must always be able to fit at least the active area
// and at least two pages for our algorithms.
// The total number of rows represented by this PageList. This is used
// specifically for scrollbar information so we can have the total size.
// The list of tracked pins. These are kept up to date automatically.
// The top-left of certain parts of the screen that are frequently
// accessed so we don't have to traverse the linked list to find them.
//
// For other tags, don't need this:
//   - screen: pages.first
//   - history: active row minus one
//
// The pin used for when the viewport scrolls. This is always pre-allocated
// so that scrolling doesn't have a failable memory allocation. This should
// never be access directly; use `viewport`.
// The row offset from the top that the viewport pin is at. We
// store the offset from the top because it doesn't change while more
// data is printed to the terminal.
//
// This is null when it isn't calculated. It is calculated on demand
// when the viewportRowOffset function is called, because it is only
// required for certain operations such as rendering the scrollbar.
//
// In order to make this more efficient, in many places where the value
// would be invalidated, we update it in-place instead. This is key to
// keeping our performance decent in normal cases since recalculating
// this from scratch, depending on the size of the scrollback and position
// of the pin, can be very expensive.
//
// This is only valid if viewport is `pin`. Every other offset is
// self-evident or quick to calculate.
// The current desired screen dimensions. I say "desired" because individual
// pages may still be a different size and not yet reflowed since we lazily
// reflow text.
// If this is true then verifyIntegrity will do nothing. This is
// only present with runtime safety enabled.
// The viewport location.
// The viewport is pinned to the active area. By using a specific marker
// for this instead of tracking the row offset, we eliminate a number of
// memory writes making scrolling faster.
// The viewport is pinned to the top of the screen, or the farthest
// back in the scrollback history.
// The viewport is pinned to a tracked pin. The tracked pin is ALWAYS
// s.viewport_pin hence this has no value. We force that value to prevent
// allocations.
// Returns the minimum valid "max size" for a given number of rows and cols
// such that we can fit the active area AND at least two pages. Note we
// need the two pages for algorithms to work properly (such as grow) but
// we don't need to fit double the active area.
//
// This min size may not be totally correct in the case that a large
// number of other dimensions makes our row size in a page very small.
// But this gives us a nice fast heuristic for determining min/max size.
// Therefore, if the page size is violated you should always also verify
// that we have enough space for the active area.
// Invariant required to ensure our divCeil below cannot overflow.
// Get our capacity to fit our rows. If the cols are too big, it may
// force less rows than we want meaning we need more than one page to
// represent a viewport.
// Calculate the number of standard sized pages we need to represent
// an active area.
// Not possible:
// - initialCapacity guarantees at least 1 row
// - numerator/denominator can't overflow because of comptime check above
// We always need at least one page extra so that we
// can fit partial pages to spread our active area across two pages.
// Even for caps that can't fit all rows in a single page, we add one
// because the most extra space we need at any given time is only
// the partial amount of one page.
// log.debug("minMaxSize cols={} rows={} cap={} pages={}", .{
//     cols,
//     rows,
//     cap,
//     pages,
// });
// Calculates the initial capacity for a new page for a given column
// count. This will attempt to fit within std_size at all times so we
// can use our memory pool, but if cols is too big, this will return a
// larger capacity.
//
// The returned capacity is always guaranteed to layout properly (not
// overflow). We are able to support capacities up to the maximum int
// value of cols, so this will never overflow.
// This is an important invariant that ensures that this function
// can never return an error. We verify here that our standard capacity
// when increased to maximum possible columns can always support at
// least one row in memory.
//
// IF THIS EVER FAILS: We probably need to modify our logic below
// to reduce other elements of the capacity (styles, graphemes, etc.).
// But, instead, I recommend taking a step back and re-evaluating
// life choices.
// If we can adjust our standard capacity, we fit within the
// standard size and we're good!
// Ensure our error set doesn't change.
// This code path means that our standard capacity can't even
// accommodate our column count! The only solution is to increase
// our capacity and go non-standard.
// This is the page allocator we'll use for all our underlying
// VM page allocations.
// In tests we use our testing allocator so we can detect leaks.
// On non-macOS we use our standard Zig page allocator.
// On macOS we want to tag our memory so we can assign it to our
// core terminal usage.
// Initialize the page. The top of the first page in the list is always the
// top of the active area of the screen (important knowledge for quickly
// setting up cursors in Screen).
//
// max_size is the maximum number of bytes that will be allocated for
// pages. If this is smaller than the bytes required to show the viewport
// then max_size will be ignored and the viewport will be shown, but no
// scrollback will be created. max_size is always rounded down to the nearest
// terminal page size (not virtual memory page), otherwise we would always
// slightly exceed max_size in the limits.
//
// If max_size is null then there is no defined limit and the screen will
// grow forever. In reality, the limit is set to the byte limit that your
// computer can address in memory. If you somehow require more than that
// (due to disk paging) then please contribute that yourself and perhaps
// search deep within yourself to find out why you need that.
// The screen starts with a single page that is the entire viewport,
// and we'll split it thereafter if it gets too large and add more as
// necessary.
// Get our minimum max size, see doc comments for more details.
// We always track our viewport pin to ensure this is never an allocation
// Add pages as needed to create our initial viewport.
// Guaranteed by comptime checks in initialCapacity but
// redundant here for safety.
// If we have an error, we need to clean up our non-standard pages
// since they're not in the pool.
// In runtime safety modes we have to memset because the Zig allocator
// interface will always memset to 0xAA for undefined. In non-safe modes
// we use a page allocator and the OS guarantees zeroed memory.
// Initialize the first set of pages to contain our viewport so that
// the top of the first page is always the active area.
// Add the page to the list
// Increment our serial
// Assert that the PageList is in a valid state. This is a no-op in
// release builds.
// Pause or resume integrity checks. This is useful when you're doing
// a multi-step operation that temporarily leaves the PageList in an
// inconsistent state.
// Verify the integrity of the PageList. This is expensive and should
// only be called in debug/test builds.
// Our viewport pin should never be garbage
// Grab our total rows
// While doing this traversal, verify no node has a serial
// number lower than our min.
// Verify that our cached total_rows matches the actual row count
// Verify that all our tracked pins point to valid pages.
// Verify that our viewport pin row offset is correct.
// Ensure our viewport has enough rows.
// Deinit the pagelist. If you own the memory pool (used clonePool) then
// this will reset the pool and retain capacity.
// Verify integrity before cleanup
// Always deallocate our hashmap.
// Go through our linked list and deallocate all pages that are
// not standard size.
// Deallocate all the pages. We don't need to deallocate the list or
// nodes because they all reside in the pool.
// Reset the PageList back to an empty state. This is similar to
// deinit and reinit but it importantly preserves the pointer
// stability of tracked pins (they're moved to the top-left since
// all contents are cleared).
//
// This can't fail because we always retain at least enough allocated
// memory to fit the active area.
// We need enough pages/nodes to keep our active area. This should
// never fail since we by definition have allocated a page already
// that fits our size but I'm not confident to make that assertion.
// The number of pages we need is the number of rows in the active
// area divided by the row capacity of a page.
// Before resetting our pools we need to free any pages that
// are non-standard size since those were allocated outside
// the pool.
// Reset our pools to free as much memory as possible while retaining
// the capacity for at least the minimum number of pages we need.
// The return value is whether memory was reclaimed or not, but in
// either case the pool is left in a valid state.
// Our page pool relies on mmap to zero our page memory. Since we're
// retaining a certain amount of memory, it won't use mmap and won't
// be zeroed. This block zeroes out all the memory in the pool arena.
// Note: we only have to do this for the page pool because the
// nodes are always fully overwritten on each allocation.
// WARN: Since HeapAllocator's BufNode is not public API,
// we have to hardcode its layout here. We do a comptime assert
// on Zig version to verify we check it on every bump.
// The fully allocated buffer
// The buffer minus our header
// Initialize our pages. This should not be able to fail since
// we retained the capacity for the minimum number of pages we need.
// Our total rows always goes back to the default
// Update all our tracked pins to point to our first page top-left
// and mark them as garbage, because it got mangled in a way where
// semantically it really doesn't make sense.
// Our viewport pin is never garbage
// Move our viewport back to the active area since everything is gone.
// The top and bottom (inclusive) points of the region to clone.
// The x coordinate is ignored; the full row is always cloned.
// If this is non-null then cloning will attempt to remap the tracked
// pins into the new cloned area and will keep track of the old to
// new mapping in this map. If this is null, the cloned pagelist will
// not retain any previously tracked pins except those required for
// internal operations.
//
// Any pins not present in the map were not remapped.
// Clone this pagelist from the top to bottom (inclusive).
//
// The viewport is always moved to the active area.
//
// The cloned pagelist must contain at least enough rows for the active
// area. If the region specified has less rows than the active area then
// rows will be added to the bottom of the region to make up the difference.
// First, count our pages so our preheat is exactly what we need.
// Setup our pool
// Create our viewport. In a clone, the viewport always goes
// to the top.
// Our list of pages
// Copy our pages
// Clone the page. We have to use createPageExt here because
// we don't know if the source page has a standard size.
// Remap our tracked pins by changing the page and
// offsetting the Y position based on the chunk start.
// We're only interested in pins that were within the chunk.
// Initialize our viewport pin to point to the first cloned page
// so it points to valid memory.
// We always need to have enough rows for our viewport because this is
// a pagelist invariant that other code relies on.
// Clear the row. This is not very fast but in reality right
// now we rarely clone less than the active area and if we do
// the area is by definition very small.
// Update our total rows to be our row size.
// Resize options
// The new cols/cells of the screen.
// Whether to reflow the text. If this is false then the text will
// be truncated if the new size is smaller than the old size.
// Set this to the current cursor position in the active area. Some
// resize/reflow behavior depends on the cursor position.
// Resize
// TODO: docs
// Resize does not work with 0 values, this should be protected
// upstream
// Resizing (especially with reflow) can cause our row offset to
// become invalid. Rather than do something fancy like we do other
// places and try to update it in place, we just invalidate it because
// its too easy to get the logic wrong in here.
// Recalculate our minimum max size. This allows grow to work properly
// when increasing beyond our initial minimum max size or explicit max
// size to fit the active area.
// On reflow, the main thing that causes reflow is column changes. If
// only rows change, reflow is impossible. So we change our behavior based
// on the change of columns.
// We grow rows after cols so that we can do our unwrapping/reflow
// before we do a no-reflow grow.
// We first change our row count so that we have the proper amount
// we can use when shrinking our cols.
// Various resize operations can change our total row count such
// that our viewport pin is now in the active area and has insufficient
// space. We need to check for this case and fix it up.
// Resize the pagelist with reflow by adding or removing columns.
// Update our cols. We have to do this early because grow() that we
// may call below relies on this to calculate the proper page size.
// If we have a cursor position (x,y), then we try under any col resizing
// to keep the same number remaining active rows beneath it. This is a
// very special case if you can imagine clearing the screen (i.e.
// scrollClear), having an empty active area, and then resizing to less
// cols then we don't want the active area to "jump" to the bottom and
// pull down scrollback.
// We count how many wraps the cursor had before it to begin with
// so that we can offset any additional wraps to avoid pushing the
// original row contents in to the scrollback.
// Create the first node that contains our reflow.
// We verify all maxed out page layouts work.
// We're growing columns so we can only get less rows so use
// the lesser of our capacity and size so we minimize wasted
// rows.
// We need to grab our rowIterator now before we rewrite our
// linked list below.
// If an error occurs, we're in a pretty disastrous broken state,
// but we should still try to clean up our leaked memory. Free
// any of the remaining orphaned pages from before. If we reflowed
// successfully this will be null.
// Set our new page as the only page. This orphans the existing pages
// in the list, but that's fine since we're gonna delete them anyway.
// Reflow all our rows.
// Once we're done reflowing a page, destroy it immediately.
// This frees memory and makes it more likely in memory
// constrained environments that the next reflow will work.
// At the end of the reflow, setup our total row cache
// log.warn("total old={} new={}", .{ self.total_rows, reflow_cursor.total_rows });
// If our total rows is less than our active rows, we need to grow.
// This can happen if you're growing columns such that enough active
// rows unwrap that we no longer have enough.
// See preserved_cursor setup for why.
// We need to determine how many rows we wrapped from the original
// and subtract that from the remaining rows we expect because if
// we wrap down we don't want to push our original row contents into
// the scrollback.
// We use a cursor to track where we are in the src/dst. This is very
// similar to Screen.Cursor, so see that for docs on individual fields.
// We don't use a Screen because we don't need all the same data and we
// do our best to optimize having direct access to the page memory.
// This is the final row count of the reflowed pages.
// Initially whatever size our input node is.
// Reflow the provided row in to this cursor.
// Calculate the columns in this row. First up we trim non-semantic
// rightmost blanks.
// If the row has a semantic prompt then the blank row is meaningful
// so we just consider pretend the first cell of the row isn't empty.
// Handle tracked pin adjustments.
// If this pin is in the blanks on the right and past the end
// of the dst col width then we move it to the end of the dst
// col width instead.
// We increase our col len to at least include this pin.
// This ensures that blank rows with pins are processed,
// so that the pins can be properly remapped.
// Defer processing of blank rows so that blank rows
// at the end of the page list are never written.
// If this blank row was a wrap continuation somehow
// then we won't need to write it since it should be
// a part of the previously written row.
// Inherit increased styles or grapheme bytes from the src page
// we're reflowing from for new pages.
// We're already a non-standard page. We don't want to
// inherit a massive set of rows, so cap it at our std size.
// Our row isn't blank, write any new rows we deferred.
// Move any tracked pins from the source.
// Wrote the cell, move to the next.
// Wrote the cell but request to skip the next so skip it.
// This is used for things like spacers.
// Remap any tracked pins at the skipped position (x+1)
// since we won't process that cell in the loop.
// Didn't write the cell, repeat writing this same cell.
// System out of memory, we can't fix this.
// We reached the capacity of a single page and can't
// add any more of some type of managed memory. When this
// happens we split out the current row we're working on
// into a new page and continue from there.
// If we're already on the first-row, we can't split
// any further, so we just ignore bad cells and take
// corrupted (but valid) cell contents.
// Move our last row to a new page.
// Do NOT increment x so that we retry writing
// the same existing cell.
// If the source row isn't wrapped then we should scroll afterwards.
// Write a cell. On error, this will not unwrite the cell but
// the cell may be incomplete (but valid). For example, if the source
// cell is styled and we failed to allocate space for styles, the
// written cell may not be styled but it is valid.
//
// The key failure to recognize for callers is when we can't increase
// capacity in our destination page. In this case, the caller may want
// to split the page at this row, rewrite the row into a new page
// and continue from there.
//
// But this function guarantees the terminal/page will be in a
// coherent state even on error.
// Initialize self.page_cell with basic, unmanaged memory contents.
// This must not fail because we want to make sure we atomically
// setup our page cell to be valid.
// Copy cell contents.
// If there's a wide character in the last column of
// the reflowed page then we need to insert a spacer
// head and wrap before handling it.
// Move to the next row (this sets pending wrap
// which will cause us to wrap on the next
// iteration).
// Decrement the source position so that when we
// loop we'll process this source cell again,
// since we can't copy it into a spacer head.
// Edge case, when resizing to 1 column, wide
// characters are just destroyed and replaced
// with empty narrow cells.
// Skip spacer tail so it doesn't cause a wrap.
// Edge case, when resizing to 1 column, wide
// characters are just destroyed and replaced
// with empty narrow cells, so we should just
// discard any spacer tails.
// Spacer heads should be ignored. If we need a
// spacer head in our reflowed page, it is added
// when processing the wide cell it belongs to.
// These are guaranteed to have no style or grapheme
// data associated with them so we can fast path them.
// These will create issues by trying to clone managed memory that
// isn't set if the current dst row needs to be moved to a new page.
// They'll be fixed once we do properly copy the relevant memory.
// Copy Kitty virtual placeholder status
// std.log.warn("\nsrc_y={} src_x={} dst_y={} dst_x={} dst_cols={} cp={X} wide={} page_cell_wide={}", .{
//     src_y,
//     x,
//     self.y,
//     self.x,
//     self.page.size.cols,
//     cell.content.codepoint,
//     cell.wide,
//     self.page_cell.wide,
// });
// From this point on we're moving on to failable, managed memory.
// If we reach an error, we do the minimal cleanup necessary to
// not leave dangling memory but otherwise we gracefully degrade
// into some functional but not strictly correct cell.
// Copy grapheme data.
// Copy the graphemes
// If our page can't support an additional cell
// with graphemes then we increase capacity.
// Attempt to allocate the space that would be required
// for these graphemes, and if it's not available, then
// increase capacity. Keep trying until we succeed.
// Grow our capacity until we can fit the extra bytes.
// This shouldn't fail since we made sure we have space
// above. There is no reasonable behavior we can take here
// so we have a warn level log. This is ALMOST non-recoverable,
// though we choose to recover by corrupting the cell
// to a non-grapheme codepoint.
// Force a crash with safe builds.
// Unsafe builds we throw away grapheme data!
// Copy hyperlink data.
// If our page can't support an additional cell
// with a hyperlink then we increase capacity.
// Ensure that the string alloc has sufficient capacity
// to dupe the link (and the ID if it's not implicit).
// Keep trying until we have enough capacity.
// We have enough capacity, free the test alloc.
// Grow our capacity until we can fit the extra bytes.
// This shouldn't fail since we did a capacity
// check above.
// Force a crash with safe builds.
// Always free our original link in case the increaseCap
// call fails so we aren't leaking memory.
// If the add failed then either the set needs to grow
// or it needs to be rehashed. Either one of those can
// be accomplished by increasing capacity, either with
// no actual change or with an increased hyperlink cap.
// We need to recreate the link into the new page.
// This shouldn't fail since we did a capacity
// check above.
// Force a crash with safe builds.
// We assume this one will succeed. We dupe the link
// again, and don't have to worry about the other one
// because increasing the capacity naturally clears up
// any managed memory not associated with a cell yet.
// This shouldn't happen since we increased capacity
// above so we handle it like the other similar
// cases and log it, crash in safe builds, and
// remove the hyperlink in unsafe builds.
// Force a crash with safe builds.
// We expect this to succeed due to the hyperlinkCapacity
// check we did before. If it doesn't succeed let's
// log it, crash (in safe builds), and clear our state.
// Force a crash with safe builds.
// Unsafe builds we throw away hyperlink data!
// Copy style data.
// If the add failed then either the set needs to grow
// or it needs to be rehashed. Either one of those can
// be accomplished by increasing capacity, either with
// no actual change or with an increased style cap.
// We assume this one will succeed.
// Should not fail since we just modified capacity
// above. Log it, crash in safe builds, clear style
// in unsafe builds.
// Force a crash with safe builds.
// Create a new page in the provided list with the provided
// capacity then clone the row currently being worked on to
// it and delete it from the old page. Places cursor in the
// same position it was in in the old row in the new one.
//
// Asserts that the cursor is on the final row of the page.
//
// Expects that the provided capacity is sufficient to copy
// the row.
//
// If this is the only row in the page, the page is removed
// from the list after cloning the row.
// Our total row count never changes, because we're removing one
// row from the last page and moving it into a new page.
// We have no cleanup for our old state from here on out. No failures!
// Restore the x position of the cursor.
// Copy our old data. This should NOT fail because we have the
// capacity of the old page which already fits the data we requested.
// Move any tracked pins from that last row into this new node.
// p.x remains the same since we're copying the row as-is
// Clear the row from the old page and truncate it.
// If that was the last row in that page
// then we should remove it from the list.
// Increase the capacity of the current page.
// Pause integrity checks because the total row count won't
// be correct during a reflow.
// We must not fail after this, we've modified our self.node
// and we need to fix it up.
// True if this cursor is at the bottom of the page by capacity,
// i.e. we can't scroll anymore.
// Create a new row and move the cursor down.
//
// Asserts that the cursor is on the bottom row of the
// page and that there is capacity to add a new one.
// Scrolling requires that we're on the bottom of our page.
// We also assert that we have capacity because reflow always
// works within the capacity of the page.
// Increase our page size
// With the increased page size, safely move down a row.
// Create a new page in the provided list with the provided
// capacity and one row and move the cursor in to it at 0,0
// Remember our new row count so we can restore it
// after reinitializing our cursor on the new page.
// Performs `cursorScroll` or `cursorNewPage` as necessary
// depending on if the cursor is currently at the bottom.
// The functions below may overwrite self so we need to cache
// our total rows. We add one because no matter what when this
// returns we'll have one more row added.
// If the row is wrapped, all empty cells are meaningful.
// If the row has a semantic prompt then the blank row is meaningful
// so we always return all but one so that the row is drawn.
// We only set the new min_max_size if we're not reflowing. If we are
// reflowing, then resize handles this for us.
// Important! We have to do cols first because cols may cause us to
// destroy pages if we're increasing cols which will free up page_size
// so that when we call grow() in the row mods, we won't prune.
// Any column change without reflow should not result in row counts
// changing.
// Making our columns smaller. We always have space for this
// in existing pages so we need to go through the pages,
// resize the columns, and clear any cells that are beyond
// the new size.
// Update all our tracked pins. If they have an X
// beyond the edge, clamp it.
// Make our columns larger. This is a bit more complicated because
// pages may not have the capacity for this. If they don't have
// the capacity we need to allocate a new page and copy the data.
// See the comment in the while loop when setting self.cols
// We need to restore our old cols after we resize because
// we have an assertion on this and we want to be able to
// call this method multiple times.
// Making rows smaller, we simply change our rows value. Changing
// the row size doesn't affect anything else since max size and
// so on are all byte-based.
// If our rows are shrinking, we prefer to trim trailing
// blank lines from the active area instead of creating
// history if we can.
//
// This matches macOS Terminal.app behavior. I chose to match that
// behavior because it seemed fine in an ocean of differing behavior
// between terminal apps. I'm completely open to changing it as long
// as resize behavior isn't regressed in a user-hostile way.
// Account for our trimmed rows in the total row cache
// If we didn't trim enough, just modify our row count and this
// will create additional history.
// Making rows larger we adjust our row count, and then grow
// to the row count.
// If our rows increased and our cursor is NOT at the bottom,
// we want to try to preserve the y value of the old cursor.
// In other words, we don't want to "pull down" scrollback.
// This is purely a UX feature.
// Cursor is not at the bottom, so we just grow our
// rows and we're done. Cursor does NOT change for this
// since we're not pulling down scrollback.
// This must be set BEFORE any calls to grow() so that
// grow() doesn't prune pages that we need for the active
// area.
// Cursor is at the bottom or we don't care about cursors.
// In this case, if we have enough rows in our pages, we
// just update our rows and we're done. This effectively
// "pulls down" scrollback.
//
// If we don't have enough scrollback, we add the difference,
// to the active area.
// Make sure that the viewport pin isn't below the active
// area, since that will lead to all sorts of problems.
// We never have less rows than our active screen has.
// Update our col count
// Unlikely fast path: we have capacity in the page. This
// is only true if we resized to less cols earlier.
// Likely slow path: we don't have capacity, so we need
// to allocate a page, and copy the old data into it.
// Try to fit our new column size into our existing page capacity.
// If that doesn't work then use a non-standard page with the
// given columns.
// We verify all maxed out page layouts don't overflow,
// We're growing columns so we can only get less rows so use
// the lesser of our capacity and size so we minimize wasted
// rows.
// On error, we need to undo all the pages we've added.
// Keeps track of all our copied rows. Assertions at the end is that
// we copied exactly our page size.
// This function has an unfortunate side effect in that it causes memory
// fragmentation on rows if the columns are increasing in a way that
// shrinks capacity rows. If we have pages that don't divide evenly then
// we end up creating a final page that is not using its full capacity.
// If this chunk isn't the last chunk in the page list, then we've created
// a page where we'll never reclaim that capacity. This makes our max size
// calculation incorrect since we'll throw away data even though we have
// excess capacity. To avoid this, we try to fill our previous page
// first if it has capacity.
//
// This can fail for many reasons (can't fit styles/graphemes, etc.) so
// if it fails then we give up and drop back into creating new pages.
// We only want scenarios where we have excess capacity.
// We can copy as much as we can to fill the capacity or our
// current page size.
// If an error happens, we undo our row copy and break out
// into creating a new page.
// Remap any tracked pins that pointed to rows we just copied to prev.
// If we have an error, we clear the rows we just added to our prev page.
// We delete any of the nodes we added.
// We need to loop because our col growth may force us
// to split pages.
// The length we can copy into the new page is at most the number
// of rows in our cap. But if we can finish our source page we use that.
// Perform the copy
// I don't THINK this should be possible, because while our
// row count may diminish due to the adjustment, our
// prior capacity should have been sufficient to hold all the
// managed memory.
// We can actually safely handle this though by exiting
// this loop early and cutting our copy short.
// Insert our new page
// Update our tracked pins that pointed to this previous page.
// Our prior errdeferes are invalid after this point so ensure
// we don't have any more errors.
// Remove the old page.
// Deallocate the old page.
// Returns the number of trailing blank lines, not to exceed max. Max
// is used to limit our traversal in the case of large scrollback.
// Go through our pages backwards since we're counting trailing blanks.
// If the row has any text then we're done.
// Inc count, if we're beyond max then we're done.
// Trims up to max trailing blank rows from the pagelist and returns the
// number of rows trimmed. A blank row is any row with no text (but may
// have styling).
//
// IMPORTANT: This function does NOT update `total_rows`. It returns the
// number of rows trimmed, and the caller is responsible for decrementing
// `total_rows` by this amount.
// If the row has any text then we're done.
// If our tracked pins are in this row then we cannot trim it
// because it implies some sort of importance. If we trimmed this
// we'd invalidate this pin, as well.
// No text, we can trim this row. Because it has
// no text we can also be sure it has no styling
// so we don't need to worry about memory.
// Scroll options.
// Scroll to the active area. This is also sometimes referred to as
// the "bottom" of the screen. This makes it so that the end of the
// screen is fully visible since the active area is the bottom
// rows/cols of the screen.
// Scroll to the top of the screen, which is the farthest back in
// the scrollback history.
// Scroll to the given absolute row from the top. A value of zero
// is the top row. This row will be the first visible row in the viewport.
// Scrolling into or below the active area will clamp to the active area.
// Scroll up (negative) or down (positive) by the given number of
// rows. This is clamped to the "top" and "active" top left.
// Jump forwards (positive) or backwards (negative) a set number of
// prompts. If the absolute value is greater than the number of prompts
// in either direction, jump to the furthest prompt in that direction.
// Scroll directly to a specific pin in the page. This will be set
// as the top left of the viewport (ignoring the pin x value).
// Scroll the viewport. This will never create new scrollback, allocate
// pages, etc. This can only be used to move the viewport within the
// previously allocated pages.
// Special case no-scrollback mode to never allow scrolling.
// If we're at the top, pin the top.
// If we're below the top of the active area, pin the active area.
// See if there are any other faster paths we can take.
// If we have a pin and we already calculated a row offset,
// then we can efficiently calculate the delta and move
// that much from that pin.
// We have an accurate row offset so store it to prevent
// calculating this again.
// Slow path, we've just got to traverse the linked list and
// get to our row. As a slight speedup, let's pick the traversal
// that's likely faster based on our absolute row and total rows.
// Iterate forward from the first node.
// Iterate backwards from the last node.
// If we reached here, then we couldn't find the offset.
// This feels impossible? Just clamp to active, screw it lol.
// If we're at the top and we're scrolling backwards,
// we don't have to do anything, because there's nowhere to go.
// If we're at active and we're scrolling forwards, we don't
// have to do anything because it'll result in staying in
// the active.
// If we're already a pin type, then we can fast-path our
// delta by simply moving the pin. This has the added benefit
// that we can update our row offset cache efficiently, too.
// If we overflow up we're at the top.
// If we offset its a valid pin but we still have to
// check if we're in the active area.
// If we overflow down we're at active.
// Slow path: we have to calculate the new pin by moving
// from our viewport.
// If we are still within the active area, then we pin the
// viewport to active. This isn't EXACTLY the same behavior as
// other scrolling because normally when you scroll the viewport
// is pinned to _that row_ even if new scrollback is created.
// But in a terminal when you get to the bottom and back into the
// active area, you usually expect that the viewport will now
// follow the active area.
// If we're at the top, then just set the top. This is a lot
// more efficient everywhere. We must check this after the
// active check above because we prefer active if they overlap.
// Pin is not active so we need to track it.
// Jump the viewport forwards (positive) or backwards (negative) a set number of
// prompts (delta).
// If we aren't jumping any prompts then we don't need to do anything.
// We start at the row before or after our viewport depending on the
// delta so that we don't land back on our current viewport.
// Go through prompts delta times
// If we found a prompt, we move to it. If the prompt is in the active
// area we keep our viewport as active because we can't scroll DOWN
// into the active area. Otherwise, we scroll up to the pin.
// Clear the screen by scrolling written contents up into the scrollback.
// This will not update the viewport.
// Go through the active area backwards to find the first non-empty
// row. We use this to determine how many rows to scroll up.
// Scroll
// Compact a page to use the minimum required memory for the contents
// it stores. Returns the new node pointer if compaction occurred, or null
// if the page was already compact or compaction would not provide meaningful
// savings.
//
// The current design of PageList at the time of writing this doesn't
// allow for smaller than `std_size` nodes so if the current node's backing
// page is standard size or smaller, no compaction will occur. In the
// future we should fix this up.
//
// If this returns OOM, the PageList is left unchanged and no dangling
// memory references exist. It is safe to ignore the error and continue using
// the uncompacted page.
// We should never have empty rows in our pagelist anyways...
// We never compact standard size or smaller pages because changing
// the capacity to something smaller won't save memory.
// Compute the minimum capacity required for this page's content
// Create the new smaller page
// cloneFrom should not fail when compacting since req_cap is
// computed to exactly fit the source content and our expectation
// of exactRowCapacity ensures it can fit all the requested
// data.
// In this case, let's gracefully degrade by pretending we
// didn't need to compact.
// Fix up all tracked pins to point to the new page
// Insert the new page and destroy the old one
// Allocator OOM
// Page can't be split further because it is already a single row.
// Split the given node in the PageList at the given pin.
//
// The row at the pin and after will be moved into a new page with
// the same capacity as the original page. Alternatively, you can "split
// above" by splitting the row following the desired split row.
//
// Since the split happens below the pin, the pin remains valid.
// Ran into a bug that I can only explain via aliasing. If a tracked
// pin is passed in, its possible Zig will alias the memory and then
// when we modify it later it updates our p here. Copying the node
// fixes this.
// A page that is already 1 row can't be split. In the future we can
// theoretically maybe split by soft-wrapping multiple pages but that
// seems crazy and the rest of our PageList can't handle heterogeneously
// sized pages today.
// Splitting at row 0 is a no-op since there's nothing before the split point.
// At this point we're doing actual modification so make sure
// on the return that we're good.
// Create a new node with the same capacity of managed memory.
// Determine how many rows we're copying
// Copy our old data. This should NOT fail because we have the
// capacity of the old page which already fits the data we requested.
// Rather than crash, we return an OutOfSpace to show that
// we couldn't split and let our callers gracefully handle it.
// Realistically though... this should not happen.
// From this point forward there is no going back. We have no
// error handling. It is possible but we haven't written it.
// Move any tracked pins from the copied rows
// p.x remains the same since we're copying the row as-is
// Clear our rows
// This represents the state necessary to render a scrollbar for this
// PageList. It has the total size, the offset, and the size of the viewport.
// Total size of the scrollable area.
// The offset into the total area that the viewport is at. This is
// guaranteed to be less than or equal to total. This includes the
// visible row.
// The length of the visible area. This is including the offset row.
// A zero-sized scrollable region.
// Sync with: ghostty_action_scrollbar_s
// Comparison for scrollbars.
// Return the scrollbar state for this PageList.
//
// This may be expensive to calculate depending on where the viewport
// is (arbitrary pins are expensive). The caller should take care to only
// call this as needed and not too frequently.
// If we have no scrollback, special case no scrollbar.
// We need to do this because the way PageList works is that
// it always has SOME extra space (due to the way we allocate by page).
// So even with no scrollback we have some growth. It is architecturally
// much simpler to just hide that for no-scrollback cases.
// Returns the offset of the current viewport from the top of the
// screen.
//
// This is potentially expensive to calculate because if the viewport
// is a pin and the pin is near the beginning of the scrollback, we
// will traverse a lot of linked list nodes.
//
// The result is cached so repeated calls are cheap.
// We assert integrity on this code path because it verifies
// that the cached value is correct.
// Return cached value if available
// Traverse from the end and count rows until we reach the
// viewport pin. We count backwards because most of the time
// a user is scrolling near the active area.
// Invalid pins are not possible.
// The offset is from the bottom and our cached value and this
// function returns from the top, so we need to invert it.
// This fixes up the viewport data when rows are removed from the
// PageList. This will update a viewport to `active` if row removal
// puts the viewport into the active area, to `top` if the viewport
// is now at row 0, and updates any row offset caches as necessary.
//
// This is unit tested transitively through other tests such as
// eraseRows.
// For pin, we check if our pin is now in the active area and if so
// we move our viewport back to the active area.
// If we have a cached row offset, we need to update it
// to account for the erased rows.
// For top, we move back to active if our erasing moved our
// top page into the active area.
// Returns the actual max size. This may be greater than the explicit
// value if the explicit value is less than the min_max_size.
//
// This value is a HEURISTIC. You cannot assert on this value. We may
// exceed this value if required to fit the active area. This may be
// required in some cases if the active area has a large number of
// graphemes, styles, etc.
// Grow the active area by exactly one row.
//
// This may allocate, but also may not if our current page has more
// capacity we can use. This will prune scrollback if necessary to
// adhere to max_size.
//
// This returns the newly allocated page node if there is one.
// Fast path: we have capacity in the last page.
// Increase our total rows by one
// Slower path: we have no space, we need to allocate a new page.
// Get the layout first so our failable work is done early.
// We'll need this for both paths.
// If allocation would exceed our max size, we prune the first page.
// We don't need to reallocate because we can simply reuse that first
// page.
//
// We only take this path if we have more than one page since pruning
// reuses the popped page. It is possible to have a single page and
// exceed the max size if that page was adjusted to be larger after
// initial allocation.
// Decrease our total row count from the pruned page
// If our total row count is now less than our required
// rows then we can't prune. The "+ 1" is because we'll add one
// more row below.
// If we have a pin viewport cache then we need to update it.
// If our offset is less than the number of rows in the
// pruned page, then we are now at the top.
// Otherwise, our viewport pin is below what we pruned
// so we just decrement our offset.
// Update any tracked pins that point to this page to point to the
// new first page to the top-left, and mark them as garbage.
// Non-standard pages can't be reused, just destroy them.
// Reset our memory
// Initialize our new page and reinsert it as the last
// We also need to reset the serial number. Since this is the only
// place we ever reuse a serial number, we also can safely set
// page_serial_min to be one more than the old serial because we
// only ever prune the oldest pages.
// In this case we do NOT need to update page_size because
// we're reusing an existing page so nothing has changed.
// We need to allocate a new memory buffer.
// we don't errdefer this because we've added it to the linked
// list and its fine to have dangling unused pages.
// We should never be more than our max size here because we've
// verified the case above.
// Record the increased row count
// Possible dimensions to increase capacity for.
// An actual system OOM trying to allocate memory.
// The existing page is already at max capacity for the given
// adjustment. The caller must create a new page, remove data from
// the old page, etc. (up to the caller).
// Increase the capacity of the given page node in the given direction.
// This will always allocate a new node and remove the old node, so the
// existing node pointer will be invalid after this call. The newly created
// node on success is returned.
//
// The increase amount is at the control of the PageList implementation,
// but is guaranteed to always increase by at least one unit in the
// given dimension. Practically, we'll always increase by much more
// (we currently double every time) but callers shouldn't depend on that.
// The only guarantee is some amount of growth.
//
// Adjustment can be null if you want to recreate, reclone the page
// with the same capacity. This is a special case used for rehashing since
// the logic is otherwise the same. In this case, OutOfMemory is the
// only possible error.
// Apply our adjustment
// We use checked math to prevent overflow. If there is an
// overflow it means we're out of space in this dimension,
// since pages can take up to their maxInt capacity in any
// category.
// Our final doubling would overflow since maxInt is
// 2^N - 1 for an unsignged int of N bits. So, if we overflow
// and we haven't used all the bits, use all the bits.
// If our capacity exceeds the maximum page size, treat it
// as an OutOfSpace because things like page splitting will
// help.
// Create our new page and clone the old page into it.
// cloneFrom only errors if there isn't capacity for the data
// from the source page but we're only increasing capacity so
// this should never be possible. If it happens, we should crash
// because we're in no man's land and can't safely recover.
// Preserve page-level dirty flag (cloneFrom only copies row data)
// Must not fail after this because the operations we do after this
// can't be recovered.
// Fix up all our tracked pins to point to the new page.
// Insert this page and destroy the old page
// Create a new page node. This does not add it to the list and this
// does not do any memory size accounting with max_size/page_size.
// log.debug("create page cap={}", .{cap});
// It would be better to encode this into the Zig error handling
// system but that is a big undertaking and we only have a few
// centralized call sites so it is handled on its own currently.
// Our page buffer comes from our standard memory pool if it
// is within our standard size since this is what the pool
// dispenses. Otherwise, we use the heap allocator to allocate.
// Required only with runtime safety because allocators initialize
// to undefined, 0xAA.
// Accumulate page size now. We don't assert or check max size
// because we may exceed it here temporarily as we are allocating
// pages before destroy.
// Destroy the memory of the given node in the PageList linked list
// and return it to the pool. The node is assumed to already be removed
// from the linked list.
//
// IMPORTANT: This function does NOT update `total_rows`. The caller is
// responsible for accounting for the removed rows. This function only
// updates `page_size` (byte accounting), not row accounting.
// Update our accounting for page size
// Reset the memory to zero so it can be reused
// Fast-path function to erase exactly 1 row. Erasing means that the row
// is completely REMOVED, not just cleared. All rows following the removed
// row will be shifted up by 1 to fill the empty space.
//
// Unlike eraseRows, eraseRow does not change the size of any pages. The
// caller is responsible for adjusting the row count of the final page if
// that behavior is required.
// In order to move the following rows up we rotate the rows array by 1.
// The rotate operation turns e.g. [ 0 1 2 3 ] in to [ 1 2 3 0 ], which
// works perfectly to move all of our elements where they belong.
// We adjust the tracked pins in this page, moving up any that were below
// the removed row.
// If we have a pinned viewport, we need to adjust for active area.
// Mark the whole page as dirty.
//
// Technically we only need to mark rows from the erased row to the end
// of the page as dirty, but that's slower and this is a hot function.
// We iterate through all of the following pages in order to move their
// rows up by 1 as well.
// We take the top row of the page and clone it in to the bottom
// row of the previous page, which gets rid of the top row that was
// rotated down in the previous page, and accounts for the row in
// this page that will be rotated down as well.
//
//  rotate -> clone --> rotate -> result
//    0 -.      1         1         1
//    1  |      2         2         2
//    2  |      3         3         3
//    3 <'      0 <.      4         4
//   ---       --- |     ---       ---  <- page boundary
//    4         4 -'      4 -.      5
//    5         5         5  |      6
//    6         6         6  |      7
//    7         7         7 <'      4
// Mark the whole page as dirty.
// Our tracked pins for this page need to be updated.
// If the pin is in row 0 that means the corresponding row has
// been moved to the previous page. Otherwise, move it up by 1.
// Clear the final row which was rotated from the top of the page.
// A variant of eraseRow that shifts only a bounded number of following
// rows up, filling the space they leave behind with blank rows.
//
// `limit` is exclusive of the erased row. A limit of 1 will erase the target
// row and shift the row below in to its position, leaving a blank row below.
// This function has a lot of repeated code in it because it is a hot path.
//
// To get a better idea of what's happening, read eraseRow first for more
// in-depth explanatory comments. To avoid repetition, the only comments for
// this function are for where it differs from eraseRow.
// If the row limit is less than the remaining rows before the end of the
// page, then we clear the row, rotate it to the end of the boundary limit
// and update our pins.
// Mark the whole page as dirty.
//
// Technically we only need to mark from the erased row to the
// limit but this is a hot function, so we want to minimize work.
// If our viewport is a pin and our pin is within the erased
// region we need to maybe shift our cache up. We do this here instead
// of in the pin loop below because its unlikely to be true and we
// don't want to run the conditional N times.
// Update pins in the shifted region.
// Mark the whole page as dirty.
//
// Technically we only need to mark rows from the erased row to the end
// of the page as dirty, but that's slower and this is a hot function.
// We need to keep track of how many rows we've shifted so that we can
// determine at what point we need to do a partial shift on subsequent
// pages.
// Update tracked pins.
// See the other places we do something similar in this function
// for a detailed explanation.
// We check to see if this page contains enough rows to satisfy the
// specified limit, accounting for rows we've already shifted in prior
// pages.
//
// The logic here is very similar to the one before the loop.
// Mark the whole page as dirty.
//
// Technically we only need to mark from the erased row to the
// limit but this is a hot function, so we want to minimize work.
// See the other places we do something similar in this function
// for a detailed explanation.
// Update pins in the shifted region.
// Mark the whole page as dirty.
// Account for the rows shifted in this node.
// See the other places we do something similar in this function
// for a detailed explanation.
// Update tracked pins.
// We reached the end of the page list before the limit, so we clear
// the final row since it was rotated down from the top of this page.
// Erase the rows from the given top to bottom (inclusive). Erasing
// the rows doesn't clear them but actually physically REMOVES the rows.
// If the top or bottom point is in the middle of a page, the other
// contents in the page will be preserved but the page itself will be
// underutilized (size < capacity).
// The count of rows that was erased.
// A pageIterator iterates one page at a time from the back forward.
// "back" here is in terms of scrollback, but actually the front of the
// linked list.
// If the chunk is a full page, deinit thit page and remove it from
// the linked list.
// A rare special case is that we're deleting everything
// in our linked list. erasePage requires at least one other
// page so to handle this we reinit this page, set it to zero
// size which will let us grow our active area back.
// We are modifying our chunk so make sure it is in a good state.
// The chunk is not a full page so we need to move the rows.
// This is a cheap operation because we're just moving cell offsets,
// not the actual cell contents.
// Mark the moved row as dirty.
// Clear our remaining cells that we didn't shift or swapped
// in case we grow back into them.
// Update any tracked pins to shift their y. If it was in the erased
// row then we move it to the top of this page.
// Our new size is the amount we scrolled
// Update our total row count
// If we deleted active, we need to regrow because one of our invariants
// is that we always have full active space.
// If this fails its a pretty big issue actually... but I don't
// want to turn this function into an error-returning function
// because erasing active is so rare and even if it happens failing
// is even more rare...
// If we have a pinned viewport, we need to adjust for active area.
// Erase a single page, freeing all its resources. The page can be
// anywhere in the linked list but must NOT be the final page in the
// entire list (i.e. must not make the list empty).
//
// IMPORTANT: This function does NOT update `total_rows`. The caller is
// responsible for accounting for the removed rows before or after calling
// this function.
// Update any tracked pins to move to the previous or next page.
// This doesn't get marked garbage because the tracked pin
// movement is sensical.
// Remove the page from the linked list
// Returns the pin for the given point. The pin is NOT tracked so it
// is only valid as long as the pagelist isn't modified.
//
// This will return null if the point is out of bounds. The caller
// should clamp the point to the bounds of the coordinate space if
// necessary.
// getTopLeft is much more expensive than checking the cols bounds
// so we do this first.
// Grab the top left and move to the point.
// Convert the given pin to a tracked pin. A tracked pin will always be
// automatically updated as the pagelist is modified. If the point the
// pin points to is removed completely, the tracked pin will be updated
// to the top-left of the screen.
// Create our tracked pin
// Add it to the tracked list
// Untrack a previously tracked pin. This will deallocate the pin.
// Returns the tracked pins for this pagelist. The slice is owned by the
// pagelist and is only valid until the pagelist is modified.
// Checks if a pin is valid for this pagelist. This is a very slow and
// expensive operation since we traverse the entire linked list in the
// worst case. Only for runtime safety/debug.
// This is very slow so we want to ensure we only ever
// call this during slow runtime safety builds.
// Returns the viewport for the given pin, preferring to pin to
// "active" if the pin is within the active area.
// If the pin is in the active page, then we can quickly determine
// if we're beyond the end.
// This loop is pretty fast because the active area is
// never that large so this is at most one, two nodes for
// reasonable terminals (including very large real world
// ones).
// A node forward in the active area is our node, so we're
// definitely in the active area.
// Returns true if the pin is at the top of the scrollback area.
// Convert a pin to a point in the given context. If the pin can't fit
// within the given tag (i.e. its in the history but you requested active),
// then this will return null.
//
// Note that this can be a very expensive operation depending on the tag and
// the location of the pin. This works by traversing the linked list of pages
// in the tagged region.
//
// Therefore, this is recommended only very rarely.
// Count our first page which is special because it may be partial.
// If our top-left is after our y then we're outside the range.
// We never saw our node, meaning we're outside the range.
// Get the cell at the given point, or null if the cell does not
// exist or is out of bounds.
//
// Warning: this is slow and should not be used in performance critical paths
// Log a debug diagram of the page list to the provided writer.
//
// EXAMPLE:
//
//      +-----+ = PAGE 0
//  ... |     |
//   50 | foo |
//  ... |     |
//     +--------+ ACTIVE
//  124 |     | | 0
//  125 |Text | | 1
//      :  ^  : : = PIN 0
//  126 |Wrap…  | 2
//      +-----+ :
//      +-----+ : = PAGE 1
//    0 …ed   | | 3
//    1 | etc.| | 4
//      +-----+ :
//     +--------+
// Whether we've just skipped some number of rows and drawn
// an ellipsis row (this is reset when a row is not skipped).
// Active header
// Page header
// Row contents
// We don't want to print this row's contents
// unless it has text or is in the active area.
// If we haven't, draw an ellipsis row.
// Left pad row number to 5 wide
// Left edge or wrap continuation marker
// Row text
// Skip spacer tails, since wide cells are, well, wide.
// Write non-printing bytes as base36, for convenience.
// Right edge or wrap marker
// Tracked pin marker(s)
// If we have more than 16 tracked pins in a row, oh well,
// don't wanna bother making this function allocating.
// Page footer
// Active footer
// Returns the boundaries of the given semantic content type for
// the prompt at the given pin. The pin row MUST be the first row
// of a prompt, otherwise the results may be nonsense.
//
// To get prompt pins, use promptIterator. Warning that if there are
// no semantic prompts ever present, promptIterator will iterate the
// entire PageList. Downstream callers should keep track of a flag if
// they've ever seen semantic prompt operations to prevent this performance
// case.
//
// Note that some semantic content type such as "input" is usually
// nested within prompt boundaries, so the returned boundaries may include
// prompt text.
// Performance note: we can do this more efficiently in a single
// forward-pass. Semantic content operations aren't usually fast path
// but if someone wants to optimize them someday that's great.
// Safety assertion, our starting point should be a prompt row.
// so the first returned prompt should be ourselves.
// Our end is the end of the line just before the next prompt
// line, which should exist since we verified we have at least
// two prompts here.
// Didn't find any further prompt so the end of our zone is
// the end of the screen.
// For the prompt, we select all the way up to command output.
// We include all the input lines, too.
// For input, we include the start of the input to the end of
// the input, which may include all the prompts in the middle, too.
// Find the start
// No input found
// Find the end
// Prompts can be nested in our input for continuation
// Output means we're done
// Find the start
// Skip empty cells - they default to .output but aren't real output
// No output found
// Find the end
// Only extend to cells with actual text
// Direction that iterators can move.
// The pin that we are currently at. Also the starting pin when
// initializing.
// The pin to end at or null if we end when we can't traverse
// anymore.
// The direction to do the traversal.
// Return the next pin that represents the first row in a prompt.
// From here, you can find the prompt input, command output, etc.
// Start at our current pin. If we have no current it means
// we reached the end and we're done.
// We need to traverse downwards and look for prompts.
// Check our limit.
// This row isn't a prompt. Keep looking.
// This is a prompt line or continuation line. In either
// case we consider the first line the prompt, and then
// skip over any remaining prompt lines. This handles the
// case where scrollback pruned the prompt.
// If we're at our limit just return this prompt.
// Skip over any continuation lines that follow this prompt,
// up to our limit.
// Start at our current pin. If we have no current it means
// we reached the end and we're done.
// We need to traverse upwards and look for prompts.
// Check our limit.
// This row isn't a prompt. Keep looking.
// This is a prompt line.
// If this is a prompt continuation, then we continue
// looking for the start of the prompt OR a non-prompt
// line, whichever is first. The non-prompt line is to handle
// poorly behaved programs or scrollback that's been cut-off.
// If we're at our limit just return this continuation as prompt.
// No prompt. That means our last pin is good!
// Prompt continuation, keep looking.
// Prompt! Found it!
// No prior rows, trimmed scrollback probably.
// We still have cells in this row, increase x.
// We need to move to the next row.
// We still have cells in this row, decrease x.
// We need to move to the previous row and last col
// Increase our offset in the chunk
// If we are beyond the chunk end, we need to move to the next chunk.
// If we are at the start of the chunk, we need to move to the
// previous chunk.
// If we're at the start of the chunk and its a non-zero
// offset then we've reached a limit.
// Create an iterator that can be used to iterate all the rows in
// a region of the screen from the given top-left. The tag of the
// top-left point will also determine the end of the iteration,
// so convert from one reference point to another to change the
// iteration bounds.
// Get our current row location
// If we have no limit, then we consume this entire page. Our
// next row is the next page.
// If this is not the same page as our limit then we
// can consume the entire page.
// If this is the same page then we only consume up to
// the limit row.
// Get our current row location
// If we have no limit, then we consume this entire page. Our
// next row is the next page.
// If this is not the same page as our limit then we
// can consume the entire page.
// If this is the same page then we only consume up to
// the limit row.
// Start y index (inclusive) of this chunk in the page.
// End y index (exclusive) of this chunk in the page.
// Returns true if this chunk represents every row in the page.
// Returns true if this chunk overlaps with the given other chunk
// in any way.
// Return an iterator that iterates through the rows in the tagged area
// of the point. The iterator returns row "chunks", which are the largest
// contiguous set of rows in a single backing page for a given portion of
// the point region.
//
// This is a more efficient way to iterate through the data in a region,
// since you can do simple pointer math and so on.
//
// If bl_pt is non-null, iteration will stop at the bottom left point
// (inclusive). If bl_pt is null, the entire region specified by the point
// tag will be iterated over. tl_pt and bl_pt must be the same tag, and
// bl_pt must be greater than or equal to tl_pt.
//
// If direction is left_up, iteration will go from bl_pt to tl_pt. If
// direction is right_down, iteration will go from tl_pt to bl_pt.
// Both inclusive.
// Get the top-left of the screen for the given tag.
// The full screen or history is always just the first page.
// The active area is calculated backwards from the last page.
// This makes getting the active top left slower but makes scrolling
// much faster because we don't need to update the top left. Under
// heavy load this makes a measurable difference.
// Returns the bottom right of the screen for the given tag. This can
// return null because it is possible that a tag is not in the screen
// (e.g. history does not yet exist).
// The total rows in the screen. This is the actual row count currently
// and not a capacity or maximum.
//
// This is very slow, it traverses the full list of pages to count the
// rows, so it is not pub. This is only used for testing/debugging.
// The total number of pages in this list. This should only be used
// for tests since it is O(N) over the list of pages.
// Grow the number of rows available in the page list by n.
// This is only used for testing so it isn't optimized in any way.
// Clear all dirty bits on all pages. This is not efficient since it
// traverses the entire list of pages. This is used for testing/debugging.
// Returns true if the point is dirty, used for testing.
// Mark a point as dirty, used for testing.
// Represents an exact x/y coordinate within the screen. This is called
// a "pin" because it is a fixed point within the pagelist direct to
// a specific page pointer and memory offset. The benefit is that this
// point remains valid even through scrolling without any additional work.
//
// A downside is that  the pin is only valid until the pagelist is modified
// in a way that may invalidate page pointers or shuffle rows, such as resizing,
// erasing rows, etc.
//
// A pin can also be "tracked" which means that it will be updated as the
// PageList is modified.
//
// The PageList maintains a list of active pin references and keeps them
// all up to date as the pagelist is modified. This isn't cheap so callers
// should limit the number of active pins as much as possible.
// This is flipped to true for tracked pins that were tracking
// a page that got pruned for any reason and where the tracked pin
// couldn't be moved to a sensical location. Users of the tracked
// pin could use this data and make their own determination of
// semantics.
// Returns the cells for the row that this pin is on. The subset determines
// what subset of the cells are returned. The "left/right" subsets are
// inclusive of the x coordinate of the pin.
// Returns the grapheme codepoints for the given cell. These are only
// the EXTRA codepoints and not the first codepoint.
// Returns the style for the given cell in this pin.
// Check if this pin is dirty.
// Mark this pin location as dirty.
// Iterators. These are the same as PageList iterator funcs but operate
// on pins rather than points. This is MUCH more efficient than calling
// pointFromPin and building up the iterator from points.
//
// The limit pin is inclusive.
// Check the order according to the iteration direction.
// Returns true if this pin is between the top and bottom, inclusive.
//
// Note: this is primarily unit tested as part of the Kitty
// graphics deletion code.
// If top is bottom, must be ordered.
// If top is not bottom, top must be before bottom.
// If our pin is the top page and our y is less than the top y
// then we can't possibly be between the top and bottom.
// If our y is after the top y but we're on the same page
// then we're between the top and bottom if our y is less
// than or equal to the bottom y if its the same page. If the
// bottom is another page then it means that the range is
// at least the full top page and since we're the same page
// we're in the range.
// Otherwise our y is the same as the top y, so we need to
// check the x coordinate.
// Our page is the bottom page so we're between the top and
// bottom if our y is less than the bottom y.
// If our y is the same, then we're between if we're before
// or equal to the bottom x.
// Our page isn't the top or bottom so we need to check if
// our page is somewhere between the top and bottom.
// Since our loop starts at top.page.next we need to check that
// top != bottom because if they're the same then we can't possibly
// be between them.
// Returns true if self is before other. This is very expensive since
// it requires traversing the linked list of pages. This should not
// be called in performance critical paths.
// Move the pin left n columns. n must fit within the size.
// Move the pin right n columns. n must fit within the size.
// Move the pin left n columns, stopping at the start of the row.
// Move the pin right n columns, stopping at the end of the row.
// Move the pin left n cells, wrapping to the previous row as needed.
//
// If the offset goes beyond the top of the screen, returns null.
//
// TODO: Unit tests.
// NOTE: This assumes that all pages have the same width, which may
//       be violated under certain circumstances by incomplete reflow.
// Move the pin right n cells, wrapping to the next row as needed.
//
// If the offset goes beyond the bottom of the screen, returns null.
//
// TODO: Unit tests.
// NOTE: This assumes that all pages have the same width, which may
//       be violated under certain circumstances by incomplete reflow.
// Move the pin down a certain number of rows, or return null if
// the pin goes beyond the end of the screen.
// Move the pin up a certain number of rows, or return null if
// the pin goes beyond the start of the screen.
// Move the offset down n rows. If the offset goes beyond the
// end of the screen, return the overflow amount.
// Index fits within this page
// Need to traverse page links to find the page
// Move the offset up n rows. If the offset goes beyond the
// start of the screen, return the overflow amount.
// Index fits within this page
// Need to traverse page links to find the page
// Returns true if this cell is marked as dirty.
//
// This is not very performant this is primarily used for assertions
// and testing.
// Get the cell style.
//
// Not meant for non-test usage since this is inefficient.
// Gets the screen point for the given cell.
//
// This is REALLY expensive/slow so it isn't pub. This was built
// for debugging and tests. If you have a need for this outside of
// this file then consider a different approach and ask yourself very
// carefully if you really need this.
// Initial total rows should be our row count
// Our viewport pin must be defined. It isn't used until the
// viewport is a pin but it prevents undefined access on clone.
// Active area should be the top
// Scrollbar should be where we expect it
// Test every failure point in `init` and ensure that we don't
// leak memory (testing.allocator verifies) since we're exiting early.
// init calls initPages transitively, so let's check that if
// any failures happen in initPages, we also don't leak memory.
// Try non-standard pages since they don't go in our pool.
// Find a cap that makes it so that rows don't fit on one page.
// Init
// Initial total rows should be our row count
// Scrollbar should be where we expect it
// Initialize with more columns than we can fit in our standard
// capacity. This is going to force us to go to a non-standard page
// immediately.
// We expect a single, non-standard page
// Initial total rows should be our row count
// Scrollbar should be where we expect it
// In history, invalid
// Grow so we take up at least 5 pages.
// Prior page
// Grow so we take up at least 2 pages.
// Prior page
// Make sure all points make sense
// Scrollbar should be in the active area
// Setup our initial page so that we fully take up one page.
// Grow once because we guarantee at least two pages of
// capacity so we want to get to that.
// Surgically modify our pages so that they have a smaller size.
// Avoid integrity check failures
// Grow our row and ensure we don't prune pages because we need
// enough for the active area.
// Need scrollback > 0 to have a scrollbar to test
// This block is all test setup. There is nothing required about this
// behavior during a refactor. This is setting up a scenario that is
// possible to trigger a bug (#2280).
// Increase our capacity until our page is larger than the standard size.
// This is important because it triggers a scenario where our calculated
// minSize() which is supposed to accommodate 2 pages is no longer true.
// Figure out the remaining number of rows. This is the amount that
// can be added to the current page before we need to allocate a new
// page.
// The next one we add will trigger a new page.
// Scrollbar should be in the active area
// Grow some rows (simulates normal terminal output)
// With no scrollback (max_size = 0), total should equal rows
// With no scrollback, offset should be 0 (nowhere to scroll back to)
// Remember initial viewport position
// Try to scroll backwards into "history" - should be no-op
// Scroll to top - should also be no-op with no scrollback
// Verify cache is populated
// Now scroll to a different row - this should use the fast path
// Verify cache is populated
// Now scroll up to a different row - this should use the fast path
// Jump back
// Jump forward
// So we know we're using capacity to grow
// Grow
// Grow to capacity
// Grow, should allocate
// Use std_size to limit scrollback so pruning is triggered.
// Grow to capacity
// Grow and allocate one more page. Then fill that page up.
// Get our page size
// Create a tracked pin in the first page
// Scroll back to create a pinned viewport (not active)
// Get the scrollbar state to populate the cache
// Next should create a new page, but it should reuse our first
// page since we're at max size.
// Our first should now be page2 and our last should be page1
// Our tracked pin should point to the top-left of the first page
// Verify the viewport offset cache was invalidated. After pruning,
// the offset should have changed because we removed rows from
// the beginning.
// Use std_size to limit scrollback so pruning is triggered.
// Grow to capacity of first page
// Grow and allocate second page, then fill it up
// Get our page size
// Scroll back to create a pinned viewport in page2 (NOT page1)
// This is the key difference from the previous test - the viewport
// pin is NOT in the page that will be pruned.
// Get the scrollbar state to populate the cache
// Next grow will trigger pruning of the first page.
// The viewport_pin.node is page2, not page1, so it won't be moved
// by the pin update loop, but the cached offset still needs to be
// invalidated because rows were removed from the beginning.
// Our first should now be page2 (page1 was pruned)
// The viewport pin should still be on page2, unchanged
// Verify the viewport offset cache was invalidated/updated.
// After pruning, the offset should have decreased by the number
// of rows that were pruned.
// Grow so we take up several pages worth of history
// Scroll back to create a pinned viewport somewhere in the middle
// of the scrollback
// Erase some history rows BEFORE the viewport pin.
// This removes rows from before our pin, which changes its absolute
// offset from the top, but the cache is not invalidated.
// Grow so we take up several pages worth of history
// Scroll back to create a pinned viewport somewhere in the middle
// of the scrollback
// Erase a single row from the history BEFORE the viewport pin.
// This removes one row from before our pin, which changes its absolute
// offset from the top by 1, but the cache is not invalidated.
// Grow so we take up several pages worth of history
// Scroll back to create a pinned viewport somewhere in the middle
// of the scrollback
// Erase a row from the history BEFORE the viewport pin with a bounded
// shift. This removes one row from before our pin, which changes its
// absolute offset from the top by 1, but the cache is not invalidated.
// Verify the scrollbar reflects the change (offset decreased by 1)
// Grow so we take up several pages worth of history
// Scroll back to create a pinned viewport somewhere in the middle
// of the scrollback, after the first page
// Erase a row from the beginning of history with a limit that spans
// across multiple pages. This ensures we hit the code path where
// eraseRowBounded finds the limit boundary in a subsequent page.
// Verify the scrollbar reflects the change (offset decreased by 1)
// Grow so we take up several pages worth of history
// Scroll back to create a pinned viewport somewhere well beyond
// the first two pages
// Erase a row from the beginning of history with a limit that is
// larger than multiple full pages. This ensures we hit the code path
// where eraseRowBounded continues looping through entire pages,
// rotating all rows in each page until it reaches the limit or
// runs out of pages.
// Verify the scrollbar reflects the change (offset decreased by 1)
// Grow so we take up several pages worth of history
// Our total rows should include history
// Scroll back to create a pinned viewport somewhere in the history,
// well after the erase will complete
// Erase a row from the beginning of history with a limit that is
// LARGER than all remaining pages combined. This ensures we exhaust
// all pages in the while loop and reach the cleanup code after the loop.
// Verify the scrollbar reflects the change (offset decreased by 1)
// Write all our data so we can assert its the same after
// Increase our styles
// Verify capacity doubled
// Verify data preserved
// Create a tracked pin on the first page
// Increase capacity
// Pin should now point to the new node
// Keep increasing styles capacity until we get OutOfSpace
// Before OutOfSpace, we should have reached maxInt
// Shrink columns
// Increase capacity
// size.cols should still be 5, not reverted to capacity.cols
// Grow to create a second page
// Now we have two pages
// Increase capacity on the first page only
// First page capacity should be doubled
// Second page should be unchanged
// Set page dirty flag and mark some rows as dirty
// Increase capacity
// The page dirty flag should be preserved
// Row dirty flags should be preserved
// The viewport should be within a single page
// Iterate the active area
// Should only have one chunk
// Grow to capacity
// Iterate the active area
// Grow to capacity
// Iterate the active area
// The viewport should be within a single page
// Iterate the active area
// Should only have one chunk
// Grow to capacity
// Iterate the active area
// Grow to capacity
// Iterate the active area
// Normal prompt
// Continuation
// Broken continuation that has non-prompts in between
// Normal prompt
// Continuation (prompt on row 6, continuation on rows 7-8)
// Broken continuation that has non-prompts in between (orphaned continuation at row 12)
// Prompt continuation at row 0 (no prior rows - simulates trimmed scrollback)
// Normal prompt later
// Should return the first continuation line since there's no prior prompt
// Prompt on row 2, continuation on rows 3-4
// Starting iteration from row 3 should still find the prompt at row 2
// Start iteration from row 3 (middle of the continuation)
// Since we start on a continuation line, we treat it as the prompt start
// (handles case where scrollback pruned the actual prompt)
// Returns row 3 since that's the first prompt-related line we encounter
// Prompt on row 5
// Prompt on row 10
// Iterate with limit at row 5 (the prompt row) - should include it
// Prompt on row 5
// Prompt on row 10
// Iterate with limit at row 10 (the prompt row) - should include it
// tl_pt is the limit (upper bound), bl_pt is the start point for left_up
// Prompt on row 5
// Start the prompt for the first 5 cols
// Next 3 let's make input
// Prompt on row 10
// Prompt on row 5
// First 3 cols are prompt
// Next 4 are input
// Rest is output (shouldn't be included in prompt highlight)
// Prompt on row 10
// Highlighting from prompt should include prompt and input, but stop at output
// Prompt starts on row 5
// First row is all prompt
// Row 6 continues with input
// Prompt on row 10
// Highlighting should span both rows
// Prompt on row 5 with only prompt content (no input)
// Prompt on row 10
// Highlighting should only include the prompt cells
// Single prompt on row 15, no following prompt
// Highlighting should include prompt and input up to column 7
// Prompt on row 5
// First 3 cols are prompt
// Next 5 are input
// Prompt on row 10
// Highlighting input should only include input cells
// Prompt on row 5
// First 2 cols are prompt
// Next 3 are input
// Rest is output
// Prompt on row 10
// Highlighting input should stop at output
// Prompt on row 5
// First 2 cols are prompt
// Rest is input
// Row 6 has continuation prompt then more input
// Continuation prompt
// More input
// Prompt on row 10
// Highlighting input should span both rows, skipping continuation prompts
// Prompt on row 5 with only prompt, then immediately output
// First 3 cols are prompt
// Rest is output (no input!)
// Prompt on row 10
// Highlighting input should return null when there's no input
// Single prompt on row 15, no following prompt
// Highlighting input with no following prompt
// Prompt on row 5 with only prompt content, no input or output
// All cells are prompt
// Mark rows 6-9 as prompt to ensure no input before next prompt
// Prompt on row 10
// Highlighting input should return null when there's only prompts
// Prompt on row 5
// First 2 cols are prompt
// Next 3 are input
// Cols 5-7 are output
// Mark remaining cells as prompt to bound the output
// Prompt on row 10
// Highlighting output should only include output cells
// Prompt on row 5
// First 2 cols are prompt
// Next 2 are input
// Rest of row 5 is output
// Row 6 is all output
// Row 7 has partial output then input to bound it
// Prompt on row 10
// Highlighting output should span multiple rows
// Prompt on row 5
// First 2 cols are prompt
// Next 2 are input
// Rest is output
// Row 6 has output then prompt starts
// Next prompt marker on same row
// Prompt on row 10
// Highlighting output should stop before prompt/input
// Single prompt on row 15, no following prompt
// Row 16 has output then prompt to bound it
// Highlighting output with no following prompt
// Prompt on row 5 with only prompt and input, no output
// First 3 cols are prompt
// Rest is input (must explicitly mark all cells to avoid default .output)
// Mark rows 6-9 as input to ensure no output between prompts
// Prompt on row 10 (no output between prompts)
// Highlighting output should return null when there's no output
// Tests that empty cells with default .output semantic content are
// not selected as output. This can happen when a prompt/input line
// doesn't fill the entire row - trailing cells have default .output.
// Prompt on row 5 - only fills first 3 cells, rest are empty with default .output
// First 3 cols are prompt with text
// Cells 3-9 are empty (codepoint = 0) with default .output semantic content
// This simulates what happens when a short prompt is written
// Row 6 has input (short, doesn't fill line)
// Cells 4-9 are empty with default .output
// Row 7-8 have actual output with text
// Prompt on row 10
// Highlighting output should skip empty cells on rows 5-6 and find
// the actual output starting at row 7
// Output should start at row 7, not row 5 (where empty cells have default .output)
// Grow so we take up at least 5 pages.
// Our total rows should be large
// Erase the entire history, we should be back to just our active set.
// We should be back to just one page
// Grow so we take up at least 5 pages.
// Erase the entire history, we should be back to just our active set.
// Grow so we take up at least 5 pages.
// Our total rows should be large
// Put a tracked pin in the history
// Erase the entire history, we should be back to just our active set.
// Our pin should move to the first page
// Put a tracked pin in the history
// Erase only a few rows in our active
// Our pin should move to the first page
// Put a tracked pin in the history
// Erase the entire history, we should be back to just our active set.
// Our pin should move to the first page
// Grow so we take up at least 5 pages.
// Move our viewport to the top
// Erase the entire history, we should be back to just our active set.
// Grow so we take up at least 5 pages.
// Move our viewport to the top
// Erase the entire history, we should be back to just our active set.
// Grow so we take up at least 5 pages.
// Move our viewport to the top
// Erase the entire history, we should be back to just our active set.
// Write our letter
// The row should be empty
// Pins
// Erase only a few rows in our active
// The erased rows should be dirty
// Pins
// Erase only a few rows in our active
// The erased rows should be dirty
// Pins
// Erase only a few rows in our active
// The erased rows should be dirty
// Our pin should move to the first page
// Grow to two pages so our active area straddles
// Pins
// Erase only a few rows in our active
// The erased rows should be dirty
// In page in first page is shifted
// Out page in first page should not be shifted
// In page is shifted
// Out page is not shifted
// Style the rows we're trimming
// We're over-counted by 1 because `add` implies `use`.
// Expect to have one style
// Put a tracked pin in the screen
// We should be able to find our tracked pin
// Put a tracked pin in the screen
// We should be able to find our tracked pin
// Mark a row as dirty
// Should still be dirty
// Put a tracked pin in the history
// Resize
// Our cursor should not move because we have no scrollback so
// we just grew.
// Put a tracked pin in the history
// Resize
// Our cursor should move since it's in the scrollback
// This is required for our writing below to work
// Write into all rows so we don't get trim behavior
// Resize
// This is required for our writing below to work
// Write into all rows so we don't get trim behavior
// Resize
// This is required for our writing below to work
// Write into all rows so we don't get trim behavior
// Put a tracked pin in the history
// Resize
// Our cursor should move since it's in the scrollback
// This is required for our writing below to work
// Write into all rows so we don't get trim behavior
// Put a tracked pin in the history
// Resize
// Our cursor should move since it's in the scrollback
// Write codepoint into first line
// Fill remaining lines with a background color
// Put a tracked pin in the history
// Resize
// Our cursor should not move since we trimmed
// Write codepoint into first line
// Fill remaining lines with a background color
// Put a tracked pin in a blank line
// Resize
// Our cursor should not move since we trimmed
// Resize to take up two pages
// Write codepoint into first line
// Resize down. Every row except the first is blank so we
// should erase the second page.
// Write codepoint into first line
// Fill remaining lines with a background color
// Resize
// When the rows are increased we need to make sure that the viewport
// doesn't end up below the active area if it's currently in pin mode.
// Make it so we have scrollback
// Set viewport above active by scrolling up one.
// The viewport should be a pin now.
// Resize
// Question: maybe the viewport should actually be in the active
// here and not pinned to the top.
// Resize
// Put a tracked pin in the history
// Resize
// Add a grapheme.
// Resize
// Resize
// Resize
// try testing.expect(!rac.row.header.wrap);
// This test is a bit convoluted so I want to explain: what we are trying
// to verify here is that when we increase cols such that our rows per page
// shrinks, we don't fragment our rows across many pages because this ends
// up wasting a lot of memory.
//
// This is particularly important for alternate screen buffers where we
// don't have scrollback so our max size is very small. If we don't do this,
// we end up pruning our pages and that causes resizes to fail!
// This test requires initially that our rows fit into one page.
// Then we need to resize our cols so that our rows per page shrinks.
// This will force our resize to split our rows across two pages.
// Every page except the last should be full
// Now we need to resize again to a col size that further shrinks
// our last capacity.
// Every page except the last should be full
// Resize less
// Resize
// Resize less
// Resize less
// Resize to a size that requires more than one page to fit our rows.
// Resize
// We want a cap that forces us to have less rows
// Create initial cap, fits in one page
// Resize to our large cap
// Our total rows should be the same, and contents should be the same.
// Grow to 5 total rows, simulating 3 active + 2 scrollback
// Active should be on row 3
// Put a tracked pin in the history
// Resize
// Our cursor should not change
// 12 because we have our 10 rows in the active + 2 in the scrollback
// because we're preserving the cursor.
// Active should be at the same place it was.
// Go through our active, we should get only 3,4,5
// Resize
// Resize
// Active should still be on top
// First row should be unwrapped
// Scroll to a pinned viewport in history
// Resize with reflow - unwrapping rows changes total_rows
// Verify scrollbar cache was invalidated during reflow
// We want a wide viewport so our row limit is rather small. This will
// force the reflow below to create multiple pages, which we assert.
// Wrap every other row so every line is wrapped for reflow
// Resize
// All pages should have the new capacity
// We should have more than one page, meaning we created at least
// one page. This is the critical aspect of this test so if this
// ever goes false we need to adjust this test.
// Grow to the capacity of the first page.
// At this point, we have some rows on the first page, and some on the second.
// We can now wrap across the boundary condition.
// PageList.diagram ->
//
//       +--+ = PAGE 0
//   ... :  :
//      +-----+ ACTIVE
// 15744 |  | | 0
// 15745 |  | | 1
// 15746 |  | | 2
// 15747 |  | | 3
// 15748 |  | | 4
// 15749 |  | | 5
// 15750 |  | | 6
// 15751 |  | | 7
// 15752 |01… | 8
//       +--+ :
//       +--+ : = PAGE 1
//     0 …01| | 9
//       +--+ :
//      +-----+
// We expect one fewer rows since we unwrapped a row.
// Resize
// PageList.diagram ->
//
//      +----+ = PAGE 0
//  ... :    :
//      +----+
//      +----+ = PAGE 1
//  ... :    :
//     +-------+ ACTIVE
// 6272 |    | | 0
// 6273 |    | | 1
// 6274 |    | | 2
// 6275 |    | | 3
// 6276 |    | | 4
// 6277 |    | | 5
// 6278 |    | | 6
// 6279 |    | | 7
// 6280 |    | | 8
// 6281 |0101| | 9
//      +----+ :
//     +-------+
// PAGE 1 ROW 6280, ACTIVE 8
// PAGE 1 ROW 6281, ACTIVE 9
// Grow to the capacity of the first page.
// At this point, we have some rows on the first page, and some on the second.
// We can now wrap across the boundary condition.
// Put a tracked pin in wrapped row on the last page
// We expect one fewer rows since we unwrapped a row.
// Resize
// Our cursor should move to the first row
// Grow to the capacity of the first page.
// At this point, we have some rows on the first page, and some on the second.
// We can now wrap across the boundary condition.
// Put a tracked pin in wrapped row on the last page
// PageList.diagram ->
//
//      +-----+ = PAGE 0
//  ... :     :
//     +--------+ ACTIVE
// 7892 |     | | 0
// 7893 |     | | 1
// 7894 |     | | 2
// 7895 |     | | 3
// 7896 |01234… | 4
//      +-----+ :
//      +-----+ : = PAGE 1
//    0 …01234| | 5
//      :  ^  : : = PIN 0
//    1 |     | | 6
//    2 |     | | 7
//    3 |     | | 8
//    4 |     | | 9
//      +-----+ :
//     +--------+
// Resize
// PageList.diagram ->
//
//      +----+ = PAGE 0
//  ... :    :
//     +-------+ ACTIVE
// 7892 |    | | 0
// 7893 |    | | 1
// 7894 |    | | 2
// 7895 |    | | 3
// 7896 |0123… | 4
// 7897 …4012… | 5
//      :   ^: : = PIN 0
// 7898 …3400| | 6
// 7899 |    | | 7
// 7900 |    | | 8
// 7901 |    | | 9
//      +----+ :
//     +-------+
// Our cursor should remain on the same cell
// PAGE 0 ROW 7895, ACTIVE 3
// PAGE 0 ROW 7896, ACTIVE 4
// PAGE 0 ROW 7897, ACTIVE 5
// PAGE 0 ROW 7898, ACTIVE 6
// PAGE 0 ROW 7899, ACTIVE 7
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Resize
// Grow to the capacity of the first page and add
// one more row so that we have two pages total.
// We now have two pages.
// We use almost all string alloc capacity with a hyperlink in the final
// row of the first page, and do the same on the first row of the second
// page. We also mark the row as wrapped so that when we resize with more
// cols the row unwraps and we have a single row that requires almost two
// times the base string alloc capacity.
//
// This forces the reflow to increase capacity.
//
//  +--+ = PAGE 0
//  :  :
//  | X… <- where X is hyperlinked with almost all string cap.
//  +--+
//  +--+ = PAGE 1
//  …X | <- X here also almost hits string cap with a hyperlink.
//  +--+
// Almost hit string alloc cap in bottom right of first page.
// Mark the final row as wrapped.
// Almost hit string alloc cap in top left of second page.
// Mark the first row as a wrap continuation.
// Resize to 1 column wider, unwrapping the row.
// Grow to the capacity of the first page and add
// one more row so that we have two pages total.
// We now have two pages.
// We use almost all grapheme alloc capacity with a grapheme in the final
// row of the first page, and do the same on the first row of the second
// page. We also mark the row as wrapped so that when we resize with more
// cols the row unwraps and we have a single row that requires almost two
// times the base grapheme alloc capacity.
//
// This forces the reflow to increase capacity.
//
//  +--+ = PAGE 0
//  :  :
//  | X… <- where X is a grapheme which uses almost all the capacity.
//  +--+
//  +--+ = PAGE 1
//  …X | <- X here also almost hits grapheme cap.
//  +--+
// Almost hit grapheme alloc cap in bottom right of first page.
// Mark the final row as wrapped.
// Almost hit grapheme alloc cap in top left of second page.
// Mark the first row as a wrap continuation.
// Resize to 1 column wider, unwrapping the row.
// Grow to the capacity of the first page and add
// one more row so that we have two pages total.
// We now have two pages.
// Give each cell in the final row of the first page a unique style.
// Mark the final row as wrapped.
// Do the same for the first row of the second page.
// Mark the first row as a wrap continuation.
// Resize to twice as wide, fully unwrapping the row.
// Resize
// Resize
// Resize
// Resize
// Resize
// Resize
// Resize
// Resize
// Active moves due to scrollback
// First row should be wrapped
// First row should be wrapped
// Resize
// Active moves due to scrollback
// First row should be wrapped
// First row should be wrapped
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Resize
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Put a tracked pin in the history
// Resize
// Our cursor should not move
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Put a tracked pin in the history
// Resize
// Our cursor should move to the first row
// Resize
// First row should be wrapped
// Resize
// Resize
// Grow blank rows to push our rows back into scrollback
// Put a tracked pin in the history
// Resize
// Important: not on last row
// Our cursor should move to the first row
// Create a style
// We're over-counted by 1 because `add` implies `use`.
// Resize
// Resize
// Resize
// We want to make the screen look like this:
//
// 👨‍👨‍👦‍👦👨‍👨‍👦‍👦
// First family emoji at (0, 0)
// Second family emoji at (2, 0)
// Resize
// Row should be wrapped
// Write unicode placeholders
// Resize
// Write unicode placeholders
// Resize smaller then larger
// Write unicode placeholders
// Active area should be the top
// Find a cap that makes it so that rows don't fit on one page.
// Init
// Create a tracked pin into the active area
// Our added pin should now be garbage
// Viewport pin should not be garbage because it makes sense.
// Active area should be the top
// This test verifies that when reflowing content with many graphemes,
// the grapheme map capacity is correctly increased when needed.
// Get the grapheme capacity from the page. We need more than this many
// graphemes in a single destination page to trigger capacity increase
// during reflow. Since each source page can only hold this many graphemes,
// we create two source pages with graphemes that will merge into one
// destination page.
// Use slightly more than half the capacity per page, so combined they
// exceed the capacity of a single destination page.
// Grow to the capacity of the first page and add more rows
// so that we have two pages total.
// We now have two pages.
// Add graphemes to both pages. We add graphemes to rows at the END of the
// first page, and graphemes to rows at the START of the second page.
// When reflowing to 2 columns, these rows will wrap and stay together
// on the same destination page, requiring capacity increase.
// Add graphemes to the end of the first page (last rows)
// Add graphemes to the beginning of the second page
// Resize to fewer columns to trigger reflow.
// The graphemes from both pages will be copied to destination pages.
// They will all end up in a contiguous region of the destination.
// If the bug exists (hyperlink_bytes increased instead of grapheme_bytes),
// this will fail with GraphemeMapOutOfMemory when we exceed capacity.
// Verify the resize succeeded
// Regression test: after resize/reflow, the viewport pin can end up at a
// position where pin.y + rows > total_rows, causing getBottomRight to panic.
// The plan is to pin viewport in history, then grow columns to unwrap rows.
// The unwrap reduces total_rows, but the tracked pin moves to a position
// that no longer has enough rows below it for the viewport height.
// Make sure we have some history, in this case we have 30 rows of history
// Fill all rows with wrapped content (pairs that unwrap when cols increase)
// Pin viewport at row 28 (in history, 2 rows before active area at row 30).
// After unwrap: row 28 -> row 14, total_rows 40 -> 20, active starts at 10.
// Pin at 14 needs rows 14-23, but only 0-19 exist -> overflow.
// Resize with reflow: unwraps rows, reducing total_rows
// Used to panic here, so test that we can get the bottom right.
// Create a PageList with 3 * std_size max so we can fit multiple pages
// but will still trigger reuse.
// Increase the first page capacity to make it non-standard (larger than std_size).
// The first page should now have non-standard memory size.
// First, fill up the first page's capacity
// Now grow to create a second page
// Continue growing until we exceed max_size AND the last page is full
// The first page should still be non-standard
// Verify we have enough rows for active area (so prune path isn't skipped)
// Verify last page is full (so grow will need to allocate/reuse)
// Remember the first page memory pointer before the reuse attempt
// Create a tracked pin pointing to the non-standard first page
// Now grow one more time to trigger the reuse path. Since the first page
// is non-standard, it should be destroyed (not reused). The testing
// allocator will detect a leak if destroyNode doesn't properly free
// the non-standard memory.
// After grow, check if the first page is a different one
// (meaning the non-standard page was pruned, not reused at the end)
// The original first page should no longer be the first page
// If the non-standard page was properly destroyed and not reused,
// the last page should not have the same memory pointer
// The tracked pin should have been moved to the new first page and marked as garbage
// This test specifically verifies the fix for the bug where pruning a
// non-standard page would cause totalRows() < self.rows.
//
// Bug trigger conditions (all must be true simultaneously):
// 1. first page is non-standard (memory.len > std_size)
// 2. page_size + PagePool.item_size > maxSize() (triggers prune consideration)
// 3. pages.first != pages.last (have multiple pages)
// 4. total_rows >= self.rows (have enough rows for active area)
// 5. total_rows - first.size.rows + 1 < self.rows (prune would lose too many)
// This is kind of magic and likely depends on std_size.
// Make the first page non-standard
// Fill first page to capacity
// Grow until we have a second page (first page fills up first)
// Fill the second page to capacity so that the next grow() triggers prune
// Now the last page is full. The next grow must either:
// 1. Prune the first page and reuse it, OR
// 2. Allocate a new page
// Verify the bug condition is present: pruning first page would leave < rows
// Verify prune path conditions are met
// Verify last page is at capacity (so grow must prune or allocate new)
// The next grow should trigger prune consideration.
// Without the fix, this would destroy the non-standard first page,
// leaving only second_cap + 1 rows, which is < self.rows.
// Verify the invariant holds - the fix prevents the destructive prune
// Regression test: when resizeWithoutReflowGrowCols copies rows to a previous
// page with spare capacity, tracked pins in those rows must be remapped.
// Without the fix, pins become dangling pointers when the original page is destroyed.
// Grow until we have two pages.
// Trim a history row so the first page has spare capacity.
// This triggers the backfill path in resizeWithoutReflowGrowCols.
// Ensure the resize takes the slow path (new capacity > current capacity).
// Track a pin in row 0 of the second page. This row will be copied
// to the first page during backfill and the pin must be remapped.
// Write a marker character to the tracked cell so we can verify
// the pin points to the correct cell after resize.
// Verify the pin points to a valid node still in the page list.
// Verify the pin still points to the cell with our marker content.
// A freshly created page should be at std_size
// compact should return null since there's nothing to compact
// Page should still be the same
// Grow until we have multiple pages
// Write content to verify it's preserved
// Create a tracked pin on this page
// Make the page oversized
// Set dirty flag after increaseCapacity
// Compact the page
// Verify memory is smaller
// Verify size preserved
// Verify dirty flag preserved
// Verify linked list integrity
// Verify pin updated correctly
// Verify content preserved
// Make the page slightly oversized (just one increase)
// This might not provide enough savings to justify compaction
// If the page is still at or below std_size, compact returns null
// If it did grow beyond std_size, verify that compaction
// works or returns null based on savings calculation
// Either it compacted or determined insufficient savings
// Write content to rows: row 0 gets codepoint 0, row 1 gets 1, etc.
// Split at row 5 (middle)
// Verify two pages exist
// First page should have rows 0-4 (5 rows)
// Second page should have rows 5-9 (5 rows)
// Verify content in first page is preserved (rows 0-4 have codepoints 0-4)
// Verify content in second page (original rows 5-9, now at y=0-4)
// Write content to all rows
// Split at row 0 should be a no-op
// Verify only one page exists (no split occurred)
// Verify all content is still in the original page
// Write content to all rows
// Split at last row (row 9)
// Verify two pages exist
// First page should have 9 rows
// Second page should have 1 row
// Verify content in second page (original row 9, now at y=0)
// Initialize with 1 row
// Track a pin at row 7
// Split at row 5
// The tracked pin should now be in the second page
// y should be adjusted: was 7, split at 5, so new y = 7 - 5 = 2
// x should remain unchanged
// Track a pin at row 2 (before the split point)
// Split at row 5
// The tracked pin should remain in the original page
// y and x should be unchanged
// Track a pin at the exact split point (row 5)
// Split at row 5
// The tracked pin should be in the new page
// y should be 0 since it was at the split point: 5 - 5 = 0
// x should remain unchanged
// Track multiple pins in different regions
// Split at row 5
// Pin before split point stays in original page
// Pin at split point moves to new page with y=0
// Pins after split point move to new page with adjusted y
// Set viewport_pin to row 7 (after split point)
// Split at row 5
// viewport_pin should be in the new page
// y should be adjusted: 7 - 5 = 2
// x should remain unchanged
// Create a single page with 12 rows
// Split at row 4 to create: page1 (rows 0-3), page2 (rows 4-11)
// Now we have 2 pages
// Split page2 at row 4 to create: page1 -> page2 (rows 0-3) -> page3 (rows 4-7)
// Now we have 3 pages
// Verify linked list order: first -> middle -> last
// Verify prev pointers
// Verify next pointers
// Verify row counts
// Create a single page with 10 rows
// Split to create 2 pages first
// Now split the last page
// The new page should be the new last
// Verify row counts: original last has 2 rows, new last has 3 rows
// Create 2 pages by splitting
// Get second page (created by first split)
// Now split the first page again
// Original first should still be first
// New page should be inserted between first and second
// Verify row counts: first has 2, inserted has 3, second has 5
// Set wrap flags on rows that will be in the second page after split
// Row 5: wrap = true (this is the start of a wrapped line)
// Row 6: wrap_continuation = true (this continues the wrap)
// Row 7: wrap = true, wrap_continuation = true (wrapped and continues)
// Split at row 5
// Verify wrap flags are preserved in new page
// Original row 5 is now row 0 in second page
// Original row 6 is now row 1 in second page
// Original row 7 is now row 2 in second page
// Create a style and apply it to cells in rows 5-7 (which will be in the second page)
// Release the extra ref from add
// Split at row 5
// First page should have no styles (all styled rows moved to second page)
// Second page should have exactly 1 style (the bold style, used by 3 cells)
// Verify styled cells are preserved in new page
// Add a grapheme cluster to row 6 (will be row 1 in second page after split at 5)
// Split at row 5
// First page should have no graphemes (the grapheme row moved to second page)
// Second page should have exactly 1 grapheme
// Verify grapheme is preserved in new page (original row 6 is now row 1)
// Add a hyperlink to row 7 (will be row 2 in second page after split at 5)
// Split at row 5
// First page should have no hyperlinks (the hyperlink row moved to second page)
// Second page should have exactly 1 hyperlink
// Verify hyperlink is preserved in new page (original row 7 is now row 2)
//
// --- Original Ghostty Comments End: src/terminal/PageList.zig

// PageList manages a doubly-linked list of Pages forming the terminal
// screen buffer with scrollback, viewport management, and text reflow.
// Translated from Ghostty's PageList.zig.

// ============================================================
// Direction for iterators
// ============================================================

pub enum IterDirection as u8 {
	left_up
	right_down
}

// ============================================================
// PageViewport - where the viewport is positioned
// ============================================================

pub enum PageViewport as u8 {
	active // Pinned to active area (bottom)
	top    // Pinned to top of scrollback
	pin    // Pinned to a tracked pin
}

// ============================================================
// Pin - a position within the PageList
// ============================================================

pub struct Pin {
pub mut:
	node    &PageNode = unsafe { nil }
	y       u16  // Row index within the page
	x       u16  // Column index within the row
	garbage bool // Set true if tracked pin was pruned
}

// Selects which part of a pin's row is returned by cells. The left and
// right subsets both include the cell at the pin.
pub enum PinCellSubset as u8 {
	all
	left
	right
}

// Returns the row and cell at this pin's position.
pub fn (self Pin) row_and_cell() RowAndCell {
	assert !isnil(self.node)
	assert self.y < self.node.data.size.rows
	assert self.x < self.node.data.size.cols
	row := unsafe { &self.node.data.rows[int(self.y)] }
	return RowAndCell{
		row:  row
		cell: unsafe { &row.cells[int(self.x)] }
	}
}

// Returns the cells for this pin's row. Left and right are inclusive of x.
pub fn (self Pin) cells(subset PinCellSubset) []CellData {
	rac := self.row_and_cell()
	all := rac.row.cells[..int(self.node.data.size.cols)]
	return match subset {
		.all { all }
		.left { all[..int(self.x) + 1] }
		.right { all[int(self.x)..] }
	}
}

// Returns the extra codepoints for a grapheme cell. The cell's first
// codepoint remains stored directly on the cell and is not returned here.
pub fn (self Pin) grapheme(cell &CellData) ?[]u32 {
	return self.node.data.lookup_grapheme(cell)
}

// Returns the resolved style for a cell on this pin's page.
pub fn (self Pin) style(cell &CellData) CellStyle {
	if cell.style_id == default_style_id {
		return CellStyle{}
	}
	return self.node.data.styles.get(cell.style_id)
}

// Returns the row data at this pin's position.
pub fn (self Pin) row_data() &RowData {
	return self.row_and_cell().row
}

// Returns the cell data at this pin's position.
pub fn (self Pin) cell_data() &CellData {
	return self.row_and_cell().cell
}

// Returns true if the row at this pin is dirty.
pub fn (self Pin) is_dirty() bool {
	return self.node.data.dirty || self.node.data.rows[int(self.y)].header.dirty
}

// Mark the row at this pin as dirty.
pub fn (self Pin) mark_dirty() {
	unsafe {
		self.node.data.rows[int(self.y)].header.dirty = true
	}
}

// Returns true if pins reference the same position.
pub fn (self Pin) eql(other Pin) bool {
	p := voidptr(self.node)
	q := voidptr(other.node)
	return p == q && self.y == other.y && self.x == other.x
}

// Returns true if self is before other in the linked list.
// This is O(N) - must traverse the linked list.
pub fn (self Pin) before(other Pin) bool {
	p := voidptr(self.node)
	q := voidptr(other.node)
	if p == q {
		if self.y < other.y {
			return true
		}
		if self.y == other.y {
			return self.x < other.x
		}
		return false
	}
	// Traverse forward from self to see if we find other
	mut node := self.node.next
	for {
		n := node or { return false }
		if voidptr(n) == q {
			return true
		}
		node = n.next
	}
	return false
}

// Returns true if self is between top and bottom (inclusive).
pub fn (self Pin) is_between(top_pin Pin, bottom_pin Pin) bool {
	$if !prod {
		if voidptr(top_pin.node) == voidptr(bottom_pin.node) {
			assert top_pin.y <= bottom_pin.y
			if top_pin.y == bottom_pin.y {
				assert top_pin.x <= bottom_pin.x
			}
		} else {
			assert top_pin.before(bottom_pin)
		}
	}

	if voidptr(self.node) == voidptr(top_pin.node) {
		if self.y < top_pin.y {
			return false
		}
		if self.y > top_pin.y {
			return if voidptr(self.node) == voidptr(bottom_pin.node) {
				self.y <= bottom_pin.y
			} else {
				true
			}
		}
		assert self.y == top_pin.y
		if self.x < top_pin.x {
			return false
		}
	}
	if voidptr(self.node) == voidptr(bottom_pin.node) {
		if self.y > bottom_pin.y {
			return false
		}
		if self.y < bottom_pin.y {
			return true
		}
		assert self.y == bottom_pin.y
		return self.x <= bottom_pin.x
	}

	if voidptr(top_pin.node) == voidptr(bottom_pin.node) {
		return false
	}
	mut node := top_pin.node.next
	for {
		n := node or { break }
		if voidptr(n) == voidptr(bottom_pin.node) {
			break
		}
		if voidptr(n) == voidptr(self.node) {
			return true
		}
		node = n.next
	}
	return false
}

// ---- Movement methods ----

// Move left by n columns (asserts n <= x).
pub fn (self Pin) left(n uint) Pin {
	assert n <= uint(self.x), 'Pin.left: n=${n} > x=${self.x}'
	mut result := self
	result.x -= u16(n)
	return result
}

// Move right by n columns (asserts fits in row).
pub fn (self Pin) right(n uint) Pin {
	assert uint(self.x) + n < uint(self.node.data.size.cols), 'Pin.right: overflow'
	mut result := self
	result.x += u16(n)
	return result
}

// Move left, clamping at 0.
pub fn (self Pin) left_clamp(n u16) Pin {
	mut result := self
	result.x = if n > self.x { u16(0) } else { self.x - n }
	return result
}

// Move right, clamping at end of row.
pub fn (self Pin) right_clamp(n u16) Pin {
	mut result := self
	max_x := self.node.data.size.cols - 1
	sum := u32(self.x) + u32(n)
	result.x = if sum > u32(max_x) { max_x } else { u16(sum) }
	return result
}

// Move left by n cells, wrapping to preceding rows as needed.
// Returns none if the movement goes beyond the start of the page list.
pub fn (self Pin) left_wrap(n uint) ?Pin {
	cols := uint(self.node.data.size.cols)
	remaining_in_row := uint(self.x)
	if n <= remaining_in_row {
		return self.left(n)
	}

	extra_after_remaining := n - remaining_in_row
	rows_off := 1 + extra_after_remaining / cols
	mut result := self.up(rows_off) or { return none }
	result.x = u16(cols - extra_after_remaining % cols)
	return result
}

// Move right by n cells, wrapping to following rows as needed.
// Returns none if the movement goes beyond the end of the page list.
pub fn (self Pin) right_wrap(n uint) ?Pin {
	cols := uint(self.node.data.size.cols)
	remaining_in_row := cols - uint(self.x) - 1
	if n <= remaining_in_row {
		return self.right(n)
	}

	extra_after_remaining := n - remaining_in_row
	rows_off := 1 + extra_after_remaining / cols
	mut result := self.down(rows_off) or { return none }
	result.x = u16(extra_after_remaining % cols - 1)
	return result
}

// Move down by n rows, crossing page boundaries. Returns none if overflow.
pub fn (self Pin) down(n uint) ?Pin {
	result := self.down_overflow(n)
	return match result {
		DownOverflowOffset { result.pin }
		DownOverflowOverflow { none }
	}
}

// Move up by n rows, crossing page boundaries. Returns none if overflow.
pub fn (self Pin) up(n uint) ?Pin {
	result := self.up_overflow(n)
	return match result {
		UpOverflowOffset { result.pin }
		UpOverflowOverflow { none }
	}
}

// DownOverflow result
pub struct DownOverflowOffset {
pub:
	pin Pin
}

pub struct DownOverflowOverflow {
pub:
	end       Pin
	remaining uint
}

pub type DownOverflowResult = DownOverflowOffset | DownOverflowOverflow

// Move down by n, returning overflow info if past end.
pub fn (self Pin) down_overflow(n uint) DownOverflowResult {
	mut rem := n
	mut node := self.node
	mut y := uint(self.y)

	// Try within current page
	avail := uint(node.data.size.rows) - y - 1
	if rem <= avail {
		return DownOverflowOffset{
			pin: Pin{
				node: node
				y:    u16(y + rem)
				x:    self.x
			}
		}
	}
	rem -= avail

	// Traverse forward
	mut last_node := node
	mut next := node.next
	for {
		nd := next or {
			return DownOverflowOverflow{
				end:       Pin{
					node: last_node
					y:    u16(last_node.data.size.rows - 1)
					x:    self.x
				}
				remaining: rem
			}
		}
		if rem <= uint(nd.data.size.rows) {
			return DownOverflowOffset{
				pin: Pin{
					node: nd
					y:    u16(rem - 1)
					x:    self.x
				}
			}
		}
		rem -= uint(nd.data.size.rows)
		unsafe {
			last_node = nd
		}
		next = nd.next
	}
	// unreachable
	return DownOverflowOverflow{
		end:       Pin{
			node: last_node
			y:    u16(last_node.data.size.rows - 1)
			x:    self.x
		}
		remaining: rem
	}
}

// UpOverflow result
pub struct UpOverflowOffset {
pub:
	pin Pin
}

pub struct UpOverflowOverflow {
pub:
	end       Pin
	remaining uint
}

pub type UpOverflowResult = UpOverflowOffset | UpOverflowOverflow

// Move up by n, returning overflow info if past beginning.
pub fn (self Pin) up_overflow(n uint) UpOverflowResult {
	mut rem := n
	mut y := uint(self.y)

	// Try within current page
	if rem <= y {
		return UpOverflowOffset{
			pin: Pin{
				node: self.node
				y:    u16(y - rem)
				x:    self.x
			}
		}
	}
	rem -= y

	// Traverse backward
	mut first_node := self.node
	mut prev := self.node.prev
	for {
		nd := prev or {
			return UpOverflowOverflow{
				end:       Pin{
					node: first_node
					y:    0
					x:    self.x
				}
				remaining: rem
			}
		}
		if rem <= uint(nd.data.size.rows) {
			return UpOverflowOffset{
				pin: Pin{
					node: nd
					y:    u16(uint(nd.data.size.rows) - rem)
					x:    self.x
				}
			}
		}
		rem -= uint(nd.data.size.rows)
		unsafe {
			first_node = nd
		}
		prev = nd.prev
	}
	return UpOverflowOverflow{
		end:       Pin{
			node: first_node
			y:    0
			x:    self.x
		}
		remaining: rem
	}
}

// ---- Pin iterator factories ----

pub fn (self Pin) page_iterator(direction IterDirection, limit ?Pin) PageIterator {
	$if !prod {
		if lim := limit {
			match direction {
				.right_down {
					assert self.eql(lim) || self.before(lim)
				}
				.left_up {
					assert self.eql(lim) || lim.before(self)
				}
			}
		}
	}
	return PageIterator{
		row:       self
		direction: direction
		limit:     if lim := limit {
			PageIteratorLimit(PageIteratorLimitRow{
				pin: lim
			})
		} else {
			PageIteratorLimit(PageIteratorLimitNone{})
		}
	}
}

pub fn (self Pin) row_iterator(direction IterDirection, limit ?Pin) RowIterator {
	mut page_it := self.page_iterator(direction, limit)
	chunk := page_it.next() or {
		return RowIterator{
			page_it: page_it
		}
	}
	return RowIterator{
		page_it: page_it
		chunk:   chunk
		offset:  match direction {
			.right_down { chunk.start }
			.left_up { chunk.end - 1 }
		}
	}
}

pub fn (self Pin) cell_iterator(direction IterDirection, limit ?Pin) CellIterator {
	mut row_it := self.row_iterator(direction, limit)
	mut cell := row_it.next() or {
		return CellIterator{
			row_it: row_it
		}
	}
	cell.x = self.x
	return CellIterator{
		row_it: row_it
		cell:   cell
	}
}

pub fn (self Pin) prompt_iterator(direction IterDirection, limit ?Pin) PromptIterator {
	return PromptIterator{
		current:   self
		limit:     limit
		direction: direction
	}
}

// ============================================================
// PageCell - return type for get_cell
// ============================================================

pub struct PageCell {
pub:
	node    &PageNode = unsafe { nil }
	row     &RowData  = unsafe { nil }
	cell    &CellData = unsafe { nil }
	row_idx u16
	col_idx u16
}

// Returns true if this cell is marked as dirty.
//
// This is not very performant; it is primarily used for assertions and
// testing.
pub fn (self &PageCell) is_dirty() bool {
	return self.node.data.dirty || self.row.header.dirty
}

// Get the cell style.
//
// Not meant for non-test usage since this is inefficient.
pub fn (self &PageCell) style() CellStyle {
	if self.cell.style_id == default_style_id {
		return CellStyle{}
	}
	return self.node.data.styles.get(self.cell.style_id)
}

// Convert to screen point (absolute row from top of page list).
// Traverses backward through the page list to compute the absolute y
// coordinate from the top of the entire page list.
pub fn (self &PageCell) screen_point() Point {
	mut y := self.row_idx

	// Traverse backward through the linked list to accumulate rows
	// from all preceding pages.
	mut prev := self.node.prev
	for {
		nd := prev or { break }
		y += nd.data.size.rows
		prev = nd.prev
	}

	return Point.new(.screen, Coordinate{
		x: self.col_idx
		y: u32(y)
	})
}

// ============================================================
// PageScroll - scroll behavior
// ============================================================

pub struct PageScrollActive {}

pub struct PageScrollTop {}

pub struct PageScrollRow {
pub:
	n uint
}

pub struct PageScrollDeltaRow {
pub:
	delta int
}

pub struct PageScrollDeltaPrompt {
pub:
	delta int
}

pub struct PageScrollPin {
pub:
	pin Pin
}

pub type PageScroll = PageScrollActive
	| PageScrollTop
	| PageScrollRow
	| PageScrollDeltaRow
	| PageScrollDeltaPrompt
	| PageScrollPin

// ============================================================
// Scrollbar
// ============================================================

pub struct Scrollbar {
pub:
	total  uint
	offset uint
	len    uint
}

pub const scrollbar_zero = Scrollbar{
	total:  0
	offset: 0
	len:    0
}

// Sync with ghostty_action_scrollbar_s.
pub struct ScrollbarC {
pub:
	total  u64
	offset u64
	len    u64
}

pub fn (self Scrollbar) cval() ScrollbarC {
	return ScrollbarC{
		total:  u64(self.total)
		offset: u64(self.offset)
		len:    u64(self.len)
	}
}

pub fn (self Scrollbar) eql(other Scrollbar) bool {
	return self.total == other.total && self.offset == other.offset && self.len == other.len
}

// ============================================================
// PageCloneOpts
// ============================================================

pub struct PageCloneOpts {
pub:
	// Top and bottom are inclusive. Their x coordinate is ignored; cloning
	// always copies complete rows.
	top Point @[required]
	bot ?Point
	// When set, tracked pins inside the cloned region are recreated and the
	// old-to-new pointer mapping is recorded here.
	tracked_pins &PageTrackedPinsRemap = unsafe { nil }
}

pub struct PageTrackedPinsRemap {
mut:
 table lib_allocator.PointerHashMap[&Pin, &Pin]
}

pub fn PageTrackedPinsRemap.init() PageTrackedPinsRemap {
 return PageTrackedPinsRemap.init_alloc(lib_allocator.c_allocator_value())
}

pub fn PageTrackedPinsRemap.init_alloc(allocator lib_allocator.Allocator) PageTrackedPinsRemap {
 return PageTrackedPinsRemap{table: lib_allocator.PointerHashMap[&Pin, &Pin]{allocator: allocator}}
}

pub fn (mut self PageTrackedPinsRemap) deinit() { self.table.deinit() }

pub fn (self &PageTrackedPinsRemap) get(old_pin &Pin) ?&Pin { return self.table.get(old_pin) }

fn (mut self PageTrackedPinsRemap) put_no_clobber(old_pin &Pin, new_pin &Pin) ! {
 self.table.put_no_clobber(old_pin, new_pin)!
}

// ============================================================
// PageResizeOpts
// ============================================================

pub struct PageResizeOpts {
pub:
	cols   ?u16
	rows   ?u16
	reflow bool = true
	cursor ?PageResizeCursor
}

pub struct PageResizeCursor {
pub:
	x u16
	y u16
	// A tracked live cursor preserves the cells leading up to it during reflow.
	pin ?&Pin
}

// ============================================================
// Iterator types
// ============================================================

// ---- PageIterator ----

pub struct PageIteratorLimitNone {}

pub struct PageIteratorLimitCount {
pub mut:
	count uint
}

pub struct PageIteratorLimitRow {
pub:
	pin Pin
}

pub type PageIteratorLimit = PageIteratorLimitNone | PageIteratorLimitCount | PageIteratorLimitRow

pub struct PageIterator {
pub mut:
	row       ?Pin
	direction IterDirection     = .right_down
	limit     PageIteratorLimit = PageIteratorLimit(PageIteratorLimitNone{})
}

pub struct PageChunk {
pub:
	node  &PageNode = unsafe { nil }
	start u16 // Inclusive
	end   u16 // Exclusive
}

// Return the rows represented by this contiguous page chunk.
pub fn (self PageChunk) rows() []RowData {
	return self.node.data.rows[int(self.start)..int(self.end)]
}

// Return true when this chunk represents every live row in its page.
pub fn (self PageChunk) full_page() bool {
	return self.start == 0 && self.end == self.node.data.size.rows
}

// Return true when two chunks cover any of the same rows.
pub fn (self PageChunk) overlaps(other PageChunk) bool {
	if voidptr(self.node) != voidptr(other.node) {
		return false
	}
	if self.end <= other.start {
		return false
	}
	if self.start >= other.end {
		return false
	}
	return true
}

pub fn (mut self PageIterator) next() ?PageChunk {
	return match self.direction {
		.right_down { self.next_down() }
		.left_up { self.next_up() }
	}
}

fn (mut self PageIterator) next_down() ?PageChunk {
	cur := self.row or { return none }

	node := cur.node
	page_rows := node.data.size.rows

	start := cur.y

	match self.limit {
		PageIteratorLimitNone {
			// Consume entire page from start
			self.row = if next := node.next {
				Pin{
					node: next
					y:    0
					x:    0
				}
			} else {
				none
			}
			return PageChunk{
				node:  node
				start: start
				end:   page_rows
			}
		}
		PageIteratorLimitCount {
			assert self.limit.count > 0
			remaining := uint(page_rows - start)
			len := if remaining < self.limit.count { remaining } else { self.limit.count }
			if len > self.limit.count {
				self.row = cur.down(len)
				self.limit.count -= len
			} else {
				self.row = none
			}
			return PageChunk{
				node:  node
				start: start
				end:   start + u16(len)
			}
		}
		PageIteratorLimitRow {
			lim := self.limit as PageIteratorLimitRow
			lim_node := voidptr(lim.pin.node)
			cur_node := voidptr(node)
			if cur_node == lim_node {
				// Same page as limit
				end := lim.pin.y + 1 // inclusive
				self.row = none
				if end <= start {
					return none
				}
				return PageChunk{
					node:  node
					start: start
					end:   end
				}
			}
			// Different page, consume to end
			self.row = if next := node.next {
				Pin{
					node: next
					y:    0
					x:    0
				}
			} else {
				none
			}
			return PageChunk{
				node:  node
				start: start
				end:   page_rows
			}
		}
	}
}

fn (mut self PageIterator) next_up() ?PageChunk {
	cur := self.row or { return none }

	node := cur.node
	end := cur.y + 1 // exclusive

	match self.limit {
		PageIteratorLimitNone {
			self.row = if prev := node.prev {
				Pin{
					node: prev
					y:    u16(prev.data.size.rows - 1)
					x:    0
				}
			} else {
				none
			}
			return PageChunk{
				node:  node
				start: 0
				end:   end
			}
		}
		PageIteratorLimitCount {
			assert self.limit.count > 0
			row := uint(cur.y)
			len := if row < self.limit.count { row } else { self.limit.count }
			if len > self.limit.count {
				self.row = cur.up(len)
				self.limit.count -= len
			} else {
				self.row = none
			}
			return PageChunk{
				node:  node
				start: cur.y - u16(len)
				end:   cur.y - 1
			}
		}
		PageIteratorLimitRow {
			lim := self.limit as PageIteratorLimitRow
			lim_node := voidptr(lim.pin.node)
			cur_node := voidptr(node)
			if cur_node == lim_node {
				start := lim.pin.y
				self.row = none
				if start >= end {
					return none
				}
				return PageChunk{
					node:  node
					start: start
					end:   end
				}
			}
			self.row = if prev := node.prev {
				Pin{
					node: prev
					y:    u16(prev.data.size.rows - 1)
					x:    0
				}
			} else {
				none
			}
			return PageChunk{
				node:  node
				start: 0
				end:   end
			}
		}
	}
}

// ---- RowIterator ----

pub struct RowIterator {
pub mut:
	page_it PageIterator
	chunk   ?PageChunk
	offset  u16
}

pub fn (mut self RowIterator) next() ?Pin {
	ch := self.chunk or { return none }
	result := Pin{
		node: ch.node
		y:    self.offset
		x:    0
	}

	match self.page_it.direction {
		.right_down {
			self.offset += 1
			if self.offset >= ch.end {
				self.chunk = self.page_it.next()
				if next_chunk := self.chunk {
					self.offset = next_chunk.start
				}
			}
		}
		.left_up {
			if self.offset == 0 {
				self.chunk = self.page_it.next()
				if next_chunk := self.chunk {
					self.offset = next_chunk.end - 1
				}
			} else if self.offset == ch.start {
				self.chunk = none
			} else {
				self.offset -= 1
			}
		}
	}

	return result
}

// ---- CellIterator ----

pub struct CellIterator {
pub mut:
	row_it RowIterator
	cell   ?Pin
}

pub fn (mut self CellIterator) next() ?Pin {
	c := self.cell or { return none }
	result := c

	match self.row_it.page_it.direction {
		.right_down {
			if c.x + 1 < c.node.data.size.cols {
				mut copy := c
				copy.x += 1
				self.cell = copy
			} else {
				self.cell = self.row_it.next()
			}
		}
		.left_up {
			if c.x > 0 {
				mut copy := c
				copy.x -= 1
				self.cell = copy
			} else {
				if next_cell := self.row_it.next() {
					mut copy := next_cell
					copy.x = next_cell.node.data.size.cols - 1
					self.cell = copy
				} else {
					self.cell = none
				}
			}
		}
	}

	return result
}

// ---- PromptIterator ----

pub struct PromptIterator {
pub mut:
	current   ?Pin
	limit     ?Pin
	direction IterDirection = .left_up
}

pub fn (mut self PromptIterator) next() ?Pin {
	return match self.direction {
		.right_down { self.next_right_down() }
		.left_up { self.next_left_up() }
	}
}

pub fn (mut self PromptIterator) next_right_down() ?Pin {
	start := self.current or { return none }
	mut current := ?Pin(start)
	for {
		p := current or { break }
		at_limit := if limit := self.limit { limit.eql(p) } else { false }
		match p.row_data().header.semantic_prompt {
			.unknown {
				if at_limit {
					break
				}
			}
			.prompt, .prompt_continuation {
				if at_limit {
					self.current = none
					return p.left(p.x)
				}

				mut end_pin := p
				for {
					next_pin := end_pin.down(1) or { break }
					match next_pin.row_data().header.semantic_prompt {
						.prompt_continuation {
							if limit := self.limit {
								if limit.eql(next_pin) {
									break
								}
							}
						}
						.prompt, .unknown {
							self.current = next_pin
							return p.left(p.x)
						}
					}
					end_pin = next_pin
				}

				self.current = none
				return p.left(p.x)
			}
		}
		current = p.down(1)
	}
	self.current = none
	return none
}

pub fn (mut self PromptIterator) next_left_up() ?Pin {
	start := self.current or { return none }
	mut current := ?Pin(start)
	for {
		p := current or { break }
		at_limit := if limit := self.limit { limit.eql(p) } else { false }
		match p.row_data().header.semantic_prompt {
			.unknown {
				if at_limit {
					break
				}
			}
			.prompt {
				self.current = if at_limit { none } else { p.up(1) }
				return p.left(p.x)
			}
			.prompt_continuation {
				if at_limit {
					self.current = none
					return p.left(p.x)
				}

				mut end_pin := p
				for {
					prior := end_pin.up(1) or { break }
					if limit := self.limit {
						if limit.eql(prior) {
							break
						}
					}
					match prior.row_data().header.semantic_prompt {
						.unknown {
							self.current = prior
							return end_pin.left(end_pin.x)
						}
						.prompt_continuation {}
						.prompt {
							self.current = prior.up(1)
							return prior.left(prior.x)
						}
					}
					end_pin = prior
				}

				self.current = none
				return p.left(p.x)
			}
		}
		current = p.up(1)
	}
	self.current = none
	return none
}

// ============================================================
// PageList struct
// ============================================================

@[heap]
pub struct PageList {
pub mut:
	// Source-owned arena pools for nodes, standard page blocks, and pins.
	pool MemoryPool
	// The linked list of pages.
	pages PageNodeList

	// Monotonically increasing serial for page allocation.
	page_serial     u64
	page_serial_min u64

	// Logical Zig backing-allocation byte size.
	page_size uint

	// Max size for scrollback (0 = no scrollback).
	explicit_max_size uint
	min_max_size      uint

	// Total rows across all pages.
	total_rows uint

	// Tracked pins that auto-update during modifications.
	tracked_pins_storage []&Pin
	tracked_pins_set lib_allocator.PointerArraySet[&Pin]

	// Viewport state.
	viewport                PageViewport = .active
	viewport_pin            &Pin         = unsafe { nil }
	viewport_pin_row_offset ?uint

	// Current desired screen dimensions.
	cols u16
	rows u16

	// A nesting counter used by multi-step mutations that temporarily leave
	// the page list inconsistent.
	pause_integrity_checks uint
}

// ============================================================
// Init / Deinit / Reset
// ============================================================

enum PageListInitFailPoint as u8 {
	init_memory_pool
	init_pages
	viewport_pin
	viewport_pin_track
}

enum PageListInitPagesFailPoint as u8 {
	page_node
	page_buf_std
	page_buf_non_std
}

struct PageListInitTripwires {
mut:
	init       tripwire.TripwireModule[PageListInitFailPoint]
	init_pages tripwire.TripwireModule[PageListInitPagesFailPoint]
}

const page_list_init_tripwires = &PageListInitTripwires{}

fn page_list_init_tripwire() &tripwire.TripwireModule[PageListInitFailPoint] {
	return unsafe { &page_list_init_tripwires.init }
}

fn page_list_init_pages_tripwire() &tripwire.TripwireModule[PageListInitPagesFailPoint] {
	return unsafe { &page_list_init_tripwires.init_pages }
}

struct PageListInitialPages {
	pages       PageNodeList
	page_serial u64
	page_size   uint
	total_rows  uint
}

// initPages only owns non-standard buffers; pool deinit releases pooled
// nodes/standard blocks on the enclosing error path.
fn cleanup_initial_pages(pool &MemoryPool, pages PageNodeList) {
	mut current := pages.first
	for {
		node := current or { break }
		current = node.next
		if uint(node.data.memory.len) > standard_page_size() {
			pool.pages.arena.child_allocator.free_bytes(node.data.memory.data,
				uint(node.data.memory.len), page_pool_alignment_log(), 0)
		}
	}
}

fn page_pool_alignment_log() u8 {
	mut alignment := u8(0)
	for (uint(1) << alignment) < page_memory_alignment() { alignment++ }
	return alignment
}

fn init_pages(mut pool MemoryPool, serial &u64, cols u16, rows u16) !PageListInitialPages {
	mut tw := page_list_init_pages_tripwire()
	cap := initial_capacity(cols)
	layout := Page.layout(cap)
	assert layout.total_size <= uint(max_page_size)
	pooled := layout.total_size <= standard_page_size()
	mut page_list := PageNodeList{}
	mut page_size := uint(0)
	mut rem := rows
	mut ready := false
	defer { if !ready { cleanup_initial_pages(&pool, page_list) } }
	for rem > 0 {
		tw.check(.page_node)!
		mut node := pool.nodes.create()!
		mut node_ready := false
		defer { if !node_ready { pool.nodes.destroy(node) } }
		tw.check(if pooled { .page_buf_std } else { .page_buf_non_std })!
		mut buffer := unsafe { nil }
		if pooled {
			buffer = pool.pages.create()!
		} else {
			buffer = pool.pages.arena.child_allocator.alloc_bytes(layout.total_size, page_pool_alignment_log(), 0)
			if isnil(buffer) { return error('OutOfMemory') }
		}
		length := if pooled { standard_page_size() } else { layout.total_size }
		if buildcfg.runtime_safety { unsafe { vmemset(buffer, 0, int(length)) } }
		serial_value := unsafe { *serial }
		unsafe { *node = PageNode{data: Page.init_buf(OffsetBuf.init(&u8(buffer)), layout), serial: serial_value} }
		node.data.memory = lib_allocator.borrowed_array[u8](buffer, int(length), int(length))
		node.data.size.rows = if rem < node.data.capacity.rows { rem } else { node.data.capacity.rows }
		rem -= node.data.size.rows
		page_list.append(node)
		page_size += length
		unsafe { *serial = *serial + 1 }
		node_ready = true
	}
	assert page_list.first != none
	ready = true
	return PageListInitialPages{pages: page_list, page_serial: unsafe { *serial }, page_size: page_size, total_rows: uint(rows)}
}

pub fn PageList.init(cols u16, rows u16, max_size ?uint) !PageList {
	return PageList.init_alloc(lib_allocator.c_allocator_value(), page_list_page_allocator(), cols, rows, max_size)
}

// Exposes the original general/page allocator injection for failure tests and
// embedders. The default entry selects the source's platform page allocator.
pub fn PageList.init_alloc(allocator lib_allocator.Allocator, page_allocator lib_allocator.Allocator, cols u16, rows u16, max_size ?uint) !PageList {
	mut tw := page_list_init_tripwire()
	tw.check(.init_memory_pool)!
	mut pool := MemoryPool.init(allocator, page_allocator, 4)!
	mut pool_ready := false
	defer { if !pool_ready { pool.deinit() } }
	tw.check(.init_pages)!
	mut serial := u64(0)
	initial := init_pages(mut pool, &serial, cols, rows)!
	// The original outer pool errdefer owns pooled buffers through later errors.
	tw.check(.viewport_pin)!
	mut viewport_pin := pool.pins.create()!
	unsafe { *viewport_pin = Pin{node: initial.pages.first or { panic('unreachable empty initial page list') }} }
	mut tracked := lib_allocator.PointerArraySet[&Pin]{}
	mut tracked_ready := false
	defer { if !tracked_ready { tracked.deinit(pool.alloc) } }
	tw.check(.viewport_pin_track)!
	tracked.put_no_clobber(pool.alloc, viewport_pin)!
	result := PageList{
		pool: pool, cols: cols, rows: rows, pages: initial.pages,
		page_serial: serial, page_serial_min: 0, page_size: initial.page_size,
		explicit_max_size: max_size or { max_usize }, min_max_size: min_max_size_calc(cols, rows),
		total_rows: uint(rows), tracked_pins_set: tracked, tracked_pins_storage: tracked.keys,
		viewport: .active, viewport_pin: viewport_pin, viewport_pin_row_offset: none
	}
	pool_ready = true
	tracked_ready = true
	result.assert_integrity()
	return result
}

pub fn (mut self PageList) deinit() {
	self.assert_integrity()
	self.tracked_pins_set.deinit(self.pool.alloc)
	cleanup_initial_pages(&self.pool, self.pages)
	self.pool.deinit()
}

pub fn (mut self PageList) reset() {
	defer { self.assert_integrity() }
	cap := initial_capacity(self.cols)
	assert cap.rows > 0
	page_count := (uint(self.rows) + uint(cap.rows) - 1) / uint(cap.rows)
	cleanup_initial_pages(&self.pool, self.pages)
	self.pool.pages.reset(lib_allocator.ArenaResetMode{kind: .retain_with_limit, limit: page_count * self.pool.pages.item_size})
	self.pool.nodes.reset(lib_allocator.ArenaResetMode{kind: .retain_with_limit, limit: page_count * self.pool.nodes.raw.item_size})
	self.pool.pages.arena.zero_payloads()
	initial := init_pages(mut self.pool, &self.page_serial, self.cols, self.rows) or { panic('initPages failed') }
	self.pages = initial.pages
	self.page_size = initial.page_size
	self.total_rows = uint(self.rows)
	first := self.pages.first or { panic('unreachable empty reset page list') }
	for mut p in self.tracked_pins_storage {
		p.node = first
		p.x = 0
		p.y = 0
		p.garbage = true
	}
	self.viewport_pin.garbage = false
	self.viewport = .active
}

// ============================================================
// Helpers
// ============================================================

const max_usize = ~uint(0)

fn initial_capacity(cols u16) PageCapacity {
	return std_capacity.adjust(PageCapacityAdjustment{ cols: cols }) or {
		mut cap := std_capacity
		cap.cols = cols
		cap
	}
}

fn standard_page_size() uint {
	return Page.layout(std_capacity).total_size
}

// Ghostty's pool always dispenses a full standard-sized backing block. Only
// pages whose exact layout exceeds that block are allocated at their own size.
fn page_backing_size(cap PageCapacity) uint {
	size := Page.layout(cap).total_size
	standard := standard_page_size()
	return if size <= standard { standard } else { size }
}

fn min_max_size_calc(cols u16, rows u16) uint {
	cap := initial_capacity(cols)
	pages_for_active := if cap.rows >= rows {
		uint(1)
	} else {
		(uint(rows) + uint(cap.rows) - 1) / uint(cap.rows)
	}
	// Always need at least one extra page
	pages := pages_for_active + 1
	return pages * standard_page_size()
}

pub fn (self &PageList) max_size() uint {
	if self.explicit_max_size > self.min_max_size {
		return self.explicit_max_size
	}
	return self.min_max_size
}

// ============================================================
// Page creation / destruction
// ============================================================

fn (mut self PageList) create_page(cap PageCapacity) !&PageNode {
	mut page := self.pool.nodes.create()!
	mut ready := false
	defer { if !ready { self.pool.nodes.destroy(page) } }
	layout := Page.layout(cap)
	pooled := layout.total_size <= standard_page_size()
	assert layout.total_size <= uint(max_page_size)
	mut buffer := unsafe { nil }
	if pooled {
		buffer = self.pool.pages.create()!
	} else {
		buffer = self.pool.pages.arena.child_allocator.alloc_bytes(layout.total_size, page_pool_alignment_log(), 0)
		if isnil(buffer) { return error('OutOfMemory') }
	}
	length := if pooled { standard_page_size() } else { layout.total_size }
	if buildcfg.runtime_safety { unsafe { vmemset(buffer, 0, int(length)) } }
	unsafe { *page = PageNode{data: Page.init_buf(OffsetBuf.init(&u8(buffer)), layout), serial: self.page_serial} }
	page.data.memory = lib_allocator.borrowed_array[u8](buffer, int(length), int(length))
	page.data.size.rows = 0
	self.page_serial++
	self.page_size += length
	ready = true
	return page
}

fn (mut self PageList) destroy_node(node &PageNode) {
	self.page_size -= uint(node.data.memory.len)
	if uint(node.data.memory.len) <= standard_page_size() {
		unsafe { vmemset(node.data.memory.data, 0, node.data.memory.len) }
		self.pool.pages.destroy(node.data.memory.data)
	} else {
		self.pool.pages.arena.child_allocator.free_bytes(node.data.memory.data,
			uint(node.data.memory.len), page_pool_alignment_log(), 0)
	}
	self.pool.nodes.destroy(node)
}

// V cannot compose Result and Option return types directly.
pub struct PageNodeOption {
pub:
	node ?&PageNode
}

// ============================================================
// Grow
// ============================================================

// Grow the active area by one row. Returns the new node if one was allocated.
pub fn (mut self PageList) grow() !PageNodeOption {
	defer { self.assert_integrity() }
	// Fast path: last page has capacity
	mut last_page := self.pages.last or { panic('page list has no last page') }
	if last_page.data.capacity.rows > last_page.data.size.rows {
		last_page.data.size.rows += 1
		last_page.data.assert_integrity()
		self.total_rows += 1
		return PageNodeOption{}
	}

	// Need a new page
	cap := initial_capacity(self.cols)

	// Check if we need to prune for max size
	first := self.pages.first or { panic('page list has no first page') }
	last := self.pages.last or { panic('page list has no last page') }
	if voidptr(first) != voidptr(last)
		&& self.page_size + standard_page_size() > self.max_size() {
		// Prune the first page
		pruned := self.pages.pop_first() or { panic('page list has no first page') }

		self.total_rows -= uint(pruned.data.size.rows)

		// Check if pruning would violate minimum rows
		if self.total_rows + 1 < uint(self.rows) {
			// Can't prune, put it back
			self.pages.prepend(pruned)
			self.total_rows += uint(pruned.data.size.rows)
		} else {
			// Update viewport if needed
			if self.viewport == .pin {
				if v := self.viewport_pin_row_offset {
					if v < uint(pruned.data.size.rows) {
						self.viewport = .top
					} else {
						self.viewport_pin_row_offset = v - uint(pruned.data.size.rows)
					}
				}
			}

			// Update tracked pins pointing to pruned page
			new_first := self.pages.first or { panic('pruning left the page list empty') }
			for mut p in self.tracked_pins_storage {
				if voidptr(p.node) == voidptr(pruned) {
					p.node = new_first
					p.y = 0
					p.x = 0
					p.garbage = true
				}
			}
			self.viewport_pin.garbage = false

			old_backing_size := page_backing_size(pruned.data.capacity)
			if old_backing_size <= standard_page_size() {
				// Standard pages reuse the fixed-size pooled allocation.
				unsafe {
					mut mp := pruned
					mp.data.capacity = cap
					mp.data.reinit()
					mp.data.size.rows = 1
					self.page_serial_min = mp.serial + 1
					mp.serial = self.page_serial
				}
				self.page_serial += 1
				self.pages.append(pruned)
				self.total_rows += 1
				pruned.data.assert_integrity()

				return PageNodeOption{ node: pruned }
			}

			// A non-standard page cannot enter Ghostty's fixed-size pool. Its
			// backing is released and the standard page below is newly allocated.
			self.destroy_node(pruned)
		}
	}

	// Allocate new page
	mut new_node := self.create_page(cap)!
	new_node.data.size.rows = 1
	self.pages.append(new_node)
	self.total_rows += 1
	new_node.data.assert_integrity()

	return PageNodeOption{ node: new_node }
}

// Grow by n rows (convenience for tests).
pub fn (mut self PageList) grow_rows(n uint) ! {
	for _ in 0 .. n {
		_ = self.grow()!
	}
}

// ============================================================
// Get top-left / bottom-right
// ============================================================

pub fn (self &PageList) get_top_left(tag PointTag) Pin {
	match tag {
		.screen, .history {
			node := self.pages.first or { panic('page list has no first page') }
			return Pin{
				node: node
				y:    0
				x:    0
			}
		}
		.viewport {
			return match self.viewport {
				.active { self.get_top_left(.active) }
				.top { self.get_top_left(.screen) }
				.pin { *self.viewport_pin }
			}
		}
		.active {
			// Walk backward from last page to find active area start
			mut rem := uint(self.rows)
			mut node := self.pages.last
			for {
				n := node or { break }
				if uint(n.data.size.rows) >= rem {
					return Pin{
						node: n
						y:    u16(uint(n.data.size.rows) - rem)
						x:    0
					}
				}
				rem -= uint(n.data.size.rows)
				node = n.prev
			}
			panic('page list has fewer rows than its active area')
		}
	}
}

pub fn (self &PageList) get_bottom_right(tag PointTag) ?Pin {
	match tag {
		.screen, .active {
			last := self.pages.last or { panic('page list has no last page') }
			return Pin{
				node: last
				y:    u16(last.data.size.rows - 1)
				x:    last.data.size.cols - 1
			}
		}
		.viewport {
			tl := self.get_top_left(.viewport)
			p := tl.down(uint(self.rows) - 1) or {
				panic('viewport has fewer rows than the active area')
			}
			return Pin{
				node: p.node
				y:    p.y
				x:    p.node.data.size.cols - 1
			}
		}
		.history {
			active_tl := self.get_top_left(.active)
			p := active_tl.up(1) or { return none }
			return Pin{
				node: p.node
				y:    p.y
				x:    p.node.data.size.cols - 1
			}
		}
	}
}

// Return the untracked page pin for a tagged point. The coordinate is
// relative to the point's active, viewport, screen, or history origin.
pub fn (self &PageList) pin(point Point) ?Pin {
	if u32(point.coord().x) >= u32(self.cols) {
		return none
	}
	mut result := self.get_top_left(point.tag()).down(uint(point.coord().y)) or { return none }
	result.x = point.coord().x
	return result
}

// Returns the debug diagram Ghostty uses to inspect page boundaries, the
// active area, wraps, and tracked pins.
pub fn (self &PageList) diagram() !string {
	active_pin := self.get_top_left(.active)
	mut active := false
	mut active_index := uint(0)
	mut page_index := uint(0)
	mut cols := uint(0)
	mut out := strings.new_builder(int(self.total_rows) * (int(self.cols) + 16))

	mut current := self.pages.first
	for {
		node := current or { break }
		cols = uint(node.data.size.cols)
		mut skipped := false
		for y in 0 .. int(node.data.size.rows) {
			if !active && voidptr(node) == voidptr(active_pin.node) && y == int(active_pin.y) {
				active = true
				out.write_string('     +-')
				out.write_string('-'.repeat(int(cols)))
				out.write_string('--+ ACTIVE\n')
			}

			if y == 0 {
				out.write_string('      +')
				out.write_string('-'.repeat(int(cols)))
				out.write_u8(u8(`+`))
				if active {
					out.write_string(' :')
				}
				out.write_string(' = PAGE ${page_index}\n')
			}

			row := node.data.rows[y]
			cells := row.cells[..int(cols)]
			row_has_content := has_text_any(cells)
			if !active && !row_has_content {
				if !skipped {
					out.write_string('  ... :')
					out.write_string(' '.repeat(int(cols)))
					out.write_string(':\n')
				}
				skipped = true
				continue
			}

			skipped = false
			out.write_string('${y:5} ')
			out.write_string(if row.header.wrap_continuation { '…' } else { '|' })
			if row_has_content {
				for x, cell in cells {
					if cell.wide == .spacer_tail {
						continue
					}
					if cell.codepoint < u32(` `) {
						out.write_u8('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[int(cell.codepoint)])
					} else {
						out.write_rune(rune(cell.codepoint))
						if cell.has_grapheme() {
							graphemes := node.data.lookup_grapheme_at(uint(y), uint(x)) or {
								panic('grapheme cell is missing its page mapping')
							}
							for cp in graphemes {
								out.write_rune(rune(cp))
							}
						}
					}
				}
			} else {
				out.write_string(' '.repeat(int(cols)))
			}
			out.write_string(if row.header.wrap { '…' } else { '|' })
			if active {
				out.write_string(' | ${active_index}')
				active_index += 1
			}
			out.write_u8(u8(`\n`))

			mut pins := []&Pin{}
			for pin in self.tracked_pins_storage {
				if voidptr(pin.node) == voidptr(node) && pin.y == u16(y) {
					pins << pin
					if pins.len >= 16 {
						return error('too many tracked pins in row')
					}
				}
			}
			if pins.len > 0 {
				pins.sort(a.x < b.x)
				out.write_string('      :')
				mut x := uint(0)
				for pin in pins {
					if x > uint(pin.x) {
						continue
					}
					out.write_string(' '.repeat(int(uint(pin.x) - x)))
					out.write_u8(u8(`^`))
					x = uint(pin.x) + 1
				}
				out.write_string(' '.repeat(int(cols - x)))
				out.write_u8(u8(`:`))
				if active {
					out.write_string(' :')
				}
				out.write_string(if pins.len > 1 { ' = PINS' } else { ' = PIN' })
				first_x := pins[0].x
				for i, pin in pins {
					if pin.x != first_x {
						out.write_u8(u8(`,`))
					}
					out.write_string(' ${i}')
				}
				out.write_u8(u8(`\n`))
			}
		}

		out.write_string('      +')
		out.write_string('-'.repeat(int(cols)))
		out.write_u8(u8(`+`))
		if active {
			out.write_string(' :')
		}
		out.write_u8(u8(`\n`))
		page_index += 1
		current = node.next
	}

	out.write_string('     +-')
	out.write_string('-'.repeat(int(cols)))
	out.write_string('--+\n')
	return out.str()
}

// PageSemanticHighlight is an untracked semantic-content range. Callers that
// need the range to survive page mutations must track both pins themselves.
pub struct PageSemanticHighlight {
pub mut:
	start Pin
	end   Pin
}

// Returns the boundaries of semantic content belonging to the prompt at `at`.
// The pin must be on the first row of a prompt, as returned by PromptIterator.
pub fn (self &PageList) highlight_semantic_content(at Pin, content SemanticContent) ?PageSemanticHighlight {
	mut prompt_it := at.prompt_iterator(.right_down, none)
	first := prompt_it.next() or { panic('semantic highlight pin is not on a prompt') }
	assert first.y == at.y

	zone_end := if next := prompt_it.next() {
		mut previous := next.up(1) or { next }
		previous.x = previous.node.data.size.cols - 1
		previous
	} else {
		self.get_bottom_right(.screen) or { panic('page list has no bottom-right pin') }
	}

	match content {
		.prompt {
			mut result := PageSemanticHighlight{
				start: at.left(at.x)
				end:   at
			}
			mut it := at.cell_iterator(.right_down, zone_end)
			for {
				p := it.next() or { break }
				match p.cell_data().semantic_content {
					.prompt, .input {
						result.end = p
					}
					.output {
						break
					}
				}
			}
			return result
		}
		.input {
			mut result_start := ?Pin(none)
			mut result_end := Pin{}
			mut it := at.cell_iterator(.right_down, zone_end)
			for {
				p := it.next() or { return none }
				match p.cell_data().semantic_content {
					.prompt {}
					.input {
						result_start = p
						result_end = p
						break
					}
					.output {
						return none
					}
				}
			}

			for {
				p := it.next() or { break }
				match p.cell_data().semantic_content {
					.prompt {}
					.output {
						break
					}
					.input {
						result_end = p
					}
				}
			}
			return PageSemanticHighlight{
				start: result_start or { return none }
				end:   result_end
			}
		}
		.output {
			mut result_start := ?Pin(none)
			mut result_end := Pin{}
			mut it := at.cell_iterator(.right_down, zone_end)
			for {
				p := it.next() or { return none }
				cell := p.cell_data()
				match cell.semantic_content {
					.prompt, .input {}
					.output {
						if !cell.has_text() {
							continue
						}
						result_start = p
						result_end = p
						break
					}
				}
			}

			for {
				p := it.next() or { break }
				cell := p.cell_data()
				match cell.semantic_content {
					.prompt, .input {
						break
					}
					.output {
						if cell.has_text() {
							result_end = p
						}
					}
				}
			}
			return PageSemanticHighlight{
				start: result_start or { return none }
				end:   result_end
			}
		}
	}
}

// ============================================================
// Pin / Track Pin
// ============================================================

// Track a pin so it auto-updates during modifications.
pub fn (mut self PageList) track_pin(p Pin) !&Pin {
	if buildcfg.slow_runtime_safety { assert self.pin_is_valid(p) }
	mut tracked := self.pool.pins.create()!
	mut ready := false
	defer { if !ready { self.pool.pins.destroy(tracked) } }
	unsafe { *tracked = p }
	self.tracked_pins_set.put_no_clobber(self.pool.alloc, tracked)!
	self.tracked_pins_storage = self.tracked_pins_set.keys
	ready = true
	return tracked
}

pub fn (mut self PageList) untrack_pin(p &Pin) {
	assert voidptr(p) != voidptr(self.viewport_pin)
	if self.tracked_pins_set.swap_remove(p) {
		self.pool.pins.destroy(p)
		self.tracked_pins_storage = self.tracked_pins_set.keys
	}
}

pub fn (self &PageList) count_tracked_pins() uint {
	return uint(self.tracked_pins_storage.len)
}

// Returns a borrowed view that remains valid only until the PageList changes.
pub fn (self &PageList) tracked_pins() []&Pin {
	return self.tracked_pins_storage
}

// Returns true if pin points to a valid page in the list.
pub fn (self &PageList) pin_is_valid(p Pin) bool {
	mut node := self.pages.first
	for {
		n := node or { return false }
		if voidptr(n) == voidptr(p.node) {
			return p.y < n.data.size.rows && p.x < n.data.size.cols
		}
		node = n.next
	}
	return false
}

// Convert a pin to a point in the given coordinate space.
pub fn (self &PageList) point_from_pin(tag PointTag, p Pin) ?Point {
	tl := self.get_top_left(tag)

	tl_ptr := voidptr(tl.node)
	p_ptr := voidptr(p.node)

	if tl_ptr == p_ptr {
		if tl.y > p.y {
			return none
		}
		return Point.new(tag, Coordinate{
			x: p.x
			y: u32(p.y - tl.y)
		})
	}

	// Traverse from tl forward to find p's node
	mut y := u32(tl.node.data.size.rows) - u32(tl.y)
	mut cur := tl.node.next
	for {
		node := cur or { return none }
		if voidptr(node) == p_ptr {
			return Point.new(tag, Coordinate{
				x: p.x
				y: y + u32(p.y)
			})
		}
		y += u32(node.data.size.rows)
		cur = node.next
	}
	return none
}

// Returns true if the pin is in the active area.
pub fn (self &PageList) pin_is_active(p Pin) bool {
	active_tl := self.get_top_left(.active)
	active_ptr := voidptr(active_tl.node)
	p_ptr := voidptr(p.node)

	if active_ptr == p_ptr {
		return p.y >= active_tl.y
	}

	// Check if p.node is after active_tl.node
	mut cur := active_tl.node.next
	for {
		node := cur or { return false }
		if voidptr(node) == p_ptr {
			return true
		}
		cur = node.next
	}
	return false
}

// Returns true if the pin is at the very top.
fn (self &PageList) pin_is_top(p Pin) bool {
	first := self.pages.first or { return false }
	return voidptr(p.node) == voidptr(first) && p.y == 0
}

// ============================================================
// Get Cell
// ============================================================

pub fn (self &PageList) get_cell(point Point) ?PageCell {
	p := self.pin(point) or { return none }
	rac := p.row_and_cell()
	return PageCell{
		node:    p.node
		row:     rac.row
		cell:    rac.cell
		row_idx: p.y
		col_idx: p.x
	}
}

// ============================================================
// Total pages / rows
// ============================================================

pub fn (self &PageList) total_pages() uint {
	mut count := uint(0)
	mut node := self.pages.first
	for {
		n := node or { break }
		count += 1
		node = n.next
	}
	return count
}

// Count total rows by traversal (for testing).
pub fn (self &PageList) count_total_rows() uint {
	mut count := uint(0)
	mut node := self.pages.first
	for {
		n := node or { break }
		count += uint(n.data.size.rows)
		node = n.next
	}
	return count
}

// ============================================================
// Scroll
// ============================================================

pub fn (mut self PageList) scroll(behavior PageScroll) {
	defer { self.assert_integrity() }

	// No-scrollback mode
	if self.explicit_max_size == 0 {
		self.viewport = .active
		return
	}

	match behavior {
		PageScrollActive {
			self.viewport = .active
		}
		PageScrollTop {
			self.viewport = .top
		}
		PageScrollPin {
			p := (behavior as PageScrollPin).pin
			if self.pin_is_active(p) {
				self.viewport = .active
				return
			}
			if self.pin_is_top(p) {
				self.viewport = .top
				return
			}
			unsafe { *self.viewport_pin = p }
			self.viewport = .pin
			self.viewport_pin_row_offset = none
		}
		PageScrollRow {
			n := (behavior as PageScrollRow).n
			if n == 0 {
				self.viewport = .top
				return
			}
			if n >= self.total_rows - uint(self.rows) {
				self.viewport = .active
				return
			}

			match self.viewport {
				.top, .active {}
				.pin {
					if cached := self.viewport_pin_row_offset {
						delta := int(n) - int(cached)
						self.scroll(PageScrollDeltaRow{ delta: delta })
						return
					}
				}
			}

			self.viewport_pin_row_offset = n
			self.viewport = .pin

			midpoint := self.total_rows / 2
			if n < midpoint {
				if n > uint(max_u16) {
					self.viewport = .active
					return
				}
				mut rem := u16(n)
				mut node := self.pages.first
				for {
					nd := node or { break }
					if rem < nd.data.size.rows {
						unsafe {
							*self.viewport_pin = Pin{
								node: nd
								y:    rem
							}
						}
						return
					}
					rem -= nd.data.size.rows
					node = nd.next
				}
			} else {
				distance := self.total_rows - n
				if distance > uint(max_u16) {
					self.viewport = .active
					return
				}
				mut rem := u16(distance)
				mut node := self.pages.last
				for {
					nd := node or { break }
					if rem <= nd.data.size.rows {
						unsafe {
							*self.viewport_pin = Pin{
								node: nd
								y:    nd.data.size.rows - rem
							}
						}
						return
					}
					rem -= nd.data.size.rows
					node = nd.prev
				}
			}
			self.viewport = .active
		}
		PageScrollDeltaRow {
			delta := (behavior as PageScrollDeltaRow).delta
			if delta == 0 {
				return
			}

			match self.viewport {
				.top {
					if delta <= 0 {
						return
					}
				}
				.active {
					if delta >= 0 {
						return
					}
				}
				.pin {
					if delta < 0 {
						abs_delta := uint(-delta)
						result := self.viewport_pin.up_overflow(abs_delta)
						match result {
							UpOverflowOffset {
								unsafe { *self.viewport_pin = result.pin }
								if v := self.viewport_pin_row_offset {
									self.viewport_pin_row_offset = v - uint(abs_delta)
								}
								return
							}
							UpOverflowOverflow {
								self.viewport = .top
								return
							}
						}
					} else if delta > 0 {
						abs_delta := uint(delta)
						result := self.viewport_pin.down_overflow(abs_delta)
						match result {
							DownOverflowOffset {
								if self.pin_is_active(result.pin) {
									self.viewport = .active
								} else {
									unsafe { *self.viewport_pin = result.pin }
									if v := self.viewport_pin_row_offset {
										self.viewport_pin_row_offset = v + uint(abs_delta)
									}
								}
								return
							}
							DownOverflowOverflow {
								self.viewport = .active
								return
							}
						}
					}
					return
				}
			}

			// Slow path: calculate from viewport top
			tl := self.get_top_left(.viewport)
			p := if delta < 0 {
				result := tl.up_overflow(uint(-delta))
				match result {
					UpOverflowOffset {
						result.pin
					}
					UpOverflowOverflow {
						result.end
					}
				}
			} else {
				result := tl.down_overflow(uint(delta))
				match result {
					DownOverflowOffset {
						result.pin
					}
					DownOverflowOverflow {
						result.end
					}
				}
			}

			if self.pin_is_active(p) {
				self.viewport = .active
				return
			}
			if self.pin_is_top(p) {
				self.viewport = .top
				return
			}
			unsafe { *self.viewport_pin = p }
			self.viewport = .pin
			self.viewport_pin_row_offset = none
		}
		PageScrollDeltaPrompt {
			delta := (behavior as PageScrollDeltaPrompt).delta
			self.scroll_prompt(delta)
		}
	}
}

fn (mut self PageList) scroll_prompt(delta int) {
	if delta == 0 {
		return
	}
	abs_delta := if delta > 0 { uint(delta) } else { uint(-delta) }
	mut rem := abs_delta

	tl := self.get_top_left(.viewport)
	start_opt := if delta > 0 { tl.down(1) } else { tl.up(1) }
	start := start_opt or { return }

	mut it := start.prompt_iterator(if delta > 0 { .right_down } else { .left_up }, none)
	mut prompt_pin := ?Pin(none)
	for {
		next := it.next() or { break }
		prompt_pin = next
		rem -= 1
		if rem == 0 {
			break
		}
	}

	if p := prompt_pin {
		if self.pin_is_active(p) {
			self.viewport = .active
		} else {
			unsafe { *self.viewport_pin = p }
			self.viewport = .pin
			self.viewport_pin_row_offset = none
		}
	}
}

// ============================================================
// Scroll Clear
// ============================================================

// Scroll written content into scrollback. Does not update viewport.
pub fn (mut self PageList) scroll_clear() ! {
	defer { self.assert_integrity() }

	mut page := self.pages.last or { panic('page list has no last page') }
	mut n := uint(0)
	mut non_empty := uint(0)
	mut done := false
	for {
		for i in 0 .. int(page.data.size.rows) {
			reverse_i := int(page.data.size.rows) - i - 1
			row := page.data.rows[reverse_i]
			cells := row.cells[..int(self.cols)]
			for cell in cells {
				if !cell.is_empty() {
					non_empty = uint(self.rows) - n
					done = true
					break
				}
			}
			if done {
				break
			}

			n += 1
			if n > uint(self.rows) {
				non_empty = 0
				done = true
				break
			}
		}
		if done {
			break
		}

		page = page.prev or {
			break
		}
	}

	for _ in 0 .. non_empty {
		_ = self.grow()!
	}
}

// ============================================================
// Scrollbar
// ============================================================

pub fn (mut self PageList) scrollbar() Scrollbar {
	if self.explicit_max_size == 0 {
		return Scrollbar{
			total:  uint(self.rows)
			offset: 0
			len:    uint(self.rows)
		}
	}
	return Scrollbar{
		total:  self.total_rows
		offset: self.viewport_row_offset()
		len:    uint(self.rows)
	}
}

fn (mut self PageList) viewport_row_offset() uint {
	match self.viewport {
		.top {
			return 0
		}
		.active {
			return self.total_rows - uint(self.rows)
		}
		.pin {
			defer { self.assert_integrity() }
			if v := self.viewport_pin_row_offset {
				return v
			}

			mut offset := uint(0)
			mut node := self.pages.last
			for {
				n := node or { panic('viewport pin is outside the page list') }
				offset += uint(n.data.size.rows)
				if voidptr(n) == voidptr(self.viewport_pin.node) {
					assert n.data.size.rows > self.viewport_pin.y
					offset -= uint(self.viewport_pin.y)
					top_offset := self.total_rows - offset
					self.viewport_pin_row_offset = top_offset
					return top_offset
				}
				node = n.prev
			}
		}
	}
	panic('invalid viewport state')
}

// ============================================================
// Erase Row
// ============================================================

// Erase a single row, shifting subsequent rows up.
pub fn (mut self PageList) erase_row(point Point) ! {
	defer { self.assert_integrity() }
	pn := self.pin(point) or { panic('erase row point is outside the page list') }

	mut node := pn.node

	// In order to move the following rows up we rotate the rows array by 1.
	// The rotate operation turns e.g. [ 0 1 2 3 ] in to [ 1 2 3 0 ], which
	// works perfectly to move all of our elements where they belong.
	mut rows := unsafe { node.data.rows[int(pn.y)..int(node.data.size.rows)] }
	rotate_row_views(mut rows, false)

	// We adjust the tracked pins in this page, moving up any that were below
	// the removed row.
	for mut p in self.tracked_pins_storage {
		if voidptr(p.node) == voidptr(node) && p.y > pn.y {
			p.y -= 1
		}
	}

	// If we have a pinned viewport, we need to adjust for active area.
	self.fixup_viewport(1)

	// Mark the whole page as dirty.
	//
	// Technically we only need to mark rows from the erased row to the end
	// of the page as dirty, but that's slower and this is a hot function.
	node.data.dirty = true

	// We iterate through all of the following pages in order to move their
	// rows up by 1 as well.
	for {
		mut next := node.next or { break }

		// We take the top row of the page and clone it in to the bottom
		// row of the previous page, which gets rid of the top row that was
		// rotated down in the previous page, and accounts for the row in
		// this page that will be rotated down as well.
		//
		//  rotate -> clone --> rotate -> result
		//    0 -.      1         1         1
		//    1  |      2         2         2
		//    2  |      3         3         3
		//    3 <'      0 <.      4         4
		//   ---       --- |     ---       ---  <- page boundary
		//    4         4 -'      4 -.      5
		//    5         5         5  |      6
		//    6         6         6  |      7
		//    7         7         7 <'      4
		node.data.clone_row_from(&next.data, node.data.size.rows - 1, 0)!

		node = next

		mut next_rows := unsafe { node.data.rows[..int(node.data.size.rows)] }
		rotate_row_views(mut next_rows, false)

		// Mark the whole page as dirty.
		node.data.dirty = true

		// Our tracked pins for this page need to be updated.
		// If the pin is in row 0 that means the corresponding row has
		// been moved to the previous page. Otherwise, move it up by 1.
		for mut p in self.tracked_pins_storage {
			if voidptr(p.node) != voidptr(node) {
				continue
			}
			if p.y == 0 {
				p.node = node.prev or { panic('page after the erased row has no previous page') }
				p.y = p.node.data.size.rows - 1
				continue
			}
			p.y -= 1
		}
	}

	// Clear the final row which was rotated from the top of the page.
	node.data.clear_cells(node.data.size.rows - 1, 0, node.data.size.cols)
}

// ============================================================
// Erase Rows
// ============================================================

// Erase a range of rows from tl to bl (inclusive).
pub fn (mut self PageList) erase_rows(tl Point, bl ?Point) {
	defer { self.assert_integrity() }

	// Count rows to erase
	mut erased := uint(0)
	mut it := self.page_iterator(.right_down, tl, bl)
	for {
		chunk := it.next() or { break }

		if chunk.full_page() {
			// A rare special case is that we're deleting everything in
			// our linked list. erase_page requires at least one other
			// page so to handle this we reinit this page, set it to zero
			// size which will let us grow our active area back.
			if chunk.node.next == none && chunk.node.prev == none {
				mut page := &chunk.node.data
				erased += uint(page.size.rows)
				page.reinit()
				page.size.rows = 0
				break
			}

			erased += uint(chunk.node.data.size.rows)
			self.erase_page(chunk.node)
			continue
		}

		// We are modifying our chunk so make sure it is in a good state.
		assert chunk.start == 0
		mut page := &chunk.node.data
		end := int(chunk.end)
		scroll_amount := int(page.size.rows) - end

		// The chunk is not a full page so we need to move the rows.
		// This is a cheap operation because we're just moving cell offsets,
		// not the actual cell contents.
		for i in 0 .. scroll_amount {
			page.swap_rows(i, i + end)

			// Mark the moved row as dirty.
			page.rows[i].header.dirty = true
		}

		// Clear our remaining cells that we didn't shift or swapped
		// in case we grow back into them.
		for i in scroll_amount .. int(page.size.rows) {
			page.clear_cells(u16(i), 0, page.size.cols)
		}

		// Update any tracked pins to shift their y. If it was in the erased
		// row then we move it to the top of this page.
		for mut tp in self.tracked_pins_storage {
			if voidptr(tp.node) == voidptr(chunk.node) {
				if tp.y >= u16(end) {
					tp.y -= u16(end)
				} else {
					tp.y = 0
					tp.x = 0
				}
			}
		}

		page.size.rows = u16(scroll_amount)
		erased += uint(end)
		page.assert_integrity()
	}

	self.total_rows -= erased

	// If we deleted active, we need to regrow because one of our invariants
	// is that we always have full active space.
	if tl.tag() == .active {
		for _ in 0 .. erased {
			_ = self.grow() or {
				eprintln('failed to regrow active area after erase err=${err}')
				return
			}
		}
	}

	// If we have a pinned viewport, we need to adjust for active area.
	self.fixup_viewport(erased)
}

// ============================================================
// Split
// ============================================================

// Split a page at the given pin, creating a new page for rows from pin.y onwards.
pub fn (mut self PageList) split(p Pin) ! {
	$if !prod {
		assert self.pin_is_valid(p)
	}

	// Keep this separate from p because a tracked pin may alias an entry that
	// is updated below.
	original_node := p.node
	mut page := unsafe { &original_node.data }
	if page.size.rows <= 1 {
		return error('OutOfSpace')
	}
	if p.y == 0 {
		return
	}
	defer { self.assert_integrity() }

	// Create new page with same capacity
	new_node := self.create_page(page.capacity)!
	mut new_page := &new_node.data

	y_start := p.y
	y_end := page.size.rows
	new_page.size.rows = y_end - y_start
	assert new_page.size.rows <= new_page.capacity.rows
	new_page.clone_from(page, y_start, y_end) or {
		// The source destroys the speculative page and translates every clone
		// failure to OutOfSpace so callers can recover from a failed split.
		self.destroy_node(new_node)
		return error('OutOfSpace')
	}

	// Update tracked pins
	for mut tp in self.tracked_pins_storage {
		if voidptr(tp.node) == voidptr(original_node) && tp.y >= p.y {
			tp.node = new_node
			tp.y -= p.y
		}
	}

	// Clear original page rows and reduce size
	for i in int(y_start) .. int(y_end) {
		page.clear_cells(u16(i), 0, page.size.cols)
	}
	page.size.rows -= y_end - y_start

	// Insert after original
	self.pages.insert_after(original_node, new_node)
}

// ============================================================
// Clone
// ============================================================

pub fn (self &PageList) clone(opts PageCloneOpts) !PageList {
 return self.clone_alloc(self.pool.alloc, opts)
}

pub fn (self &PageList) clone_alloc(allocator lib_allocator.Allocator, opts PageCloneOpts) !PageList {
	mut it := self.page_iterator(.right_down, opts.top, opts.bot)

	mut count_it := it
	mut page_count := uint(0)
	for { _ := count_it.next() or { break }; page_count++ }
	mut pool := MemoryPool.init(allocator, page_list_page_allocator(), page_count)!
	mut pool_ready := false
	defer { if !pool_ready { pool.deinit() } }
	mut viewport_pin := pool.pins.create()!
	mut tracked := lib_allocator.PointerArraySet[&Pin]{}
	mut tracked_ready := false
	defer { if !tracked_ready { tracked.deinit(pool.alloc) } }
	tracked.put_no_clobber(pool.alloc, viewport_pin)!
	mut result := PageList{
		pool: pool
		tracked_pins_set: tracked
		cols:                    self.cols
		rows:                    self.rows
		pages:                   PageNodeList{}
		page_serial:             0
		page_serial_min:         0
		page_size:               0
		explicit_max_size:       self.explicit_max_size
		min_max_size:            self.min_max_size
		total_rows:              0
		tracked_pins_storage:    tracked.keys
		viewport:                .active
		viewport_pin:            viewport_pin
		viewport_pin_row_offset: none
	}

	pool_ready = true
	tracked_ready = true
	mut result_ready := false
	defer {
		if !result_ready {
			cleanup_initial_pages(&result.pool, result.pages)
			result.tracked_pins_set.deinit(result.pool.alloc)
			result.pool.deinit()
		}
	}
	for {
		chunk := it.next() or { break }
		new_node := result.create_page(chunk.node.data.capacity)!
		mut new_page := &new_node.data
		assert new_page.capacity.rows >= chunk.end - chunk.start
		new_page.size.rows = chunk.end - chunk.start
		new_page.size.cols = chunk.node.data.size.cols
		new_page.clone_from(&chunk.node.data, chunk.start, chunk.end)!
		new_page.dirty = chunk.node.data.dirty

		result.pages.append(new_node)
		result.total_rows += uint(new_page.size.rows)
		new_page.assert_integrity()

		// Recreate every tracked pin that falls within this cloned chunk.
		if opts.tracked_pins != unsafe { nil } {
			for old_pin in self.tracked_pins_storage {
				if voidptr(old_pin.node) != voidptr(chunk.node) || old_pin.y < chunk.start
					|| old_pin.y >= chunk.end {
					continue
				}
				mut new_pin := result.pool.pins.create()!
				unsafe { *new_pin = Pin{
					node:    new_node
					y:       old_pin.y - chunk.start
					x:       old_pin.x
					garbage: old_pin.garbage
				} }
				unsafe {
					mut remap := opts.tracked_pins
					remap.put_no_clobber(old_pin, new_pin)!
				}
				result.tracked_pins_set.put_no_clobber(result.pool.alloc, new_pin)!
				result.tracked_pins_storage = result.tracked_pins_set.keys
			}
		}
	}

	// Ensure viewport pin points to valid node
	first := result.pages.first or { panic('cloned page list is empty') }
	unsafe { *result.viewport_pin = Pin{ node: first } }

	// Ensure we have enough rows for active area
	if result.total_rows < uint(result.rows) {
		len := uint(result.rows) - result.total_rows
		for _ in 0 .. len {
			_ = result.grow()!
			mut last := result.pages.last or { panic('cloned page list is empty') }
			last.data.clear_cells(last.data.size.rows - 1, 0, result.cols)
		}
		result.total_rows = uint(result.rows)
	}

	result_ready = true
	pool_ready = true
	tracked_ready = true
	result.assert_integrity()
	return result
}

// ============================================================
// ReflowCursor - drives column reflow
// ============================================================

// We use a cursor to track where we are in the src/dst. This is very
// similar to Screen.Cursor. We don't use a Screen because we don't need
// all the same data and we do our best to optimize having direct access
// to the page memory.
struct ReflowCursor {
mut:
	x            u16
	y            u16
	pending_wrap bool
	node         &PageNode = unsafe { nil }
	new_rows     uint
	// This is the final row count of the reflowed pages.
	total_rows uint
}

fn ReflowCursor.init(node &PageNode) ReflowCursor {
	return ReflowCursor{
		x:            0
		y:            0
		pending_wrap: false
		node:         node
		new_rows:     0
		// Initially whatever size our input node is.
		total_rows:   uint(node.data.size.rows)
	}
}

// Result of writing a cell.
enum PageReflowWriteResult as u8 {
	success
	repeat
	skip_next
}

// The destination page for the cursor.
fn (self &ReflowCursor) page() &Page {
	return &self.node.data
}

// True if this cursor is at the bottom of the page by capacity,
// i.e. we can't scroll anymore.
fn (self &ReflowCursor) bottom() bool {
	return self.y == self.node.data.capacity.rows - 1
}

fn (mut self ReflowCursor) cursor_forward() {
	if self.x == self.node.data.size.cols - 1 {
		self.pending_wrap = true
	} else {
		self.x += 1
	}
}

// Create a new row and move the cursor down. Asserts that the cursor is
// on the bottom row of the page and that there is capacity to add one.
fn (mut self ReflowCursor) cursor_scroll() {
	assert self.y == self.node.data.size.rows - 1
	assert self.node.data.size.rows < self.node.data.capacity.rows

	mut page := &self.node.data
	page.size.rows += 1
	self.pending_wrap = false
	self.x = 0
	self.y += 1
}

// Create a new page in the provided list with the provided capacity and
// one row and move the cursor into it at 0,0.
fn (mut self ReflowCursor) cursor_new_page(mut list PageList, cap PageCapacity) ! {
	// Remember our new row count so we can restore it after
	// reinitializing our cursor on the new page.
	new_rows := self.new_rows

	mut node := list.create_page(cap)!
	node.data.size.rows = 1
	list.pages.insert_after(self.node, node)

	old := ReflowCursor.init(node)
	self.x = old.x
	self.y = old.y
	self.pending_wrap = old.pending_wrap
	self.node = old.node
	self.total_rows = old.total_rows
	self.new_rows = new_rows
}

// Performs cursor_scroll or cursor_new_page as necessary depending on if
// the cursor is currently at the bottom.
fn (mut self ReflowCursor) cursor_scroll_or_new_page(mut list PageList, cap PageCapacity) ! {
	// The functions below may overwrite self so we cache our total rows.
	// We add one because no matter what when this returns we'll have one
	// more row added.
	new_total_rows := self.total_rows + 1
	if self.bottom() {
		self.cursor_new_page(mut list, cap)!
	} else {
		self.cursor_scroll()
	}
	self.total_rows = new_total_rows
}

fn (mut self ReflowCursor) cursor_absolute(x u16, y u16) {
	assert x < self.node.data.size.cols
	assert y < self.node.data.size.rows
	self.pending_wrap = false
	self.x = x
	self.y = y
}

// Increase the capacity of the cursor's page and reload cursor state after
// PageList replaces the underlying node.
fn (mut self ReflowCursor) increase_capacity(mut list PageList, adjustment ?IncreaseCapacity) ! {
	old_x := self.x
	old_y := self.y
	old_total_rows := self.total_rows

	// During reflow the list's cached total is intentionally transient.
	list.pause_integrity_checks(true)
	node := list.increase_capacity(self.node, adjustment) or {
		list.pause_integrity_checks(false)
		return err
	}
	list.pause_integrity_checks(false)

	mut reloaded := ReflowCursor.init(node)
	reloaded.cursor_absolute(old_x, old_y)
	reloaded.total_rows = old_total_rows
	self.x = reloaded.x
	self.y = reloaded.y
	self.pending_wrap = reloaded.pending_wrap
	self.node = reloaded.node
	self.new_rows = reloaded.new_rows
	self.total_rows = reloaded.total_rows
}

fn (self &ReflowCursor) count_trailing_empty_cells() uint {
	row := &self.node.data.rows[int(self.y)]
	// If the row is wrapped, all empty cells are meaningful.
	if row.header.wrap {
		return 0
	}

	len := uint(self.node.data.size.cols - self.x)
	for i in 0 .. len {
		rev_i := len - i - 1
		if !row.cells[int(self.x) + int(rev_i)].is_empty() {
			return i
		}
	}

	// A semantic prompt makes an otherwise blank row meaningful, so retain
	// one cell and report every other trailing cell as empty.
	if row.header.semantic_prompt != .unknown {
		return len - 1
	}
	return len
}

fn (mut self ReflowCursor) copy_row_metadata(other &RowData) {
	mut page := &self.node.data
	page.rows[int(self.y)].header.semantic_prompt = other.header.semantic_prompt
}

// Reflow the provided row into this cursor.
fn (mut self ReflowCursor) reflow_row(mut list PageList, row Pin, cursor_pin &Pin) ! {
	mut src_page := &row.node.data
	src_row := src_page.rows[int(row.y)]
	src_y := row.y
	cells := src_row.cells[..int(src_page.size.cols)]

	// Calculate the columns in this row. First up we trim non-semantic
	// rightmost blanks.
	mut cols_len := src_page.size.cols
	if !src_row.header.wrap {
		for cols_len > 0 {
			if !cells[int(cols_len) - 1].is_empty() {
				break
			}
			cols_len -= 1
		}

		// If the row has a semantic prompt then the blank row is meaningful
		// so we just pretend the first cell of the row isn't empty.
		if cols_len == 0 && src_row.header.semantic_prompt != .unknown {
			cols_len = 1
		}
	}

	// Handle tracked pin adjustments.
	dst_x := if self.new_rows > 0 || self.pending_wrap { u16(0) } else { self.x }
	for mut p in list.tracked_pins_storage {
		if voidptr(p.node) != voidptr(row.node) || p.y != src_y || voidptr(p) == voidptr(cursor_pin) {
			continue
		}
		// If this pin is in the blanks on the right and past the end of the
		// dst col width then we move it to the end of the dst col width.
		if p.x >= cols_len {
			limit := self.node.data.size.cols - 1 - dst_x
			p.x = if p.x < limit { p.x } else { limit }
		}
		// We increase our col len to at least include this pin. This
		// ensures blank rows with pins are processed so pins are remapped.
		if p.x + 1 > cols_len {
			cols_len = p.x + 1
		}
	}
	// The blanks before the live cursor determine where the next write goes.
	if !isnil(cursor_pin) && voidptr(cursor_pin.node) == voidptr(row.node) && cursor_pin.y == src_y {
		if cursor_pin.x >= cols_len {
			cols_len = cursor_pin.x + 1
		}
	}

	// Defer processing of blank rows so that blank rows at the end of the
	// page list are never written.
	if cols_len == 0 {
		// If this blank row was a wrap continuation somehow then we won't
		// need to write it since it should be part of the previous row.
		if !src_row.header.wrap_continuation {
			self.new_rows += 1
		}
		return
	}

	// Inherit increased styles or grapheme bytes from the src page we're
	// reflowing from for new pages.
	cap := src_page.capacity.adjust(PageCapacityAdjustment{
		cols: self.node.data.size.cols
	}) or {
		mut c2 := src_page.capacity
		c2.cols = self.node.data.size.cols
		// We're already a non-standard page. We don't want to inherit a
		// massive set of rows, so cap it at our std size.
		c2.rows = if src_page.size.rows < std_capacity.rows {
			src_page.size.rows
		} else {
			std_capacity.rows
		}
		c2
	}

	// Our row isn't blank, write any new rows we deferred.
	for self.new_rows > 0 {
		self.cursor_scroll_or_new_page(mut list, cap)!
		self.new_rows -= 1
	}

	self.copy_row_metadata(src_row)

	mut x := 0
	for x < int(cols_len) {
		if self.pending_wrap {
			self.node.data.rows[int(self.y)].header.wrap = true
			self.cursor_scroll_or_new_page(mut list, cap)!
			self.copy_row_metadata(src_row)
			self.node.data.rows[int(self.y)].header.wrap_continuation = true
		}

		// Move any tracked pins from the source.
		for mut p in list.tracked_pins_storage {
			if voidptr(p.node) != voidptr(row.node) || p.y != src_y || int(p.x) != x {
				continue
			}
			p.node = self.node
			p.x = self.x
			p.y = self.y
		}

		result := self.write_cell(mut list, &cells[x], src_page) or {
			if err.msg() != 'OutOfSpace' {
				return err
			}
			// We reached the managed-memory capacity of a single page. If
			// we're on the first row we can't split further, so we take the
			// valid base cell without the managed value.
			if self.y == 0 {
				x += 1
				self.cursor_forward()
			} else {
				// Move our last row to a new page. Do NOT increment x so
				// that we retry writing the same existing cell.
				self.move_last_row_to_new_page(mut list, cap)!
			}
			continue
		}
		match result {
			.success {
				// Wrote the cell, move to the next.
				x += 1
			}
			.skip_next {
				// Wrote the cell but request to skip the next so skip it.
				// Remap any tracked pins at the skipped position (x+1).
				for mut p in list.tracked_pins_storage {
					if voidptr(p.node) != voidptr(row.node) || p.y != src_y
						|| int(p.x) != x + 1 {
						continue
					}
					p.node = self.node
					p.x = self.x
					p.y = self.y
				}
				x += 2
			}
			.repeat {
				// Didn't write the cell, repeat writing this same cell.
			}
		}
	}

	// If the source row isn't wrapped then we should scroll afterwards.
	if !src_row.header.wrap {
		self.new_rows += 1
	}
}

// Write a cell. On error, this will not unwrite the cell but the cell may
// be incomplete (but valid). This guarantees the page is in a coherent
// state even on error.
fn (mut self ReflowCursor) write_cell(mut list PageList, cell &CellData, src_page &Page) !PageReflowWriteResult {
	mut page := &self.node.data
	dst_cols := page.size.cols

	// Copy cell contents.
	match cell.content_tag {
		.codepoint, .codepoint_grapheme {
			match cell.wide {
				.narrow {
					page.rows[int(self.y)].cells[int(self.x)] = *cell
				}
				.wide {
					if dst_cols > 1 {
						if self.x == dst_cols - 1 {
							// If there's a wide character in the last column of
							// the reflowed page then we need to insert a spacer
							// head and wrap before handling it.
							page.rows[int(self.y)].cells[int(self.x)] = CellData{
								content_tag: .codepoint
								codepoint:   0
								wide:        .spacer_head
							}
							// Move to the next row (this sets pending wrap
							// which will cause us to wrap on the next iteration).
							self.cursor_forward()
							// Reprocess this source cell again.
							return .repeat
						} else {
							page.rows[int(self.y)].cells[int(self.x)] = *cell
						}
					} else {
						// Edge case, when resizing to 1 column, wide characters
						// are just destroyed and replaced with empty narrow
						// cells.
						page.rows[int(self.y)].cells[int(self.x)] = CellData{
							content_tag: .codepoint
							codepoint:   0
							wide:        .narrow
						}
						self.cursor_forward()
						// Skip spacer tail so it doesn't cause a wrap.
						return .skip_next
					}
				}
				.spacer_tail {
					if dst_cols > 1 {
						page.rows[int(self.y)].cells[int(self.x)] = *cell
					} else {
						// Edge case, resizing to 1 column: discard spacer tails.
						return .success
					}
				}
				.spacer_head {
					// Spacer heads should be ignored. If we need a spacer head
					// in our reflowed page, it is added when processing the
					// wide cell it belongs to.
					return .success
				}
			}
		}
		.bg_color_palette, .bg_color_rgb {
			// These are guaranteed to have no style or grapheme data
			// associated with them so we can fast path them.
			page.rows[int(self.y)].cells[int(self.x)] = *cell
			self.cursor_forward()
			return .success
		}
	}

	// Reset any managed-memory markers set by the base copy; they'll be
	// re-applied below if the copy of managed memory succeeds.
	mut dst := &page.rows[int(self.y)].cells[int(self.x)]
	dst.content_tag = .codepoint
	dst.has_hyperlink = false
	dst.style_id = default_style_id

	// Copy Kitty virtual placeholder status.
	if cell.codepoint() == kitty_unicode_placeholder {
		page.rows[int(self.y)].header.kitty_virtual_placeholder = true
	}

	// Copy grapheme data through the page mapping. The inline slice carries the
	// translated allocation bytes, but the mapping determines whether those
	// bytes belong to this source cell.
	if cell.content_tag == .codepoint_grapheme {
		cps := src_page.lookup_grapheme(cell) or {
			panic('grapheme source cell is missing its page mapping')
		}
		if page.grapheme_count() >= page.grapheme_capacity() {
			self.increase_capacity(mut list, .grapheme_bytes)!
			page = &self.node.data
		}
		for {
			offset := page.grapheme_alloc.alloc(uint(cps.len) * uint(sizeof(u32))) or {
				self.increase_capacity(mut list, .grapheme_bytes)!
				page = &self.node.data
				continue
			}
			page.grapheme_alloc.release(offset, uint(cps.len) * uint(sizeof(u32)))
			break
		}
		page.set_graphemes(uint(self.y), uint(self.x), cps) or {
			$if !prod {
				panic('set_graphemes failed after PageList capacity increase: ${err}')
			} $else {
				mut current_cell := &page.rows[int(self.y)].cells[int(self.x)]
				current_cell.content_tag = .codepoint
				current_cell.codepoint = 0xFFFD
			}
		}
	}

	// Copy hyperlink data.
	if cell.has_hyperlink {
		src_id := src_page.lookup_hyperlink(cell) or {
			panic('hyperlinked source cell is missing its page mapping')
		}
		src_link := src_page.hyperlink_set.get(src_id)
		if page.hyperlink_count() >= page.hyperlink_capacity() {
			self.increase_capacity(mut list, .hyperlink_bytes)!
			page = &self.node.data
		}
		additional_string_bytes := uint(src_link.uri.len + match src_link.id {
			HyperlinkExplicitId { src_link.id.value.len }
			else { 0 }
		})
		for !page.hyperlink_set.can_allocate_string_bytes(additional_string_bytes) {
			self.increase_capacity(mut list, .string_bytes)!
			page = &self.node.data
		}

		mut hyperlink_valid := true
		mut dst_id := HyperlinkId(0)
		if initial_id := page.hyperlink_set.add_with_id(src_link, src_id) {
			dst_id = initial_id
		} else {
			if err.msg() == 'strings out of memory' {
				$if !prod {
					panic('hyperlink copy failed after PageList capacity check: ${err}')
				} $else {
					hyperlink_valid = false
				}
			} else {
				adjustment := if err.msg() == 'set needs rehash' {
					?IncreaseCapacity(none)
				} else {
					?IncreaseCapacity(.hyperlink_bytes)
				}
				self.increase_capacity(mut list, adjustment)!
				page = &self.node.data
				if retry_id := page.hyperlink_set.add_with_id(src_link, src_id) {
					dst_id = retry_id
				} else {
					$if !prod {
						panic('hyperlink insertion failed after PageList capacity increase: ${err}')
					} $else {
						hyperlink_valid = false
					}
				}
			}
		}
		if hyperlink_valid {
			page.set_hyperlink(uint(self.y), uint(self.x), dst_id) or {
				$if !prod {
					panic('set_hyperlink failed after PageList capacity increase: ${err}')
				} $else {
					page.hyperlink_set.release(dst_id)
				}
			}
		}
	}

	// Copy style data.
	if cell.has_styling() {
		style := src_page.styles.get(cell.style_id)
		mut style_valid := true
		mut id := default_style_id
		if initial_id := page.styles.add_with_id(style, cell.style_id) {
			id = initial_id
		} else {
			mut adjustment := ?IncreaseCapacity(none)
			if err.msg() != 'needs rehash' {
				adjustment = .styles
			}
			self.increase_capacity(mut list, adjustment)!
			mut grown_page := &self.node.data
			if retry_id := grown_page.styles.add_with_id(style, cell.style_id) {
				id = retry_id
			} else {
				$if !prod {
					panic('style insertion failed after PageList capacity increase: ${err}')
				} $else {
					style_valid = false
				}
			}
		}
		if style_valid {
			mut current_page := &self.node.data
			current_page.rows[int(self.y)].cells[int(self.x)].style_id = id
			current_page.rows[int(self.y)].header.styled = true
		}
	}

	self.cursor_forward()
	return .success
}

// Create a new page in the provided list with the provided capacity then
// clone the row currently being worked on to it and delete it from the old
// page. Places cursor in the same position it was in the old row in the new
// one. Asserts that the cursor is on the final row of the page.
fn (mut self ReflowCursor) move_last_row_to_new_page(mut list PageList, cap PageCapacity) ! {
	assert self.y == self.node.data.size.rows - 1
	assert !self.pending_wrap

	old_node := self.node
	mut old_page := &old_node.data
	old_x := self.x

	// Our total row count never changes, because we're removing one row
	// from the last page and moving it into a new page.
	old_total_rows := self.total_rows

	self.cursor_new_page(mut list, cap)!
	assert voidptr(self.node) != voidptr(old_node)
	assert self.y == 0

	// Restore the x position of the cursor.
	self.cursor_absolute(old_x, 0)

	// Copy our old data.
	old_row_idx := old_page.size.rows - 1
	mut new_page := &self.node.data
	new_page.clone_row_from(old_page, self.y, old_row_idx) or {
		panic('unexpected last-row copy failure: ${err}')
	}

	// Move any tracked pins from that last row into this new node.
	for mut p in list.tracked_pins_storage {
		if voidptr(p.node) != voidptr(old_node) || p.y != old_page.size.rows - 1 {
			continue
		}
		p.node = self.node
		p.y = self.y
	}

	// Clear the row from the old page and truncate it.
	old_page.clear_cells(old_row_idx, 0, old_page.size.cols)
	old_page.size.rows -= 1

	// If that was the last row in that page then remove it from the list.
	if old_page.size.rows == 0 {
		list.pages.remove(old_node)
		list.destroy_node(old_node)
	}

	self.total_rows = old_total_rows
}

// ============================================================
// Trailing blank line trimming
// ============================================================

// Returns the number of trailing blank lines, not to exceed max. Max is
// used to limit our traversal in the case of large scrollback.
fn (self &PageList) trailing_blank_lines(max u16) u16 {
	mut count := u16(0)

	// Go through our pages backwards since we're counting trailing blanks.
	mut it := self.pages.last
	for {
		page := it or { break }
		len := int(page.data.size.rows)
		for i in 0 .. len {
			rev_i := len - i - 1
			// If the row has any text then we're done.
			if has_text_any(page.data.rows[rev_i].cells[..int(page.data.size.cols)]) {
				return count
			}
			count += 1
			if count >= max {
				return count
			}
		}
		it = page.prev
	}

	return count
}

// Trims up to max trailing blank rows from the pagelist and returns the
// number of rows trimmed. A blank row is any row with no text (but may have
// styling).
//
// IMPORTANT: This function does NOT update total_rows. It returns the
// number of rows trimmed and the caller must decrement total_rows.
fn (mut self PageList) trim_trailing_blank_rows(max u16) u16 {
	mut trimmed := u16(0)
	bl_pin := self.get_bottom_right(.screen) or { panic('page list has no bottom-right pin') }
	mut it := bl_pin.row_iterator(.left_up, none)
	for {
		row_pin := it.next() or { break }
		mut page := &row_pin.node.data
		cells := page.rows[int(row_pin.y)].cells[..int(page.size.cols)]

		// If the row has any text then we're done.
		if has_text_any(cells) {
			return trimmed
		}

		// If our tracked pins are in this row then we cannot trim it because
		// it implies some sort of importance.
		for p in self.tracked_pins_storage {
			if voidptr(p.node) == voidptr(row_pin.node) && p.y == row_pin.y {
				return trimmed
			}
		}

		// No text, we can trim this row. Because it has no text we can also be
		// sure it has no styling, so we don't need to worry about memory.
		page.size.rows -= 1
		if page.size.rows == 0 {
			self.erase_page(row_pin.node)
		} else {
			page.assert_integrity()
		}

		trimmed += 1
		if trimmed >= max {
			return trimmed
		}
	}

	return trimmed
}

// ============================================================
// Erase page / fixup viewport / compact / increaseCapacity
// ============================================================

// Erase a single page, freeing all its resources. The page can be anywhere
// in the linked list but must NOT be the final page in the entire list
// (i.e. must not make the list empty).
//
// IMPORTANT: This does NOT update total_rows. The caller is responsible.
fn (mut self PageList) erase_page(node &PageNode) {
	assert node.next != none || node.prev != none
	// Update any tracked pins to move to the previous or next page.
	next := node.prev or { node.next or { panic('cannot erase the final page') } }
	for mut p in self.tracked_pins_storage {
		if voidptr(p.node) == voidptr(node) {
			p.node = next
			p.y = 0
			p.x = 0
		}
	}
	self.pages.remove(node)
	self.destroy_node(node)
}

// This fixes up the viewport data when rows are removed from the PageList.
// It updates the viewport to `active` if row removal puts the viewport into
// the active area, to `top` if the viewport is now at row 0, and updates any
// row offset caches as necessary.
fn (mut self PageList) fixup_viewport(removed uint) {
	match self.viewport {
		.active {}
		.pin {
			vp := Pin{
				node: self.viewport_pin.node
				y:    self.viewport_pin.y
				x:    self.viewport_pin.x
			}
			if self.pin_is_active(vp) {
				self.viewport = .active
			} else if v := self.viewport_pin_row_offset {
				if v < removed {
					self.viewport = .top
				} else {
					self.viewport_pin_row_offset = v - removed
				}
			}
		}
		.top {
			first := self.pages.first or { return }
			if self.pin_is_active(Pin{ node: first }) {
				self.viewport = .active
			}
		}
	}
}

pub enum IncreaseCapacity as u8 {
	styles
	grapheme_bytes
	hyperlink_bytes
	string_bytes
}

// Increase one bounded capacity dimension by replacing and recloning the
// page. The node replacement, pin fixup, and serial change mirror Ghostty's
// increaseCapacity.
pub fn (mut self PageList) increase_capacity(node &PageNode, adjustment ?IncreaseCapacity) !&PageNode {
	defer { self.assert_integrity() }
	page := &node.data
	mut cap := page.capacity
	if value := adjustment {
		match value {
			.styles {
				if cap.styles == max_u16 {
					return error('OutOfSpace')
				}
				cap.styles = if cap.styles > max_u16 / 2 { max_u16 } else { cap.styles * 2 }
			}
			.grapheme_bytes {
				if cap.grapheme_bytes == max_u32 {
					return error('OutOfSpace')
				}
				cap.grapheme_bytes = if cap.grapheme_bytes > max_u32 / 2 {
					max_u32
				} else {
					cap.grapheme_bytes * 2
				}
			}
			.hyperlink_bytes {
				if cap.hyperlink_bytes == max_u16 {
					return error('OutOfSpace')
				}
				cap.hyperlink_bytes = if cap.hyperlink_bytes > max_u16 / 2 {
					max_u16
				} else {
					cap.hyperlink_bytes * 2
				}
			}
			.string_bytes {
				if cap.string_bytes == max_u32 {
					return error('OutOfSpace')
				}
				cap.string_bytes = if cap.string_bytes > max_u32 / 2 {
					max_u32
				} else {
					cap.string_bytes * 2
				}
			}
		}
	}

	// Ghostty rejects an adjusted capacity whose exact backing layout exceeds
	// the largest representable page. Rehashing keeps the same capacity, so it
	// is the one adjustment that does not need this check.
	if adjustment != none && Page.layout(cap).total_size > uint(max_page_size) {
		return error('OutOfSpace')
	}

	mut new_node := self.create_page(cap)!
	mut new_page := &new_node.data
	assert new_page.capacity.rows >= page.capacity.rows
	assert new_page.capacity.cols >= page.capacity.cols
	new_page.size = page.size
	new_page.clone_from(page, 0, page.size.rows) or {
		panic('capacity-increased page clone failed: ${err}')
	}
	new_page.dirty = page.dirty

	for mut pin in self.tracked_pins_storage {
		if voidptr(pin.node) == voidptr(node) {
			pin.node = new_node
		}
	}

	self.pages.insert_before(node, new_node)
	self.pages.remove(node)
	self.destroy_node(node)
	new_page.assert_integrity()
	return new_node
}

// Compact a page to use the minimum required memory for the contents it
// stores. Returns the new node if compaction occurred, or none if the page
// was already compact.
//
// The current design doesn't allow smaller-than-std pages, so if the node's
// backing page is standard-size or smaller, no compaction occurs.
pub fn (mut self PageList) compact(node &PageNode) !PageNodeOption {
	mut page := &node.data
	assert page.size.rows > 0

	// We never compact standard size or smaller pages because changing the
	// capacity to something smaller won't save memory.
	old_size := page_backing_size(page.capacity)
	if old_size <= standard_page_size() {
		return PageNodeOption{}
	}

	// Compute the minimum capacity required for this page's content.
	req_cap := page.exact_row_capacity(0, uint(page.size.rows))
	new_size := Page.layout(req_cap).total_size
	if new_size >= old_size {
		return PageNodeOption{}
	}

	// Create the new smaller page.
	mut new_node := self.create_page(req_cap)!
	mut new_page := &new_node.data
	new_page.size = page.size
	new_page.dirty = page.dirty
	new_page.clone_from(page, 0, page.size.rows) or {
		// The requested capacity was computed from this exact content. Preserve
		// the original page if a bounded clone nevertheless rejects it.
		self.destroy_node(new_node)
		return PageNodeOption{}
	}

	// Fix up all tracked pins to point to the new page.
	for mut p in self.tracked_pins_storage {
		if voidptr(p.node) == voidptr(node) {
			p.node = new_node
		}
	}

	// Insert the new page and destroy the old one.
	self.pages.insert_before(node, new_node)
	self.pages.remove(node)
	self.destroy_node(node)

	return PageNodeOption{ node: new_node }
}

// A variant of erase_row that shifts only a bounded number of following
// rows up, filling the space they leave behind with blank rows.
//
// `limit` is exclusive of the erased row. A limit of 1 will erase the target
// row and shift the row below into its position, leaving a blank row below.
pub fn (mut self PageList) erase_row_bounded(point Point, limit uint) ! {
	defer { self.assert_integrity() }

	// This function has a lot of repeated code in it because it is a hot path.
	//
	// To get a better idea of what's happening, read eraseRow first for more
	// in-depth explanatory comments. To avoid repetition, the only comments for
	// this function are for where it differs from eraseRow.

	pn := self.pin(point) or { panic('erase row point is outside the page list') }

	mut node := pn.node

	// If the row limit is less than the remaining rows before the end of the
	// page, then we clear the row, rotate it to the end of the boundary limit
	// and update our pins.
	if uint(node.data.size.rows - pn.y) > limit {
		node.data.clear_cells(pn.y, 0, node.data.size.cols)
		mut rows := unsafe { node.data.rows[int(pn.y)..int(pn.y) + int(limit) + 1] }
		rotate_row_views(mut rows, false)

		// Mark the whole page as dirty.
		//
		// Technically we only need to mark from the erased row to the
		// limit but this is a hot function, so we want to minimize work.
		node.data.dirty = true

		// If our viewport is a pin and our pin is within the erased
		// region we need to maybe shift our cache up. We do this here instead
		// of in the pin loop below because its unlikely to be true and we
		// don't want to run the conditional N times.
		if self.viewport == .pin {
			if v := self.viewport_pin_row_offset {
				vp := self.viewport_pin
				if !(voidptr(vp.node) != voidptr(node) || vp.y < pn.y
					|| uint(vp.y) > uint(pn.y) + limit || vp.y == 0) {
					self.viewport_pin_row_offset = v - 1
				}
			}
		}

		// Update pins in the shifted region.
		for mut p in self.tracked_pins_storage {
			if voidptr(p.node) == voidptr(node) && p.y >= pn.y && uint(p.y) <= uint(pn.y) + limit {
				if p.y == 0 {
					p.x = 0
				} else {
					p.y -= 1
				}
			}
		}

		return
	}

	mut rows := unsafe { node.data.rows[int(pn.y)..int(node.data.size.rows)] }
	rotate_row_views(mut rows, false)

	// Mark the whole page as dirty.
	//
	// Technically we only need to mark rows from the erased row to the end
	// of the page as dirty, but that's slower and this is a hot function.
	node.data.dirty = true

	// We need to keep track of how many rows we've shifted so that we can
	// determine at what point we need to do a partial shift on subsequent
	// pages.
	mut shifted := uint(node.data.size.rows - pn.y)

	// Update tracked pins.
	{
		// See the other places we do something similar in this function
		// for a detailed explanation.
		if self.viewport == .pin {
			if v := self.viewport_pin_row_offset {
				vp := self.viewport_pin
				if !(voidptr(vp.node) != voidptr(node) || vp.y < pn.y || vp.y == 0) {
					self.viewport_pin_row_offset = v - 1
				}
			}
		}

		for mut p in self.tracked_pins_storage {
			if voidptr(p.node) == voidptr(node) && p.y >= pn.y {
				if p.y == 0 {
					p.x = 0
				} else {
					p.y -= 1
				}
			}
		}
	}

	for {
		mut next := node.next or { break }

		node.data.clone_row_from(&next.data, node.data.size.rows - 1, 0)!

		node = next

		// We check to see if this page contains enough rows to satisfy the
		// specified limit, accounting for rows we've already shifted in prior
		// pages.
		//
		// The logic here is very similar to the one before the loop.
		shifted_limit := limit - shifted
		if uint(node.data.size.rows) > shifted_limit {
			node.data.clear_cells(0, 0, node.data.size.cols)
			mut next_rows := unsafe { node.data.rows[..int(shifted_limit) + 1] }
			rotate_row_views(mut next_rows, false)

			// Mark the whole page as dirty.
			//
			// Technically we only need to mark from the erased row to the
			// limit but this is a hot function, so we want to minimize work.
			node.data.dirty = true

			// See the other places we do something similar in this function
			// for a detailed explanation.
			if self.viewport == .pin {
				if v := self.viewport_pin_row_offset {
					vp := self.viewport_pin
					if !(voidptr(vp.node) != voidptr(node) || uint(vp.y) > shifted_limit) {
						self.viewport_pin_row_offset = v - 1
					}
				}
			}

			// Update pins in the shifted region.
			for mut p in self.tracked_pins_storage {
				if voidptr(p.node) != voidptr(node) || uint(p.y) > shifted_limit {
					continue
				}
				if p.y == 0 {
					p.node = node.prev or { panic('page after the erased row has no previous page') }
					p.y = p.node.data.size.rows - 1
					continue
				}
				p.y -= 1
			}

			return
		}

		mut next_rows := unsafe { node.data.rows[..int(node.data.size.rows)] }
		rotate_row_views(mut next_rows, false)

		// Mark the whole page as dirty.
		node.data.dirty = true

		// Account for the rows shifted in this node.
		shifted += uint(node.data.size.rows)

		// See the other places we do something similar in this function
		// for a detailed explanation.
		if self.viewport == .pin {
			if v := self.viewport_pin_row_offset {
				vp := self.viewport_pin
				if voidptr(vp.node) == voidptr(node) {
					self.viewport_pin_row_offset = v - 1
				}
			}
		}

		// Update tracked pins.
		for mut p in self.tracked_pins_storage {
			if voidptr(p.node) != voidptr(node) {
				continue
			}
			if p.y == 0 {
				p.node = node.prev or { panic('page after the erased row has no previous page') }
				p.y = p.node.data.size.rows - 1
				continue
			}
			p.y -= 1
		}
	}

	// We reached the end of the page list before the limit, so we clear
	// the final row since it was rotated down from the top of this page.
	node.data.clear_cells(node.data.size.rows - 1, 0, node.data.size.cols)
}

// ============================================================
// Resize
// ============================================================

pub fn (mut self PageList) resize(opts PageResizeOpts) ! {
	defer { self.assert_integrity() }
	$if !prod {
		if cols := opts.cols {
			assert cols > 0
		}
		if rows := opts.rows {
			assert rows > 0
		}
	}

	// Resizing (especially with reflow) can cause our row offset to
	// become invalid. Rather than do something fancy like we do other
	// places and try to update it in place, we just invalidate it because
	// its too easy to get the logic wrong in here.
	self.viewport_pin_row_offset = none

	if !opts.reflow {
		self.resize_without_reflow(opts)!
		return
	}

	// Recalculate our minimum max size. This allows grow to work properly
	// when increasing beyond our initial minimum max size or explicit max
	// size to fit the active area.
	old_min_max_size := self.min_max_size
	self.min_max_size = min_max_size_calc(opts.cols or { self.cols }, opts.rows or { self.rows })

	// On reflow, the main thing that causes reflow is column changes. If
	// only rows change, reflow is impossible. So we change our behavior based
	// on the change of columns.
	cols := opts.cols or { self.cols }

	if cols == self.cols {
		self.resize_without_reflow(opts) or {
			self.min_max_size = old_min_max_size
			return err
		}
	} else if cols > self.cols {
		// We grow rows after cols so that we can do our unwrapping/reflow
		// before we do a no-reflow grow.
		self.resize_cols(cols, opts.cursor) or {
			self.min_max_size = old_min_max_size
			return err
		}
		self.resize_without_reflow(opts) or {
			self.min_max_size = old_min_max_size
			return err
		}
	} else {
		// We first change our row count so that we have the proper amount
		// we can use when shrinking our cols.
		mut copy_opts := PageResizeOpts{
			cols:   self.cols
			rows:   opts.rows
			reflow: opts.reflow
			cursor: opts.cursor
		}
		self.resize_without_reflow(copy_opts) or {
			self.min_max_size = old_min_max_size
			return err
		}
		self.resize_cols(cols, opts.cursor) or {
			self.min_max_size = old_min_max_size
			return err
		}
	}

	// Various resize operations can change our total row count such
	// that our viewport pin is now in the active area and has insufficient
	// space. We need to check for this case and fix it up.
	if self.viewport == .pin {
		vp := Pin{
			node: self.viewport_pin.node
			y:    self.viewport_pin.y
			x:    self.viewport_pin.x
		}
		if self.pin_is_active(vp) {
			self.viewport = .active
		}
	}
}

// Resize the pagelist with reflow by adding or removing columns.
fn (mut self PageList) resize_cols(cols u16, cursor ?PageResizeCursor) ! {
	assert cols != self.cols

	// If we have a cursor position (x,y), then we try under any col resizing
	// to keep the same number remaining active rows beneath it. This is a
	// very special case if you can imagine clearing the screen (i.e.
	// scrollClear), having an empty active area, and then resizing to less
	// cols then we don't want the active area to "jump" to the bottom and
	// pull down scrollback.
	mut preserved_pin := &Pin(unsafe { nil })
	mut preserved_remaining := uint(0)
	mut preserved_wrapped := uint(0)
	mut untrack_preserved := false
	if c := cursor {
		pin := if tracked := c.pin {
			?Pin(*tracked)
		} else {
			self.pin(Point.new(.active, Coordinate{ x: c.x, y: c.y }))
		}
		if p := pin {
			active_pin := self.get_top_left(.active)

			// We count how many wraps the cursor had before it to begin with
			// so that we can offset any additional wraps to avoid pushing the
			// original row contents in to the scrollback.
			mut wrapped := uint(0)
			// Height changes may have moved the cursor above the active area.
			if !p.before(active_pin) {
				mut row_it := p.row_iterator(.left_up, active_pin)
				for {
					next := row_it.next() or { break }
					if next.row_and_cell().row.header.wrap_continuation {
						wrapped += 1
					}
				}
			}

			preserved_pin = c.pin or {
				untrack_preserved = true
				self.track_pin(p)!
			}
			preserved_remaining = if c.y < self.rows { uint(self.rows - c.y - 1) } else { uint(0) }
			preserved_wrapped = wrapped
		}
	}
	defer {
		if untrack_preserved {
			self.untrack_pin(preserved_pin)
		}
	}

	// The cursor must be resolved using the old width. Growth during reflow
	// uses the new width to size destination pages.
	self.cols = cols

	// Create the first node that contains our reflow.
	first_page := &(self.pages.first or { panic('page list has no first page') }).data
	first_cap := first_page.capacity.adjust(PageCapacityAdjustment{ cols: cols }) or {
		// We verify all maxed out page layouts work. We're growing columns so
		// we can only get less rows so use the lesser of our capacity and size
		// so we minimize wasted rows.
		mut c2 := first_page.capacity
		c2.cols = cols
		c2.rows = if first_page.size.rows < c2.rows { first_page.size.rows } else { c2.rows }
		c2
	}
	mut first_rewritten_node := self.create_page(first_cap)!
	first_rewritten_node.data.size.rows = 1

	// We need to grab our row iterator now before we rewrite our
	// linked list below.
	mut it := self.row_iterator(.right_down, Point.new(.screen, Coordinate{}), none)

	// Set our new page as the only page. This orphans the existing pages
	// in the list, but that's fine since we're gonna delete them anyway.
	self.pages.first = first_rewritten_node
	self.pages.last = first_rewritten_node

	// Reflow all our rows.
	mut reflow_cursor := ReflowCursor.init(first_rewritten_node)
	for {
		row := it.next() or { break }
		reflow_cursor.reflow_row(mut self, row, preserved_pin) or {
			// The old pages were orphaned above. On error, destroy every source
			// page still held by the iterator, matching Ghostty's errdefer cleanup.
			mut orphan := ?&PageNode(none)
			if chunk := it.chunk {
				orphan = chunk.node
			}
			for {
				node := orphan or { break }
				orphan = node.next
				self.destroy_node(node)
			}
			return err
		}

		// Once we're done reflowing a page, destroy it immediately. The old
		// pages are already orphaned from self.pages, so no unlink is needed.
		if int(row.y) == int(row.node.data.size.rows) - 1 {
			self.destroy_node(row.node)
		}
	}

	// At the end of the reflow, setup our total row cache.
	self.total_rows = reflow_cursor.total_rows

	// If our total rows is less than our active rows, we need to grow.
	// This can happen if you're growing columns such that enough active
	// rows unwrap that we no longer have enough.
	mut total := uint(0)
	mut node_it := self.pages.first
	mut enough := false
	for {
		node := node_it or { break }
		total += uint(node.data.size.rows)
		if total >= uint(self.rows) {
			enough = true
			break
		}
		node_it = node.next
	}
	if !enough {
		for _ in total .. uint(self.rows) {
			_ = self.grow()!
		}
	}

	// See preserved_cursor setup for why.
	if !isnil(preserved_pin) {
		vp := Pin{
			node: preserved_pin.node
			y:    preserved_pin.y
			x:    preserved_pin.x
		}
		active_pt := self.point_from_pin(.active, vp) or {
			return
		}
		active_pin := self.get_top_left(.active)

		// We need to determine how many rows we wrapped from the original
		// and subtract that from the remaining rows we expect because if
		// we wrap down we don't want to push our original row contents into
		// the scrollback.
		mut wrapped := uint(0)
		mut row_it := preserved_pin.row_iterator(.left_up, active_pin)
		for {
			next := row_it.next() or { break }
			if int(next.y) < next.node.data.rows.len {
				if next.node.data.rows[int(next.y)].header.wrap_continuation {
					wrapped += 1
				}
			}
		}

		current := uint(self.rows) - uint(active_pt.coord().y) - 1

		mut req_rows := preserved_remaining
		// req_rows -|= wrapped -| c.wrapped_rows  (saturating subtractions)
		wrap_delta := if wrapped > preserved_wrapped {
			wrapped - preserved_wrapped
		} else {
			uint(0)
		}
		req_rows = if req_rows > wrap_delta { req_rows - wrap_delta } else { uint(0) }
		req_rows = if req_rows > current { req_rows - current } else { uint(0) }

		for req_rows > 0 {
			_ = self.grow()!
			req_rows -= 1
		}
	}
}

fn (mut self PageList) resize_without_reflow(opts PageResizeOpts) ! {
	// We only set the new min_max_size if we're not reflowing. If we are
	// reflowing, then resize handles this for us.
	old_min_max_size := self.min_max_size
	if !opts.reflow {
		self.min_max_size = min_max_size_calc(opts.cols or { self.cols }, opts.rows or {
			self.rows
		})
	}

	// Important! We have to do cols first because cols may cause us to
	// destroy pages if we're increasing cols which will free up page_size
	// so that when we call grow() in the row mods, we won't prune.
	if cols := opts.cols {
		old_total_rows := self.total_rows
		if cols < self.cols {
			// Making our columns smaller. We always have space for this
			// in existing pages so we need to go through the pages,
			// resize the columns, and clear any cells that are beyond
			// the new size.
			mut it := self.page_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
			for {
				chunk := it.next() or { break }
				mut page := &chunk.node.data
				for i in 0 .. int(page.size.rows) {
					page.clear_cells(u16(i), cols, self.cols)
				}
				page.size.cols = cols
				page.assert_integrity()
			}

			// Update all our tracked pins. If they have an X
			// beyond the edge, clamp it.
			for mut p in self.tracked_pins_storage {
				if p.x >= cols {
					p.x = cols - 1
				}
			}

			self.cols = cols
		} else if cols > self.cols {
			// Make our columns larger. This is a bit more complicated because
			// pages may not have the capacity for this. If they don't have
			// the capacity we need to allocate a new page and copy the data.
			old_cols := self.cols

			mut it := self.page_iterator(.right_down, Point.new(.screen, Coordinate{}), none)
			for {
				chunk := it.next() or { break }
				// We need to restore our old cols after we resize because
				// we have an assertion on this and we want to be able to
				// call this method multiple times.
				self.cols = old_cols
				self.resize_without_reflow_grow_cols(cols, chunk) or {
					self.min_max_size = old_min_max_size
					return err
				}
			}

			self.cols = cols
		}
		assert self.total_rows == old_total_rows
	}

	if rows := opts.rows {
		if rows < self.rows {
			// Making rows smaller, we simply change our rows value. Changing
			// the row size doesn't affect anything else since max size and
			// so on are all byte-based.
			//
			// If our rows are shrinking, we prefer to trim trailing
			// blank lines from the active area instead of creating
			// history if we can. This matches macOS Terminal.app behavior.
			trimmed := self.trim_trailing_blank_rows(self.rows - rows)

			// Account for our trimmed rows in the total row cache.
			self.total_rows -= uint(trimmed)

			// If we didn't trim enough, just modify our row count and this
			// will create additional history.
			self.rows = rows
		} else if rows > self.rows {
			// Making rows larger we adjust our row count, and then grow
			// to the row count.
			mut handled := false
			if c := opts.cursor {
				// If our rows increased and our cursor is NOT at the bottom,
				// we want to try to preserve the y value of the old cursor.
				// In other words, we don't want to "pull down" scrollback.
				if c.y < self.rows - 1 {
					delta := rows - self.rows
					self.rows = rows
					for _ in 0 .. delta {
						_ = self.grow()!
					}
					handled = true
				}
			}

			if !handled {
				// This must be set BEFORE any calls to grow() so that
				// grow() doesn't prune pages that we need for the active area.
				self.rows = rows

				// Cursor is at the bottom or we don't care about cursors.
				// In this case, if we have enough rows in our pages, we
				// just update our rows and we're done. This effectively
				// "pulls down" scrollback. If we don't have enough
				// scrollback, we add the difference to the active area.
				mut count := uint(0)
				mut page := self.pages.first
				mut enough := false
				for {
					p := page or { break }
					count += uint(p.data.size.rows)
					if count >= uint(rows) {
						enough = true
						break
					}
					page = p.next
				}
				if !enough {
					for _ in count .. uint(rows) {
						_ = self.grow()!
					}
				}

				// Make sure that the viewport pin isn't below the active
				// area, since that will lead to all sorts of problems.
				if self.viewport == .pin {
					vp := Pin{
						node: self.viewport_pin.node
						y:    self.viewport_pin.y
						x:    self.viewport_pin.x
					}
					if self.pin_is_active(vp) {
						self.viewport = .active
					}
				}
			}
		}

		$if !prod {
			assert self.count_total_rows() >= uint(self.rows)
		}
	}
}

// Resize a single chunk to grow its columns. This may split the chunk's
// page into multiple pages if the new column count reduces the row
// capacity of a page.
fn (mut self PageList) resize_without_reflow_grow_cols(cols u16, chunk PageChunk) ! {
	assert cols > self.cols
	mut page := &chunk.node.data

	// Update our col count.
	self.cols = cols

	// Unlikely fast path: we have capacity in the page. This
	// is only true if we resized to less cols earlier.
	if page.capacity.cols >= cols {
		page.size.cols = cols
		return
	}

	// Likely slow path: we don't have capacity, so we need
	// to allocate a page, and copy the old data into it.
	//
	// Try to fit our new column size into our existing page capacity.
	// If that doesn't work then use a non-standard page with the
	// given columns.
	cap := page.capacity.adjust(PageCapacityAdjustment{ cols: cols }) or {
		mut c2 := page.capacity
		c2.cols = cols
		// We're growing columns so we can only get less rows so use
		// the lesser of our capacity and size so we minimize wasted rows.
		c2.rows = if page.size.rows < c2.rows { page.size.rows } else { c2.rows }
		c2
	}

	// Keeps track of all our copied rows. Assertion at the end is that
	// we copied exactly our page size.
	mut copied := u16(0)

	// If this chunk isn't the last chunk in the page list, then we've
	// created a page where we'll never reclaim capacity. To avoid this, we
	// try to fill our previous page first if it has excess capacity.
	if initial_prev_node := chunk.node.prev {
		prev_node := unsafe { initial_prev_node }
		mut prev_page := &prev_node.data
		// We only want scenarios where we have excess capacity.
		if prev_page.size.rows < prev_page.capacity.rows {
			len := if u32(prev_page.capacity.rows) - u32(prev_page.size.rows) < u32(page.size.rows) {
				prev_page.capacity.rows - prev_page.size.rows
			} else {
				page.size.rows
			}
			mut copied_all := true
			for i in 0 .. int(len) {
				dst_idx := prev_page.size.rows
				prev_page.size.rows += 1
				prev_page.clone_row_from(page, dst_idx, u16(i)) or {
					prev_page.size.rows -= 1
					copied_all = false
					break
				}
				copied += 1
			}

			if copied_all {
				assert copied == len
				assert prev_page.size.rows <= prev_page.capacity.rows

				// Remap any tracked pins that pointed to rows we just copied.
				for mut p in self.tracked_pins_storage {
					if voidptr(p.node) == voidptr(chunk.node) && p.y < len {
						p.node = prev_node
						p.y += prev_page.size.rows - len
					}
				}
			}
		}
	}

	// We need to loop because our col growth may force us to split pages.
	for copied < page.size.rows {
		mut new_node := self.create_page(cap)!
		mut new_page := &new_node.data

		// The length we can copy into the new page is at most the number
		// of rows in our cap. But if we can finish our source page we use that.
		len := if cap.rows < page.size.rows - copied { cap.rows } else { page.size.rows - copied }

		// Perform the copy.
		y_start := copied
		for i in 0 .. int(len) {
			new_page.size.rows += 1
			new_page.clone_row_from(page, u16(i), u16(int(y_start) + i)) or {
				// Ghostty safely cuts this page copy short. The next page gets a
				// chance to hold the row when the combined managed data did not fit.
				new_page.size.rows -= 1
				break
			}
			copied += 1
		}
		y_end := copied

		// Insert our new page.
		self.pages.insert_before(chunk.node, new_node)

		// Update our tracked pins that pointed to this previous page.
		for mut p in self.tracked_pins_storage {
			if voidptr(p.node) == voidptr(chunk.node) && p.y >= y_start && p.y < y_end {
				p.node = new_node
				p.y -= y_start
			}
		}
		new_page.assert_integrity()
	}
	assert copied == page.size.rows

	// Remove the old page. Deallocate the old page.
	self.pages.remove(chunk.node)
	self.destroy_node(chunk.node)
}

// ============================================================
// Dirty tracking
// ============================================================

pub fn (mut self PageList) clear_dirty() {
	mut node := self.pages.first
	for {
		mut n := node or { break }
		n.data.dirty = false
		for y in 0 .. int(n.data.size.rows) {
			n.data.rows[y].header.dirty = false
		}
		node = n.next
	}
}

// Returns true if the point is dirty, used for testing.
pub fn (self &PageList) is_dirty(point Point) bool {
	return (self.pin(point) or { panic('dirty point is outside the page list') }).is_dirty()
}

// Mark a point as dirty, used for testing.
fn (mut self PageList) mark_dirty(point Point) {
	mut pin := self.pin(point) or { panic('dirty point is outside the page list') }
	pin.mark_dirty()
}

// ============================================================
// Iterator factory methods on PageList
// ============================================================

pub fn (self &PageList) page_iterator(direction IterDirection, tl Point, bl ?Point) PageIterator {
	tl_pin := self.pin(tl) or { panic('page iterator top-left is outside the page list') }
	bl_pin := if bottom := bl {
		self.pin(bottom) or { panic('page iterator bottom-left is outside the page list') }
	} else {
		self.get_bottom_right(tl.tag()) or { return PageIterator{} }
	}

	return match direction {
		.right_down {
			tl_pin.page_iterator(.right_down, bl_pin)
		}
		.left_up {
			bl_pin.page_iterator(.left_up, tl_pin)
		}
	}
}

pub fn (self &PageList) row_iterator(direction IterDirection, tl Point, bl ?Point) RowIterator {
	tl_pin := self.pin(tl) or { panic('row iterator top-left is outside the page list') }
	bl_pin := if bottom := bl {
		self.pin(bottom) or { panic('row iterator bottom-left is outside the page list') }
	} else {
		self.get_bottom_right(tl.tag()) or { return RowIterator{} }
	}

	return match direction {
		.right_down {
			tl_pin.row_iterator(.right_down, bl_pin)
		}
		.left_up {
			bl_pin.row_iterator(.left_up, tl_pin)
		}
	}
}

pub fn (self &PageList) cell_iterator(direction IterDirection, tl Point, bl ?Point) CellIterator {
	tl_pin := self.pin(tl) or { panic('cell iterator top-left is outside the page list') }
	bl_pin := if bottom := bl {
		self.pin(bottom) or { panic('cell iterator bottom-left is outside the page list') }
	} else {
		self.get_bottom_right(tl.tag()) or { return CellIterator{} }
	}

	return match direction {
		.right_down {
			tl_pin.cell_iterator(.right_down, bl_pin)
		}
		.left_up {
			bl_pin.cell_iterator(.left_up, tl_pin)
		}
	}
}

pub fn (self &PageList) prompt_iterator(direction IterDirection, tl Point, bl ?Point) PromptIterator {
	tl_pin := self.pin(tl) or { panic('prompt iterator top-left is outside the page list') }
	bl_pin := if bottom := bl {
		self.pin(bottom) or { panic('prompt iterator bottom-left is outside the page list') }
	} else {
		self.get_bottom_right(tl.tag()) or { return PromptIterator{} }
	}

	return match direction {
		.right_down {
			tl_pin.prompt_iterator(.right_down, bl_pin)
		}
		.left_up {
			bl_pin.prompt_iterator(.left_up, tl_pin)
		}
	}
}

// ============================================================
// Assert Integrity
// ============================================================

pub enum PageListIntegrityError {
	page_serial_invalid
	total_rows_mismatch
	tracked_pin_invalid
	viewport_pin_offset_mismatch
	viewport_pin_insufficient_rows
}

pub fn (self &PageList) assert_integrity() {
	if !buildcfg.slow_runtime_safety {
		return
	}
	if self.pause_integrity_checks > 0 {
		return
	}
	if violation := self.verify_integrity() {
		panic('PageList integrity check failed: ${violation}')
	}
}

pub fn (self &PageList) verify_integrity() ?PageListIntegrityError {
	if !buildcfg.slow_runtime_safety {
		return none
	}
	if self.pause_integrity_checks > 0 {
		return none
	}
	// The viewport pin is permanently tracked and must never be garbage.
	assert !self.viewport_pin.garbage

	// Verify the row cache and reject nodes whose serial predates the oldest
	// still-valid allocation after page recycling.
	mut actual_rows := uint(0)
	mut node := self.pages.first
	for {
		current := node or { break }
		if current.serial < self.page_serial_min {
			return .page_serial_invalid
		}
		actual_rows += uint(current.data.size.rows)
		node = current.next
	}
	if actual_rows != self.total_rows {
		return .total_rows_mismatch
	}

	// Verify every tracked pin still points into a live page.
	for p in self.tracked_pins_storage {
		if !self.pin_is_valid(Pin{
			node: p.node
			y:    p.y
			x:    p.x
		}) {
			return .tracked_pin_invalid
		}
	}

	if self.viewport == .pin {
		// Calculate the pinned viewport offset without consulting the cache so
		// a stale cache cannot validate itself.
		mut offset := uint(0)
		mut actual_offset := ?uint(none)
		mut current_node := self.pages.last
		for {
			current := current_node or { break }
			offset += uint(current.data.size.rows)
			if voidptr(current) == voidptr(self.viewport_pin.node) {
				offset -= uint(self.viewport_pin.y)
				actual_offset = self.total_rows - offset
				break
			}
			current_node = current.prev
		}
		actual := actual_offset or { return .viewport_pin_offset_mismatch }
		if cached_offset := self.viewport_pin_row_offset {
			if cached_offset != actual {
				return .viewport_pin_offset_mismatch
			}
		}
		if self.total_rows - actual < uint(self.rows) {
			return .viewport_pin_insufficient_rows
		}
	}

	return none
}

// Temporarily pause or resume integrity checks around multi-step mutations.
pub fn (mut self PageList) pause_integrity_checks(pause bool) {
	if !buildcfg.slow_runtime_safety {
		return
	}
	if pause {
		self.pause_integrity_checks += 1
	} else {
		assert self.pause_integrity_checks > 0
		self.pause_integrity_checks -= 1
	}
}
