import SwiftUI
import StreamProtocol

// MARK: - Keys

/// The USB HID usages the modifier row sends, plus the small character table a latched
/// ⌘/⌃/⌥ needs: those combinations never reach the software keyboard as text.
enum HIDKey {
    static let escape: UInt16 = 0x29
    static let tab: UInt16 = 0x2B
    static let deleteBackward: UInt16 = 0x2A
    static let rightArrow: UInt16 = 0x4F
    static let leftArrow: UInt16 = 0x50
    static let downArrow: UInt16 = 0x51
    static let upArrow: UInt16 = 0x52

    /// US-layout character → HID usage. Shortcuts are named by the unshifted key (⌘⇧S is the S
    /// key with two modifiers), so the character is lowercased first. Returns nil for anything
    /// outside the table — accented letters, emoji, IME output — which stays on the text path.
    static func usage(for character: Character) -> UInt16? {
        let lowered = character.lowercased()
        guard lowered.count == 1, let ascii = lowered.first?.asciiValue else { return nil }
        switch ascii {
        case 0x61...0x7A: return 0x04 + UInt16(ascii - 0x61)   // a–z
        case 0x31...0x39: return 0x1E + UInt16(ascii - 0x31)   // 1–9
        case 0x30: return 0x27                                  // 0
        case 0x20: return 0x2C                                  // space
        case 0x0A, 0x0D: return 0x28                            // return
        case 0x09: return tab
        case 0x08: return deleteBackward
        case 0x2D: return 0x2D                                  // -
        case 0x3D: return 0x2E                                  // =
        case 0x5B: return 0x2F                                  // [
        case 0x5D: return 0x30                                  // ]
        case 0x5C: return 0x31                                  // \
        case 0x3B: return 0x33                                  // ;
        case 0x27: return 0x34                                  // '
        case 0x60: return 0x35                                  // `
        case 0x2C: return 0x36                                  // ,
        case 0x2E: return 0x37                                  // .
        case 0x2F: return 0x38                                  // /
        default: return nil
        }
    }
}

// MARK: - Unified stream layout view

/// One layout view for every orientation and every device, driven by `StreamLayout`:
/// - Portrait: picture (aspect-fit), one bar (Apps | window thumbnails | Menus | Keyboard | Settings;
///   hidden while the software keyboard is up), trackpad (>= 75 pt), modifier row, then keyboard top.
/// - Landscape: slim 56 pt leading vertical rail (Apps, Menus, Keyboard, Settings) + full picture with
///   direct touch while the keyboard is down; picture (~55%) beside trackpad (~45%) above modifier row
///   and keyboard while the keyboard is up.
struct StreamLayoutView: View {
    @ObservedObject var client: StreamClient
    @Binding var drawerOpen: Bool
    @Binding var keyboardShown: Bool
    @Binding var textScale: Double?
    @Binding var windowMenu: UInt32?
    @Binding var latched: KeyModifiers
    let overlay: InputOverlayProxy
    let settingsOpen: Bool
    let setSettings: (_ open: Bool, _ restoreKeyboard: Bool) -> Void
    let menusOpened: () -> Void
    let menusClosed: () -> Void
    let settingsTransition: (_ anchor: UnitPoint) -> AnyTransition
    let onPanelSize: (CGSize) -> Void
    var onTrackpadShown: (Bool) -> Void = { _ in }
    var pairThisDevice: () -> Void = {}
    var linkLine: String? = nil
    var linkLineLines = 2
    var takeTour: () -> Void = {}
    let zoom: StreamZoomModel
    var hidden = false
    var room: CGRect = .zero
    var preview = false
    var chromeTransition: AnyTransition = .identity
    var fullScreen: HostSettingsPanel.FullScreenRow? = nil
    var showChrome: () -> Void = {}

