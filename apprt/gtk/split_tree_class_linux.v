@[has_globals]
module gtk

// split_tree_class_linux.v - The GObject SplitTree *widget* class for the GTK
// apprt.
//
// Translated from ghostty/src/apprt/gtk/class/split_tree.zig.
//
// This is the GTK4 GObject widget that displays a tree of terminal surfaces
// divided by draggable splits. The actual immutable tree data structure (the
// layout/navigation/split/resize arithmetic) is witty's `datastruct.SplitTree`
// (see witty/datastruct/split_tree.v); this widget WRAPS that data structure
// and builds a GtkPaned-based widget tree from it, writing user resize actions
// back into the tree.
//
// Witty keeps the immutable surface tree in V and constructs the equivalent
// GtkBox/AdwBin/GtkPaned graph directly. The surrounding GhosttySplitTree
// GObject class, boxed tree value, properties, signal, and lifecycle are
// registered through the same GLib contracts as Ghostty's Zig implementation.

import datastruct
import log

// --- New C bindings unique to this file -----------------------------------
//
// GtkPaned / GtkOrientable / AdwBin / GLib idle-source functions used by the
// widget-tree build and the paned<->ratio conversion. Grep-verified that none
// of these `fn C.` decls already exist in the module.

// GtkPaned*.
pub type GtkPaned = voidptr

// GtkOrientation. The two values we care about (0 = horizontal, 1 = vertical).
pub type GtkOrientation = int

// GtkPaned
fn C.gtk_paned_set_start_child(paned GtkPaned, child GtkWidget)

fn C.gtk_paned_set_end_child(paned GtkPaned, child GtkWidget)

fn C.gtk_paned_set_orientation(paned GtkPaned, orientation GtkOrientation)

fn C.gtk_paned_get_position(paned GtkPaned) int

fn C.gtk_paned_set_position(paned GtkPaned, position int)

fn C.gtk_paned_new(orientation GtkOrientation) GtkPaned

// AdwBin
fn C.adw_bin_set_child(bin AdwBin, child GtkWidget)

// GtkWidget extra helpers (not declared elsewhere in the module)
fn C.gtk_widget_get_parent(widget GtkWidget) GtkWidget

fn C.gtk_label_new(text &char) GtkWidget

// GLib idle source
fn C.g_idle_add(function voidptr, data voidptr) u32

// --- SurfaceTree alias -----------------------------------------------------

// SurfaceTree is the surface split-tree data model. In ghostty this is
// `Surface.Tree` (a `SplitTree(*Surface)`); here it is the same immutable tree
// data structure parameterized on the local `SurfaceWidget` view type.
pub type SurfaceTree = datastruct.SplitTree[SurfaceWidget]

// --- GObject class and boxed tree registration ----------------------------

__global g_split_tree_type = GType(0)

// The instance-private offset: the size until class_init adjusts it, then
// the (negative) offset from the instance. Mirrors zig-gobject's `Private.offset`.
__global g_split_tree_priv_offset = int(0)
__global g_surface_tree_boxed_type = GType(0)
__global g_split_tree_pspec_active_surface = &C.GParamSpec(unsafe { nil })
__global g_split_tree_pspec_has_surfaces = &C.GParamSpec(unsafe { nil })
__global g_split_tree_pspec_is_zoomed = &C.GParamSpec(unsafe { nil })
__global g_split_tree_pspec_tree = &C.GParamSpec(unsafe { nil })
__global g_split_tree_pspec_is_split = &C.GParamSpec(unsafe { nil })

struct C.GhosttySplitTreePrivate {
mut:
	wrapper voidptr
}

const split_tree_prop_active_surface = u32(1)
const split_tree_prop_has_surfaces = u32(2)
const split_tree_prop_is_zoomed = u32(3)
const split_tree_prop_tree = u32(4)
const split_tree_prop_is_split = u32(5)

// defineProperty marks its compile-time name/nick/blurb strings as static.
const split_tree_param_static_strings = int(32 | 64 | 128)

fn split_tree_priv(obj voidptr) &C.GhosttySplitTreePrivate {
	return &C.GhosttySplitTreePrivate(instance_private(obj, g_split_tree_priv_offset))
}

// surface_tree_boxed_copy/free mirror Surface.Tree.getGObjectType's custom
// boxed callbacks. A boxed copy owns a cloned immutable tree and therefore a
// reference to every SurfaceWidget leaf.
fn surface_tree_boxed_copy(value voidptr) voidptr {
	if isnil(value) {
		return unsafe { nil }
	}
	tree := unsafe { &SurfaceTree(value) }
	copy := tree.clone()
	return voidptr(&SurfaceTree{
		nodes:  copy.nodes
		zoomed: copy.zoomed
	})
}

fn surface_tree_boxed_free(value voidptr) {
	if isnil(value) {
		return
	}
	mut tree := unsafe { &SurfaceTree(value) }
	tree.free()
	unsafe { free(tree) }
}

// surface_tree_get_type returns the exact boxed type instantiated by
// datastruct.SplitTree(Surface) in the pinned Ghostty source.
pub fn surface_tree_get_type() GType {
	if g_surface_tree_boxed_type == GType(0) {
		g_surface_tree_boxed_type = C.g_boxed_type_register_static(c'GhosttySplitTreeSurface', voidptr(surface_tree_boxed_copy), voidptr(surface_tree_boxed_free))
	}
	return g_surface_tree_boxed_type
}

fn split_tree_get_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	priv := split_tree_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &SplitTreeWidget(priv.wrapper) }
	match property_id {
		split_tree_prop_active_surface {
			if surface := self.get_active_surface() {
				C.g_value_set_object(value, surface.widget)
			} else {
				C.g_value_set_object(value, unsafe { nil })
			}
		}
		split_tree_prop_has_surfaces {
			C.g_value_set_boolean(value, b2i(self.get_has_surfaces()))
		}
		split_tree_prop_is_zoomed {
			C.g_value_set_boolean(value, b2i(self.get_is_zoomed()))
		}
		split_tree_prop_tree {
			if self.has_tree {
				C.g_value_set_boxed(value, &self.tree)
			} else {
				C.g_value_set_boxed(value, unsafe { nil })
			}
		}
		split_tree_prop_is_split {
			C.g_value_set_boolean(value, b2i(self.get_is_split()))
		}
		else {}
	}
}

