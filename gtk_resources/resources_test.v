module gtk_resources

import os

fn test_source_resource_aliases_and_inputs() ! {
	root := @VMODROOT
	assert blueprints.len == 21
	assert blueprint_resource(Blueprint{major: 1, minor: 5, name: 'command-palette'})! == '/com/alexander/witty/ui/1.5/command-palette.ui'
	text := xml(root, ['/tmp/1.5/command-palette.ui'])!
	for name in css { assert text.contains('alias="${name}"') }
	assert text.contains('alias="1024x1024@2/apps/com.alexander.witty.png"')
	assert text.contains('alias="1.5/command-palette.ui"')
	assert os.read_file(os.join_path(root, 'apprt', 'gtk', 'style-dark.css'))!.contains('rgba(36, 36, 36, 1)')
}

fn test_unmatched_blueprint_is_rejected() {
	xml(@VMODROOT, ['/tmp/1.5/unknown.ui']) or {
		assert err.msg() == 'BlueprintNotFound'
		return
	}
	assert false
}

fn test_blueprint_process_output_uses_separate_source_bounds() ! {
	assert run('/bin/sh', ['-c', 'printf success; printf diagnostic >&2'])! == 'success'
	for stream in ['stdout', 'stderr'] {
		command := if stream == 'stdout' { 'head -c 65536 /dev/zero' } else { 'head -c 65536 /dev/zero >&2' }
		run('/bin/sh', ['-c', command]) or {
			assert err.msg() == if stream == 'stdout' { 'StdoutStreamTooLong' } else { 'StderrStreamTooLong' }
			continue
		}
		assert false, 'each source output stream has its own limit'
	}
}