    private var streamShape: RoundedRectangle { RoundedRectangle(cornerRadius: hidden ? 0 : 12, style: .continuous) }
    @Environment(\.duoFold) private var duoFold
    @ObservedObject private var keyboardFrame = KeyboardFrameMonitor.shared

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let kbTop: CGFloat? = (preview || hidden || !keyboardShown) ? nil :
                StreamLayout.keyboardTop(reported: keyboardFrame.frame, read: keyboardFrame.read,
                                         size: geo.size, origin: origin, fold: duoFold)
            let aspect: CGFloat = (client.videoSize.width > 0 && client.videoSize.height > 0)
                ? client.videoSize.width / client.videoSize.height
                : StreamLayout.defaultAspect
            let layout = StreamLayout(size: geo.size, fold: duoFold, keyboardTop: kbTop,
                                      aspect: aspect, hasMenus: client.menus.hasMenus)
            content(layout, origin: origin)
        }
    }

    private func content(_ layout: StreamLayout, origin: CGPoint) -> some View {
        let pictureRect: CGRect = hidden ? room
            : (layout.isLandscape && !layout.keyboardUp ? layout.pictureRoom : layout.picture)
        let viewport = hidden ? room.size : StreamLayout.viewportSize(for: layout.size, fold: duoFold)
        let laptopReadingWanted = !preview && !hidden && keyboardShown && duoFold.horizontalBand != nil && !layout.isLandscape
        let controlsTop = origin.y + (duoFold.horizontalBand.map { min(layout.size.height, $0.maxY.rounded(.up)) } ?? 0)

        return ZStack(alignment: .topLeading) {
            if preview {
                Color.black.placed(RevealCut.shown(RevealCut.place(for: layout), in: layout.size), in: layout.size)
            } else {
                Color.black
            }

            if !preview {
                livePicturePane
                    .placed(pictureRect, in: layout.size)
                    .accessibilityHidden(drawerOpen)
            }

            if !hidden {
                if let bar = layout.bar {
                    portraitBar(layout, bar: bar)
                        .placed(bar, in: layout.size)
                        .transition(chromeTransition)
                }

                if let rail = layout.rail {
                    landscapeRail(layout, rail: rail)
                        .placed(rail, in: layout.size)
                        .transition(chromeTransition)
                }

                if let pad = layout.trackpad, pad.width > 0, pad.height > 0 {
                    trackpad(verticalSpan: layout.trackpadSpan)
                        .placed(pad, in: layout.size)
                        .accessibilityHidden(drawerOpen)
                        .transition(chromeTransition)
                }

                if let keys = layout.keys, keys.width > 0, keys.height > 0 {
                    if let trailing = layout.keysTrailing, trailing.width > 0, trailing.height > 0 {
                        keyRow(slice: .leading, showsArrows: false, showsKeyboard: false, capHeight: keys.height)
                            .placed(keys, in: layout.size)
                            .accessibilityHidden(drawerOpen)
                            .transition(chromeTransition)
                        keyRow(slice: .trailing, showsArrows: true, showsKeyboard: layout.showsKeyboardCap, capHeight: trailing.height)
                            .placed(trailing, in: layout.size)
                            .accessibilityHidden(drawerOpen)
                            .transition(chromeTransition)
                    } else {
                        keyRow(slice: .all, showsArrows: layout.showsArrows, showsKeyboard: layout.showsKeyboardCap, capHeight: keys.height)
                            .placed(keys, in: layout.size)
                            .accessibilityHidden(drawerOpen)
                            .transition(chromeTransition)
                    }
                }
            }

            if drawerOpen, !preview {
                ForEach(layout.dim.indices, id: \.self) { index in
                    dim.placed(layout.dim[index], in: layout.size)
                }
                AppDrawer(client: client, drawerOpen: $drawerOpen)
                    .placed(layout.drawer, in: layout.size)
                    .transition(.opacity)
            }

            if settingsOpen, !preview {
                ForEach(layout.dim.indices, id: \.self) { index in
                    catcher.placed(layout.dim[index], in: layout.size)
                }
                HostSettingsPanel(client: client, close: { setSettings(false, true) }, textScale: $textScale,
                                  pairThisDevice: pairThisDevice, takeTour: takeTour, fullScreen: fullScreen)
                    .frame(width: layout.settings.width)
                    .frame(maxHeight: layout.settings.height, alignment: .top)
                    .placed(at: layout.settings.origin, in: layout.size)
                    .transition(settingsTransition(UnitPoint(x: layout.settingsAnchor.x, y: layout.settingsAnchor.y)))
            }
        }
        .onChange(of: viewport, initial: true) { _, size in
            if !preview { onPanelSize(size) }
        }
        .onChange(of: layout.trackpad != nil && !hidden, initial: true) { _, shown in
            if !preview { onTrackpadShown(shown) }
        }
        .onChange(of: KeyboardReadings(wanted: laptopReadingWanted, controlsTop: controlsTop), initial: true) { _, now in
            if !preview { KeyboardFrameMonitor.shared.setWantsReadings(now.wanted, controlsTop: now.controlsTop) }
        }
        .onChange(of: duoFold) { _, _ in if !preview { KeyboardFrameMonitor.shared.poseChanged() } }
        .onDisappear { if !preview { KeyboardFrameMonitor.shared.setWantsReadings(false, controlsTop: 0) } }
    }

    private struct KeyboardReadings: Equatable {
        var wanted: Bool
        var controlsTop: CGFloat
    }

    // MARK: Portrait one-bar

    private func portraitBar(_ layout: StreamLayout, bar: CGRect) -> some View {
        let wide = bar.width >= 520
        let thumbW: CGFloat = wide ? 74 : 68
        let thumbH: CGFloat = 42
        let thumbPad: CGFloat = max(0, (bar.height - thumbH) / 2)
        let badge: CGFloat = wide ? 20 : 18
        let spacing: CGFloat = wide ? 12 : 10
        return ZStack(alignment: .topLeading) {
            if let r = layout.appsButton {
                appsButton(size: r.size, radius: 13)
                    .offset(x: r.minX - bar.minX, y: r.minY - bar.minY)
            }
            if let r = layout.strip, r.width > 0 {
                WindowStrip(client: client, width: thumbW, height: thumbH, radius: 7, spacing: spacing,
                            pad: thumbPad, fade: 0.88, badge: badge, menuFor: $windowMenu)
                    .tourTarget(.strip, inset: WindowStrip.tourBand(pad: thumbPad))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX - bar.minX, y: r.minY - bar.minY)
                    .opacity(drawerOpen || settingsOpen ? 0 : 1)
                    .allowsHitTesting(!(drawerOpen || settingsOpen))
                    .accessibilityHidden(drawerOpen)
            }
            if let r = layout.menusButton {
                MacMenuButton(client: client, width: r.width, height: r.height, radius: 13,
                              iconSize: 18, spacing: 2, iconBox: 22, onOpen: menusOpened, onClose: menusClosed)
                    .offset(x: r.minX - bar.minX, y: r.minY - bar.minY)
                    .transition(.opacity)
            }
            if let r = layout.keyboardButton {
                keyboardButton(size: r.size, radius: 13)
                    .offset(x: r.minX - bar.minX, y: r.minY - bar.minY)
            }
            if let r = layout.settingsButton {
                settingsButton(size: r.size, radius: 13)
                    .offset(x: r.minX - bar.minX, y: r.minY - bar.minY)
            }
        }
        .frame(width: bar.width, height: bar.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.18), value: client.menus.hasMenus)
    }

    // MARK: Landscape leading vertical rail

    private func landscapeRail(_ layout: StreamLayout, rail: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Palette.bar.ignoresSafeArea(edges: .leading)
            if let r = layout.appsButton {
                appsButton(size: r.size, radius: 12, compact: true)
                    .offset(x: r.minX - rail.minX, y: r.minY - rail.minY)
            }
            if let r = layout.menusButton {
                MacMenuButton(client: client, width: r.width, height: r.height, radius: 12,
                              iconSize: 18, spacing: 2, iconBox: 20, onOpen: menusOpened, onClose: menusClosed)
                    .offset(x: r.minX - rail.minX, y: r.minY - rail.minY)
                    .transition(.opacity)
            }
            if let r = layout.keyboardButton {
                keyboardButton(size: r.size, radius: 12, compact: true)
                    .offset(x: r.minX - rail.minX, y: r.minY - rail.minY)
            }
            if let r = layout.settingsButton {
                settingsButton(size: r.size, radius: 12, compact: true)
                    .offset(x: r.minX - rail.minX, y: r.minY - rail.minY)
            }
        }
        .frame(width: rail.width, height: rail.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.18), value: client.menus.hasMenus)
    }

    // MARK: Picture, trackpad, key row, buttons

    private var livePicturePane: some View {
        ZStack {
            ZoomedStreamView(client: client, zoom: zoom)
            InputOverlay(videoSize: client.videoSize,
                         send: { client.sendInput($0) },
                         setOwnPointer: { client.setOwnPointer($0, from: $1) },
                         pointerFeed: { let f = client.pointerFeedState; return (f.anchor, f.reseeds) },
                         proxy: overlay,
                         isKeyboardShown: $keyboardShown,
                         latchedModifiers: latched,
                         onModifiersConsumed: { latched = [] },
                         sendGesture: { client.sendGesture($0, fingers: $1) },
                         macRepeatsKeys: { KeyTyping.macRepeats(keyRepeat: client.hostKeyRepeat) },
                         readZoom: { [zoom] in zoom.zoom },
                         writeZoom: { [zoom] in zoom.set($0) })
        }
        .background(hidden ? Color.black : Palette.panel)
        .overlay { LockedMacShade(client: client) }
        .overlay(alignment: .top) { LinkLineView(text: linkLine, lines: linkLineLines) }
        .overlay { HiddenPictureElement(hidden: hidden, mac: client.macName.isEmpty ? "The Mac" : client.macName, show: showChrome) }
        .clipShape(streamShape)
        .overlay(streamShape.strokeBorder(Color.white.opacity(hidden ? 0 : 0.09), lineWidth: 1))
        .tourTarget(.stream)
    }

    private func keyRow(slice: KeyRow.Slice, showsArrows: Bool, showsKeyboard: Bool, capHeight: CGFloat) -> some View {
        KeyRow(slice: slice, showsArrows: showsArrows, showsKeyboard: showsKeyboard,
               capHeight: capHeight, gap: StreamLayout.keyGap,
               latched: $latched, keyboardShown: keyboardShown,
               send: { client.sendFromKeyRow($0) },
               toggleKeyboard: { overlay.toggleKeyboard() })
            .tourTarget(.keys)
    }

    @ViewBuilder
    private func trackpad(verticalSpan: CGFloat?) -> some View {
        if preview {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Palette.trackpad)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        } else {
            Trackpad(send: { client.sendInput($0) },
                     setPointer: { client.setOwnPointer($0, from: .trackpad) },
                     feed: { let f = client.pointerFeedState; return (f.anchor, f.reseeds) },
                     onFingers: { client.trackpadFingers($0) },
                     latched: latched,
                     onModifiersConsumed: { latched = [] },
                     verticalSpan: verticalSpan,
                     sendGesture: { client.sendGesture($0, fingers: $1) },
                     readZoom: { [zoom] in zoom.zoom },
                     writeZoom: { [zoom] in zoom.set($0) })
                .tourTarget(.trackpad)
        }
    }

    private var dim: some View {
        Color.black.opacity(0.58)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { drawerOpen = false } }
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    private var catcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { setSettings(false, true) }
            .accessibilityHidden(true)
    }

    private func appsButton(size: CGSize, radius: CGFloat, compact: Bool = false) -> some View {
        barButton(open: drawerOpen, symbol: "magnifyingglass", label: "Apps", size: size, radius: radius, compact: compact,
                  accessibilityLabel: drawerOpen ? "Close the app list" : "Open the app list",
                  action: {
                      setSettings(false, false)
                      withAnimation(.easeOut(duration: 0.18)) { drawerOpen.toggle() }
                  })
            .tourTarget(.apps)
    }

    private func keyboardButton(size: CGSize, radius: CGFloat, compact: Bool = false) -> some View {
        barButton(open: keyboardShown, symbol: "keyboard", label: "Keyboard", size: size, radius: radius, compact: compact,
                  accessibilityLabel: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                  action: {
                      setSettings(false, false)
                      overlay.toggleKeyboard()
                  })
            .tourTarget(.keyboard)
    }

    private func settingsButton(size: CGSize, radius: CGFloat, compact: Bool = false) -> some View {
        barButton(open: settingsOpen, symbol: "gearshape", label: "Settings", size: size, radius: radius, compact: compact,
                  accessibilityLabel: settingsOpen ? "Close settings" : "Settings for \(client.macName.isEmpty ? "the Mac" : client.macName)",
                  action: { setSettings(!settingsOpen, true) })
            .tourTarget(.settings)
    }

    private func barButton(open: Bool, symbol: String, label: String, size: CGSize, radius: CGFloat, compact: Bool,
                           accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        BarButton(open: open, width: size.width, height: size.height, radius: radius,
                  accessibilityLabel: accessibilityLabel, action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 18 : 19))
                    .foregroundStyle(open ? Palette.accent : Palette.text)
                    .frame(height: compact ? 20 : 22)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(open ? Palette.accent : Palette.barLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 2)
        }
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }
}

