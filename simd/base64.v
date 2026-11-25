module simd

import log
$if ghostty_wasm_module ? { import wasm_log }

// Base64 routines translated from src/simd/base64.zig.

// base64_scalar_input removes trailing padding so the scalar decoder has the
// same output behavior as Ghostty's SIMD implementation.
fn base64_scalar_input(input []u8) []u8 {
	mut end := input.len
	for end > 0 && input[end - 1] == `=` {
		end--
	}
	return input[..end]
}

// max_len returns the exact decoded length, or zero for an invalid input
// length. This is Ghostty's maxLen entry point.
pub fn max_len(input []u8) uint {
	$if !js && !wasm32 && !no_simd ? {
		return C.ghostty_simd_base64_max_length(input.data, uint(input.len))
	}
	return max_len_scalar(input)
}

fn max_len_scalar(input []u8) uint {
	scalar := base64_scalar_input(input)
	return calc_size_for_slice(scalar) or {
		$if ghostty_wasm_module ? { wasm_log.write(.warn, 'simd_base64', 'failed to calculate base64 size for payload: ${err}') } $else { log.warn('failed to calculate base64 size for payload: ${err}') }
		return 0
	}
}

// decode decodes input into caller-owned storage and returns the used prefix.
// Invalid alphabet characters produce Base64Invalid.
pub fn decode(input []u8, mut output []u8) ![]u8 {
	$if !js && !wasm32 && !no_simd ? {
		result := int(C.ghostty_simd_base64_decode(input.data, uint(input.len), output.data))
		if result < 0 {
			return error('Base64Invalid')
		}
		return output[..int(result)]
	}
	return decode_scalar(input, mut output)
}

fn decode_scalar(input []u8, mut output []u8) ![]u8 {
	scalar := base64_scalar_input(input)
	size := max_len_scalar(scalar)
	if size == 0 {
		return output[..0]
	}
	assert uint(output.len) >= size
	scalar_base64_decode(scalar, mut output) or { return error('Base64Invalid') }
	return output[..size]
}
