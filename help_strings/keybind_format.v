module help_strings

import strings

// web_keybind_actions formats the bundled records for the website reference.
pub fn web_keybind_actions() string {
	return format_keybind_actions(keybind_records, true, true)
}

// format_keybind_actions renders the keybinding help records as plain text or Markdown.
pub fn format_keybind_actions(source string, markdown bool, show_docs bool) string {
	entries := binding_action_help_entries(source)
	mut out := strings.new_builder(entries.len * 64)
	if markdown {
		out.write_string('---\n')
		out.write_string('title: Keybinding Action Reference\n')
		out.write_string('description: Reference of all Witty keybinding actions.\n')
		out.write_string('editOnGithubLink: https://github.com/ghostty-org/ghostty/edit/main/src/input/Binding.zig\n')
		out.write_string('---\n\n')
		out.write_string('This is a reference of all Witty keybinding actions.\n\n')
	}

	mut pending_docs := []string{}
	for entry in entries {
		// Ghostty buffers documentation so a shared comment placed above a run
		// of related actions is emitted immediately before the next documented
		// action. The V ActionTag has a comment on every field, but retaining the
		// buffer preserves the source algorithm for future shared comments.
		if show_docs && entry.docs.len > 0 {
			if pending_docs.len > 0 {
				write_help_docs(mut out, markdown, pending_docs)
			}
			out.write_u8(`\n`)
			pending_docs = []
		}
		if show_docs {
			if markdown {
				out.write_string('## `${entry.name}`\n')
			} else {
				out.write_string('${entry.name}:\n')
			}
		} else {
			out.write_string('${entry.name}\n')
		}
		if show_docs && entry.docs.len > 0 {
			pending_docs = entry.docs.clone()
		}
	}
	if pending_docs.len > 0 {
		write_help_docs(mut out, markdown, pending_docs)
	}
	return out.str()
}

struct KeybindHelpEntry {
	name string
	docs []string
}

// binding_action_help_entries reads the help_strings data generated from the
// pinned Binding.zig Action union and embedded into the executable at build
// time. Installed binaries therefore never need the source checkout.
fn binding_action_help_entries(source string) []KeybindHelpEntry {
	mut entries := []KeybindHelpEntry{}
	mut name := ''
	mut docs := []string{}
	for line in source.split_into_lines() {
		if line.starts_with('@@') {
			if name.len > 0 {
				// HelpStrings represents a trailing blank doc-comment line as a
				// trailing newline. The source generator explicitly skips the
				// final empty split field before buffering documentation.
				if docs.len > 0 && docs.last().len == 0 {
					docs.delete_last()
				}
				entries << KeybindHelpEntry{
					name: name
					docs: docs
				}
			}
			name = line[2..]
			docs = []string{}
			continue
		}
		docs << line
	}
	if name.len > 0 && name != '__end' {
		if docs.len > 0 && docs.last().len == 0 {
			docs.delete_last()
		}
		entries << KeybindHelpEntry{
			name: name
			docs: docs
		}
	}
	return entries
}

fn write_help_docs(mut out strings.Builder, markdown bool, docs []string) {
	for line in docs {
		if !markdown {
			out.write_string('  ')
		}
		out.write_string('${line}\n')
	}
}
