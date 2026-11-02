import Foundation

/// A key that can start dictation on its own: a right-hand modifier or a
/// function key. Modifiers arrive as flagsChanged events and are told apart
/// by their device-dependent flag; function keys arrive as keyDown/keyUp.
struct Hotkey: Equatable, Identifiable {
    let keyCode: Int64
    /// Short label for a keycap, e.g. "Right ⌥".
    let label: String
    /// Spelled out for sentences, e.g. "Right Option".
    let name: String
    /// NX_DEVICE* mask for modifiers; nil for ordinary keys.
    let deviceMask: UInt64?

    var id: Int64 { keyCode }
    var isModifier: Bool { deviceMask != nil }

    static let rightOption = Hotkey(keyCode: 61, label: "Right ⌥", name: "Right Option", deviceMask: 0x40)

    static let all: [Hotkey] = {
        var keys = [
            rightOption,
            Hotkey(keyCode: 54, label: "Right ⌘", name: "Right Command", deviceMask: 0x10),
            Hotkey(keyCode: 62, label: "Right ⌃", name: "Right Control", deviceMask: 0x2000),
        ]
        let functionKeys: [Int64] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                     105, 107, 113, 106, 64, 79, 80]
        for (i, code) in functionKeys.enumerated() {
            keys.append(Hotkey(keyCode: code, label: "F\(i + 1)", name: "F\(i + 1)", deviceMask: nil))
        }
        return keys
    }()

    static func with(keyCode: Int64) -> Hotkey? { all.first { $0.keyCode == keyCode } }

    static var current: Hotkey { with(keyCode: Settings.hotkeyCode) ?? rightOption }

    /// Said when someone presses a key that can't be used.
    static let choices = "Right Option, Right Command, Right Control or a function key"
}
