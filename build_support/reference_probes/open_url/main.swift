import AppKit

// C ABI producer fixtures only. Original OpenURL and AllocatedString decode
// bytes using their real explicit length; original actions choose the route.
typealias ghostty_action_open_url_kind_e = Int32
let GHOSTTY_ACTION_OPEN_URL_KIND_TEXT: Int32 = 1
let GHOSTTY_ACTION_OPEN_URL_KIND_HTML: Int32 = 2
struct ghostty_action_open_url_s {
    var url: UnsafePointer<CChar>? = nil
    var len: UInt = 0
    var kind: Int32 = 0
}
struct ghostty_string_s { var ptr: UnsafePointer<UInt8>? = nil; var len: UInt = 0 }
var configBytes = ghostty_string_s()
func ghostty_config_open_path() -> ghostty_string_s { configBytes }
// Borrowed fixture data lives for the complete synchronous source action.
func ghostty_string_free(_ value: ghostty_string_s) {}

final class URLProbeWorkspace {
    static let shared = URLProbeWorkspace()
    var lastURL = ""
    var lastEditor = ""
    var calls = 0
    var defaultTextEditor: URL? { NSWorkspace.shared.defaultTextEditor }
    func defaultApplicationURL(forExtension ext: String) -> URL? {
        NSWorkspace.shared.defaultApplicationURL(forExtension: ext)
    }
    func open(_ url: URL) -> Bool {
        lastURL = url.absoluteString
        lastEditor = ""
        calls += 1
        return false
    }
    func open(_ urls: [URL], withApplicationAt editor: URL, configuration: NSWorkspace.OpenConfiguration) {
        precondition(urls.count == 1)
        lastURL = urls[0].absoluteString
        lastEditor = editor.absoluteString
        calls += 1
    }
}

struct URLProbeRecord: Codable { let input: String; let kind: Int32; let url: String; let editor: String }
let values = ["https://ghostty.org/docs?query=hello world", "https://ghostty.org/docs/a%20b",
              "/tmp/witty config.witty", "relative config.txt", "file:///tmp/witty%20config.txt",
              "/tmp/readme.md", "/tmp/unknown-extension.witty-ultra-nonexistent-extension",
              "/tmp/no-extension", "", "mailto:alex@example.test", "/tmp/native.html"]
var inputs: [(String, [UInt8])] = values.map { ($0, Array($0.utf8)) }
inputs.append(("url-with-NUL", Array("https://ghostty.org/a".utf8) + [0, 98]))
inputs.append(("path-with-NUL", Array("/tmp/witty".utf8) + [0] + Array("config.txt".utf8)))
inputs.append(("path-NUL-before-extension", Array("/tmp/a".utf8) + [0] + Array(".md".utf8)))
inputs.append(("path-NUL-inside-extension", Array("/tmp/a.m".utf8) + [0] + Array("d".utf8)))
inputs.append(("relative-path-NUL", Array("relative a".utf8) + [0] + Array(".md".utf8)))
inputs.append(("relative-dot-path-NUL", Array("a/../b".utf8) + [0] + Array(".md".utf8)))
inputs.append(("trailing-slash-path-NUL", Array("/tmp/a".utf8) + [0] + Array("/".utf8)))
inputs.append(("tilde-path-NUL", Array("~/a".utf8) + [0] + Array(".md".utf8)))
inputs.append(("unknown-tilde-path-NUL", Array("~witty-audit-nonexistent-user/a".utf8) + [0] + Array(".md".utf8)))
inputs.append(("invalid-UTF8", [0xff]))
inputs.append(("invalid-truncated-UTF8", [0xe2, 0x82]))
inputs.append(("unterminated-length-slice", Array("https://ghostty.org/bounded.txt".utf8)))
inputs.append(("encoded-extension", Array("file:///tmp/a.%6dd".utf8)))
inputs.append(("opaque-extension", Array("mailto:alex@example.md".utf8)))
inputs.append(("encoded-NUL-before-encoded-extension", Array("file:///tmp/a%00.%6dd".utf8)))
inputs.append(("encoded-NUL-inside-encoded-extension", Array("file:///tmp/a.%6d%00d".utf8)))
var records: [URLProbeRecord] = []
for (input, bytes) in inputs {
    for kind: Int32 in [0, 1, 2] {
        let before = URLProbeWorkspace.shared.calls
        let backing = input == "unterminated-length-slice" ? bytes + Array("-ignored-trailing-bytes".utf8) : bytes
        backing.withUnsafeBytes { buffer in
            let pointer = buffer.baseAddress?.assumingMemoryBound(to: CChar.self)
            precondition(SourceURLAction.openURL(ghostty_action_open_url_s(url: pointer, len: UInt(bytes.count), kind: kind)))
        }
        precondition(URLProbeWorkspace.shared.calls == before + 1)
        records.append(URLProbeRecord(input: input, kind: kind,
                                      url: URLProbeWorkspace.shared.lastURL,
                                      editor: URLProbeWorkspace.shared.lastEditor))
    }
}
let configs: [(String, [UInt8])] = [
    ("config-valid", Array("/tmp/witty config.witty".utf8)),
    ("config-empty", []),
    ("config-with-NUL", Array("/tmp/witty".utf8) + [0] + Array("config.witty".utf8)),
    ("config-invalid-UTF8", [0xff])]
for (input, bytes) in configs {
    let before = URLProbeWorkspace.shared.calls
    bytes.withUnsafeBufferPointer { buffer in
        configBytes = ghostty_string_s(ptr: buffer.baseAddress, len: UInt(bytes.count))
        SourceURLAction.openConfig()
    }
    precondition(URLProbeWorkspace.shared.calls == before || URLProbeWorkspace.shared.calls == before + 1)
    let opened = URLProbeWorkspace.shared.calls > before
    records.append(URLProbeRecord(input: input, kind: -1,
                                  url: opened ? URLProbeWorkspace.shared.lastURL : "",
                                  editor: opened ? URLProbeWorkspace.shared.lastEditor : ""))
}
print(String(data: try JSONEncoder().encode(records), encoding: .utf8)!)
