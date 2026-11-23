module input

// --- Original Ghostty Comments Start: src/input/key_mods.zig
//
// Source: /Users/alexander/code/3rd/ghostty/src/input/key_mods.zig
//
// Aliases for modifier names.
// Single modifier
// A bitmask for all key modifiers.
//
// IMPORTANT: Any changes here update include/witty.h
// The standard modifier keys only. Does not include the lock keys,
// only standard bindable keys.
// Tracks the side that is active for any given modifier. Note
// that this doesn't confirm a modifier is pressed; you must check
// the bool for that in addition to this.
//
// Not all platforms support this, check apprt for more info.
// The mask that has all the side bits set.
// Integer value of this struct.
// Returns true if no modifiers are set.
// Returns true if two mods are equal.
// Returns only the keys.
//
// In the future I want to remove `binding` for this. I didn't want
// to do that all in one PR where I added this because its a bigger
// change.
// Return mods that are only relevant for bindings.
// Perform `self &~ other` to remove the other mods from self.
// Returns the mods without locks set.
// Return the mods to use for key translation. This handles settings
// like macos-option-as-alt. The translation mods should be used for
// translation but never sent back in for the key callback.
// macos-option-as-alt for darwin
// Alt has to be set only on the correct side
// Unset alt
// Checks to see if super is on (MacOS) or ctrl.
// For our own understanding
// Unset
// Set
// Set but disabled
// Set wrong side
// Set with other mods
// Modifier remapping. See `key-remap` in Config.zig for detailed docs.
// Available mappings.
// The mask of remapped modifiers that can be used to quickly
// check if some input mods need remapping.
// Parse from CLI input. Required by Config.
// Empty value resets the set
// Parse a modifier remap and add it to the set.
// Find the assignment point ('=')
// The to side defaults to "left" if no explicit side is given.
// This is because this is the default unsided value provided by
// the apprts in the current Mods layout.
// The from side, if sided, is easy and we put it directly into
// the map.
// We need to do some combinatorial explosion here for unsided
// from in order to assign all possible sides.
// Must be called prior to any remappings so that the mapping
// is sorted properly. Otherwise, you will get invalid results.
// Mods with any right sides prioritize
// Deep copy of the struct. Required by Config.
// Compare if two RemapSets are equal. Required by Config.
// Used by Formatter. Required by Config.
// Check which mod is set and format it with optional side prefix
// Only write left_ if we need to distinguish
// For now, always write left_ if it's a sided mapping
// Parses a single mode in a single remapping string. E.g.
// `ctrl` or `left_shift`.
// Returns true if the given mods need remapping.
// Apply a remap to the given mods.
// Tracks which modifier keys and sides have remappings registered.
// Used as a fast pre-check before doing expensive map lookups.
//
// The mask uses separate tracking for left and right sides because
// remappings can be side-specific (e.g., only remap left_ctrl).
//
// Note: `left_sides` uses inverted logic where 1 means "left is remapped"
// even though `Mod.Side.left = 0`. This allows efficient bitwise matching
// since we can AND directly with the side bits.
// Which modifier keys (shift/ctrl/alt/super) have any remapping.
// Which modifiers have left-side remappings (inverted: 1 = left remapped).
// Which modifiers have right-side remappings (1 = right remapped).
// Adds a modifier to the mask, marking it as having a remapping.
// OR the new keys into our existing keys mask.
// Example: keys=0b0000, new ctrl → keys=0b0010
// Both Keys and Side are u4 with matching bit positions.
// This lets us use keys_int to select which side bits to update.
// Update left_sides: set bit if this key is active AND side is left.
// Since Side.left=0, we invert sides (~sides) so left becomes 1.
// keys_int masks to only affect the modifier being added.
// Example: left_ctrl → keys_int=0b0010, ~sides=0b1111 (left=0 inverted)
//          result: left_int | (0b0010 & 0b1111) = left_int | 0b0010
// Update right_sides: set bit if this key is active AND side is right.
// Since Side.right=1, we use sides directly.
// Example: right_ctrl → keys_int=0b0010, sides=0b0010 (right=1)
//          result: right_int | (0b0010 & 0b0010) = right_int | 0b0010
// Returns true if the given mods match any remapping in this mask.
// This is a fast check to avoid expensive map lookups when no
// remapping could possibly apply.
//
// Checks both that the modifier key is remapped AND that the
// specific side (left/right) being pressed has a remapping.
// Find which pressed keys have remappings registered.
// Example: pressed={ctrl,alt}, mask={ctrl} → active=0b0010 (just ctrl)
// Check if the pressed side matches a remapped side.
// For left (sides bit = 0): check against left_int (where 1 = left remapped)
//   ~sides inverts so left becomes 1, then AND with left_int
// For right (sides bit = 1): check against right_int directly
//
// Example: pressing left_ctrl (sides.ctrl=0, left_int.ctrl=1)
//   ~sides = 0b1111, left_int = 0b0010
//   (~sides & left_int) = 0b0010 ✓ matches
//
// Example: pressing right_ctrl but only left_ctrl is remapped
//   sides = 0b0010, left_int = 0b0010, right_int = 0b0000
//   (~0b0010 & 0b0010) | (0b0010 & 0b0000) = 0b0000 ✗ no match
// Final check: is any active (pressed + remapped) key also side-matched?
// Unsided creates both left and right mappings
//
// --- Original Ghostty Comments End: src/input/key_mods.zig

