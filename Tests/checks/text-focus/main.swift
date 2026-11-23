// TextFocusRule (Sources/SillHost/TextFocusRule.swift) and kind 48 TextFocus
// (Sources/StreamProtocol/TextFocus.swift): Accessibility focus classification, debounced
// transition tracking, and wire encode/decode (including WindowList.textFocus and older-client skip).
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

typealias E = TextFocusRule.Element
let sorted: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = .sortedKeys
    return e
}()
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }

// MARK: - Classification helper

check("nil element is not editable", TextFocusRule.classify(nil) == TextFocus(editable: false))

for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
    check("\(role) (default attributes) is editable, not secure",
          TextFocusRule.classify(E(role: role)) == TextFocus(editable: true))
    check("\(role) with valueSettable=true is editable",
          TextFocusRule.classify(E(role: role, enabled: true, valueSettable: true)) == TextFocus(editable: true))
    check("\(role) disabled is not editable",
          TextFocusRule.classify(E(role: role, enabled: false, valueSettable: true)) == TextFocus(editable: false))
    check("\(role) read-only (valueSettable=false) is not editable",
          TextFocusRule.classify(E(role: role, enabled: true, valueSettable: false)) == TextFocus(editable: false))
    check("\(role) with AXEditable=false is not editable",
          TextFocusRule.classify(E(role: role, enabled: true, editableAttribute: false, valueSettable: true)) == TextFocus(editable: false))
    check("\(role) with AXEditable=true overrides valueSettable=false",
          TextFocusRule.classify(E(role: role, enabled: true, editableAttribute: true, valueSettable: false)) == TextFocus(editable: true))
}

// Secure & search subroles
check("AXTextField with AXSecureTextField subrole is editable and secure",
      TextFocusRule.classify(E(role: "AXTextField", subrole: "AXSecureTextField")) == TextFocus(editable: true, secure: true))
check("disabled AXSecureTextField is not editable and does not leak secure",
      TextFocusRule.classify(E(role: "AXTextField", subrole: "AXSecureTextField", enabled: false)) == TextFocus(editable: false))
check("read-only AXSecureTextField is not editable",
      TextFocusRule.classify(E(role: "AXTextField", subrole: "AXSecureTextField", valueSettable: false)) == TextFocus(editable: false))
check("unknown role with AXSecureTextField subrole is editable and secure",
      TextFocusRule.classify(E(role: "AXUnknown", subrole: "AXSecureTextField")) == TextFocus(editable: true, secure: true))
check("AXTextField with AXSearchField subrole is editable, not secure",
      TextFocusRule.classify(E(role: "AXTextField", subrole: "AXSearchField")) == TextFocus(editable: true))
check("unknown role with AXSearchField subrole is editable",
      TextFocusRule.classify(E(role: "AXGroup", subrole: "AXSearchField")) == TextFocus(editable: true))

// Editable web content vs regular web browsing
check("AXWebArea with AXEditable=true is editable",
      TextFocusRule.classify(E(role: "AXWebArea", editableAttribute: true)) == TextFocus(editable: true))
check("AXWebArea with AXEditable=false is not editable",
      TextFocusRule.classify(E(role: "AXWebArea", editableAttribute: false)) == TextFocus(editable: false))
check("AXWebArea with no editable signals is not editable",
      TextFocusRule.classify(E(role: "AXWebArea")) == TextFocus(editable: false))
check("AXWebArea with valueSettable=true is editable",
      TextFocusRule.classify(E(role: "AXWebArea", valueSettable: true)) == TextFocus(editable: true))
check("AXWebArea with AXEditable=false and valueSettable=true is not editable",
      TextFocusRule.classify(E(role: "AXWebArea", editableAttribute: false, valueSettable: true)) == TextFocus(editable: false))
check("AXGroup with AXEditable=true (contenteditable div) is editable",
      TextFocusRule.classify(E(role: "AXGroup", editableAttribute: true)) == TextFocus(editable: true))
check("AXGroup disabled even with AXEditable=true is not editable",
      TextFocusRule.classify(E(role: "AXGroup", enabled: false, editableAttribute: true)) == TextFocus(editable: false))

// Non-text controls (even when AXValue is settable, e.g. sliders, checkboxes, scrollbars)
for role in ["AXButton", "AXSlider", "AXCheckBox", "AXScrollBar", "AXPopUpButton", "AXStaticText", "AXWindow", "AXGroup"] {
    check("\(role) with valueSettable=true is not editable",
          TextFocusRule.classify(E(role: role, enabled: true, valueSettable: true)) == TextFocus(editable: false))
}

