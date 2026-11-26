module build_support

import os

// The selected V runtime uses a byte array as opaque pthread mutex storage.
// Its 128-byte capacity is correct, but the byte array has alignment 1; a
// large shared library can place it at an unaligned address and fault during
// _vinit. Keep the compiler's operations and capacity, and give that storage
// pointer alignment. Application and dependency logic are copied unchanged.
fn (d Driver) compiler_runtime_path() !string {
	compiler_root := os.dir(os.real_path(d.cfg.compiler))
	source := os.join_path(compiler_root, 'vlib', 'os')
	mutex_source := os.join_path(source, 'execute_lock_nix.c.v')
	if !os.exists(mutex_source) { return '' }
	text := os.read_file(mutex_source)!
	before := '__global g_v_os_execute_mutex_storage = [128]u8{}'
	if !text.contains(before) { return '' }
	path := d.cache_path('compiler-runtime')
	copy := os.join_path(path, 'os')
	os.mkdir_all(copy)!
	for filename in os.walk_ext(source, '.v') {
		if filename.ends_with('_test.v') { continue }
		output := os.join_path(copy, filename.all_after(source + os.path_separator))
		os.mkdir_all(os.dir(output))!
		os.cp(filename, output)!
	}
	os.write_file(os.join_path(copy, 'execute_lock_nix.c.v'),
		text.replace(before, '__global g_v_os_execute_mutex_storage = [16]u64{}'))!
	return path
}

fn (d Driver) compiler_module_path() !string {
	mut paths := [d.cfg.root]
	modules := d.cache_path('ui2-modules')
	if os.exists(os.join_path(modules, 'ui2', '.witty-ui2')) {
		paths << modules
	}
	runtime := d.compiler_runtime_path()!
	if runtime.len > 0 {
		paths << runtime
	}
	paths << ['@vlib', '@vmodules']
	return paths.join('|')
}