fn split_tree_set_property(obj voidptr, property_id u32, value voidptr, pspec voidptr) {
	_ = pspec
	if property_id != split_tree_prop_tree {
		return
	}
	priv := split_tree_priv(obj)
	if isnil(priv.wrapper) {
		return
	}
	mut self := unsafe { &SplitTreeWidget(priv.wrapper) }
	boxed := C.g_value_get_boxed(value)
	if isnil(boxed) {
		self.set_tree(none)
	} else {
		tree := unsafe { &datastruct.SplitTree[SurfaceWidget](boxed) }
		self.set_tree(tree)
	}
}

fn split_tree_dispose(obj voidptr) {
	priv := split_tree_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SplitTreeWidget(priv.wrapper) }
		self.last_focused.set(unsafe { nil })
		if self.rebuild_source != 0 {
			if !C.g_source_remove(self.rebuild_source) {
				log.warn('unable to remove rebuild source')
			}
			self.rebuild_source = 0
		}
		self.rebuild_pending = false
		if !isnil(self.tree_bin) {
			C.adw_bin_set_child(self.tree_bin, GtkWidget(unsafe { nil }))
		}
	}
	C.witty_gobject_call_parent_dispose(obj)
}

fn split_tree_finalize(obj voidptr) {
	mut priv := split_tree_priv(obj)
	if !isnil(priv.wrapper) {
		mut self := unsafe { &SplitTreeWidget(priv.wrapper) }
		if self.has_tree {
			self.disconnect_surface_handlers()
			self.tree.free()
			self.has_tree = false
		}
		self.surfaces.clear()
		self.scrolled_windows.clear()
		self.splits.clear()
		self.widget = unsafe { nil }
		self.tree_bin = unsafe { nil }
		priv.wrapper = unsafe { nil }
	}
	C.witty_gobject_call_parent_finalize(obj)
}

fn split_tree_class_init(klass voidptr, class_data voidptr) {
	C.g_type_class_adjust_private_offset(klass, &g_split_tree_priv_offset)
	_ = class_data
	_ = terminal_surface_get_type()
	tree_type := surface_tree_get_type()
	C.witty_gobject_class_set_get_property(klass, voidptr(split_tree_get_property))
	C.witty_gobject_class_set_set_property(klass, voidptr(split_tree_set_property))
	C.witty_gobject_class_set_dispose(klass, voidptr(split_tree_dispose))
	C.witty_gobject_class_set_finalize(klass, voidptr(split_tree_finalize))
	readable := g_param_readable | split_tree_param_static_strings
	readwrite := g_param_readwrite | split_tree_param_static_strings
	nil_str := &char(unsafe { nil })
	g_split_tree_pspec_active_surface = C.g_param_spec_object(c'active-surface', nil_str, nil_str, terminal_surface_get_type(), readable)
	g_split_tree_pspec_has_surfaces = C.g_param_spec_boolean(c'has-surfaces', nil_str, nil_str, 0, readable)
	g_split_tree_pspec_is_zoomed = C.g_param_spec_boolean(c'is-zoomed', nil_str, nil_str, 0, readable)
	g_split_tree_pspec_tree = C.g_param_spec_boxed(c'tree', nil_str, nil_str, tree_type, readwrite)
	g_split_tree_pspec_is_split = C.g_param_spec_boolean(c'is-split', nil_str, nil_str, 0, readable)
	C.g_object_class_install_property(klass, split_tree_prop_active_surface, g_split_tree_pspec_active_surface)
	C.g_object_class_install_property(klass, split_tree_prop_has_surfaces, g_split_tree_pspec_has_surfaces)
	C.g_object_class_install_property(klass, split_tree_prop_is_zoomed, g_split_tree_pspec_is_zoomed)
	C.g_object_class_install_property(klass, split_tree_prop_tree, g_split_tree_pspec_tree)
	C.g_object_class_install_property(klass, split_tree_prop_is_split, g_split_tree_pspec_is_split)
	C.g_signal_new(c'changed', g_split_tree_type, g_signal_run_last, 0, unsafe { nil }, unsafe { nil }, unsafe { nil }, g_type_none, 2, tree_type, tree_type)
}

fn split_tree_instance_init(instance voidptr, klass voidptr) {
	_ = klass
	C.gtk_orientable_set_orientation(instance, 1)
	C.gtk_widget_set_hexpand(GtkWidget(instance), 1)
	C.gtk_widget_set_vexpand(GtkWidget(instance), 1)
}

pub fn split_tree_get_type() GType {
	if g_split_tree_type == GType(0) {
		parent := C.gtk_box_get_type()
		mut query := C.GTypeQuery{}
		C.g_type_query(parent, &query)
		info := C.GTypeInfo{
			class_size:    u16(query.class_size)
			instance_size: u16(query.instance_size)
			class_init:    voidptr(split_tree_class_init)
			instance_init: voidptr(split_tree_instance_init)
		}
		g_split_tree_type = C.g_type_register_static(parent, c'GhosttySplitTree', &info, 0)
		g_split_tree_priv_offset = C.g_type_add_instance_private(g_split_tree_type, sizeof(C.GhosttySplitTreePrivate))
	}
	return g_split_tree_type
}

// --- SplitTreeWidget ------------------------------------------------------

// SplitTreeWidget is the V model of the `GhosttySplitTree` GObject class. It
// wraps the GtkWidget pointer and carries the state that lived in Ghostty's
// private GObject storage.
@[heap]
pub struct SplitTreeWidget {
pub mut:
	// The GtkWidget (gtk.Box) pointer for this instance.
	widget GtkWidget = unsafe { nil }

	window &Window = unsafe { nil }
	config &Config = unsafe { nil }

	// The tree data structure containing all of our surface views. `none`
	// (modeled with the has_tree flag) means an empty tree. In ghostty this is
	// `?*Surface.Tree`; we store the value inline and track presence.
	tree     SurfaceTree
	has_tree bool

	// The adw.Bin that holds the rendered widget tree (template child).
	tree_bin AdwBin = unsafe { nil }

