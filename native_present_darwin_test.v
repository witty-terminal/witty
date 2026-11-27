module main

import apprt
import witty_macos as macos
fn test_native_present_terminal_preserves_zoom_and_source_observer_guards() {
	macos.app_init()
	first := macos.create_window(640, 480, 'present')
	mut actions := macos.new_action_surface(first, unsafe { nil }, macos.ActionCallbacks{})
	mut host := macos.create_split_host(first)
	second := macos.create_split_surface_view(host)
	mut other_actions := macos.new_action_surface(second, unsafe { nil }, macos.ActionCallbacks{})
	tree := host.tree.inserting(second, first, .right) or { panic(err) }
	zoomed := tree.root.find(first) or { panic('missing original leaf') }
	host.replace_tree(macos.NativeSplitTree{ root: tree.root, zoomed: zoomed })
	controller := &TerminalController{ host: host }
	current := &TermState{ view: first, controller: controller, actions: actions }
	other := &TermState{ view: second, controller: controller, actions: other_actions }
	macos.view_set_userdata(first, voidptr(current))
	macos.view_set_userdata(second, voidptr(other))
	defer { actions.deinit(); other_actions.deinit(); macos.close_tab(first) }
	for state in [current, other] {
		runtime := &apprt.Surface{ userdata: voidptr(state) }
		core := &apprt.CoreSurface{ runtime_surface: voidptr(runtime) }
		assert runtime_action(unsafe { nil }, apprt.SurfaceTarget{ surface: voidptr(core) }, apprt.RuntimeAction{ action: .present_terminal })
		assert host.tree.root == tree.root
		assert host.tree.zoomed == zoomed
	}
	// A valid source App request remains acknowledged even when no controller
	// notification observer contains the surface.
	macos.view_set_userdata(host.container, voidptr(&TermState{ view: host.container, controller: controller, actions: actions }))
	native_present_view(unsafe { nil }, host.container)
	assert host.tree.zoomed == zoomed
}
