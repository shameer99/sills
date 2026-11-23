import Foundation
import AppKit
import ApplicationServices
import StreamProtocol

/// Watches the streamed Mac app's Accessibility focused UI element (`kAXFocusedUIElementChangedNotification`)
/// and emits debounced `TextFocus` transitions (kind 48) while a source streams, so an iOS client
/// without a hardware keyboard can show or dismiss its software keyboard automatically.
///
/// Main actor for state, `AXObserver` lifecycle and debouncing; `AXUIElement` attribute reads run
/// off the main actor on `sill.textfocus` with a short messaging timeout so a hung app never stalls
/// the coordinator or the network queue.
@MainActor
final class TextFocusWatcher {
    enum Mode: Equatable {
        /// Nothing streams (or synthetic test host): observer torn down, nothing emitted.
        case stopped
        /// Streaming a source with no watchable app (e.g. Sill's own window): non-editable.
        case none
        /// Streaming a specific app's window: observe that app's focused UI element.
        case app(pid_t)
        /// Streaming the Desktop: observe the frontmost app and follow app activation.
        case desktop
    }

    /// Fires on `@MainActor` only on debounced transitions while streaming.
    var onChange: ((TextFocus) -> Void)?
    /// The last emitted focus state while streaming, for newly connected clients (`sendCatalog`).
    var current: TextFocus? { tracker.current }

    private let appKitLoop: Bool
    private let frontmostPID: () -> pid_t?
    private let readQueue = DispatchQueue(label: "sill.textfocus", qos: .userInitiated)
    private nonisolated static let axTimeout: Float = 0.3

    /// Sends an `AXUIElement` reference across to `readQueue` (its API is thread-safe per element).
    private struct SendableElement: @unchecked Sendable {
        let value: AXUIElement
    }

    private var mode: Mode = .stopped
    private var observedPID: pid_t?
    private var observer: AXObserver?
    private var observerSource: CFRunLoopSource?
    private var observerApp: AXUIElement?
    private var observerBox: UnsafeMutableRawPointer?
    private var workspaceObserver: NSObjectProtocol?

    private var tracker = TextFocusRule.Tracker()
    private var debounceTimer: DispatchSourceTimer?
    private var probeGeneration: UInt64 = 0

    /// Weak wrapper passed through `AXObserverCreate`'s C `refcon`. Retained while the observer's
    /// run loop source is attached to `CFRunLoopGetMain()` and released in `teardownObserver()`.
    private final class ObserverBox {
        weak var watcher: TextFocusWatcher?
        init(_ watcher: TextFocusWatcher) { self.watcher = watcher }
    }

    init(appKitLoop: Bool, frontmostPID: @escaping () -> pid_t?) {
        self.appKitLoop = appKitLoop
        self.frontmostPID = frontmostPID
    }

    deinit {
        debounceTimer?.cancel()
    }

    func stop() {
        watch(mode: .stopped)
    }

    func watch(mode newMode: Mode) {
        if newMode == .stopped {
            guard mode != .stopped else { return }
            mode = .stopped
            probeGeneration &+= 1
            teardownObserver()
            removeWorkspaceObserver()
            cancelDebounce()
            tracker.reset()
            return
        }
        let modeChanged = newMode != mode
        mode = newMode
        installWorkspaceObserverIfNeeded()
        switch newMode {
        case .stopped:
            break
        case .none:
            teardownObserver()
            probeGeneration &+= 1
            handleReading(TextFocus(editable: false))
        case .app(let pid):
            if modeChanged || observedPID != pid {
                retarget(pid: pid)
            } else {
                probe(pid: pid, element: nil)
            }
        case .desktop:
            let pid = resolvedDesktopPID()
            if modeChanged || observedPID != pid {
                retarget(pid: pid)
            } else if let pid {
                probe(pid: pid, element: nil)
            }
        }
    }

    /// Re-evaluates the watched app when app activation may have changed (from `NSWorkspace`
    /// notifications under `appKitLoop`, or from catalog polls in plain CLI mode).
    func frontmostMayHaveChanged() {
        switch mode {
        case .stopped, .none:
            return
        case .desktop:
            let pid = resolvedDesktopPID()
            if pid != observedPID {
                retarget(pid: pid)
            } else if let pid {
                probe(pid: pid, element: nil)
            }
        case .app(let pid):
            probe(pid: pid, element: nil)
        }
    }

    private func resolvedDesktopPID() -> pid_t? {
        guard let pid = frontmostPID(), pid != WindowCatalog.ownPID else { return nil }
        return pid
    }

