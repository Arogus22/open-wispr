import AppKit
import Foundation

/// Borderless `NSPanel` that captures the next keystroke or modifier-only key
/// from the user, parses it via `KeyCodes.parse`, and persists it as the new
/// recording hotkey via `Config.save` + `onSaved`.
///
/// Phase 2 / U6.
///
/// Critical for `.accessory` apps (this app sets `setActivationPolicy(.accessory)`
/// in `main.swift`): the panel MUST use `.nonactivatingPanel` style mask AND
/// override `canBecomeKey` to true AND have `NSApp.activate(ignoringOtherApps:)`
/// called before `makeKeyAndOrderFront`, otherwise the local event monitor
/// never fires (key events only deliver to the key window).
///
/// Cancellation paths: Esc, Cmd+Q, click-outside (resignKey), 5s no-input
/// watchdog. Resume of the global hotkey (`AppDelegate.resumeHotkey`) is wired
/// to BOTH `windowWillClose` AND `windowDidResignKey` notifications — defends
/// against the "panel loses key without closing" path.
public class HotkeyCaptureWindow: NSObject {
    private weak var appDelegate: AppDelegate?
    private let onSaved: (Config) -> Void

    private var panel: HotkeyCapturePanel?
    private var localMonitor: Any?
    private var watchdog: Timer?
    private var willCloseObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?
    private var promptLabel: NSTextField?
    private var previewLabel: NSTextField?

    // State machine for capture detection.
    private var previousModifierFlags: NSEvent.ModifierFlags = []
    private var modifierHoldKeyCode: UInt16?
    private var keyDownSinceHold: Bool = false
    private var didCommit: Bool = false
    private var didCleanup: Bool = false

    /// Modifier-only keys (matches `HotkeyManager.isModifierOnlyKey`).
    private static let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    public init(appDelegate: AppDelegate, onSaved: @escaping (Config) -> Void) {
        self.appDelegate = appDelegate
        self.onSaved = onSaved
        super.init()
    }

