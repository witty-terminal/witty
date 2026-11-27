@[has_globals]
module witty_macos

import json2
import os

__global (
	g_url_probe_calls int
	g_url_probe_target string
	g_url_probe_application string
	g_url_probe_configuration bool
)

fn url_probe_general(_self ObjId, _cmd Sel, url ObjId) bool {
	g_url_probe_calls++
	g_url_probe_target = objc_utf8_string(msg_id(url, 'absoluteString'))
	g_url_probe_application = ''
	g_url_probe_configuration = false
	return false // The source ignores this result and still handles the action.
}
fn url_probe_editor(_self ObjId, _cmd Sel, urls ObjId, application ObjId, configuration ObjId, completion ObjId) {
	g_url_probe_calls++
	assert msg_u64(urls, 'count') == 1
	assert is_nil(completion)
	g_url_probe_target = objc_utf8_string(msg_id(msg_id_u64(urls, 'objectAtIndex:', 0), 'absoluteString'))
	g_url_probe_application = objc_utf8_string(msg_id(application, 'absoluteString'))
	g_url_probe_configuration = msg_bool1(configuration, 'isKindOfClass:', get_class('NSWorkspaceOpenConfiguration'))
}
fn url_probe_workspace() ObjId {
	if is_nil(get_class('VTURLWorkspaceProbe')) {
		cls := C.macos_objc_allocate_class_pair(get_class('NSObject'), cstr('VTURLWorkspaceProbe'), 0)
		add_method(cls, 'openURL:', voidptr(url_probe_general), 'B@:@')
		add_method(cls, 'openURLs:withApplicationAtURL:configuration:completionHandler:', voidptr(url_probe_editor), 'v@:@@@@')
		C.macos_objc_register_class_pair(cls)
	}
	return msg_id(alloc('VTURLWorkspaceProbe'), 'init')
}

struct URLProbeRecord {
	input string
	kind i32
	url string
	editor string
}
struct URLInput {
	label string
	bytes []u8
}
fn test_source_url_editor_selection_and_real_native_workspace_selectors() {
	app_init()
	workspace := url_probe_workspace()
	defer { msg_void(workspace, 'release') }
	mut records := []URLProbeRecord{}
	values := ['https://ghostty.org/docs?query=hello world', 'https://ghostty.org/docs/a%20b',
		'/tmp/witty config.witty', 'relative config.txt', 'file:///tmp/witty%20config.txt',
		'/tmp/readme.md', '/tmp/unknown-extension.witty-ultra-nonexistent-extension',
		'/tmp/no-extension', '', 'mailto:alex@example.test', '/tmp/native.html']
	mut inputs := []URLInput{}
	nul := [u8(0)].bytestr()
	for value in values { inputs << URLInput{value, value.bytes()} }
	inputs << URLInput{'url-with-NUL', ('https://ghostty.org/a' + nul + 'b').bytes()}
	inputs << URLInput{'path-with-NUL', ('/tmp/witty' + nul + 'config.txt').bytes()}
	inputs << URLInput{'path-NUL-before-extension', ('/tmp/a' + nul + '.md').bytes()}
	inputs << URLInput{'path-NUL-inside-extension', ('/tmp/a.m' + nul + 'd').bytes()}
	inputs << URLInput{'relative-path-NUL', ('relative a' + nul + '.md').bytes()}
	inputs << URLInput{'relative-dot-path-NUL', ('a/../b' + nul + '.md').bytes()}
	inputs << URLInput{'trailing-slash-path-NUL', ('/tmp/a' + nul + '/').bytes()}
	inputs << URLInput{'tilde-path-NUL', ('~/a' + nul + '.md').bytes()}
	inputs << URLInput{'unknown-tilde-path-NUL', ('~witty-audit-nonexistent-user/a' + nul + '.md').bytes()}
	inputs << URLInput{'invalid-UTF8', [u8(0xff)]}
	inputs << URLInput{'invalid-truncated-UTF8', [u8(0xe2), u8(0x82)]}
	inputs << URLInput{'unterminated-length-slice', 'https://ghostty.org/bounded.txt'.bytes()}
	inputs << URLInput{'encoded-extension', 'file:///tmp/a.%6dd'.bytes()}
	inputs << URLInput{'opaque-extension', 'mailto:alex@example.md'.bytes()}
	inputs << URLInput{'encoded-NUL-before-encoded-extension', 'file:///tmp/a%00.%6dd'.bytes()}
	inputs << URLInput{'encoded-NUL-inside-encoded-extension', 'file:///tmp/a.%6d%00d'.bytes()}
	for input in inputs {
		// This view is bounded by its explicit length, without a terminator.
		mut backing := input.bytes.clone()
		if input.label == 'unterminated-length-slice' { backing << '-ignored-trailing-bytes'.bytes() }
		value := if input.bytes.len == 0 { '' } else { unsafe { tos(backing.data, input.bytes.len) } }
		for kind in [i32(0), i32(1), i32(2)] {
			before := g_url_probe_calls
			assert source_open_url_with_workspace(value, kind, workspace)
			assert g_url_probe_calls == before + 1
			url := source_url(value)
			assert g_url_probe_target == objc_utf8_string(msg_id(url, 'absoluteString'))
			editor := if kind == 1 { source_text_editor(url) } else { nil_obj() }
			assert g_url_probe_application == objc_utf8_string(msg_id(editor, 'absoluteString'))
			assert g_url_probe_configuration == !is_nil(editor)
			records << URLProbeRecord{input.label, kind, g_url_probe_target, g_url_probe_application}
		}
	}
	for input in [URLInput{'config-valid', '/tmp/witty config.witty'.bytes()},
		URLInput{'config-empty', []u8{}},
		URLInput{'config-with-NUL', ('/tmp/witty' + nul + 'config.witty').bytes()},
		URLInput{'config-invalid-UTF8', [u8(0xff)]}] {
		before := g_url_probe_calls
		file_url := source_config_file_url(input.bytes.bytestr())
		if file_url.len > 0 { assert source_open_url_with_workspace(file_url, 1, workspace) }
		assert g_url_probe_calls == before + if file_url.len > 0 { 1 } else { 0 }
		records << URLProbeRecord{input.label, -1,
			if file_url.len > 0 { g_url_probe_target } else { '' },
			if file_url.len > 0 { g_url_probe_application } else { '' }}
	}
	if path := os.getenv_opt('WITTY_URL_MODEL_OUTPUT') { os.write_file(path, json2.encode(records, escape_unicode: true, time_as_unix: true))! }
}
fn test_source_config_open_path_conversion() {
	assert source_config_file_url('/tmp/witty config.witty') == 'file:///tmp/witty%20config.witty'
	assert source_config_file_url('relative config.txt') == objc_utf8_string(msg_id(source_url('relative config.txt'), 'absoluteString'))
	assert source_config_file_url('') == ''
	assert source_config_file_url([u8(0xff)].bytestr()) == ''
}