	// Last focused surface in the tree. We need this to handle various tree
	// change states. The weak reference clears itself if the surface is
	// finalized and takes a temporary strong reference when read.
	last_focused WeakRef = weak_ref_empty()

	// The source that we use to rebuild the tree. Also used to debounce
	// updates. 0 means "none".
	rebuild_source u32

	// Whether we want a rebuild to happen at the next tick that our surface
	// tree has no surfaces with parents. See prop_tree for details.
	rebuild_pending bool

	// State about a pending surface close for the close dialog.
	pending_close ?datastruct.Handle

	// Keep wrapper state alive for the GObjects referenced by tree nodes.
	surfaces         []&SurfaceWidget
	scrolled_windows []&SurfaceScrolledWindow
	splits           []&SplitTreeSplit
}

// --- Construction ---------------------------------------------------------

// new_split_tree_widget creates a new SplitTreeWidget. Mirrors the GObject
// `init`: it sets up the widget graph, action group, and basic state.
pub fn new_split_tree_widget(window &Window, config &Config) &SplitTreeWidget {
	tree_bin := C.adw_bin_new()
	widget := GtkWidget(C.g_object_new(split_tree_get_type(), &char(unsafe { nil })))
	C.gtk_widget_set_hexpand(GtkWidget(tree_bin), 1)
	C.gtk_widget_set_vexpand(GtkWidget(tree_bin), 1)
	C.gtk_box_append(widget, GtkWidget(tree_bin))
	mut w := &SplitTreeWidget{
		widget:   widget
		window:   window
		config:   config
		tree_bin: tree_bin
	}
	mut priv := split_tree_priv(voidptr(widget))
	priv.wrapper = voidptr(w)
	w.pending_close = none
	w.init_action_map()
	return w
}

// init_action_map registers the "split-tree" action group. Mirrors
// `initActionMap`.
fn (mut self SplitTreeWidget) init_action_map() {
	string_type := C.g_variant_type_new(c's')
	actions := [
		Action.init('new-split', GCallback(voidptr(split_tree_action_new_split_cb)), string_type),
		Action.init('equalize', GCallback(voidptr(split_tree_action_equalize_cb)), unsafe { nil }),
		Action.init('zoom', GCallback(voidptr(split_tree_action_zoom_cb)), unsafe { nil }),
	]
	add_as_group(voidptr(self), self.widget, 'split-tree', actions)
	C.g_variant_type_free(string_type)
}

fn split_tree_action_new_split_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	if isnil(data) {
		return
	}
	if isnil(parameter) {
		log.warn('split-tree.new-split called without a parameter')
		return
	}
	mut length := uint(0)
	value := C.g_variant_get_string(parameter, &length)
	if isnil(value) {
		return
	}
	mut self := unsafe { &SplitTreeWidget(data) }
	self.action_new_split(unsafe { cstring_to_vstring(value) })
}

fn split_tree_action_equalize_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	_ = parameter
	if !isnil(data) {
		mut self := unsafe { &SplitTreeWidget(data) }
		self.action_equalize()
	}
}

fn split_tree_action_zoom_cb(action GSimpleAction, parameter GVariant, data voidptr) {
	_ = action
	_ = parameter
	if !isnil(data) {
		mut self := unsafe { &SplitTreeWidget(data) }
		self.action_zoom()
	}
}

// --- Tree get/set ---------------------------------------------------------

// get_tree returns the tree data model, or `none` if empty. Does not clone.
// Mirrors `getTree`.
pub fn (mut self SplitTreeWidget) get_tree() ?&datastruct.SplitTree[SurfaceWidget] {
	if !self.has_tree {
		return none
	}
	return &self.tree
}

// set_tree sets the tree data model. In ghostty this clones the given tree; the
// datastruct tree is ref-counted so we clone to take our own reference. Empty
// trees are normalized to "no tree". Mirrors `setTree`.
pub fn (mut self SplitTreeWidget) set_tree(tree_ ?&datastruct.SplitTree[SurfaceWidget]) {
	// Normalize: empty trees become "no tree".
	mut new_has := false
	mut new_ptr := voidptr(&self.tree)
	if t := tree_ {
		if !t.is_empty() {
			new_has = true
			new_ptr = voidptr(t)
		}
	}
	if !new_has {
		new_ptr = unsafe { nil }
	}

	// Emit before replacing the tree so handlers can inspect both values.
	mut old_ptr := voidptr(&self.tree)
	if !self.has_tree {
		old_ptr = unsafe { nil }
	}
	if !isnil(self.widget) {
		C.g_signal_emit_by_name(self.widget, c'changed', old_ptr, new_ptr)
	}

	// Free the old tree (unref its views) and disconnect surface handlers.
	if self.has_tree {
		self.disconnect_surface_handlers()
		self.tree.free()
		self.has_tree = false
	}

	if new_has {
		if t := tree_ {
			self.tree = t.clone()
			self.has_tree = true
			self.connect_surface_handlers()
		}
	}

	// Ghostty binds SplitTree.is-split to every Surface.is-split. Keep the
	// programmatic widget graph synchronized whenever the immutable tree is
	// replaced, including when the last split is closed.
	is_split := self.get_is_split()
	for mut surface in self.surfaces {
		surface.set_is_split(is_split)
	}

	self.notify_property(g_split_tree_pspec_tree)
	self.prop_tree()
}

fn (self &SplitTreeWidget) notify_property(pspec &C.GParamSpec) {
	if !isnil(self.widget) && !isnil(pspec) {
		C.g_object_notify_by_pspec(self.widget, pspec)
	}
}

// sync_tab evaluates the Tab blueprint's nested Surface title/tooltip bindings
// when a surface property changes. SplitTree property changes use native
// notify signals and the callbacks installed by new_tab.
fn (self &SplitTreeWidget) sync_tab() {
	if isnil(self.window) {
		return
	}
	mut window := unsafe { self.window }
	for mut tab in window.tabs {
		if tab.split_tree == self {
			tab.sync_from_active_surface()
			return
		}
	}
}

// --- Derived state (properties) -------------------------------------------