    private func installWorkspaceObserverIfNeeded() {
        guard appKitLoop, workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.frontmostMayHaveChanged() }
        }
    }

    private func removeWorkspaceObserver() {
        guard let obs = workspaceObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(obs)
        workspaceObserver = nil
    }

    private func retarget(pid: pid_t?) {
        teardownObserver()
        guard let pid else {
            probeGeneration &+= 1
            handleReading(TextFocus(editable: false))
            return
        }
        guard AXIsProcessTrusted() else { return }
        observedPID = pid
        if appKitLoop {
            installObserver(for: pid)
        }
        probe(pid: pid, element: nil)
    }

    private func installObserver(for pid: pid_t) {
        var obs: AXObserver?
        guard AXObserverCreate(pid, Self.axCallback, &obs) == .success, let obs else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.axTimeout)
        let box = Unmanaged.passRetained(ObserverBox(self)).toOpaque()
        let focusErr = AXObserverAddNotification(obs, app, kAXFocusedUIElementChangedNotification as CFString, box)
        let windowErr = AXObserverAddNotification(obs, app, kAXFocusedWindowChangedNotification as CFString, box)
        guard focusErr == .success || focusErr == .notificationAlreadyRegistered || windowErr == .success else {
            Unmanaged<ObserverBox>.fromOpaque(box).release()
            return
        }
        let source = AXObserverGetRunLoopSource(obs)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        observer = obs
        observerSource = source
        observerApp = app
        observerBox = box
    }

    private func teardownObserver() {
        if let obs = observer, let app = observerApp {
            AXObserverRemoveNotification(obs, app, kAXFocusedUIElementChangedNotification as CFString)
            AXObserverRemoveNotification(obs, app, kAXFocusedWindowChangedNotification as CFString)
        }
        if let source = observerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let box = observerBox {
            Unmanaged<ObserverBox>.fromOpaque(box).release()
        }
        observer = nil
        observerSource = nil
        observerApp = nil
        observerBox = nil
        observedPID = nil
    }

    private static let axCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let box = Unmanaged<ObserverBox>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        let focused: AXUIElement? = name == (kAXFocusedUIElementChangedNotification as String) ? element : nil
        MainActor.assumeIsolated {
            box.watcher?.observerFired(element: focused)
        }
    }

    private func observerFired(element: AXUIElement?) {
        guard mode != .stopped, let pid = observedPID else { return }
        probe(pid: pid, element: element)
    }

    private func probe(pid: pid_t, element: AXUIElement?) {
        probeGeneration &+= 1
        let gen = probeGeneration
        let boxed = element.map(SendableElement.init)
        readQueue.async { [weak self] in
            let focus = Self.readFocus(pid: pid, element: boxed?.value)
            guard let focus else { return }
            Task { @MainActor [weak self] in
                guard let self, self.mode != .stopped, self.probeGeneration == gen else { return }
                self.handleReading(focus)
            }
        }
    }

    private func handleReading(_ focus: TextFocus) {
        let now = CFAbsoluteTimeGetCurrent()
        guard let due = tracker.observe(focus, at: now) else {
            cancelDebounce()
            return
        }
        scheduleDebounce(delay: max(0.001, due - now))
    }

    private func scheduleDebounce(delay: TimeInterval) {
        cancelDebounce()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + delay, leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.flushDebounce()
            }
        }
        t.resume()
        debounceTimer = t
    }

    private func cancelDebounce() {
        debounceTimer?.cancel()
        debounceTimer = nil
    }

    private func flushDebounce() {
        cancelDebounce()
        guard mode != .stopped, let emitted = tracker.flush(at: CFAbsoluteTimeGetCurrent()) else { return }
        onChange?(emitted)
        Stats.shared.bump("text.focus")
    }

    /// Reads the focused element's Accessibility attributes on `readQueue` and classifies them.
    /// Returns nil when Accessibility is untrusted or a transient timeout occurs, so we never
    /// falsely dismiss the keyboard while an app is momentarily busy.
    private nonisolated static func readFocus(pid: pid_t, element: AXUIElement?) -> TextFocus? {
        guard AXIsProcessTrusted() else { return nil }
        let target: AXUIElement
        if let element {
            target = element
        } else {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, axTimeout)
            var focused: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
            if err == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                target = focused as! AXUIElement
            } else if err == .noValue || err == .attributeUnsupported || err == .invalidUIElement {
                return TextFocus(editable: false)
            } else {
                return nil
            }
        }
        AXUIElementSetMessagingTimeout(target, axTimeout)
        let attrs = [kAXRoleAttribute, kAXSubroleAttribute, kAXEnabledAttribute, "AXEditable"]
        var array: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(target, attrs as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &array)
        guard err == .success, let list = array as [AnyObject]? else {
            return err == .invalidUIElement ? TextFocus(editable: false) : nil
        }
        func extract(_ index: Int) -> CFTypeRef? {
            guard index < list.count else { return nil }
            let v = list[index] as CFTypeRef
            if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError { return nil }
            if CFGetTypeID(v) == CFNullGetTypeID() { return nil }
            return v
        }
        let role = extract(0) as? String
        let subrole = extract(1) as? String
        let enabled = extract(2) as? Bool
        let editableAttr = extract(3) as? Bool
        var valueSettable: Bool?
        if editableAttr == nil && TextFocusRule.needsValueSettable(role: role, subrole: subrole) {
            var settable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(target, kAXValueAttribute as CFString, &settable) == .success {
                valueSettable = settable.boolValue
            }
        }
        return TextFocusRule.classify(TextFocusRule.Element(
            role: role,
            subrole: subrole,
            enabled: enabled,
            editableAttribute: editableAttr,
            valueSettable: valueSettable
        ))
    }
}
