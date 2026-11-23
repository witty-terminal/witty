module build

import crypto.sha256
import build_meta
import help_strings

fn test_web_document_generators_match_witty_output() {
	cases := {
		'web-commands':    [gen_web_actions(), 'a5da01589b15e75fc82ccedde1e3d9511a1e1a55226e5fdb77ee71ff9a3678f6']
		'web-config':      [gen_web_config(), '2ca54afd943547e986c3e524f345be9d8e539a3cb588a884aede7a6f0342217e']
		'web-actions':     [gen_web_keybind_actions(), 'fe104cf9f20eba4a901876aed55e1d4b799b5d6a2278c595acfecd03b72f439a']
		'man-actions':     [gen_actions(), '793568947ae07a3255c9e446ef77ec77516af117b415dde63cb2c21bc49abe29']
		'man-config-cli':  [gen_config(true), 'c60df6e46aa1fe1835d78bbc770b0c71b967969abd8e1c2806879835b39193b3']
		'man-config':      [gen_config(false), '874fa5a9e97edcbba9d0ed62d1c2f58dff9d0fe41723be43b757ef10a0d8d43a']
		'man-keybinds':    [gen_keybind_actions(), '6fdc46e91e30076cae69dce7d7e2c7afdfa75dacea68412b51330fd6dd2c0463']
		'witty-1':       [witty_1(), '44e8f209fc88d11a08365fe4568888893d16c502f300599801150c5210770c79']
		'witty-5':       [witty_5(), '5baa2c7479437d504587eb366ce8fe9daad16359a3f7d565fe51c0eeb89c5a71']
		'config-help-data': [$embed_file('../configpkg/config_help.txt').to_string(), 'd0732bc3e84e62e291eacf631a38a69dadfa2db32f686588b0b847abf47e4b2a']
	}
	for name, values in cases {
		actual := sha256.sum(values[0].bytes()).hex()
		assert actual == values[1], '${name} documentation differs: ${actual}'
	}
}

fn test_manpage_generators_cover_all_translated_records() {
	actions := gen_actions()
	assert actions.contains('**`--version`**')
	assert actions.contains('**`--help`**')
	assert actions.contains('**`+new-window`**')
	assert actions.count('**`') == 15

	config_cli := gen_config(true)
	config_file := gen_config(false)
	assert config_cli.count('**`--') == help_strings.config_keys.len
	assert config_file.count('**`') == help_strings.config_keys.len
	assert config_cli.contains('**`--font-family-bold`**\n\n')
	assert config_file.contains('**`font-family-bold`**\n\n')

	keybinds := gen_keybind_actions()
	assert keybinds.count('**`') == 83
	assert keybinds.contains('**`ignore`**')
	assert keybinds.contains('**`crash`**')

	page_1 := witty_1()
	page_5 := witty_5()
	assert page_1.starts_with('% WITTY(1) Version ${build_meta.version_string}')
	assert page_1.ends_with('**witty(5)**\n')
	assert page_5.starts_with('% WITTY(5) Version ${build_meta.version_string}')
	assert page_5.ends_with('**witty(1)**\n')
}

fn test_web_config_rewrites_code_and_callout_blocks() {
	result := gen_web_config()
	assert result.contains('## `font-family-bold`\n## `font-family-italic`\n')
	assert result.contains('```\nwitty +list-fonts\n```')
	assert result.contains('<Note>\n')
	assert result.contains('</Note>\n')
	assert result.contains('<Warning>\n')
	assert result.contains('</Warning>\n')
}