// get_has_surfaces returns whether the tree has any surfaces. Mirrors
// `getHasSurfaces`.
pub fn (self &SplitTreeWidget) get_has_surfaces() bool {
	if !self.has_tree {
		return false
	}
	return !self.tree.is_empty()
}

// get_is_zoomed returns whether the tree has a zoomed node. Mirrors
// `getIsZoomed`.
pub fn (self &SplitTreeWidget) get_is_zoomed() bool {
	if !self.has_tree {
		return false
	}
	return self.tree.zoomed != none
}

// get_is_split returns whether the root node is a split. Mirrors `getIsSplit`.
pub fn (self &SplitTreeWidget) get_is_split() bool {
	if !self.has_tree {
		return false
	}
	return self.tree.is_split()
}

// get_needs_confirm_quit returns true if any surface in the tree needs
// confirmation before quitting. Mirrors `getNeedsConfirmQuit`.
pub fn (self &SplitTreeWidget) get_needs_confirm_quit() bool {
	if !self.has_tree {
		return false
	}
	mut it := self.tree.iterator()
	for {
		entry := it.next() or { break }
		mut view := entry.view
		if mut core := view.core() {
			if core.needs_confirm_quit() {
				return true
			}
		}
	}
	return false
}

// --- Active surface -------------------------------------------------------

// get_active_surface returns the currently active surface, or `none`. Mirrors
// `getActiveSurface`. Does not ref.
pub fn (mut self SplitTreeWidget) get_active_surface() ?&SurfaceWidget {
	if !self.has_tree {
		return none
	}
	handle := self.get_active_surface_handle() or { return none }
	node := self.tree.nodes[handle.idx()]
	if node is datastruct.Leaf[SurfaceWidget] {
		return node.view
	}
	panic('active split tree handle ${handle.idx()} is not a leaf node')
}

// get_active_surface_handle returns the tree handle (node index) of the active
// surface, or `none`. The active surface is the focused surface, falling back
// to the last-focused surface. Mirrors `getActiveSurfaceHandle`.
fn (mut self SplitTreeWidget) get_active_surface_handle() ?datastruct.Handle {
	if !self.has_tree {
		return none
	}

	// Prefer the currently-focused surface.
	mut it := self.tree.iterator()
	for {
		entry := it.next() or { break }
		if entry.view.get_focused() {
			return entry.handle
		}
	}

	// Otherwise fall back to the last-focused surface, if it's still in the
	// tree. This keeps background actions (bell etc.) working.
	last_focused := self.last_focused.get()
	if !isnil(last_focused) {
		defer {
			object_unref(last_focused)
		}
		mut it2 := self.tree.iterator()
		for {
			entry := it2.next() or { break }
			if GObject(entry.view.widget) == last_focused {
				return entry.handle
			}
		}
	}

	return none
}

// get_last_focused_surface returns the last-focused surface in the tree, or
// `none`. Mirrors `getLastFocusedSurface`.
pub fn (mut self SplitTreeWidget) get_last_focused_surface() ?&SurfaceWidget {
	last_focused := self.last_focused.get()
	if isnil(last_focused) {
		return none
	}
	defer {
		object_unref(last_focused)
	}
	return window_surface_wrapper(GtkWidget(last_focused)) or {
		panic('last-focused object is not a translated surface')
	}
}

// get_tree_has_parents returns whether any surface in the tree currently has a
// GTK parent. We can only rebuild the widget tree when every surface has been
// unparented. Mirrors `getTreeHasParents`.
fn (self &SplitTreeWidget) get_tree_has_parents() bool {
	if !self.has_tree {
		return false
	}
	mut it := self.tree.iterator()
	for {
		entry := it.next() or { break }
		w := entry.view.as_widget()
		parent := C.gtk_widget_get_parent(w)
		if !isnil(parent) {
			return true
		}
	}
	return false
}

// --- Mutations ------------------------------------------------------------

// new_split creates a new split in the given direction from the currently
// active surface. If the tree is empty this creates a new tree with a new
// surface (ignoring direction). The `parent_` surface is used as the parent of
// the new surface. Mirrors `newSplit`.
pub fn (mut self SplitTreeWidget) new_split(direction datastruct.Direction, parent_ ?&SurfaceWidget) {
	// Create our new surface.
	mut surface := new_surface_widget(self.window, self, self.config)
	C.g_object_ref_sink(GObject(surface.widget))
	defer {
		surface.unref()
	}
	self.surfaces << surface

	// Inherit from the parent if asked to.
	if p := parent_ {
		if core_parent := p.core() {
			surface.set_parent(core_parent, .split)
		}
	}
	surface.set_is_split(self.get_is_split())

	// Create a single-node tree from the new surface.
	mut single_tree := datastruct.SplitTree.new[SurfaceWidget](surface)
	defer {
		single_tree.free()
	}

	// Move focus to the new surface no matter what.
	self.last_focused.set(GObject(surface.widget))

	// If we have no tree yet, this single tree becomes our tree.
	if !self.has_tree {
		self.set_tree(&single_tree)
		return
	}

	// Split relative to the active surface (root if none).
	handle := self.get_active_surface_handle() or { datastruct.handle_root }

	// Create the split! Always split equally for new splits.
	mut new_tree := self.tree.split_(handle, direction, 0.5, &single_tree)
	defer {
		new_tree.free()
	}
	self.set_tree(&new_tree)
}

// resize resizes the active surface's nearest split matching the given
// direction by `amount` pixels. Returns true if a resize happened. Mirrors
// `resize`: it converts the pixel amount into a grid-relative ratio using the
// current pixel dimensions of the tree bin, then delegates to the tree's
// immutable resize.
pub fn (mut self SplitTreeWidget) resize(direction datastruct.Direction, amount u16) bool {
	// Avoid useless work.
	if amount == 0 {
		return false
	}
	if !self.has_tree {
		return false
	}
	active := self.get_active_surface_handle() or { return false }

	// Get the dimensions needed to turn the pixel amount into a percentage.
	bin_widget := GtkWidget(self.tree_bin)
	width := C.gtk_widget_get_width(bin_widget)
	height := C.gtk_widget_get_height(bin_widget)
	if width == 0 || height == 0 {
		return false
	}
	width_f := f64(width)
	height_f := f64(height)
	amount_f := f64(amount)

	// Positive is right/down, negative is left/up.
	ratio := match direction {
		.right { amount_f / width_f }
		.left { -(amount_f / width_f) }
		.down { amount_f / height_f }
		.up { -(amount_f / height_f) }
	}

	layout := match direction {
		.left, .right { datastruct.Layout.horizontal }
		.up, .down { datastruct.Layout.vertical }
	}

	mut new_tree := self.tree.resize(active, layout, f32(ratio))
	defer {
		new_tree.free()
	}
	self.set_tree(&new_tree)
	return true
}