// needsValueSettable avoids IPC on non-text controls
check("needsValueSettable true for text roles, web area, and secure/search subroles",
      ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"].allSatisfy {
          TextFocusRule.needsValueSettable(role: $0, subrole: nil)
      }
      && TextFocusRule.needsValueSettable(role: "AXGroup", subrole: "AXSecureTextField")
      && TextFocusRule.needsValueSettable(role: "AXGroup", subrole: "AXSearchField"))
check("needsValueSettable false for non-text controls",
      ["AXButton", "AXSlider", "AXCheckBox", "AXStaticText", "AXWindow", "AXGroup"].allSatisfy {
          !TextFocusRule.needsValueSettable(role: $0, subrole: nil)
      })

// MARK: - Debounced transition tracker

do {
    var t = TextFocusRule.Tracker()
    check("fresh tracker has nil current and flushes nothing", t.current == nil && t.flush(at: 10) == nil)
    let due1 = t.observe(TextFocus(editable: true), at: 1.0)
    check("first observe schedules debounce deadline", due1 == 1.0 + TextFocusRule.Tracker.debounce)
    check("flush before debounce emits nothing", t.flush(at: 1.05) == nil && t.current == nil)
    check("flush at debounce emits transition and sets current",
          t.flush(at: 1.0 + TextFocusRule.Tracker.debounce) == TextFocus(editable: true)
          && t.current == TextFocus(editable: true))
    check("second flush emits nothing", t.flush(at: 2.0) == nil)
    check("observing current state again schedules nothing", t.observe(TextFocus(editable: true), at: 2.0) == nil)

    // Coalesce transient drop (field A -> transient nil/false -> field B within debounce)
    let dropDue = t.observe(TextFocus(editable: false), at: 3.0)
    check("transient drop schedules debounce", dropDue == 3.0 + TextFocusRule.Tracker.debounce)
    let backDue = t.observe(TextFocus(editable: true), at: 3.03)
    check("returning to current within debounce cancels pending drop", backDue == nil && t.pending == nil)
    check("flush after cancelled drop emits nothing", t.flush(at: 4.0) == nil && t.current == TextFocus(editable: true))

    // Repeated identical pending observations do not starve the debounce
    let d1 = t.observe(TextFocus(editable: false), at: 5.0)
    let d2 = t.observe(TextFocus(editable: false), at: 5.05)
    check("repeated same pending state keeps original deadline", d1 == d2 && d1 == 5.0 + TextFocusRule.Tracker.debounce)
    check("flushes at original deadline despite repeat",
          t.flush(at: 5.0 + TextFocusRule.Tracker.debounce) == TextFocus(editable: false)
          && t.current == TextFocus(editable: false))

    // Transition between plain editable and secure editable
    _ = t.observe(TextFocus(editable: true), at: 6.0)
    _ = t.flush(at: 6.1)
    let secDue = t.observe(TextFocus(editable: true, secure: true), at: 7.0)
    check("plain -> secure schedules transition", secDue == 7.0 + TextFocusRule.Tracker.debounce)
    check("plain -> secure flushes secure state",
          t.flush(at: 7.1) == TextFocus(editable: true, secure: true) && t.current?.isSecure == true)

    // Clock stepped backwards does not hang a pending transition
    _ = t.observe(TextFocus(editable: false), at: 10.0)
    check("clock step back flushes pending transition", t.flush(at: 9.0) == TextFocus(editable: false))

    // Reset clears both current and pending
    _ = t.observe(TextFocus(editable: true), at: 11.0)
    t.reset()
    check("reset clears current and pending", t.current == nil && t.pending == nil && t.flush(at: 12.0) == nil)
}

// MARK: - Wire encode/decode and older-client skip

check("kind 48 is textFocus", StreamMessageKind.textFocus.rawValue == 48 && StreamMessageKind(rawValue: 48) == .textFocus)
check("TextFocus.generation is 1", TextFocus.generation == 1)