// Modifier remapping. See key-remap in Config for detailed docs.

// Mod represents a single modifier key.
pub enum Mod as u8 {
	shift
	ctrl
	alt
	super_
}

// Aliases for modifier names.
const mod_aliases = {
	'cmd':     Mod.super_
	'command': Mod.super_
	'opt':     Mod.alt
	'option':  Mod.alt
	'control': Mod.ctrl
}

// RemapSet contains a set of modifier remappings.
// Modifier remapping allows users to remap one modifier key to another.
pub struct RemapSet {
pub mut:
	// Available mappings: maps from-mods to to-mods.
	entries []RemapEntry
	// Mask of which modifier keys have remappings registered.
	mask RemapMask
}

// RemapEntry is a single from→to modifier mapping.
pub struct RemapEntry {
pub:
	from Mods
	to   Mods
}

// RemapMask tracks which modifier keys and sides have remappings registered.
// Used as a fast pre-check before doing expensive lookups.
pub struct RemapMask {
mut:
	value u16
}

// keys returns the low four-bit lane containing modifiers with remappings.
pub fn (m RemapMask) keys() u8 {
	return u8(m.value & 0x000f)
}

// left_sides returns the inverted-left four-bit lane.
pub fn (m RemapMask) left_sides() u8 {
	return u8((m.value >> 4) & 0x000f)
}

// right_sides returns the right-side four-bit lane.
pub fn (m RemapMask) right_sides() u8 {
	return u8((m.value >> 8) & 0x000f)
}

// int returns the packed 12-bit source value.
pub fn (m RemapMask) int() u16 {
	return m.value
}

// update adds a modifier to the mask, marking it as having a remapping.
pub fn (mut m RemapMask) update(mods Mods) {
	keys := mods.keys_int()
	side_bits := mods.sides_int()
	m.value |= u16(keys) | (u16((keys & ~side_bits) & 0x0f) << 4) | (u16((keys & side_bits) & 0x0f) << 8)
}

// does_match returns true if the given mods match any remapping in this mask.
pub fn (m RemapMask) does_match(mods Mods) bool {
	// Find which pressed keys have remappings registered.
	active := mods.keys_int() & m.keys()
	if active == 0 {
		return false
	}

	sides := mods.sides_int()
	side_match := (~sides & m.left_sides()) | (sides & m.right_sides())

	return (active & side_match & 0x0f) != 0
}

// keys_int returns a 4-bit mask of which standard modifier keys are set.
// Bit 0=shift, 1=ctrl, 2=alt, 3=super.
pub fn (m Mods) keys_int() u8 {
	return u8(m.int() & 0x000f)
}

// sides_int returns a 4-bit mask of which sides are right.
// Each bit corresponds to shift/ctrl/alt/super. 0=left, 1=right.
pub fn (m Mods) sides_int() u8 {
	return m.sides().int()
}

// without_locks returns mods without lock keys set.
pub fn (m Mods) without_locks() Mods {
	return Mods.from_int(m.int() & ~u16(0x0030))
}

