module macos

import json2
import os

struct SourceStringInput {
	label string
	bytes []u8
	length int = -1
}
struct SourceStringRecord {
	input string
	search ?string
	key_table string
	hover ?string
	c_strict ?string
}

fn test_original_swift_string_boundary_and_invalid_subpart_rules() {
	app_init()
	inputs := [
		SourceStringInput{'empty', [], -1},
		SourceStringInput{'ascii', 'ghostty'.bytes(), -1},
		SourceStringInput{'unicode', 'Ω🚀'.bytes(), -1},
		SourceStringInput{'valid-replacement', [u8(0xef), 0xbf, 0xbd], -1},
		SourceStringInput{'nul', [u8(`a`), 0, `b`], -1},
		SourceStringInput{'invalid-after-nul', [u8(`a`), 0, 0xff], -1},
		SourceStringInput{'invalid-before-nul', [u8(0xff), 0, `a`], -1},
		SourceStringInput{'continuation', [u8(0x80)], -1},
		SourceStringInput{'invalid-lead', [u8(0xff)], -1},
		SourceStringInput{'overlong-2', [u8(0xc0), 0xaf], -1},
		SourceStringInput{'overlong-3', [u8(0xe0), 0x80, 0xaf], -1},
		SourceStringInput{'surrogate', [u8(0xed), 0xa0, 0x80], -1},
		SourceStringInput{'beyond-max', [u8(0xf4), 0x90, 0x80, 0x80], -1},
		SourceStringInput{'obsolete-5', [u8(0xf8), 0x88, 0x80, 0x80, 0x80], -1},
		SourceStringInput{'truncated-2', [u8(0xc2)], -1},
		SourceStringInput{'truncated-3', [u8(0xe2), 0x82], -1},
		SourceStringInput{'truncated-4', [u8(0xf0), 0x9f, 0x92], -1},
		SourceStringInput{'broken-continuation', [u8(0xe2), `X`, 0xa1], -1},
		SourceStringInput{'maximal-subpart', [u8(`a`), 0xe2, 0x82, `b`], -1},
		SourceStringInput{'broken-4', [u8(0xf0), 0x9f, `A`], -1},
		SourceStringInput{'bounded-tail', [u8(`t`), `a`, `b`, `l`, `e`, 0xff], 5},
	]
	mut records := []SourceStringRecord{}
	for input in inputs {
		mut backing := input.bytes.clone()
		backing << u8(0)
		length := if input.length >= 0 { input.length } else { input.bytes.len }
		value := unsafe { tos(backing.data, length) }
		strict := source_utf8(value)
		records << SourceStringRecord{input.label, source_c_utf8_repair(value), strict or { '' },
			if length > 0 { strict } else { none }, source_c_utf8(value)}
	}
	// The optional StartSearch producer does not invoke String(cString:) for nil.
	records << SourceStringRecord{'nil-search', none, '', none, none}
	assert records[2].search? == 'Ω🚀'
	assert records[4].search? == 'a'
	assert records[4].key_table.len == 3
	assert records[4].hover?.len == 3
	assert records[5].search? == 'a'
	assert records[5].hover == none
	assert records[8].search? == '�'
	assert records[18].search? == 'a�b'
	assert records[20].key_table == 'table'
	assert records[20].search? == 'table�'
	assert records[20].c_strict == none
	if path := os.getenv_opt('WITTY_STRING_MODEL_OUTPUT') { os.write_file(path, json2.encode(records, escape_unicode: true, time_as_unix: true))! }
}