// goto_ moves focus from the currently focused surface in the given direction.
// Returns true if focus switched to a new surface. Mirrors `goto`. (Named with
// a trailing underscore to match the datastruct method and avoid the keyword.)
pub fn (mut self SplitTreeWidget) goto_(to datastruct.Goto) bool {
	if !self.has_tree {
		return false
	}
	active := self.get_active_surface_handle() or { return false }

	target := self.tree.goto_(active, to) or { return false }

	// If we aren't changing targets then we did nothing.
	if active == target {
		return false
	}

	// Grab focus on the target surface.
	node := self.tree.nodes[target.idx()]
	mut surface := &SurfaceWidget(unsafe { nil })
	if node is datastruct.Leaf[SurfaceWidget] {
		surface = node.view
	} else {
		panic('split tree navigation target ${target.idx()} is not a leaf node')
	}
	surface.grab_focus()

	// Record the new last-focused so a subsequent tree change refocuses right.
	self.last_focused.set(GObject(surface.widget))

	// Handle zoom preservation on navigation.
	if self.tree.zoomed != none {
		if !self.config.get().split_preserve_zoom.navigation() {
			self.tree.zoom(none)
		} else {
			self.tree.zoom(target)
		}
		self.notify_property(g_split_tree_pspec_tree)
		self.prop_tree()
		self.notify_property(g_split_tree_pspec_is_zoomed)
	}

	return true
}

// --- Surface lifecycle wiring ---------------------------------------------

fn split_tree_surface_close_request_cb(widget GtkWidget, data voidptr) {
	if isnil(data) {
		return
	}
	surface := window_surface_wrapper(widget) or { return }
	mut self := unsafe { &SplitTreeWidget(data) }
	self.surface_close_request(surface)
}

fn split_tree_surface_focused_cb(widget GtkWidget, pspec voidptr, data voidptr) {
	_ = pspec
	if isnil(data) {
		return
	}
	surface := window_surface_wrapper(widget) or { return }
	mut self := unsafe { &SplitTreeWidget(data) }
	self.prop_surface_focused(surface)
}

fn split_tree_surface_parent_cb(widget GtkWidget, pspec voidptr, data voidptr) {
	_ = widget
	_ = pspec
	if !isnil(data) {
		mut self := unsafe { &SplitTreeWidget(data) }
		self.prop_surface_parent()
	}
}

// connect_surface_handlers connects per-surface close/focus/parent handlers.
// Mirrors `connectSurfaceHandlers`.
fn (mut self SplitTreeWidget) connect_surface_handlers() {
	tree := self.get_tree() or { return }
	mut it := tree.iterator()
	for {
		entry := it.next() or { break }
		surface := entry.view
		C.g_signal_connect_data(surface.widget, c'close-request', GCallback(voidptr(split_tree_surface_close_request_cb)), voidptr(self), unsafe { nil }, 0)
		C.g_signal_connect_data(surface.widget, c'notify::focused', GCallback(voidptr(split_tree_surface_focused_cb)), voidptr(self), unsafe { nil }, 0)
		C.g_signal_connect_data(surface.widget, c'notify::parent', GCallback(voidptr(split_tree_surface_parent_cb)), voidptr(self), unsafe { nil }, 0)
	}
}

// disconnect_surface_handlers disconnects the per-surface handlers.
// Mirrors `disconnectSurfaceHandlers`.
fn (mut self SplitTreeWidget) disconnect_surface_handlers() {
	tree := self.get_tree() or { return }
	mut it := tree.iterator()
	for {
		entry := it.next() or { break }
		C.g_signal_handlers_disconnect_matched(entry.view.widget, g_signal_match_data, 0, 0, unsafe { nil }, unsafe { nil }, voidptr(self))
	}
}

// --- Action handlers ------------------------------------------------------

// action_new_split handles the "split-tree.new-split" action. Mirrors
// `actionNewSplit`. The direction is parsed from the action's string parameter.
pub fn (mut self SplitTreeWidget) action_new_split(dir string) {
	direction := match dir {
		'left' { datastruct.Direction.left }
		'right' { datastruct.Direction.right }
		'down' { datastruct.Direction.down }
		'up' { datastruct.Direction.up }
		else {
			log.warn('invalid split direction for split-tree.new-split: ${dir}')
			return
		}
	}
	self.new_split(direction, self.get_active_surface())
}

// action_equalize handles the "split-tree.equalize" action. Mirrors
// `actionEqualize`.
pub fn (mut self SplitTreeWidget) action_equalize() {
	if !self.has_tree {
		return
	}
	mut new_tree := self.tree.equalize()
	defer {
		new_tree.free()
	}
	self.set_tree(&new_tree)
}

// action_zoom handles the "split-tree.zoom" action: toggles the zoom of the
// active surface. Mirrors `actionZoom`.
pub fn (mut self SplitTreeWidget) action_zoom() {
	if !self.has_tree {
		return
	}
	if self.tree.zoomed != none {
		self.tree.zoom(none)
	} else {
		active := self.get_active_surface_handle() or { return }
		self.tree.zoom(active)
	}
	self.notify_property(g_split_tree_pspec_tree)
	self.prop_tree()
}

// --- Close handling -------------------------------------------------------

