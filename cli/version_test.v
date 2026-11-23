module cli

import apprt
import build_meta
import font
import renderer
import v.util.version as vversion
import xev

fn test_version_output_reports_translated_build_metadata() {
	output := version_output(false)
	assert output.starts_with('Witty ${build_meta.version_string}\n\nVersion\n')
	assert output.contains('  - version: ${build_meta.version_string}\n')
	assert output.contains('  - channel: ${build_meta.release_channel}\n')
	assert output.contains('  - V version     : ${vversion.v_version}\n')
	assert output.contains('  - app runtime   : ${runtime_name(apprt.Runtime.selected())}\n')
	assert output.contains('  - font engine   : ${font.Backend.selected_()}\n')
	assert output.contains('  - renderer      : ${renderer.Backend.selected_()}\n')
	assert output.contains('  - libxev        : ${xev.backend()}\n')
	assert !output.contains(@VEXE)
}

fn test_version_output_hyperlink_requires_commit_metadata() {
	assert build_meta.reference_commit == '6c0e02d1138d5376e4ac2f5e311b225494514a97'
	plain := version_output(false)
	tty := version_output(true)
	assert !plain.contains('\x1b]8;;')
	assert tty.starts_with('\x1b]8;;https://github.com/witty-terminal/witty/commit/${build_meta.commit_hash}\x1b\\Witty ${build_meta.version_string}\n\n')
	assert tty.contains('\x1b]8;;\x1b\\Version\n')
}