    public func show() {
        let panelRect = NSRect(x: 0, y: 0, width: 360, height: 140)
        let panel = HotkeyCapturePanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear

        // Center on the active screen.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panelRect.width / 2,
                y: frame.midY - panelRect.height / 2
            ))
        }

        // Content view with a rounded background.
        let contentView = NSView(frame: panelRect)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.layer?.cornerRadius = 12
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor

        let prompt = NSTextField(labelWithString: "Press a key…")
        prompt.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        prompt.alignment = .center
        prompt.frame = NSRect(x: 20, y: 90, width: 320, height: 22)
        contentView.addSubview(prompt)

        let preview = NSTextField(labelWithString: " ")
        preview.font = NSFont.boldSystemFont(ofSize: 28)
        preview.alignment = .center
        preview.frame = NSRect(x: 20, y: 44, width: 320, height: 36)
        contentView.addSubview(preview)

        let hint = NSTextField(labelWithString: "Esc, ⌘Q, or click outside to cancel")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.frame = NSRect(x: 20, y: 14, width: 320, height: 16)
        contentView.addSubview(hint)

        panel.contentView = contentView

        self.panel = panel
        self.promptLabel = prompt
        self.previewLabel = preview

        // Pause the global hotkey before showing — so pressing the current
        // recording hotkey while the panel is up rebinds it instead of
        // triggering a recording.
        appDelegate?.pauseHotkey()

        // Mandatory for .accessory apps: activate ourselves so the panel
        // can become key and the local monitor receives events.
        NSApp.activate(ignoringOtherApps: true)

        // Local event monitor — return nil to consume the event so it does
        // not propagate to other parts of the app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
            return nil
        }

        // Resume on close OR resignKey — covers the "panel loses key but
        // doesn't close" path (e.g., user clicks the menu bar icon).
        let nc = NotificationCenter.default
        willCloseObserver = nc.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.cleanup()
        }
        resignKeyObserver = nc.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.cancelDueToResignKey()
        }

        startWatchdog()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Event handling

    private func handleEvent(_ event: NSEvent) {
        // Reset watchdog on every input.
        startWatchdog()

        // Cmd+Q intercept (keyCode 12 = "q") — cancel without quitting.
        if event.type == .keyDown,
           event.keyCode == 12,
           event.modifierFlags.contains(.command) {
            close()
            return
        }
        // Escape (keyCode 53) — cancel.
        if event.type == .keyDown, event.keyCode == 53 {
            close()
            return
        }

        if event.type == .flagsChanged {
            handleFlagsChanged(event)
            return
        }

        if event.type == .keyDown {
            keyDownSinceHold = true
            handleKeyDown(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let prevMask = previousModifierFlags
        let nowMask = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        previousModifierFlags = nowMask

        let isDownEdge = nowMask.rawValue & ~prevMask.rawValue != 0  // a flag became set
        let isUpEdge = prevMask.rawValue & ~nowMask.rawValue != 0    // a flag became unset

        let kc = event.keyCode
        let isModifierOnly = HotkeyCaptureWindow.modifierOnlyCodes.contains(kc)

        if isDownEdge {
            updatePreview(modifiers: nowMask, suffix: nil)
            if isModifierOnly {
                modifierHoldKeyCode = kc
                keyDownSinceHold = false
            }
        } else if isUpEdge {
            updatePreview(modifiers: nowMask, suffix: nil)
            // Modifier-only commit: down edge of this same keyCode happened
            // earlier, no keyDown landed in between, and now the user
            // released it. That signals "I want this single modifier as
            // my hotkey".
            if let held = modifierHoldKeyCode,
               held == kc,
               !keyDownSinceHold,
               let keyName = KeyCodes.codeToName[kc] {
                commitCapture(keyName: keyName, modifiers: [])
                return
            }
            modifierHoldKeyCode = nil
        } else {
            // No bit transition — could be a Caps Lock toggle (which behaves
            // oddly because the flag persists). Update preview and treat
            // like a down edge for capture-on-release semantics.
            updatePreview(modifiers: nowMask, suffix: nil)
            if isModifierOnly {
                modifierHoldKeyCode = kc
                keyDownSinceHold = false
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        let kc = event.keyCode
        // Modifier-only key arriving via keyDown is unusual — skip and let
        // flagsChanged handle it.
        guard !HotkeyCaptureWindow.modifierOnlyCodes.contains(kc) else { return }
        guard let keyName = KeyCodes.codeToName[kc] else {
            // Unknown key — ignore (keep the panel open for another attempt).
            return
        }
        let mods = modifiersFromFlags(event.modifierFlags)
        commitCapture(keyName: keyName, modifiers: mods)
    }

    private func modifiersFromFlags(_ flags: NSEvent.ModifierFlags) -> [String] {
        // Order matches the standard Mac convention (ctrl < opt < shift < cmd)
        // when joined. KeyCodes.parse is order-insensitive, so this is purely
        // for display consistency in the saved string.
        var mods: [String] = []
        if flags.contains(.control) { mods.append("ctrl") }
        if flags.contains(.option) { mods.append("opt") }
        if flags.contains(.shift) { mods.append("shift") }
        if flags.contains(.command) { mods.append("cmd") }
        return mods
    }

    private func updatePreview(modifiers: NSEvent.ModifierFlags, suffix: String?) {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("⌃") }
        if modifiers.contains(.option) { symbols.append("⌥") }
        if modifiers.contains(.shift) { symbols.append("⇧") }
        if modifiers.contains(.command) { symbols.append("⌘") }
        var text = symbols.joined()
        if let suffix = suffix {
            text += suffix
        }
        previewLabel?.stringValue = text.isEmpty ? " " : text
    }

    private func commitCapture(keyName: String, modifiers: [String]) {
        guard !didCommit else { return }
        let str = (modifiers + [keyName]).joined(separator: "+")
        guard let parsed = KeyCodes.parse(str) else {
            close()
            return
        }
        didCommit = true
        var cfg = Config.load()
        cfg.hotkey = HotkeyConfig(keyCode: parsed.keyCode, modifiers: parsed.modifiers)
        try? cfg.save()
        let savedConfig = cfg
        // Show the captured combo briefly before closing — gives the user
        // visual confirmation. Then close (cleanup fires resumeHotkey via
        // willCloseObserver).
        previewLabel?.stringValue = (modifiers.map(symbolFor) + [keyName.uppercased()]).joined()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onSaved(savedConfig)
            self?.close()
        }
    }

    private func symbolFor(_ modifier: String) -> String {
        switch modifier.lowercased() {
        case "ctrl", "control": return "⌃"
        case "opt", "option", "alt": return "⌥"
        case "shift": return "⇧"
        case "cmd", "command": return "⌘"
        default: return modifier
        }
    }

    // MARK: - Lifecycle

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.close()
        }
    }

    private func cancelDueToResignKey() {
        // Outside click / focus loss → cancel without saving. Cleanup runs
        // via willCloseObserver after close() fires.
        close()
    }

    private func close() {
        guard let panel = panel, panel.isVisible else {
            // Already closing — ensure cleanup fires.
            cleanup()
            return
        }
        panel.close()
        // willCloseObserver runs cleanup synchronously after close.
    }

    private func cleanup() {
        guard !didCleanup else { return }
        didCleanup = true

        watchdog?.invalidate()
        watchdog = nil

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        let nc = NotificationCenter.default
        if let obs = willCloseObserver {
            nc.removeObserver(obs)
            willCloseObserver = nil
        }
        if let obs = resignKeyObserver {
            nc.removeObserver(obs)
            resignKeyObserver = nil
        }

        // Always resume — pauseHotkey was idempotent, resumeHotkey is too.
        appDelegate?.resumeHotkey()
    }
}

/// Subclass needed because `canBecomeKey` defaults to false for
/// borderless+nonactivating panels — and without it being key, the local
/// event monitor never fires.
private class HotkeyCapturePanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}