// surface_close_request handles a surface's "close-request" signal. Mirrors
// `surfaceCloseRequest`: records the pending-close handle and either closes
// immediately or shows a confirmation dialog.
pub fn (mut self SplitTreeWidget) surface_close_request(surface &SurfaceWidget) {
	mut core := surface.core() or { return }

	// Reset pending close.
	self.pending_close = none

	if !self.has_tree {
		return
	}

	// Find the surface in the tree.
	mut found := ?datastruct.Handle(none)
	mut it := self.tree.iterator()
	for {
		entry := it.next() or { break }
		view := entry.view
		if view.eql(surface) {
			found = entry.handle
			break
		}
	}
	handle := found or { return }
	self.pending_close = handle

	// If we don't need to confirm, close immediately.
	if !core.needs_confirm_quit() {
		self.close_confirmation_close()
		return
	}

	mut dialog := close_confirmation_dialog_new(.surface)
	dialog.set_canvas_enabled(!isnil(self.config) && gtk_canvas_styles_enabled(self.config.get()))
	C.g_signal_connect_data(dialog.dialog.obj, c'close-request', GCallback(voidptr(split_tree_close_confirmed_cb)), voidptr(self), unsafe { nil }, 0)
	dialog.present(self.widget)
}

fn split_tree_close_confirmed_cb(dialog GObject, data voidptr) {
	_ = dialog
	if isnil(data) {
		return
	}
	mut self := unsafe { &SplitTreeWidget(data) }
	self.close_confirmation_close()
}

// close_confirmation_close finalizes a pending surface close: it computes the
// next focus target (previous, else next), removes the surface from the tree,
// and sets the new last-focused. Mirrors `closeConfirmationClose`.
pub fn (mut self SplitTreeWidget) close_confirmation_close() {
	handle := self.pending_close or { return }
	self.pending_close = none
	if !self.has_tree {
		return
	}
	mut closing := &SurfaceWidget(unsafe { nil })
	closing_node := self.tree.nodes[handle.idx()]
	if closing_node is datastruct.Leaf[SurfaceWidget] {
		closing = closing_node.view
	} else {
		panic('pending close handle ${handle.idx()} is not a leaf node')
	}

	// Figure out the next focus target: the "previous" surface unless we're
	// the leftmost, then the "next".
	mut next_focus := &SurfaceWidget(unsafe { nil })
	mut next_handle := self.tree.goto_(handle, datastruct.Goto(datastruct.GotoPrevious{}))
	if next_handle == none {
		next_handle = self.tree.goto_(handle, datastruct.Goto(datastruct.GotoNext{}))
	}
	if target := next_handle {
		if target != handle {
			node := self.tree.nodes[target.idx()]
			if node is datastruct.Leaf[SurfaceWidget] {
				next_focus = node.view
			} else {
				panic('next focus handle ${target.idx()} is not a leaf node')
			}
		}
	}

	// Tear down the core surface before publishing the empty/new tree. An empty
	// tree synchronously closes its tab, so doing this first prevents the tab
	// close path from deinitializing the same surface twice.
	mut new_tree := self.tree.remove(handle)
	defer {
		new_tree.free()
	}
	if !isnil(closing) && !isnil(closing.core_surface_ref) && !isnil(closing.app)
		&& !isnil(closing.app.core_app) {
		mut app := unsafe { closing.app.core_app }
		app.delete_surface(closing.core_surface_ref)
		if closing.has_core() {
			mut core_surface := closing.core_surface
			core_surface.deinit()
			closing.core_surface = unsafe { nil }
		}
		for i, candidate in self.surfaces {
			if candidate == closing {
				self.surfaces.delete(i)
				break
			}
		}
	}
	self.set_tree(&new_tree)

	// Grab focus. We set last_focused because focus is set when the tree is
	// redrawn.
	if !isnil(next_focus) {
		self.last_focused.set(GObject(next_focus.widget))
	}
}

// deinit_surfaces releases every core surface owned by this tab. It is called
// only after AdwTabView has accepted a page close; detached/moved pages keep
// their surfaces alive.
pub fn (mut self SplitTreeWidget) deinit_surfaces() {
	for mut surface in self.surfaces {
		if isnil(surface) {
			continue
		}
		if !isnil(surface.core_surface_ref) && !isnil(surface.app)
			&& !isnil(surface.app.core_app) {
			mut app := unsafe { surface.app.core_app }
			app.delete_surface(surface.core_surface_ref)
		}
		if surface.has_core() {
			mut core_surface := surface.core_surface
			core_surface.deinit()
			surface.core_surface = unsafe { nil }
			surface.core_surface_ref = unsafe { nil }
		}
	}
	self.surfaces.clear()
	if self.has_tree {
		self.disconnect_surface_handlers()
		self.tree.free()
		self.has_tree = false
	}
}

// --- Focus / parent property handlers -------------------------------------

// prop_surface_focused handles a surface's notify::focused. Mirrors
// `propSurfaceFocused`: records the last-focused surface (never clears it).
pub fn (mut self SplitTreeWidget) prop_surface_focused(surface &SurfaceWidget) {
	if !surface.get_focused() {
		return
	}
	self.last_focused.set(GObject(surface.widget))
	self.notify_property(g_split_tree_pspec_active_surface)
}

// prop_surface_parent handles a surface's notify::parent. Mirrors
// `propSurfaceParent`: once all surfaces are unparented, schedule the rebuild.
pub fn (mut self SplitTreeWidget) prop_surface_parent() {
	if !self.rebuild_pending {
		return
	}
	if self.get_tree_has_parents() {
		return
	}
	assert self.rebuild_source == 0
	self.rebuild_pending = false
	self.rebuild_source = C.g_idle_add(voidptr(split_tree_rebuild_cb), self)
}

// prop_tree handles our own notify::tree. Mirrors `propTree`: it tears down the
// current bin child (forcing surfaces to unparent) and either rebuilds
// immediately (via an idle source) or waits for all surfaces to be unparented.
fn (mut self SplitTreeWidget) prop_tree() {
	// Cancel any pending rebuild so we start clean.
	if self.rebuild_source != 0 {
		if !C.g_source_remove(self.rebuild_source) {
			log.warn('unable to remove rebuild source')
		}
		self.rebuild_source = 0
	}

	// We need to wait for prior surfaces to lose their parent before adding
	// them to a new one (a GTK GLArea quirk).
	self.rebuild_pending = self.get_tree_has_parents()

	// Reset our bin, forcing prior surfaces to eventually unparent.
	if !isnil(self.tree_bin) {
		C.adw_bin_set_child(self.tree_bin, GtkWidget(unsafe { nil }))
	}
	if self.rebuild_pending {
		self.prop_surface_parent()
	}

	// If nothing needs unparenting, we can rebuild immediately (on idle).
	if !self.rebuild_pending && self.rebuild_source == 0 {
		self.rebuild_source = C.g_idle_add(voidptr(split_tree_rebuild_cb), self)
	}

	// Dependent properties.
	self.notify_property(g_split_tree_pspec_has_surfaces)
	self.notify_property(g_split_tree_pspec_is_zoomed)
}