private extension View {
    func placed(at origin: CGPoint, in size: CGSize) -> some View {
        padding(.leading, origin.x)
            .padding(.top, origin.y)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    func placed(_ rect: CGRect, in size: CGSize) -> some View {
        frame(width: rect.width, height: rect.height).placed(at: rect.origin, in: size)
    }
}

// MARK: - Key row

private struct HeldCapStyle: ButtonStyle {
    let pressed: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in pressed(isPressed) }
    }
}

private enum Key {
    case press(String, UInt16, String)
    case arrow(String, UInt16, String)
    case modifier(String, KeyModifiers, String)
    case keyboard

    #if DEBUG
    var title: String? {
        switch self {
        case .press(let title, _, _), .modifier(let title, _, _): return title
        case .arrow, .keyboard: return nil
        }
    }
    #endif
}

/// The modifier row: esc, tab, ctrl, opt, cmd, shift, plus arrows where width allows and a
/// hide-keyboard cap while the software keyboard is up (or split across the Duo's book-pose fold).
private struct KeyRow: View {
    enum Slice { case all, leading, trailing }

    let slice: Slice
    let showsArrows: Bool
    let showsKeyboard: Bool
    let capHeight: CGFloat
    let gap: CGFloat
    @Binding var latched: KeyModifiers
    let keyboardShown: Bool
    let send: (InputEvent) -> Void
    let toggleKeyboard: () -> Void
    @State private var heldCap = HeldCap()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var capsHold: Bool { !dynamicTypeSize.isAccessibilitySize }