// ctrl_or_super checks if super is on (macOS) or ctrl (everything else).
pub fn (m Mods) ctrl_or_super() bool {
	// Faithful to Zig: `if (comptime builtin.target.os.tag.isDarwin())`.
	// On Darwin the "command" (super) key is the primary modifier; on
	// all other platforms it is ctrl.
	$if darwin {
		return m.super_()
	} $else {
		return m.ctrl()
	}
}

// ctrl_or_super_mods sets either ctrl or super (but not both) on mods.
// On Mac, sets super. On non-Mac, sets ctrl.
pub fn ctrl_or_super_mods(m Mods) Mods {
	mut copy := m
	$if darwin {
		copy.set_super(true)
	} $else {
		copy.set_ctrl(true)
	}
	return copy
}

// parse parses a modifier remap string like "ctrl=super" or "left_alt=ctrl"
// and adds it to the set.
pub fn (mut s RemapSet) parse(inp string) ! {
	// Find the assignment point ('=')
	eql_idx := inp.index_u8(`=`)
	if eql_idx < 0 {
		return error('missing assignment')
	}

	// Parse the "to" side (defaults to left if no explicit side)
	to_str := inp[eql_idx + 1..]
	to_mod, to_side_opt := parse_mod(to_str)!
	to_side := to_side_opt or { Side.left }
	to_mods := init_mods(to_mod, to_side)

	// Parse the "from" side
	from_str := inp[..eql_idx]
	from_mod, from_side_opt := parse_mod(from_str)!

	if from_side := from_side_opt {
		// Sided from: add single mapping
		from_mods := init_mods(from_mod, from_side)
		s.put_mapping(from_mods, to_mods)
	} else {
		// Unsided from: add both left and right mappings
		from_left := init_mods(from_mod, .left)
		from_right := init_mods(from_mod, .right)
		s.put_mapping(from_left, to_mods)
		s.put_mapping(from_right, to_mods)
	}
}

// put_mapping matches AutoArrayHashMap.put in the source: parsing the same
// physical modifier and side again replaces its destination in place.
fn (mut s RemapSet) put_mapping(from Mods, to Mods) {
	for i, entry in s.entries {
		if entry.from.equal_sided(from) {
			s.entries[i] = RemapEntry{
				from: from
				to: to
			}
			s.mask.update(from)
			return
		}
	}
	s.entries << RemapEntry{
		from: from
		to: to
	}
	s.mask.update(from)
}

// finalize must be called prior to any remappings so that the mapping
// is sorted properly. Right-sided entries sort first.
pub fn (mut s RemapSet) finalize() {
	// Sort so that entries with right sides come first
	s.entries.sort_with_compare(fn (a &RemapEntry, b &RemapEntry) int {
		a_has_right := a.from.sides_int() != 0
		b_has_right := b.from.sides_int() != 0
		if a_has_right && !b_has_right {
			return -1
		}
		if !a_has_right && b_has_right {
			return 1
		}
		return 0
	})
}

// is_remapped returns true if the given mods need remapping.
pub fn (s RemapSet) is_remapped(mods Mods) bool {
	return s.mask.does_match(mods)
}

// apply applies a remap to the given mods.
pub fn (s RemapSet) apply(mods Mods) Mods {
	if !s.is_remapped(mods) {
		return mods
	}

	mods_binding := mods.keys_int()
	mods_sides := mods.sides_int()

	for entry in s.entries {
		from_binding := entry.from.keys_int()
		if mods_binding & from_binding != from_binding {
			continue
		}
		from_sides := entry.from.sides_int()
		if (mods_sides ^ from_sides) & from_binding != 0 {
			continue
		}

		// Found a match - apply the remap
		mut mods_int := mods.int()
		mods_int &= ~entry.from.int()
		mods_int |= entry.to.int()
		return mods_from_int(mods_int)
	}

	return mods
}

// parse_cli parses from CLI input. Required by Config.
//
// An empty value resets the set. A non-empty value is parsed and added
// to the set. Faithful to Zig `parseCLI`.
pub fn (mut s RemapSet) parse_cli(inp ?string) ! {
	value := inp or { '' }

	// Empty value resets the set
	if value.len == 0 {
		s.entries = []RemapEntry{}
		s.mask = RemapMask{}
		return
	}

	s.parse(value) or { return error('invalid value') }
}

// deinit releases any resources held by the set. Required by Config.
pub fn (mut s RemapSet) deinit() {
	s.entries = []RemapEntry{}
	s.mask = RemapMask{}
}

