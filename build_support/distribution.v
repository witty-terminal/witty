module build_support

import gtk_resources
import os

// GhosttyDist.init: add VERSION and generated GTK/frame resources to git's
// tracked, export-ignore-aware source archive. --add-file uses the most recent
// prefix and the added file's basename, so copies retain the distributed names.
pub fn (d Driver) build_distribution(check bool) !string {
	adwaita :=
		checked_process(d.cfg.root, ['pkg-config', '--modversion', 'libadwaita-1'])!.trim_space()
	gtk_c := gtk_resources.build(d.cfg.root, adwaita)!
	resources := {
		'apprt/gtk/ghostty_resources.c':              gtk_c
		'apprt/gtk/ghostty_resources.h':              os.join_path(os.dir(gtk_c),
			'ghostty_resources.h')
		'build_assets/framegen/framedata.compressed': d.generate_frame_data()!
	}
	dir := d.cache_path('dist', 'inputs')
	os.mkdir_all(dir)!
	version := os.join_path(dir, 'VERSION')
	os.write_file(version, d.cfg.version)!
	mut args := ['git', 'archive', '--format=tgz', '--prefix=ghostty-${d.cfg.version}/',
		'--add-file=' + version]
	for destination, generated in resources {
		copied := os.join_path(dir, os.base(destination))
		os.cp(generated, copied)!
		args << ['--prefix=ghostty-${d.cfg.version}/${os.dir(destination)}/', '--add-file=' + copied]
	}
	output := d.cache_path('dist', 'ghostty-${d.cfg.version}.tar.gz')
	args << ['--prefix=ghostty-${d.cfg.version}/', '-o', output, 'HEAD']
	checked_process(d.cfg.root, args)!
	d.install_file(output, 'dist/' + os.base(output))!
	if check {
		extract := d.cache_path('dist', 'check')
		os.mkdir_all(extract)!
		checked_process(d.cfg.root, ['tar', 'xvzf', tar_relative(d.cfg.root, output),
			'-C', tar_relative(d.cfg.root, extract)])!
		root := os.join_path(extract, 'ghostty-${d.cfg.version}')
		for destination, _ in resources {
			if !os.exists(os.join_path(root, destination)) {
				return error('missing dist resource: ${destination}')
			}
		}
		// The extracted tree shares the compiler cache, matching the original
		// distcheck; its own driver discovers that tree's tests/resources.
		checked_process(root, [d.cfg.compiler, '-path', '${root}|@vlib|@vmodules', 'run',
			os.join_path(root, 'tools', 'build'), 'test'])!
	}
	return output
}