    private static let base: [Key] = [
        .press("esc", HIDKey.escape, "Escape"),
        .press("tab", HIDKey.tab, "Tab"),
        .modifier("ctrl", .control, "Control"),
        .modifier("opt", .option, "Option"),
        .modifier("cmd", .command, "Command"),
        .modifier("shift", .shift, "Shift"),
    ]

    private static let arrows: [Key] = [
        .arrow("chevron.left", HIDKey.leftArrow, "Left arrow"),
        .arrow("chevron.down", HIDKey.downArrow, "Down arrow"),
        .arrow("chevron.up", HIDKey.upArrow, "Up arrow"),
        .arrow("chevron.right", HIDKey.rightArrow, "Right arrow"),
    ]

    private var shown: [Key] {
        switch slice {
        case .leading:
            return Self.base
        case .trailing:
            return (showsArrows ? Self.arrows : []) + (showsKeyboard ? [.keyboard] : [])
        case .all:
            return Self.base + (showsArrows ? Self.arrows : []) + (showsKeyboard ? [.keyboard] : [])
        }
    }

    var body: some View {
        HStack(spacing: gap) {
            ForEach(shown.indices, id: \.self) { index in
                key(shown[index])
            }
        }
        .frame(height: capHeight)
        .onDisappear { heldCap.releaseAll().forEach(send) }
        #if DEBUG
        .onAppear(perform: runInputTest)
        #endif
    }

