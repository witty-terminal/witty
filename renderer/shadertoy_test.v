module renderer

import configpkg
import os

fn test_shader_target_source_layout_and_ordinals() {
	assert sizeof(Target) == 1
	assert u8(Target.glsl) == 0
	assert u8(Target.msl) == 1
}

fn test_glsl_from_shader_uses_ghostty_prefix() {
	user_source := 'void mainImage(out vec4 color, in vec2 coord) { color = vec4(1); }'
	source := glsl_from_shader(user_source)
	assert source.starts_with('#version 430 core\n')
	assert source.contains('layout(binding = 1, std140) uniform Globals')
	assert source.contains('uniform vec4  iCurrentCursor;')
	assert source.contains('void main() { mainImage (_fragColor, gl_FragCoord.xy); }')
	assert source == shadertoy_prefix + '\n\n' + user_source
}

fn test_load_shaders_skips_only_missing_optional_files() {
	missing := os.join_path(os.temp_dir(), 'witty-shader-missing-${os.getpid()}.glsl')
	paths := configpkg.RepeatablePath{
		items: [configpkg.Path(configpkg.PathOptional{
			path: missing
		})]
	}
	assert load_from_files(paths, .glsl)! == []string{}

	required := configpkg.RepeatablePath{
		items: [configpkg.Path(configpkg.PathRequired{
			path: missing
		})]
	}
	load_from_files(required, .glsl) or {
		assert err.msg().starts_with('shader file not found:')
		return
	}
	assert false, 'missing required shader should fail'
}

fn test_spirv_cross_rejects_invalid_byte_length_before_tool_lookup() {
	msl_from_spv([u8(1), 2, 3]) or {
		assert err.msg() == 'SpirvInvalid'
		return
	}
	assert false, 'invalid SPIR-V should fail'
}

fn test_load_shader_compiles_after_reaching_end_of_file() {
	path := os.join_path(os.temp_dir(), 'witty-shader-eof-${os.getpid()}.glsl')
	os.write_file(path, 'void mainImage(out vec4 color, in vec2 coord) { color = vec4(1); }')!
	defer { os.rm(path) or {} }
	assert load_from_file(path, .msl)!.contains('metal_stdlib')
}

fn test_shader_conversion_uses_linked_native_compilers_without_path_tools() {
	old_path := os.getenv_opt('PATH')
	os.setenv('PATH', '', true)
	defer {
		if path := old_path {
			os.setenv('PATH', path, true)
		} else {
			os.unsetenv('PATH')
		}
	}
	spv :=
		spirv_from_glsl(glsl_from_shader('void mainImage(out vec4 color, in vec2 coord) { color = vec4(1); }'))!
	assert spv.len > 4 && spv.len % 4 == 0
	assert spv[..4] == [u8(3), 2, 35, 7]
	assert glsl_from_spv(spv)!.contains('#version 430')
	assert msl_from_spv(spv)!.contains('metal_stdlib')
}

fn test_glslang_failure_populates_source_diagnostics() {
	mut diagnostics := SpirvLog{}
	spirv_from_glsl_logged('#version 430 core\ninvalid shader source', mut diagnostics) or {
		assert err.msg() == 'GlslangFailed'
		assert diagnostics.info.len > 0
		return
	}
	assert false
}