let plain = TextFocus(editable: true)
let secure = TextFocus(editable: true, secure: true)
let off = TextFocus(editable: false)
check("plain editable encodes without secure key", json(plain) == #"{"editable":true}"#)
check("secure editable encodes both keys", json(secure) == #"{"editable":true,"secure":true}"#)
check("non-editable encodes editable=false", json(off) == #"{"editable":false}"#)
check("empty TextFocus encodes as {} and decodes with false helpers",
      json(TextFocus()) == "{}"
      && Wire.decode(TextFocus.self, from: Data("{}".utf8)) == TextFocus()
      && !TextFocus().isEditable && !TextFocus().isSecure)
check("isEditable / isSecure semantics (secure without editable is not secure)",
      plain.isEditable && !plain.isSecure
      && secure.isEditable && secure.isSecure
      && !off.isEditable && !off.isSecure
      && !TextFocus(editable: false, secure: true).isEditable
      && !TextFocus(editable: false, secure: true).isSecure)
check("TextFocus round-trips through Wire",
      Wire.decode(TextFocus.self, from: Wire.encode(secure)) == secure
      && Wire.decode(TextFocus.self, from: Wire.encode(off)) == off)
check("future unknown keys in TextFocus JSON are skipped",
      Wire.decode(TextFocus.self, from: Data(#"{"editable":true,"secure":false,"keyboard":"url"}"#.utf8))
      == TextFocus(editable: true, secure: false))
check("malformed types in TextFocus JSON fail decode",
      Wire.decode(TextFocus.self, from: Data(#"{"editable":"yes"}"#.utf8)) == nil
      && Wire.decode(TextFocus.self, from: Data(#"{"secure":1}"#.utf8)) == nil)

// Framing with 14-byte header
let wireMsg = StreamMessage(kind: .textFocus, timestamp: 1_790_000_000.5, isKeyframe: false, payload: Wire.encode(secure)).serialized()
let parsedHeader = StreamMessage.parseHeader(wireMsg)
check("kind 48 message header parses with payload length",
      wireMsg.first == 48
      && parsedHeader?.kind == .textFocus
      && parsedHeader?.timestamp == 1_790_000_000.5
      && parsedHeader?.isKeyframe == false
      && parsedHeader?.payloadLength == wireMsg.count - StreamMessage.headerLength)
check("kind 48 payload decodes back from serialized message",
      Wire.decode(TextFocus.self, from: wireMsg.subdata(in: StreamMessage.headerLength..<wireMsg.count)) == secure)
check("kind 48 payload is well within maxOtherHostPayload",
      (parsedHeader?.payloadLength ?? Int.max) <= StreamMessage.maxOtherHostPayload)

// Older-client skip: an older build whose StreamMessageKind stops at 47 maps raw byte 48 to .unknown
// and still reads the payload length to skip past it cleanly to the next message.
enum OldStreamMessageKind: UInt8 {
    case windowList = 2, keyframeRequest = 44, nextDisplay = 47, unknown = 255
}
let oldKind = OldStreamMessageKind(rawValue: wireMsg[wireMsg.startIndex]) ?? .unknown
let skippedOffset = StreamMessage.headerLength + (parsedHeader?.payloadLength ?? 0)
let followUp = StreamMessage(kind: .windowList, timestamp: 2, isKeyframe: false, payload: Data("{}".utf8)).serialized()
let combined = wireMsg + followUp
let nextHeader = StreamMessage.parseHeader(combined.subdata(in: skippedOffset..<combined.count))
check("older client maps kind 48 to .unknown and skips cleanly to the following message",
      oldKind == .unknown && nextHeader?.kind == .windowList && nextHeader?.payloadLength == 2)

// WindowList.textFocus capability field
var list = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L")
check("WindowList omits textFocus when nil", !json(list).contains("textFocus") && list.textFocus == nil)
list.textFocus = TextFocus.generation
check("WindowList encodes textFocus=1 and round-trips",
      json(list).contains(#""textFocus":1"#)
      && Wire.decode(WindowList.self, from: Wire.encode(list))?.textFocus == 1)
struct OlderWindowList: Decodable { var macName: String; var keyRepeat: Int? }
check("older WindowList reader skips textFocus",
      Wire.decode(OlderWindowList.self, from: Wire.encode(list))?.macName == "Mac mini")
check("older host WindowList without textFocus decodes with textFocus == nil",
      Wire.decode(WindowList.self, from: Data(#"{"macName":"Mac","windows":[],"active":{"desktop":{}}}"#.utf8))?.textFocus == nil)

print(fails == 0 ? "ok: \(passes) checks" : "FAILED: \(fails) of \(passes + fails) checks")
exit(fails == 0 ? 0 : 1)
