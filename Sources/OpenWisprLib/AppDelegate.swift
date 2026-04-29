import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var transcriber: Transcriber!
    var inserter: TextInserter!
    var config: Config!
    var isPressed = false
    var isReady = false
    public var lastTranscription: String?

    // Focus-lock state (Phase 2 / U3).
    // pendingFocusTarget: snapshot of the frontmost app at record-start, captured
    // by value into the Whisper completion closure so each in-flight transcription
    // owns its own target reference even across overlapping recordings.
    // screenLocked: maintained by DistributedNotificationCenter observers below;
    // when true, focus-lock activation + paste are skipped and the text only
    // lands on the clipboard.
    var pendingFocusTarget: NSRunningApplication?
    var screenLocked: Bool = false
    private var screenLockObservers: [NSObjectProtocol] = []

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        config = Config.load()
        inserter = TextInserter()
        recorder.preferredDeviceID = config.audioInputDeviceID

        // Screen-lock observers (Phase 2 / U3). Public API; replaces the
        // private CGSSession SPI considered earlier. Notifications fire on
        // lock-screen activation and unlock; we maintain screenLocked in
        // memory and read it inside the Whisper completion closure.
        let dnc = DistributedNotificationCenter.default()
        let lockObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenLocked = true
        }
        let unlockObs = dnc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.screenLocked = false
        }
        screenLockObservers = [lockObs, unlockObs]
        if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
            RecordingStore.deleteAllRecordings()
        }
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false

        DispatchQueue.main.async {
            self.statusBar.reprocessHandler = { [weak self] url in
                self?.reprocess(audioURL: url)
            }
            self.statusBar.onConfigChange = { [weak self] newConfig in
                self?.applyConfigChange(newConfig)
            }
            self.statusBar.buildMenu()
        }

        if Transcriber.findWhisperBinary() == nil {
            print("Error: whisper-cpp not found. Install it with: brew install whisper-cpp")
            return
        }

        if Permissions.didUpgrade() {
            print("Accessibility: upgrade detected, resetting permissions...")
            Permissions.resetAccessibility()
            Thread.sleep(forTimeInterval: 1)
        }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async {
                self.statusBar.state = .waitingForPermission
                self.statusBar.buildMenu()
            }
        }

        Permissions.ensureMicrophone()

        if !AXIsProcessTrusted() {
            print("Accessibility: not granted")
            Permissions.openAccessibilitySettings()
            print("Waiting for Accessibility permission...")
            while !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 0.5)
            }
            print("Accessibility: granted")
        } else {
            print("Accessibility: granted")
        }

        if !Transcriber.modelExists(modelSize: config.modelSize) {
            DispatchQueue.main.async {
                self.statusBar.state = .downloading
                self.statusBar.updateDownloadProgress("Downloading \(self.config.modelSize) model...")
            }
            print("Downloading \(config.modelSize) model...")
            try ModelDownloader.download(modelSize: config.modelSize) { [weak self] percent in
                DispatchQueue.main.async {
                    let pct = Int(percent)
                    self?.statusBar.updateDownloadProgress("Downloading \(self?.config.modelSize ?? "") model... \(pct)%", percent: percent)
                }
            }
            DispatchQueue.main.async {
                self.statusBar.updateDownloadProgress(nil)
            }
        }

        if let modelPath = Transcriber.findModel(modelSize: config.modelSize) {
            let modelURL = URL(fileURLWithPath: modelPath)
            if !ModelDownloader.isValidGGMLFile(at: modelURL) {
                let msg = "Model file is corrupted. Re-download with: open-wispr download-model \(config.modelSize)"
                print("Error: \(msg)")
                DispatchQueue.main.async {
                    self.statusBar.state = .error(msg)
                    self.statusBar.buildMenu()
                }
                return
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
        }
    }

    private func startListening() {
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )

        hotkeyManager?.start(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("open-wispr v\(OpenWispr.version)")
        print("Hotkey: \(hotkeyDesc)")
        print("Model: \(config.modelSize)")
        print("Ready.")
    }

    public func reloadConfig() {
        let newConfig = Config.load()
        applyConfigChange(newConfig)
    }

    func applyConfigChange(_ newConfig: Config) {
        guard isReady else { return }
        let wasDownloading: Bool
        if case .downloading = statusBar.state { wasDownloading = true } else { wasDownloading = false }
        config = newConfig
        recorder.preferredDeviceID = config.audioInputDeviceID
        transcriber = Transcriber(modelSize: config.modelSize, language: config.language)
        transcriber.spokenPunctuation = config.spokenPunctuation?.value ?? false
        inserter = TextInserter()

        hotkeyManager?.stop()
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )
        hotkeyManager?.start(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )

        if !wasDownloading && !Transcriber.modelExists(modelSize: config.modelSize) {
            statusBar.state = .downloading
            statusBar.updateDownloadProgress("Downloading \(config.modelSize) model...")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try ModelDownloader.download(modelSize: newConfig.modelSize) { percent in
                        DispatchQueue.main.async {
                            let pct = Int(percent)
                            self?.statusBar.updateDownloadProgress("Downloading \(newConfig.modelSize) model... \(pct)%", percent: percent)
                        }
                    }
                    DispatchQueue.main.async {
                        self?.statusBar.state = .idle
                        self?.statusBar.updateDownloadProgress(nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("Error downloading model: \(error.localizedDescription)")
                        self?.statusBar.state = .idle
                        self?.statusBar.updateDownloadProgress(nil)
                    }
                }
            }
        }

        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("Config updated: lang=\(config.language) model=\(config.modelSize) hotkey=\(hotkeyDesc)")
    }

    private func handleKeyDown() {
        guard isReady else { return }

        let isToggle = config.toggleMode?.value ?? false

        if isToggle {
            if isPressed {
                handleRecordingStop()
            } else {
                handleRecordingStart()
            }
        } else {
            guard !isPressed else { return }
            handleRecordingStart()
        }
    }

    private func handleKeyUp() {
        let isToggle = config.toggleMode?.value ?? false
        if isToggle { return }

        handleRecordingStop()
    }

    private func handleRecordingStart() {
        guard !isPressed else { return }

        // Snapshot the frontmost app for focus-lock (Phase 2 / U3). We filter
        // ourselves out by processIdentifier — robust against
        // Bundle.main.bundleIdentifier being nil for SwiftPM executables run
        // inside a brew-installed .app bundle. The snapshot is later captured
        // by value into the Whisper completion closure inside handleRecordingStop.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost = frontmost,
           frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            pendingFocusTarget = nil
        } else {
            pendingFocusTarget = frontmost
        }

        isPressed = true
        statusBar.state = .recording
        do {
            let outputURL: URL
            if Config.effectiveMaxRecordings(config.maxRecordings) == 0 {
                outputURL = RecordingStore.tempRecordingURL()
            } else {
                outputURL = RecordingStore.newRecordingURL()
            }
            try recorder.startRecording(to: outputURL)
            if config.startSoundEnabled?.value ?? true {
                SoundPlayer.play(config.startSound)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            isPressed = false
            statusBar.state = .idle
        }
    }

    private func handleRecordingStop() {
        guard isPressed else { return }
        isPressed = false

        guard let audioURL = recorder.stopRecording() else {
            statusBar.state = .idle
            return
        }

        if config.endSoundEnabled?.value ?? true {
            SoundPlayer.play(config.endSound)
        }

        statusBar.state = .transcribing

        // Capture focus-lock context for this recording (Phase 2 / U3). These
        // locals are captured by value into the Whisper completion closure
        // below; toggling Focus Lock or Preserve Clipboard mid-Whisper
        // affects the next recording, never the in-flight one.
        let target = self.pendingFocusTarget
        let focusLock = config.focusLockEnabled?.value ?? true
        let preserve = config.preserveClipboard?.value ?? false
        let pasteDelay = TimeInterval(Config.effectivePasteDelayMs(config.pasteDelayMs)) / 1000.0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let maxRecordings = Config.effectiveMaxRecordings(self.config.maxRecordings)
            defer {
                if maxRecordings == 0 {
                    try? FileManager.default.removeItem(at: audioURL)
                }
            }
            do {
                let raw = try self.transcriber.transcribe(audioURL: audioURL)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        self.performFocusLockedPaste(
                            text: text,
                            target: target,
                            focusLock: focusLock,
                            preserve: preserve,
                            pasteDelay: pasteDelay
                        )
                    }
                    self.statusBar.state = .idle
                    self.statusBar.buildMenu()
                }
            } catch {
                if maxRecordings > 0 {
                    RecordingStore.prune(maxCount: maxRecordings)
                }
                DispatchQueue.main.async {
                    print("Error: \(error.localizedDescription)")
                    self.statusBar.state = .error(error.localizedDescription)
                    self.statusBar.buildMenu()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if case .error = self.statusBar.state {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    }
                }
            }
        }
    }

    /// Performs the post-Whisper paste with optional focus-lock activation.
    ///
    /// When focus-lock conditions hold (enabled, target alive, screen unlocked,
    /// no overlapping recording in progress), brings the snapshot target app
    /// to the front, waits `pasteDelay` seconds, verifies the activation took
    /// effect (macOS 14+ may silently no-op), then pastes. Otherwise pastes
    /// directly into whatever is currently frontmost. The clipboard contains
    /// the transcribed text either way, controlled by `preserve`.
    private func performFocusLockedPaste(
        text: String,
        target: NSRunningApplication?,
        focusLock: Bool,
        preserve: Bool,
        pasteDelay: TimeInterval
    ) {
        let canActivate = focusLock
            && target != nil
            && !(target?.isTerminated ?? true)
            && !screenLocked
            && !isPressed   // skip activate if a new recording is already in progress

        if canActivate, let target = target {
            target.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) { [weak self] in
                guard let self = self else { return }
                // Verify activation actually took effect — macOS 14+ may silently no-op
                // under tightened focus-stealing rules.
                let currentFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                if currentFrontmost != target.processIdentifier {
                    print("focus-lock: activation no-op (target pid \(target.processIdentifier), frontmost pid \(currentFrontmost ?? -1))")
                }
                self.inserter.insert(text: text, restoreClipboard: preserve)
            }
        } else {
            inserter.insert(text: text, restoreClipboard: preserve)
        }
    }

    public func reprocess(audioURL: URL) {
        guard case .idle = statusBar.state else { return }

        statusBar.state = .transcribing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let raw = try self.transcriber.transcribe(audioURL: audioURL)
                let text = (self.config.spokenPunctuation?.value ?? false) ? TextPostProcessor.process(raw) : raw
                DispatchQueue.main.async {
                    if !text.isEmpty {
                        self.lastTranscription = text
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.statusBar.state = .copiedToClipboard
                        self.statusBar.buildMenu()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.statusBar.state = .idle
                            self.statusBar.buildMenu()
                        }
                    } else {
                        self.statusBar.state = .idle
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Reprocess error: \(error.localizedDescription)")
                    self.statusBar.state = .idle
                }
            }
        }
    }
}
