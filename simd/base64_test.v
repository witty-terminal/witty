module simd

fn test_base64_max_len() {
	assert max_len('aGVsbG8gd29ybGQ='.bytes()) == 11
}

fn test_base64_scalar_source_size_entry_points() {
	assert calc_size_upper_bound(0)! == 0
	assert calc_size_upper_bound(2)! == 1
	assert calc_size_upper_bound(3)! == 2
	assert calc_size_upper_bound(4)! == 3
	assert calc_size_for_slice('aGVsbG8gd29ybGQ'.bytes())! == 11
	calc_size_upper_bound(1) or {
		assert err.msg() == 'InvalidPadding'
		return
	}
	assert false, 'one trailing Base64 byte must be rejected'
}

fn test_base64_decode() {
	input := 'aGVsbG8gd29ybGQ='.bytes()
	mut output := []u8{len: int(max_len(input))}
	decoded := decode(input, mut output)!
	assert decoded.bytestr() == 'hello world'
}

fn test_base64_decode_accepts_noncanonical_trailing_bits() {
	mut output := []u8{len: 1}
	decoded := decode('Zh=='.bytes(), mut output)!
	assert decoded == [u8(`f`)]
}

fn test_base64_decode_rejects_invalid_character() {
	mut output := []u8{len: 3}
	decode('AA!A'.bytes(), mut output) or {
		assert err.msg().contains('Base64Invalid')
		return
	}
	assert false, 'expected invalid Base64 to fail'
}

fn test_base64_decode_one_byte_input_matches_scalar_fallback() {
	mut output := []u8{}
	assert decode_scalar('A'.bytes(), mut output)! == []u8{}
}

fn test_base64_scalar_empty_input() {
	mut output := []u8{}
	assert max_len_scalar([]u8{}) == 0
	assert decode_scalar([]u8{}, mut output)! == []u8{}
}

fn test_scalar_base64_preserves_source_partial_writes_on_error() {
	for i, input in ['AAA!AAAA', 'AAAA!AAA'] {
		mut output := []u8{len: 6, init: 0xa5}
		decode_scalar(input.bytes(), mut output) or {
			assert err.msg() == 'Base64Invalid'
			assert output == if i == 0 {
				[u8(0xa5), 0xa5, 0xa5, 0xa5, 0xa5, 0xa5]
			} else {
				[u8(0), 0, 0, 0, 0xa5, 0xa5]
			}
			continue
		}
		assert false
	}
}

fn test_scalar_base64_sixteen_byte_group_validates_before_writing() {
	mut output := []u8{len: 24, init: 0xa5}
	scalar_base64_decode('AAAAAAAAAAAAAAA!AAAAAAAAAAAAAAAA'.bytes(), mut output) or {
		assert err.msg() == 'InvalidCharacter'
		assert output == []u8{len: 24, init: 0xa5}
		return
	}
	assert false
}
