import AppKit
import Foundation

@MainActor
public enum VoiceInputApplication {
    private static var delegate: AppDelegate?

    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let historyStore = HistoryStore()
    private let hotkeyManager = HotkeyManager()
    private let recorder = AudioRecorderService()
    private let overlay = OverlayWindowController()

    private var settingsWindow: SettingsWindowController?
    private var statusItem: NSStatusItem?
    private var currentAudioURL: URL?
    private var processingTask: Task<Void, Never>?
    private var state: CaptureState = .idle {
        didSet {
            overlay.update(state)
            updateStatusMenu()
            updateCancelHotkey()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsWindow = SettingsWindowController(settingsStore: settingsStore, historyStore: historyStore)
        setupMenu()
        hotkeyManager.onToggle = { [weak self] in self?.toggleRecording() }
        hotkeyManager.onCancel = { [weak self] in self?.cancelCapture() }
        hotkeyManager.start()
        _ = PasteboardService.requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "语音输入")
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        let menu = NSMenu()
        switch state {
        case .recording:
            menu.addItem(NSMenuItem(title: "停止录音", action: #selector(stopRecordingFromMenu), keyEquivalent: ""))
        case .processing:
            let item = NSMenuItem(title: "整理中...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        default:
            menu.addItem(NSMenuItem(title: "开始录音", action: #selector(startRecordingFromMenu), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let permissions = PermissionService.snapshot()
        let permissionItem = NSMenuItem(
            title: "权限：麦克风 \(permissions.microphone)，辅助功能 \(permissions.accessibility)",
            action: nil,
            keyEquivalent: ""
        )
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)
        menu.addItem(NSMenuItem(title: "打开隐私设置...", action: #selector(openPrivacySettings), keyEquivalent: ""))
        menu.addItem(.separator())
        if let latest = historyStore.items.first {
            let copy = NSMenuItem(title: "复制最近一次结果", action: #selector(copyLatestResult), keyEquivalent: "")
            copy.isEnabled = !latest.refinedText.isEmpty
            menu.addItem(copy)
        } else {
            let empty = NSMenuItem(title: "暂无历史记录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func toggleRecording() {
        switch state {
        case .idle, .done, .failed:
            startRecording()
        case .recording:
            stopRecording()
        case .processing:
            break
        }
    }

    private func startRecording() {
        Task { @MainActor in
            let granted = await recorder.requestPermission()
            guard granted else {
                state = .failed("请开启麦克风权限")
                return
            }
            do {
                currentAudioURL = try recorder.start()
                recorder.onLevelChange = { [weak self] level in
                    self?.overlay.updateAudioLevel(level)
                }
                state = .recording(startedAt: Date())
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        recorder.stop()
        overlay.updateAudioLevel(0)
        guard let audioURL = currentAudioURL else {
            state = .failed("没有找到录音文件")
            return
        }
        currentAudioURL = nil
        state = .processing

        processingTask = Task { @MainActor in
            defer { processingTask = nil }
            do {
                let stt = TranscriptionClient(
                    baseURL: settingsStore.settings.baseURL,
                    model: settingsStore.settings.sttModel,
                    apiKey: KeychainStore.readAPIKey(),
                    timeout: settingsStore.settings.timeoutSeconds
                )
                let rawText = try await stt.transcribe(audioURL: audioURL)
                if Task.isCancelled { try? FileManager.default.removeItem(at: audioURL); return }
                do {
                    let chat = ChatRefinementClient(
                        provider: .siliconflow,
                        baseURL: settingsStore.settings.baseURL,
                        model: settingsStore.settings.textModel,
                        apiKey: KeychainStore.readAPIKey(),
                        timeout: settingsStore.settings.timeoutSeconds
                    )
                    let refinedText = try await chat.refine(rawText: rawText)
                    if Task.isCancelled { try? FileManager.default.removeItem(at: audioURL); return }
                    historyStore.add(rawText: rawText, refinedText: refinedText, limit: settingsStore.settings.historyLimit)
                    deliver(refinedText, usedRawFallback: false)
                } catch {
                    if Task.isCancelled { try? FileManager.default.removeItem(at: audioURL); return }
                    historyStore.add(rawText: rawText, refinedText: rawText, limit: settingsStore.settings.historyLimit)
                    deliver(rawText, usedRawFallback: true)
                }
                try? FileManager.default.removeItem(at: audioURL)
            } catch {
                try? FileManager.default.removeItem(at: audioURL)
                if Task.isCancelled || error is CancellationError { return }
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func cancelCapture() {
        switch state {
        case .recording:
            recorder.stop()
            overlay.updateAudioLevel(0)
            if let url = currentAudioURL {
                try? FileManager.default.removeItem(at: url)
            }
            currentAudioURL = nil
            state = .idle
        case .processing:
            processingTask?.cancel()
            processingTask = nil
            state = .idle
        default:
            break
        }
    }

    private func updateCancelHotkey() {
        switch state {
        case .recording, .processing:
            hotkeyManager.startCancelHotkey()
        default:
            hotkeyManager.stopCancelHotkey()
        }
    }

    private func deliver(_ text: String, usedRawFallback: Bool) {
        let settings = settingsStore.settings

        // Decide whether to auto-paste. Unknown focus (nil) still pastes, so opaque web/Electron
        // inputs keep working; only a positively non-editable focus skips the paste.
        let hasAccess = settings.autoPaste && PasteboardService.requestAccessibilityIfNeeded()
        let willPaste = hasAccess && (PasteboardService.focusedElementPasteDecision() ?? true)

        guard willPaste else {
            if settings.keepClipboardCopy || settings.autoPaste {
                PasteboardService.copy(text)
            }
            state = .done(DeliveryMessage.message(didPaste: false, usedRawFallback: usedRawFallback))
            return
        }

        // Snapshot the user's clipboard so we can restore it after pasting, unless they asked to
        // keep the result on the clipboard.
        let previousClipboard = settings.keepClipboardCopy ? nil : PasteboardService.currentString()
        PasteboardService.copy(text)

        Task { @MainActor in
            // Release the toggle's Option modifier and let the pasteboard settle before injecting
            // Cmd+V, otherwise the paste can merge with held modifiers or fire before the copy lands.
            await PasteboardService.waitForModifiersCleared()
            try? await Task.sleep(nanoseconds: 60_000_000)
            PasteboardService.paste()

            if let previousClipboard {
                // Give the target app time to consume the paste before restoring the old clipboard.
                try? await Task.sleep(nanoseconds: 250_000_000)
                PasteboardService.copy(previousClipboard)
            }

            state = .done(DeliveryMessage.message(didPaste: true, usedRawFallback: usedRawFallback))
        }
    }

    @objc private func startRecordingFromMenu() {
        startRecording()
    }

    @objc private func stopRecordingFromMenu() {
        stopRecording()
    }

    @objc private func copyLatestResult() {
        guard let latest = historyStore.items.first else { return }
        PasteboardService.copy(latest.refinedText)
        state = .done("已复制到剪贴板")
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    @objc private func openPrivacySettings() {
        PermissionService.openPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