fn split_tree_rebuild_cb(data voidptr) int {
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SplitTreeWidget(data) }
	self.on_rebuild()
	return 0
}

// on_rebuild rebuilds the widget tree from the current data model. Mirrors
// `onRebuild`; split_tree_rebuild_cb is its GLib idle trampoline.
pub fn (mut self SplitTreeWidget) on_rebuild() {
	self.rebuild_source = 0

	// Prior to rebuilding, all surfaces must be orphaned.
	assert !self.get_tree_has_parents()

	// The previous native widget graph has been disposed now that its terminal
	// surfaces are orphaned, so its translated wrappers can be released before
	// constructing their replacements.
	self.scrolled_windows.clear()
	self.splits.clear()

	if self.has_tree && !self.tree.is_empty() {
		root := self.tree.zoomed or { datastruct.handle_root }
		child := self.build_tree(root)
		if !isnil(self.tree_bin) {
			C.adw_bin_set_child(self.tree_bin, child)
		}
	}

	// Refocus the last-focused surface (GTK resets focus during rebuild).
	last_focused := self.last_focused.get()
	if !isnil(last_focused) {
		defer {
			object_unref(last_focused)
		}
		surface := window_surface_wrapper(GtkWidget(last_focused)) or {
			panic('last-focused object is not a translated surface')
		}
		surface.grab_focus()
	}

	self.notify_property(g_split_tree_pspec_is_split)
	self.notify_property(g_split_tree_pspec_active_surface)
}

// build_tree builds the widget subtree for the node at `current`. Leaves become
// a SurfaceScrolledWindow around the surface; splits become a SplitTreeSplit
// (GtkPaned wrapper) with recursively-built children. Mirrors `buildTree`.
fn (mut self SplitTreeWidget) build_tree(current datastruct.Handle) GtkWidget {
	node := self.tree.nodes[current.idx()]
	match node {
		datastruct.Leaf[SurfaceWidget] {
			mut scrolled := new_surface_scrolled_window()
			scrolled.set_surface(node.view)
			self.scrolled_windows << scrolled
			return scrolled.widget
		}
		datastruct.Split {
			start_child := self.build_tree(node.left)
			end_child := self.build_tree(node.right)
			split := new_split_tree_split(current, node.layout, start_child, end_child)
			self.splits << split
			return split.widget
		}
	}
}

// --- SplitTreeSplit -------------------------------------------------------

// SplitTreeSplit is the internal-only widget representing a single split in the
// tree. It wraps a gtk.Paned so that we can position the split by ratio (0..1)
// and write the updated ratio back to the tree when the user drags the divider.
// Mirrors the Zig `SplitTreeSplit`.
//
// This is an immutable widget: it isn't meant to be updated after creation.
@[heap]
pub struct SplitTreeSplit {
pub mut:
	// The GtkWidget (adw.Bin) pointer for this instance.
	widget GtkWidget = unsafe { nil }

	// The handle of the node in the tree that this split represents.
	handle datastruct.Handle

	// Source to reposition the split when properties change. 0 means none.
	idle u32

	// The gtk.Paned template child.
	paned GtkPaned = unsafe { nil }
}