// clone returns a deep copy of the struct. Required by Config.
pub fn (s RemapSet) clone() RemapSet {
	return RemapSet{
		entries: s.entries.clone()
		mask: s.mask
	}
}

// equal compares if two RemapSets are equal. Required by Config.
pub fn (s RemapSet) equal(other RemapSet) bool {
	if s.entries.len != other.entries.len {
		return false
	}

	// For every from->to mapping in self, the other must have a mapping
	// with the same "from" and an equal "to".
	for entry in s.entries {
		mut found := false
		for oentry in other.entries {
			if oentry.from.equal_sided(entry.from) {
				if !oentry.to.equal_sided(entry.to) {
					return false
				}
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}

	return true
}

// format_entry returns the configuration entry lines for this set. Used by
// the Formatter. Required by Config. In Zig this writes into a formatter;
// here we return the list of `key-remap` value strings (one per mapping).
// If the set is empty, a single empty string is returned to represent the
// unset (void) value.
pub fn (s RemapSet) format_entry() []string {
	if s.entries.len == 0 {
		return ['']
	}

	mut out := []string{cap: s.entries.len}
	for entry in s.entries {
		from := format_mod(entry.from)
		to := format_mod(entry.to)
		out << '${from}=${to}'
	}
	return out
}

// format_mod formats the single set modifier of `mods` with its side prefix.
// Faithful to Zig `formatMod`: iterates shift, ctrl, alt, super in order and
// emits the first one that is set, prefixed with its side.
fn format_mod(mods Mods) string {
	sides := mods.sides()
	if mods.shift() {
		return side_prefix(sides.shift()) + 'shift'
	}
	if mods.ctrl() {
		return side_prefix(sides.ctrl()) + 'ctrl'
	}
	if mods.alt() {
		return side_prefix(sides.alt()) + 'alt'
	}
	if mods.super_() {
		return side_prefix(sides.super_()) + 'super'
	}
	return ''
}

// side_prefix returns the "right_"/"left_" prefix for the given side.
fn side_prefix(side Side) string {
	return if side == .right { 'right_' } else { 'left_' }
}

// equal_sided compares two Mods including their side information. This is
// needed for RemapSet.equal since remappings are side-specific.
fn (a Mods) equal_sided(b Mods) bool {
	return a.equal(b)
}

// parse_mod parses a single modifier string like "ctrl", "left_shift", "cmd".
// Returns the Mod and an optional Side.
fn parse_mod(inp string) !(Mod, ?Side) {
	// Check for side prefix
	underscore_idx := inp.index_u8(`_`)
	mut side_str := ''
	mut mod_str := inp
	if underscore_idx >= 0 {
		side_str = inp[..underscore_idx]
		mod_str = inp[underscore_idx + 1..]
	}

	// Parse the modifier name
	mod_val := if mod_str == 'shift' {
		Mod.shift
	} else if mod_str == 'ctrl' {
		Mod.ctrl
	} else if mod_str == 'alt' {
		Mod.alt
	} else if mod_str == 'super' {
		Mod.super_
	} else if mod_str in mod_aliases {
		mod_aliases[mod_str]
	} else {
		return error('invalid modifier: ${mod_str}')
	}

	// Parse optional side
	if side_str.len > 0 {
		side_val := if side_str == 'left' {
			Side.left
		} else if side_str == 'right' {
			Side.right
		} else {
			return error('invalid side: ${side_str}')
		}
		return mod_val, side_val
	}

	return mod_val, none
}

// init_mods creates a Mods with a single modifier set on the given side.
fn init_mods(mod_val Mod, side Side) Mods {
	mut m := Mods{}
	match mod_val {
		.shift {
			m.set_shift(true)
			m.set_side_shift(side)
		}
		.ctrl {
			m.set_ctrl(true)
			m.set_side_ctrl(side)
		}
		.alt {
			m.set_alt(true)
			m.set_side_alt(side)
		}
		.super_ {
			m.set_super(true)
			m.set_side_super(side)
		}
	}
	return m
}

// mods_from_int reconstructs Mods from a u16 integer value.
//
// Faithful to the Zig packed `Mods` bitcast layout; the round-trip with
// `Mods.int()` preserves the standard keys, the locks and the sides.
pub fn mods_from_int(v u16) Mods {
	return Mods.from_int(v)
}
