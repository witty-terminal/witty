module internal_os

fn test_filter_snap_paths_matches_source() {
	mut env := {
		'SNAP':                  '/snap/ghostty/42'
		'SNAP_USER_COMMON':      '/home/alex/snap/ghostty/common'
		'SNAP_USER_DATA':        '/home/alex/snap/ghostty/42'
		'SNAP_DATA':             '/var/snap/ghostty/42'
		'SNAP_COMMON':           '/var/snap/ghostty/common'
		'SNAP_NAME':             'ghostty'
		'PATH':                  '/snap/ghostty/42/bin:/usr/bin:/home/alex/snap/ghostty/common/bin'
		'EMPTY_AFTER_FILTER':    '/var/snap/ghostty/42/bin'
		'TERMINFO':              '/snap/ghostty/42/terminfo'
		'GHOSTTY_RESOURCES_DIR': '/snap/ghostty/42/share/witty'
		'UNCHANGED':             '/opt/bin:/usr/local/bin'
	}

	filter_snap_paths(mut env)
	assert 'SNAP' !in env
	assert 'SNAP_NAME' !in env
	assert env['PATH'] == '/usr/bin'
	assert 'EMPTY_AFTER_FILTER' !in env
	assert env['TERMINFO'] == '/snap/ghostty/42/terminfo'
	assert env['GHOSTTY_RESOURCES_DIR'] == '/snap/ghostty/42/share/witty'
	assert env['UNCHANGED'] == '/opt/bin:/usr/local/bin'
}
