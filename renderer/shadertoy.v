module renderer

import configpkg
import os
import glslang
import spirv_cross as _
import log

const shadertoy_prefix = $embed_file('shaders/shadertoy_prefix.glsl').to_string()
const max_shader_size = 4 * 1024 * 1024

// The target to load shaders for.
pub enum Target as u8 {
	glsl
	msl
}

// SpirvLog retrieves errors from SPIR-V compilation.
pub struct SpirvLog {
pub mut:
	info  string
	debug string
}

pub fn (mut self SpirvLog) deinit() {
	self.info = ''
	self.debug = ''
}

// Load a set of shaders from files and convert them to the target
// format. The shader order is preserved.
//
pub fn load_from_files(paths configpkg.RepeatablePath, target Target) ![]string {
	mut shaders := []string{cap: paths.items.len}
	for item in paths.items {
		path := match item {
			configpkg.PathOptional { item.path }
			configpkg.PathRequired { item.path }
		}

		optional := item is configpkg.PathOptional
		shader := load_from_file(path, target) or {
			if optional && is_missing_file_error(err) {
				continue
			}
			return err
		}
		shaders << shader
	}
	return shaders
}

// Load a single shader from a file and convert it to the target language
// ready to be used with renderers.
pub fn load_from_file(path string, target Target) !string {
	if !os.exists(path) {
		return error('shader file not found: ${path}')
	}
	mut file := os.open(path) or { return error('unable to read shader ${path}: ${err}') }
	defer { file.close() }
	mut bytes := []u8{}
	mut buffer := []u8{len: 4096}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof {
				break
			}
			return err
		}
		if count == 0 {
			break
		}
		if count > max_shader_size - bytes.len {
			return error('shader exceeds 4 MiB limit: ${path}')
		}
		bytes << buffer[..count]
	}
	mut diagnostics := SpirvLog{}
	defer { diagnostics.deinit() }
	spv := spirv_from_glsl_logged(glsl_from_shader(bytes.bytestr()), mut diagnostics) or {
		if diagnostics.info.len > 0 || diagnostics.debug.len > 0 {
			log.warn('spirv error path=${path} info=${diagnostics.info} debug=${diagnostics.debug}')
		}
		return err
	}
	return match target {
		.glsl { glsl_from_spv(spv)! }
		.msl { msl_from_spv(spv)! }
	}
}

// Convert a ShaderToy shader into valid GLSL.
//
// ShaderToy shaders aren't full shaders, they're just implementing a
// mainImage function and don't define any of the uniforms. This function
// will convert the ShaderToy shader into a valid GLSL shader that can be
// compiled and linked.
pub fn glsl_from_shader(src string) string {
	return shadertoy_prefix + '\n\n' + src
}

// Convert a GLSL shader into SPIR-V assembly.
pub fn spirv_from_glsl(src string) ![]u8 {
	mut diagnostics := SpirvLog{}
	return spirv_from_glsl_logged(src, mut diagnostics)
}

