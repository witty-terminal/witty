import AppKit

// Fixture surface uses the original SurfaceView Codable keys. SplitTree.swift
// is compiled directly from the pinned source checkout, without copying it.
final class FixtureSurface: NSView, Codable, Identifiable {
    let id: UUID
    let pwd: String?
    let savedTitle: String
    let isUserSetTitle: Bool
    init(_ suffix: String, pwd: String?, title: String, user: Bool) {
        id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE" + suffix)!
        self.pwd = pwd; savedTitle = title; isUserSetTitle = user
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("unused fixture path") }
    enum CodingKeys: String, CodingKey { case pwd, uuid, title, isUserSetTitle }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID(uuidString: try c.decode(String.self, forKey: .uuid))!
        pwd = try c.decode(String?.self, forKey: .pwd)
        savedTitle = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isUserSetTitle = try c.decodeIfPresent(Bool.self, forKey: .isUserSetTitle) ?? false
        super.init(frame: .zero)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pwd, forKey: .pwd); try c.encode(id.uuidString, forKey: .uuid)
        try c.encode(savedTitle, forKey: .title); try c.encode(isUserSetTitle, forKey: .isUserSetTitle)
    }
}
typealias Tree = SplitTree<FixtureSurface>
if CommandLine.arguments[1] == "decode-cache" {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
    let cache = decoder.decodeDecodable(QuickTerminalScreenStateCache.Entries.self, forKey: "value")!
    let entry = cache[UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1")!]!
    precondition(entry.frame.width == 479.52 && entry.scale == 2)
    precondition(entry.lastSeen.timeIntervalSince1970 == 1700000000)
    print("source Swift decoded native V screen cache")
} else if CommandLine.arguments[1] == "encode-cache" {
    let entry = QuickTerminalScreenStateCache.DisplayEntry(frame: .init(x: 4, y: 5, width: 479.52, height: 350), screenSize: .init(width: 1440, height: 900), scale: 2, lastSeen: Date(timeIntervalSince1970: 1700000000))
    let cache: QuickTerminalScreenStateCache.Entries = [UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1")!: entry]
    let encoder = NSKeyedArchiver(requiringSecureCoding: true)
    try encoder.encodeEncodable(cache, forKey: "value")
    try encoder.encodedData.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} else if CommandLine.arguments[1] == "decode" {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
    let tree = decoder.decodeDecodable(Tree.self, forKey: "value")!
    precondition(tree.root?.leaves().count == 3)
    precondition(tree.root?.path(to: tree.zoomed!)?.path.count == 1)
    precondition(tree.root!.leaves()[1].isUserSetTitle)
    print("source Swift decoded native V archive")
} else {
    let a = FixtureSurface("1", pwd: "/tmp/one", title: "one", user: false)
    let b = FixtureSurface("2", pwd: nil, title: "manual", user: true)
    let c = FixtureSurface("3", pwd: "/tmp/three", title: "", user: false)
    let right = Tree.Node.split(.init(direction: .vertical, ratio: 0.6, left: .leaf(view: b), right: .leaf(view: c)))
    let tree = Tree(root: .split(.init(direction: .horizontal, ratio: 0.3, left: .leaf(view: a), right: right)), zoomed: right)
    let encoder = NSKeyedArchiver(requiringSecureCoding: true)
    try encoder.encodeEncodable(tree, forKey: "value")
    try encoder.encodedData.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
