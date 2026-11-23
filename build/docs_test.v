module build

import crypto.sha256
import help_strings

fn test_web_document_generators_match_pinned_ghostty() {
	cases := {
		'web-commands':    [gen_web_actions(), '5523d7df4988f80b08dd18cc3e5baea13ccbb4ef91c97305eba2502a72680d32']
		'web-config':      [gen_web_config(), '8c8df9149f7cb59eaf273df8a6caccea4309ae9c82702640b82c1160163f8a46']
		'web-actions':     [gen_web_keybind_actions(), '79f8761fc73e57f1fc81f135ccc851ae50d456f1905c5a981f0f2c67d485b132']
		'man-actions':     [gen_actions(), 'e559dbdb6d1605c710d7770e3eaa530ab75628709eaba9c9a9e84cf0810b5918']
		'man-config-cli':  [gen_config(true), '3d1dc316e8170046540c7bdf643429e45991d5d971c325ef6151c697174768a2']
		'man-config':      [gen_config(false), '1ebe9b0f736f8efcca4bfacadec41178131f2092622cd9725c6b06a4fa4c2977']
		'man-keybinds':    [gen_keybind_actions(), 'a5f4e7271397a48f60be1f59935a8b232c3d36f4bfb2222ee470a193b962ecba']
		'ghostty-1':       [ghostty_1(), '052c3ef42226c4fbdb5ead524d07d3971d2bde8acd2b4cbccd12a4a1c02006dd']
		'ghostty-5':       [ghostty_5(), '20a1a77fb75d78aeba481c7bcb35dd29e9794976d9bb0726e68313d6ca1cf8aa']
		'config-help-data': [$embed_file('../configpkg/config_help.txt').to_string(), '2148b788168cd9d5eb3d7619f3f2f730100aa699c606ad8233c9140f34257360']
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

	page_1 := ghostty_1()
	page_5 := ghostty_5()
	assert page_1.starts_with('% GHOSTTY(1) Version 1.3.0-main+6c0e02d')
	assert page_1.ends_with('**ghostty(5)**\n')
	assert page_5.starts_with('% GHOSTTY(5) Version 1.3.0-main+6c0e02d')
	assert page_5.ends_with('**ghostty(1)**\n')
}

fn test_web_config_rewrites_code_and_callout_blocks() {
	result := gen_web_config()
	assert result.contains('## `font-family-bold`\n## `font-family-italic`\n')
	assert result.contains('```\nghostty +list-fonts\n```')
	assert result.contains('<Note>\n')
	assert result.contains('</Note>\n')
	assert result.contains('<Warning>\n')
	assert result.contains('</Warning>\n')
}