// new_split_tree_split creates a new SplitTreeSplit for the given node handle,
// layout, and child widgets. Mirrors `SplitTreeSplit.new`.
pub fn new_split_tree_split(handle datastruct.Handle, layout datastruct.Layout, start_child GtkWidget, end_child GtkWidget) &SplitTreeSplit {
	orientation := match layout {
		.horizontal { GtkOrientation(0) }
		.vertical { GtkOrientation(1) }
	}
	paned := C.gtk_paned_new(orientation)
	bin := C.adw_bin_new()
	C.gtk_widget_add_css_class(GtkWidget(bin), c'split')
	C.adw_bin_set_child(bin, GtkWidget(paned))
	mut self := &SplitTreeSplit{
		widget: GtkWidget(bin)
		handle: handle
		paned:  paned
	}

	// Setup our paned fields.
	C.gtk_paned_set_start_child(self.paned, start_child)
	C.gtk_paned_set_end_child(self.paned, end_child)
	C.g_signal_connect_data(self.paned, c'notify::position', GCallback(voidptr(split_tree_split_changed_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.paned, c'notify::max-position', GCallback(voidptr(split_tree_split_changed_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.paned, c'notify::min-position', GCallback(voidptr(split_tree_split_changed_cb)), voidptr(self), unsafe { nil }, 0)
	C.g_signal_connect_data(self.widget, c'destroy', GCallback(voidptr(split_tree_split_destroy_cb)), voidptr(self), unsafe { nil }, 0)

	return self
}

// The split's widget is disposed when a rebuild replaces it. The source's
// `dispose` removes any pending idle source here so `onIdle` never runs
// against the torn-down paned; GTK emits `destroy` from the widget's dispose.
fn split_tree_split_destroy_cb(widget voidptr, data voidptr) {
	if isnil(data) {
		return
	}
	mut self := unsafe { &SplitTreeSplit(data) }
	if self.idle != 0 {
		if !C.g_source_remove(self.idle) {
			log.warn('unable to remove idle source')
		}
		self.idle = 0
	}
	self.paned = unsafe { nil }
}

// refresh schedules an idle reposition of the split. Mirrors `refresh`.
fn (mut self SplitTreeSplit) refresh() {
	// Disposed: the paned is gone and no reposition is needed.
	if isnil(self.paned) {
		return
	}
	if self.idle == 0 {
		self.idle = C.g_idle_add(voidptr(split_tree_split_idle_cb), self)
	}
}

fn split_tree_split_changed_cb(paned GtkPaned, pspec voidptr, data voidptr) {
	_ = paned
	_ = pspec
	if !isnil(data) {
		mut self := unsafe { &SplitTreeSplit(data) }
		self.refresh()
	}
}

fn split_tree_split_idle_cb(data voidptr) int {
	if isnil(data) {
		return 0
	}
	mut self := unsafe { &SplitTreeSplit(data) }
	self.on_idle()
	return 0
}

fn object_int_property(object voidptr, name &char) int {
	mut storage := GValueStorage{}
	value := C.g_value_init(storage.ptr(), g_type_int)
	defer { C.g_value_unset(value) }
	C.g_object_get_property(GObject(object), name, value)
	return C.g_value_get_int(value)
}

fn object_bool_property(object voidptr, name &char) bool {
	mut storage := GValueStorage{}
	value := C.g_value_init(storage.ptr(), g_type_boolean)
	defer { C.g_value_unset(value) }
	C.g_object_get_property(GObject(object), name, value)
	return C.g_value_get_boolean(value) != 0
}

// on_idle reconciles the paned position with the tree's desired ratio, and
// writes user drags back to the tree. Faithful translation of `onIdle`;
// split_tree_split_idle_cb is its GLib idle trampoline.
pub fn (mut self SplitTreeSplit) on_idle() {
	paned := self.paned

	// Our idle source is always over
	self.idle = 0

	// Get our split. This is the most dangerous part of this entire
	// widget. We assume that this widget is always a child of a
	// SplitTree, we assume that our handle is valid, and we assume
	// the handle is always a split node.
	ancestor := get_ancestor(self.widget, split_tree_get_type())
	if isnil(ancestor) {
		return
	}
	wrapper := split_tree_priv(voidptr(ancestor)).wrapper
	if isnil(wrapper) {
		return
	}
	mut split_tree := unsafe { &SplitTreeWidget(wrapper) }
	mut tree := split_tree.get_tree() or { return }
	node := tree.nodes[self.handle.idx()]
	split := if node is datastruct.Split {
		node
	} else {
		panic('split tree handle ${self.handle.idx()} is not a split node')
	}

	// Current, min, and max positions as pixels.
	pos := C.gtk_paned_get_position(paned)
	min := object_int_property(voidptr(paned), c'min-position')
	max := object_int_property(voidptr(paned), c'max-position')
	pos_set := object_bool_property(voidptr(paned), c'position-set')

	// We don't actually use min, but we don't expect this to ever
	// be non-zero, so let's add an assert to ensure that.
	assert min == 0

	// If our max is zero then we can't do any math. I don't know
	// if this is possible but I suspect it can be if you make a nested
	// split completely minimized.
	if max == 0 {
		return
	}

	// Determine our current ratio.
	current_ratio := f64(pos) / f64(max)
	desired_ratio := f64(split.ratio.f32())

	// If our ratio is close enough to our desired ratio, then
	// we ignore the update. This is to avoid constant split updates
	// for lossy floating point math.
	if abs_f64(current_ratio - desired_ratio) <= 0.001 {
		return
	}

	// If we're out of bounds, then we need to either set the position
	// to what we expect OR update our expected ratio.

	// If we've never set the position, then we set it to the desired.
	if !pos_set {
		desired_pos := int(round_f64(f64(max) * desired_ratio))
		C.gtk_paned_set_position(paned, desired_pos)
		return
	}

	// If we've set the position, then this is a manual human update
	// and we need to write our update back to the tree.
	tree.resize_in_place(self.handle, f32(current_ratio))
}

// --- SplitTreeSplit signal handlers ---------------------------------------

// prop_position handles the paned's notify::position. Mirrors `propPosition`.
pub fn (mut self SplitTreeSplit) prop_position() {
	self.refresh()
}

// prop_max_position handles the paned's notify::max-position. Mirrors
// `propMaxPosition`.
pub fn (mut self SplitTreeSplit) prop_max_position() {
	self.refresh()
}

// prop_min_position handles the paned's notify::min-position. Mirrors
// `propMinPosition`.
pub fn (mut self SplitTreeSplit) prop_min_position() {
	self.refresh()
}

// --- SurfaceWidget: datastruct.SplitTree[T] view interface ----------------
//
// The immutable `datastruct.SplitTree[T]` requires its view type `T` to
// implement ref/unref/eql/split_tree_label. `SurfaceWidget` is our `T`, so we
// provide those here. These wrap the GObject refcount and identity/label so the
// tree's clone/free/format logic works.

// ref increments the surface's GObject reference count and returns a new
// reference (a copy of the pointer). Mirrors `Surface.ref` used by the tree.
pub fn (mut self SurfaceWidget) ref() &SurfaceWidget {
	if !isnil(self.widget) {
		object_ref(self.widget)
	}
	return self
}

// ref_sink converts a floating surface reference into a strong reference, or
// adds a strong reference when it is already sunk. Mirrors `Common.refSink`.
pub fn (mut self SurfaceWidget) ref_sink() &SurfaceWidget {
	if !isnil(self.widget) {
		C.g_object_ref_sink(self.widget)
	}
	return self
}

// unref decrements the surface's GObject reference count. Mirrors
// `Surface.unref` used by the tree.
pub fn (mut self SurfaceWidget) unref() {
	if !isnil(self.widget) {
		object_unref(self.widget)
	}
}

// eql reports whether two surfaces are the same object. Mirrors the tree's `T`
// equality (pointer identity of the underlying widget).
pub fn (self &SurfaceWidget) eql(other &SurfaceWidget) bool {
	if isnil(other) {
		return false
	}
	return self == other
}

// split_tree_label returns a short debug label for the surface, used by the
// tree's ASCII diagram formatter.
pub fn (self &SurfaceWidget) split_tree_label() string {
	if title := self.title {
		return title
	}
	return 'surface'
}

// --- small numeric helper -------------------------------------------------

// round_f64 rounds to the nearest integer (ties away from zero), matching Zig's
// @round used in the split reposition math.
fn round_f64(v f64) f64 {
	if v < 0 {
		return f64(int(v - 0.5))
	}
	return f64(int(v + 0.5))
}