    @ViewBuilder private func key(_ key: Key) -> some View {
        switch key {
        case .press(let title, let usage, let label):
            cap(open: false, label: label, largeContent: title, held: capsHold ? { touch(usage, down: $0) } : nil,
                action: { activate(usage) }) { text(title) }
        case .arrow(let symbol, let usage, let label):
            cap(open: false, label: label, held: capsHold ? { touch(usage, down: $0) } : nil, action: { activate(usage) }) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.text)
            }
        case .modifier(let title, let flag, let label):
            latchKey(key, title, flag, label: label)
        case .keyboard:
            cap(open: keyboardShown,
                label: keyboardShown ? "Hide the keyboard" : "Show the keyboard",
                action: { tap(key) }) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18))
                    .foregroundStyle(keyboardShown ? Palette.accent : Palette.text)
            }
        }
    }

    private func touch(_ usage: UInt16, down: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard down else { heldCap.touchUp(usage, at: now).forEach(send); return }
        let events = heldCap.touchDown(usage, latched: latched, at: now)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    private func activate(_ usage: UInt16) {
        let events = heldCap.activated(usage, latched: latched, at: ProcessInfo.processInfo.systemUptime)
        events.forEach(send)
        if HeldCap.spendsLatch(events) { latched = [] }
    }

    private func tap(_ key: Key) {
        switch key {
        case .press(_, let usage, _), .arrow(_, let usage, _):
            press(usage)
        case .modifier(_, let flag, _):
            latched.formSymmetricDifference(flag)
        case .keyboard:
            toggleKeyboard()
        }
    }

    @ViewBuilder
    private func cap<Content: View>(open: Bool, label: String, largeContent: String? = nil,
                                    held: ((Bool) -> Void)? = nil,
                                    action: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let base = Button(action: action) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(open ? Palette.controlOpen : Palette.control))
                .contentShape(shape)
        }
        let button = Group {
            if let held {
                base.buttonStyle(HeldCapStyle(pressed: held))
            } else {
                base.buttonStyle(.plain)
            }
        }
        .accessibilityLabel(label)
        if let largeContent {
            button.accessibilityShowsLargeContentViewer { Text(largeContent) }
        } else {
            button
        }
    }

    private func text(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func latchKey(_ key: Key, _ title: String, _ flag: KeyModifiers, label: String) -> some View {
        let on = latched.contains(flag)
        return cap(open: on,
                   label: on ? "\(label), held. Tap to release." : "\(label), hold for the next key",
                   largeContent: title, action: { tap(key) }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Palette.accent : Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func press(_ usage: UInt16) {
        KeyChord.press(usage, with: latched).forEach(send)
        latched = []
    }

    #if DEBUG
    private func runInputTest() {
        guard slice != .trailing, InputTest.claim("key row") else { return }
        for (time, title) in [(1.0, "cmd"), (1.4, "esc"), (1.8, "shift"), (2.0, "ctrl")] {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                guard let key = shown.first(where: { $0.title == title }) else {
                    print("input test: no \(title) cap in this key row"); return
                }
                tap(key)
                print("input test: the key row's \(title) tapped; latched now " + InputTest.describe(latched))
            }
        }
    }
    #endif
}
