module cli

import cli_args
import configpkg
import diagnostics
import encoding.utf8.validate
import font

pub struct ShowFaceOptions {
pub mut:
	cp           ?u32 @['cli_u21']
	string_      ?string
	style        font.Style = .regular
	presentation ?font.Presentation
	diagnostics  diagnostics.DiagnosticList
}

pub fn (opts ShowFaceOptions) deinit() {
	_ = opts
}

pub fn (opts ShowFaceOptions) help() ! {
	_ = opts
	action_options_help()!
}

pub struct ShowFaceResult {
pub:
	code   int
	output string
	errors string
}

// show_face resolves codepoints through the same SharedGrid used by terminal
// surfaces, including configured faces, platform fallbacks, embedded faces,
// emoji presentation, and Ghostty's internal sprite font.
pub fn show_face(args []string) !ShowFaceResult {
	opts := parse_show_face_options(args)!
	mut errors := []string{}
	for diagnostic in opts.diagnostics.items() {
		if diagnostic.location is diagnostics.CliLocation
			&& cli_args.has_field[ShowFaceOptions](diagnostic.key) {
			errors << 'config error: ${diagnostic.format()}'
		}
	}
	if errors.len > 0 {
		return ShowFaceResult{
			code:   1
			errors: output_lines(errors)
		}
	}
	if opts.cp == none && opts.string_ == none {
		return ShowFaceResult{
			code:   1
			errors: 'You must specify a codepoint with --cp or a string with --string\n'
		}
	}

	mut config := configpkg.Config.load_args(args) or {
		return ShowFaceResult{
			code:   1
			errors: 'Unable to load config: ${err}'
		}
	}
	for diagnostic in config.diagnostics {
		if cli_args.has_field[ShowFaceOptions](diagnostic.key)
			&& (diagnostic.location is diagnostics.NoneLocation
			|| diagnostic.location is diagnostics.CliLocation) {
			continue
		}
		errors << 'config error: ${diagnostic.format()}'
	}

	mut grid_set := font.SharedGridSet.init() or {
		return ShowFaceResult{
			code:   1
			errors: output_lines(errors) + 'Unable to initialize font grid set: ${err}\n'
		}
	}
	defer {
		grid_set.deinit()
	}
	mut font_config := font.DerivedConfig.init(config)!
	defer {
		font_config.deinit()
	}
	key, mut grid := grid_set.ref(&font_config, font.DesiredSize{
		points: config.font_size
		xdpi:   96
		ydpi:   96
	}) or {
		return ShowFaceResult{
			code:   1
			errors: output_lines(errors) + 'Unable to get font grid: ${err}\n'
		}
	}
	defer {
		grid_set.deref(key)
	}
	mut output := []string{}
	if cp := opts.cp {
		if lookup_error := show_face_lookup(mut grid, cp, opts.style, opts.presentation, mut output) {
			errors << lookup_error
			return ShowFaceResult{
				code:   1
				output: output_lines(output)
				errors: output_lines(errors)
			}
		}
	}
	if value := opts.string_ {
		if !validate.utf8_string(value) {
			errors << 'Unable to parse string as unicode: invalid UTF-8'
			return ShowFaceResult{
				code:   1
				output: output_lines(output)
				errors: output_lines(errors)
			}
		}
		for cp in value.runes() {
			if lookup_error := show_face_lookup(mut grid, u32(cp), opts.style, opts.presentation, mut
				output)
			{
				errors << lookup_error
				return ShowFaceResult{
					code:   1
					output: output_lines(output)
					errors: output_lines(errors)
				}
			}
		}
	}

	return ShowFaceResult{
		output: output_lines(output)
		errors: output_lines(errors)
	}
}

pub fn run_show_face(args []string) !int {
	result := show_face(args) or {
		if is_action_help_requested(err) {
			return err
		}
		eprintln('Error parsing args: ${err}')
		return 1
	}
	print(result.output)
	eprint(result.errors)
	return result.code
}

fn parse_show_face_options(args []string) !ShowFaceOptions {
	mut opts := ShowFaceOptions{}
	cli_args.parse[ShowFaceOptions](mut opts, args)!
	return opts
}

fn show_face_lookup(mut grid font.SharedGrid, cp u32, style font.Style, presentation ?font.Presentation, mut output []string) ?string {
	value := grid.get_index(cp, style, presentation) or { return 'Unable to get face: ${err}' }
	display := rune(cp).str()
	if !value.has_value {
		output << 'U+${cp:02X} « ${display} » not found.'
		return none
	}
	if _ := value.index.special() {
		output << "U+${cp:02X} « ${display} » is handled by Witty's internal sprites."
		return none
	}
	mut name_buf := []u8{len: 1024}
	face := grid.resolver.collection.get_face(value.index) or {
		return 'Unable to get face: ${err}'
	}
	name := face.name(mut name_buf) or { return 'Unable to get name of face: ${err}' }
	output << 'U+${cp:02X} « ${display} » found in face “${name}”.'
	return none
}