// Direct translation of the source shader/program API sequence and logs.
pub fn spirv_from_glsl_logged(src string, mut diagnostics SpirvLog) ![]u8 {
	$if test { glslang.initialize()! }
	input := C.glslang_input_t{
		language:                C.GLSLANG_SOURCE_GLSL
		stage:                   C.GLSLANG_STAGE_FRAGMENT
		client:                  C.GLSLANG_CLIENT_VULKAN
		client_version:          C.GLSLANG_TARGET_VULKAN_1_2
		target_language:         C.GLSLANG_TARGET_SPV
		target_language_version: C.GLSLANG_TARGET_SPV_1_5
		code:                    &char(src.str)
		default_version:         100
		default_profile:         C.GLSLANG_NO_PROFILE
		messages:                C.GLSLANG_MSG_DEFAULT_BIT
		resource:                C.glslang_default_resource()
	}
	shader := C.glslang_shader_create(&input)
	if isnil(shader) { return error('OutOfMemory') }
	defer { C.glslang_shader_delete(shader) }
	if C.glslang_shader_preprocess(shader, &input) == 0
		|| C.glslang_shader_parse(shader, &input) == 0 {
		diagnostics.info = unsafe { cstring_to_vstring(C.glslang_shader_get_info_log(shader)).clone() }
		diagnostics.debug = unsafe { cstring_to_vstring(C.glslang_shader_get_info_debug_log(shader)).clone() }
		return error('GlslangFailed')
	}
	program := C.glslang_program_create()
	if isnil(program) { return error('OutOfMemory') }
	defer { C.glslang_program_delete(program) }
	C.glslang_program_add_shader(program, shader)
	if C.glslang_program_link(program, C.GLSLANG_MSG_SPV_RULES_BIT | C.GLSLANG_MSG_VULKAN_RULES_BIT) == 0 {
		diagnostics.info = unsafe { cstring_to_vstring(C.glslang_program_get_info_log(program)).clone() }
		diagnostics.debug = unsafe { cstring_to_vstring(C.glslang_program_get_info_debug_log(program)).clone() }
		return error('GlslangFailed')
	}
	C.glslang_program_SPIRV_generate(program, C.GLSLANG_STAGE_FRAGMENT)
	size := C.glslang_program_SPIRV_get_size(program)
	ptr := C.glslang_program_SPIRV_get_ptr(program)
	return unsafe { (&u8(ptr)).vbytes(int(size * 4)).clone() }
}

pub fn msl_from_spv(spv []u8) !string {
	return source_from_spv(spv, .msl)
}

pub fn glsl_from_spv(spv []u8) !string {
	return source_from_spv(spv, .glsl)
}

fn spirv_cross_error(_ voidptr, message &char) {
	log.warn('spirv-cross error message=${unsafe { cstring_to_vstring(message) }}')
}

fn source_from_spv(spv []u8, target Target) !string {
	if spv.len % 4 != 0 { return error('SpirvInvalid') }
	mut context := voidptr(unsafe { nil })
	if C.spvc_context_create(&context) != C.SPVC_SUCCESS { return error('SpvcFailed') }
	defer { C.spvc_context_destroy(context) }
	C.spvc_context_set_error_callback(context, spirv_cross_error, unsafe { nil })
	mut ir := voidptr(unsafe { nil })
	// Source @alignCast checks the u32 alignment in runtime-safe builds.
	assert uint(spv.data) % 4 == 0
	if C.spvc_context_parse_spirv(context, &u32(spv.data), uint(spv.len / 4), &ir) != C.SPVC_SUCCESS {
		return error('SpvcFailed')
	}
	mut compiler := voidptr(unsafe { nil })
	backend := if target == .msl { C.SPVC_BACKEND_MSL } else { C.SPVC_BACKEND_GLSL }
	if C.spvc_context_create_compiler(context, backend, ir, C.SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
		&compiler) != C.SPVC_SUCCESS {
		return error('SpvcFailed')
	}
	mut options := voidptr(unsafe { nil })
	if C.spvc_compiler_create_compiler_options(compiler, &options) != C.SPVC_SUCCESS {
		return error('SpvcFailed')
	}
	if target == .msl {
		if C.spvc_compiler_options_set_bool(options,
			C.SPVC_COMPILER_OPTION_MSL_ENABLE_DECORATION_BINDING, true) != C.SPVC_SUCCESS {
			return error('SpvcFailed')
		}
	} else {
		if C.spvc_compiler_options_set_uint(options, C.SPVC_COMPILER_OPTION_GLSL_VERSION, 430) != C.SPVC_SUCCESS {
			return error('SpvcFailed')
		}
	}
	if C.spvc_compiler_install_compiler_options(compiler, options) != C.SPVC_SUCCESS {
		return error('SpvcFailed')
	}
	mut result := &char(unsafe { nil })
	if C.spvc_compiler_compile(compiler, &result) != C.SPVC_SUCCESS { return error('SpvcFailed') }
	return unsafe { cstring_to_vstring(result).clone() }
}

fn is_missing_file_error(err IError) bool {
	return err.msg().starts_with('shader file not found:')
}
