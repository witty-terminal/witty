module native_metallib

import os

pub struct Options {
pub:
	name            string = 'witty'
	os_tag          string = os.user_os()
	simulator       bool
	minimum_version ?string
	sources         []string
}

pub struct Step {
pub:
	output_ir      string
	output_library string
	compile_args   []string
	archive_args   []string
}

// Source: src/build/MetallibStep.zig. Non-Apple targets have no step.
pub fn create(repo_root string, options Options) ?Step {
	if options.os_tag !in ['macos', 'ios'] { return none }
	sdk := if options.os_tag == 'macos' { 'macosx' } else { 'iphoneos' }
	platform := if options.os_tag == 'macos' {
		'-mmacos-version-min'
	} else if options.simulator {
		'-mios-simulator-version-min'
	} else {
		'-mios-version-min'
	}
	minimum := options.minimum_version or { if options.os_tag == 'macos' { '10.14' } else { '11.0' } }
	directory := os.join_path(repo_root, '.witty-build', 'native')
	ir := os.join_path(directory, options.name + '.ir')
	library := os.join_path(directory, options.name + '.metallib')
	mut compile := ['-sdk', sdk, 'metal', '-o', ir, '-c']
	compile << if options.sources.len > 0 {
		options.sources
	} else {
		[os.join_path(repo_root, 'renderer', 'shaders.metal')]
	}
	compile << platform + '=' + minimum
	return Step{
		output_ir:      ir
		output_library: library
		compile_args:   compile
		archive_args:   ['-sdk', sdk, 'metallib', '-o', library, ir]
	}
}

pub struct BuildResult {
pub:
	output ?string
}

pub fn build(repo_root string, options Options) !BuildResult {
	step := create(repo_root, options) or { return BuildResult{} }
	os.mkdir_all(os.dir(step.output_library))!
	run('/usr/bin/xcrun', step.compile_args)!
	run('/usr/bin/xcrun', step.archive_args)!
	return BuildResult{ output: step.output_library }
}

fn run(executable string, args []string) ! {
	mut process := os.new_process(executable)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	errors := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${executable} failed (${code}): ${output}${errors}') }
}
