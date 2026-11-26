import AppKit
import SwiftUI

private let columns = 12
private let tileWidth = 22.0
private let tileHeight = 30.0

private struct CoveragePanel: View {
    let widths: [Int]
    let radius: Double
    let opacity: Double

    var body: some View {
        let rows = (widths.count * 4 + columns - 1) / columns
        ZStack(alignment: .topLeading) {
            ForEach(0..<(widths.count * 4), id: \.self) { index in
                let width = widths[index / 4]
                let phase = index % 4
                UnevenRoundedRectangle(cornerRadii: .init(topTrailing: radius))
                    .fill(.white.opacity(opacity))
                    .frame(width: Double(width) / 2, height: 26)
                    .offset(x: Double(index % columns) * tileWidth + 1 + Double((phase ^ width) & 1) / 2,
                            y: Double(index / columns) * tileHeight + 1 + Double(phase >> 1) / 2)
            }
            Rectangle().fill(.white.opacity(opacity)).frame(width: 10, height: 5)
                .offset(y: Double(rows) * tileHeight)
        }
        .frame(width: Double(columns) * tileWidth, height: Double(rows) * tileHeight + 7,
               alignment: .topLeading)
    }
}

@main struct Probe {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let scale = Int(CommandLine.arguments[2])!
        let widths = scale == 2 ? Array(20...34) : Array(10...17)
        let rows = (widths.count * 4 + columns - 1) / columns
        let frame = NSRect(x: 0, y: 0, width: Double(columns) * tileWidth,
                           height: Double(rows) * tileHeight + 7)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered,
                              defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.colorSpace = .displayP3
        window.appearance = NSAppearance(named: .aqua)

        // Load the window-capture API dynamically on SDKs that mark it unavailable.
        typealias WindowImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID,
            CGWindowImageOption) -> Unmanaged<CGImage>?
        let capture = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage")!,
                                    to: WindowImage.self)
        for step in 0..<65 {
            let opacity = 1 - Double(step) / 128
            // Run both profiles on a 2× display. Halving the radius and the
            // width in points gives 1× corner geometry in backing pixels.
            let host = NSHostingView(rootView: CoveragePanel(widths: widths,
                                     radius: 4.5 * Double(scale), opacity: opacity))
            host.frame = frame
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            window.orderBack(nil)
            window.displayIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.075))
            let image = capture(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                [.boundsIgnoreFraming, .bestResolution])!.takeRetainedValue()
            precondition(image.width == Int(frame.width) * 2, "Use a 2× display")
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent("\(step).png"))
        }
        window.close()
    }
}
