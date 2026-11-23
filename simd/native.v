module simd

// Ghostty selects SIMD on native targets unless explicitly disabled.
// The C++ algorithms below are unchanged source from the reference commit.
pub const native_enabled = $if js {
	false
} $else $if wasm32 {
	false
} $else $if no_simd ? {
	false
} $else {
	true
}

$if !js && !wasm32 && !no_simd ? {
	#flag -I @VMODROOT/simd/native
	#flag -I @VMODROOT/simd/native/highway
	#flag -I @VMODROOT/simd/native/simdutf
	#flag -I @VMODROOT/simd/native/utfcpp/source
	$if !managed_native ? {
		#flag @VMODROOT/simd/native/simd/base64.o
		#flag @VMODROOT/simd/native/simd/index_of.o
		#flag @VMODROOT/simd/native/simd/codepoint_width.o
		#flag @VMODROOT/simd/native/simd/vt.o
		#flag @VMODROOT/simd/native/simdutf/simdutf.o
		#flag @VMODROOT/simd/native/abort.o
		#flag @VMODROOT/simd/native/aligned_allocator.o
		#flag @VMODROOT/simd/native/nanobenchmark.o
		#flag @VMODROOT/simd/native/per_target.o
		#flag @VMODROOT/simd/native/print.o
		#flag @VMODROOT/simd/native/targets.o
		#flag @VMODROOT/simd/native/timer.o
		#flag @VMODROOT/simd/native/highway_bridge.o
	}
	// GCC notes that passing 64-byte AVX-512 vectors changed ABI in GCC 4.6.
	// Highway's per-target functions are internal, so the note is noise; it
	// also makes cc1plus report V's clang-only -Wno-incompatible-function-pointer-types.
	#flag linux -Wno-psabi
	#flag freebsd -Wno-psabi
	#flag darwin -lc++
	#flag linux -lstdc++
	#flag freebsd -lstdc++
	#include "witty_simd.h"
}

fn C.ghostty_simd_base64_max_length(&u8, uint) uint
fn C.ghostty_simd_base64_decode(&u8, uint, &u8) uint
fn C.ghostty_simd_index_of(u8, &u8, uint) uint
fn C.ghostty_simd_codepoint_width(u32) i8
fn C.ghostty_simd_decode_utf8_until_control_seq(&u8, uint, &u32, &uint) uint
