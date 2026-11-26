#!/usr/bin/env python3
"""Compare original Tahoe titlebar model/toolbar against the native V host."""
import argparse
import json
import pathlib
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument("ghostty", type=pathlib.Path)
p.add_argument("translated_output", type=pathlib.Path)
args = p.parse_args()
sources = args.ghostty / "macos/Sources"

def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]

view = (sources / "Helpers/Extensions/NSView+Extension.swift").read_text()
window = (sources / "Helpers/Extensions/NSWindow+Extension.swift").read_text()
array = (sources / "Helpers/Extensions/Array+Extension.swift").read_text()
tahoe = (sources / "Features/Terminal/Window Styles/TitlebarTabsTahoeTerminalWindow.swift").read_text()
with tempfile.TemporaryDirectory(prefix="witty-tahoe-source-") as tmp:
    fixture = pathlib.Path(tmp) / "TahoeSource.swift"
    fixture.write_text("import AppKit\nimport SwiftUI\n"
        + "enum Ghostty { enum SurfaceView { struct DerivedConfig {} } }\n"
        + "enum FixtureButtons { case hidden, visible }\n"
        + "struct FixtureConfig { var macosWindowButtons = FixtureButtons.visible }\n"
        + "class TransparentTitlebarTerminalWindow: NSWindow {\n"
        + "var titlebarFont: NSFont?\nvar supportsUpdateAccessory: Bool { true }\n"
        + "var derivedConfig = FixtureConfig()\n"
        + "func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {}\n"
        + "func reduceTabBarBackgroundGoldenGate() {}\n"
        + "func isTabBar(_ controller: NSTitlebarAccessoryViewController) -> Bool {\n"
        + "if let identifier = controller.identifier { return identifier.rawValue == \"_ghosttyTabBar\" }\n"
        + "return controller.view.contains(className: \"NSTabBar\") || "
        + "(controller.layoutAttribute == .bottom && controller.view.className == \"NSView\" "
        + "&& controller.view.subviews.isEmpty)\n}\n}\n"
        + "extension Array {\n" + block(array, "    subscript(safe index:") + "\n}\n"
        + "extension NSView {\n" + "\n".join(block(view, marker) for marker in (
            "    var rootView:", "    func contains(className", "    func firstSuperview(withClassName",
            "    func firstDescendant(withClassName")) + "\n}\n"
        + "extension NSWindow {\n" + block(window, "    var titlebarView:")
        + "\n" + block(window, "    var tabBarView:") + "\n}\n" + tahoe)
    binary = pathlib.Path(tmp) / "tahoe-source"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(fixture),
        str(pathlib.Path(__file__).with_name("main.swift")), "-o", str(binary)], check=True)
    actual = json.loads(subprocess.run([str(binary)], check=True,
        text=True, capture_output=True).stdout)
    expected = json.loads(args.translated_output.read_text())
    for records in (actual, expected):
        for record in records:
            record.setdefault("font_name", None)
    assert actual[0]["title"] == actual[0]["display_title"] == "👻 Ghostty"
    assert expected[0]["title"] == expected[0]["display_title"] == "👻 Witty"
    actual[0].update(title=expected[0]["title"], display_title=expected[0]["display_title"])
    assert actual == expected, (actual, expected)
    print(f"{len(actual)} unchanged Swift Tahoe title/model/toolbar records matched")
