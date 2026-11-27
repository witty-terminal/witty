module witty_macos

#flag darwin -framework CoreServices
#flag darwin -framework UniformTypeIdentifiers
#insert "@VMODROOT/witty_macos/open_url_abi.h"
fn C.witty_open_url_utf8_string(bytes &u8, length uint) ObjId
fn C.witty_open_url_plain_text_type() ObjId
fn C.witty_open_url_decoded_path(path ObjId) ObjId
fn C.witty_open_url_default_application(identifier ObjId) ObjId
fn C.witty_open_urls_with_application(workspace ObjId, urls ObjId, application ObjId, configuration ObjId)

// Ghostty.App.openURL and NSWorkspace+Extension.swift, pinned 6c0e02d.
fn source_file_url(path ObjId) ObjId {
	url := msg_id1(get_class('NSURL'), 'fileURLWithPath:', path)
	if !is_nil(url) { return url }
	// Swift Foundation.URL preserves NUL as %00 in file paths. NSURL's older
	// filesystem constructor rejects it; native URLComponents preserves the
	// complete NSString path and performs Foundation's URL encoding.
	standardized := msg_id(path, 'stringByStandardizingPath')
	mut absolute := if msg_bool1(standardized, 'hasPrefix:', nsstring('/')) { standardized } else {
		// The filesystem append API also rejects NUL. NSString concatenation
		// preserves it, and NSURL.standardizedURL resolves relative dot segments.
		prefix := msg_id1(msg_id(msg_id(get_class('NSFileManager'), 'defaultManager'),
			'currentDirectoryPath'), 'stringByAppendingString:', nsstring('/'))
		msg_id1(prefix, 'stringByAppendingString:', standardized)
	}
	if msg_bool1(path, 'hasSuffix:', nsstring('/')) && !msg_bool1(absolute, 'hasSuffix:', nsstring('/')) {
		absolute = msg_id1(absolute, 'stringByAppendingString:', nsstring('/'))
	}
	components := msg_id(alloc('NSURLComponents'), 'init')
	defer { msg_void(components, 'release') }
	msg_void1(components, 'setScheme:', nsstring('file'))
	msg_void1(components, 'setHost:', nsstring(''))
	msg_void1(components, 'setPath:', absolute)
	return msg_id(msg_id(components, 'URL'), 'standardizedURL')
}

// The source falls back to a file URL when URL(string:) has no scheme.
fn source_url(value string) ObjId {
	// Ghostty.Action.OpenURL decodes all c.len bytes and maps invalid UTF-8 to
	// "". NSString's explicit byte length preserves embedded NUL characters.
	decoded := C.witty_open_url_utf8_string(value.str, uint(value.len))
	text := if is_nil(decoded) { nsstring('') } else { decoded }
	candidate := msg_id1(get_class('NSURL'), 'URLWithString:', text)
	if !is_nil(candidate) && !is_nil(msg_id(candidate, 'scheme')) { return candidate }
	// URL(filePath: "") resolves the current directory. NSURL's older constructor
	// rejects an empty string; its "." path performs the same native resolution.
	return source_file_url(if msg_u64(text, 'length') == 0 { nsstring('.') } else { text })
}

fn source_default_application(content_type ObjId) ObjId {
	// takeRetainedValue() becomes an autoreleased Foundation object.
	return msg_id(C.witty_open_url_default_application(content_type), 'autorelease')
}

fn source_default_application_for_extension(extension ObjId) ObjId {
	uti := msg_id1(get_class('UTType'), 'typeWithFilenameExtension:', extension)
	if is_nil(uti) { return nil_obj() }
	return source_default_application(msg_id(uti, 'identifier'))
}

fn source_text_editor(url ObjId) ObjId {
	// Swift URL.pathExtension is nonoptional even for scheme-only URLs. NSURL
	// returns nil for those paths, so preserve Swift's empty-string projection.
	// NSURL's decoded path truncates at NUL. Swift's URL path projection keeps
	// %00 escaped; Foundation's percent decoder takes that exact exclusion.
	components := msg_id2(get_class('NSURLComponents'), 'componentsWithURL:resolvingAgainstBaseURL:', url, nil_obj())
	encoded_path := msg_id(components, 'percentEncodedPath')
	decoded_path := if is_nil(encoded_path) { nil_obj() } else { C.witty_open_url_decoded_path(encoded_path) }
	path_extension := msg_id(if is_nil(decoded_path) { encoded_path } else { decoded_path }, 'pathExtension')
	editor := source_default_application_for_extension(if is_nil(path_extension) { nsstring('') } else { path_extension })
	if !is_nil(editor) { return editor }
	return source_default_application(msg_id(C.witty_open_url_plain_text_type(), 'identifier'))
}

fn source_open_url_with_workspace(value string, kind i32, workspace ObjId) bool {
	url := source_url(value)
	if kind == 1 {
		editor := source_text_editor(url)
		if !is_nil(editor) {
			configuration := msg_id(alloc('NSWorkspaceOpenConfiguration'), 'init')
			defer { msg_void(configuration, 'release') }
			C.witty_open_urls_with_application(workspace,
				msg_id1(get_class('NSArray'), 'arrayWithObject:', url), editor, configuration)
			return true
		}
	}
	// Source HTML/unknown actions and text without an editor use the default app.
	// The action is handled even if NSWorkspace declines or fails to open it.
	msg_bool1(workspace, 'openURL:', url)
	return true
}

// kind uses ghostty_action_open_url_kind_e: unknown=0, text=1, html=2.
pub fn source_open_url(value string, kind i32) bool {
	return source_open_url_with_workspace(value, kind,
		msg_id(get_class('NSWorkspace'), 'sharedWorkspace'))
}

// Ghostty.App.openConfig first converts config_open_path to an absolute file URL.
pub fn source_config_file_url(path string) string {
	// AllocatedString.string decodes the entire byte slice; openConfig skips
	// invalid UTF-8 (decoded as "") as well as genuinely empty paths.
	text := C.witty_open_url_utf8_string(path.str, uint(path.len))
	if is_nil(text) || msg_u64(text, 'length') == 0 { return '' }
	return objc_utf8_string(msg_id(source_file_url(text), 'absoluteString'))
}
