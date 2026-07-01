import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settingsStore: SettingsStore
    private let historyStore: HistoryStore

    init(settingsStore: SettingsStore, historyStore: HistoryStore) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(settingsStore: settingsStore, historyStore: historyStore)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "语音输入设置"
        // We keep a strong reference in `self.window`; without this, AppKit's default
        // release-on-close over-releases the window and reopening crashes (EXC_BAD_ACCESS).
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var historyStore: HistoryStore
    @State private var sttApiKey = KeychainStore.readAPIKey(for: .siliconflow)
    @State private var textApiKey = ""
    @State private var savedMessage = ""
    @State private var apiTestMessage = ""
    @State private var apiTestSucceeded: Bool?
    @State private var isTestingAPI = false
    @State private var permissionSnapshot = PermissionService.snapshot()
    @State private var launchAtLogin = LoginItemService.isEnabled()
    @State private var launchAtLoginMessage = ""

    var body: some View {
        Form {
            Section("权限") {
                LabeledContent("麦克风", value: permissionSnapshot.microphone)
                LabeledContent("辅助功能", value: permissionSnapshot.accessibility)
                LabeledContent("输入监控（可选）", value: permissionSnapshot.inputMonitoring)
                Text("麦克风、辅助功能为必需权限。输入监控通常不需要开启，仅当 Option+1 全局快捷键无效时再尝试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("刷新权限状态") {
                        permissionSnapshot = PermissionService.snapshot()
                    }
                    Button("打开隐私设置") {
                        PermissionService.openPrivacySettings()
                    }
                }
            }

            Section("语音转文字") {
                LabeledContent("服务商", value: LLMProvider.siliconflow.displayName)
                TextField("Base URL", text: $settingsStore.settings.sttConfig.baseURL)
                TextField("语音转文字模型", text: $settingsStore.settings.sttConfig.model)
                HStack {
                    SecureField("硅基流动 API Key", text: $sttApiKey)
                    Button("粘贴") { sttApiKey = pasteFromClipboard() }
                    Button("清空") {
                        sttApiKey = ""
                        KeychainStore.deleteAPIKey(for: .siliconflow)
                        savedMessage = "已清空硅基流动 Key"
                    }
                }
                Button("保存硅基流动 Key") {
                    KeychainStore.saveAPIKey(sttApiKey, for: .siliconflow)
                    savedMessage = "已保存"
                }
            }

            Section("文本润色") {
                Picker("服务商", selection: $settingsStore.settings.textConfig.provider) {
                    ForEach(LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settingsStore.settings.textConfig.provider) { newValue in
                    settingsStore.settings.textConfig.baseURL = newValue.defaultBaseURL
                    settingsStore.settings.textConfig.model = newValue.defaultTextModel
                    textApiKey = KeychainStore.readAPIKey(for: newValue)
                }
                TextField("Base URL", text: $settingsStore.settings.textConfig.baseURL)
                TextField("文本整理模型", text: $settingsStore.settings.textConfig.model)

                if settingsStore.settings.textConfig.provider != .siliconflow {
                    HStack {
                        SecureField("\(settingsStore.settings.textConfig.provider.displayName) API Key", text: $textApiKey)
                        Button("粘贴") { textApiKey = pasteFromClipboard() }
                        Button("清空") {
                            textApiKey = ""
                            KeychainStore.deleteAPIKey(for: settingsStore.settings.textConfig.provider)
                            savedMessage = "已清空"
                        }
                    }
                    Button("保存 \(settingsStore.settings.textConfig.provider.displayName) Key") {
                        KeychainStore.saveAPIKey(textApiKey, for: settingsStore.settings.textConfig.provider)
                        savedMessage = "已保存"
                    }
                } else {
                    Text("硅基流动文本润色复用上方的硅基流动 API Key。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(isTestingAPI ? "测试中..." : "测试文本整理模型") {
                    testTextModel()
                }
                .disabled(isTestingAPI)
                if !savedMessage.isEmpty {
                    Text(savedMessage).foregroundStyle(.secondary)
                }
                if !apiTestMessage.isEmpty {
                    Text(apiTestMessage)
                        .foregroundStyle(apiTestSucceeded == true ? .green : .red)
                }
            }

            Section("输入") {
                Toggle("处理完成后自动粘贴", isOn: $settingsStore.settings.autoPaste)
                Toggle("始终复制到剪贴板", isOn: $settingsStore.settings.keepClipboardCopy)
                Text("快捷键：Option+1。Fn 会和 macOS 输入法切换冲突，因此不再作为触发键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("开机自启", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if !launchAtLoginMessage.isEmpty {
                    Text(launchAtLoginMessage).foregroundStyle(.secondary)
                }
                Stepper("历史记录：\(settingsStore.settings.historyLimit) 条", value: $settingsStore.settings.historyLimit, in: 1...50)
                Stepper(
                    "API 超时：\(Int(settingsStore.settings.timeoutSeconds)) 秒",
                    value: $settingsStore.settings.timeoutSeconds,
                    in: 10...120,
                    step: 5
                )
                Stepper(
                    "短于 \(settingsStore.settings.refineMinLength) 字直接发送原文（0 = 始终润色）",
                    value: $settingsStore.settings.refineMinLength,
                    in: 0...50
                )
            }

            Section("历史") {
                if historyStore.items.isEmpty {
                    Text("暂无历史记录").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(historyStore.items) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.createdAt, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(item.refinedText)
                                            .lineLimit(3)
                                    }
                                    Spacer()
                                    Button("复制") {
                                        PasteboardService.copy(item.refinedText)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
                Button("清空历史", role: .destructive) {
                    historyStore.clear()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 560, height: 520)
        .onAppear {
            textApiKey = KeychainStore.readAPIKey(for: settingsStore.settings.textConfig.provider)
        }
    }

    /// The API key for the currently selected text provider. When that provider is siliconflow
    /// it is the same Keychain entry as the STT key, so read it from `sttApiKey`.
    private var currentTextKey: String {
        settingsStore.settings.textConfig.provider == .siliconflow ? sttApiKey : textApiKey
    }

    private func testTextModel() {
        let textConfig = settingsStore.settings.textConfig
        let key = currentTextKey
        KeychainStore.saveAPIKey(key, for: textConfig.provider)
        savedMessage = "已保存"
        apiTestMessage = ""
        apiTestSucceeded = nil
        isTestingAPI = true

        Task {
            do {
                let client = ChatRefinementClient(
                    provider: textConfig.provider,
                    baseURL: textConfig.baseURL,
                    model: textConfig.model,
                    apiKey: key,
                    timeout: settingsStore.settings.timeoutSeconds
                )
                let result = try await client.refine(rawText: "嗯那个我想测试一下这个语音输入软件然后看看它能不能把口水词去掉")
                await MainActor.run {
                    let ok = !result.isEmpty
                    apiTestSucceeded = ok
                    apiTestMessage = ok ? "可用：文本整理模型返回正常" : "测试失败：返回为空"
                    isTestingAPI = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    apiTestSucceeded = false
                    apiTestMessage = "测试失败：\(message)"
                    isTestingAPI = false
                }
            }
        }
    }

    private func pasteFromClipboard() -> String {
        let text = (NSPasteboard.general.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        savedMessage = text.isEmpty ? "剪贴板没有文本" : "已从剪贴板填入"
        return text
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            guard let executablePath = Bundle.main.executablePath else {
                launchAtLoginMessage = "无法定位当前应用"
                launchAtLogin = LoginItemService.isEnabled()
                return
            }
            try LoginItemService.setEnabled(enabled, executablePath: executablePath)
            launchAtLogin = enabled
            launchAtLoginMessage = enabled ? "已开启开机自启" : "已关闭开机自启"
        } catch {
            launchAtLogin = LoginItemService.isEnabled()
            launchAtLoginMessage = "设置失败：\(error.localizedDescription)"
        }
    }
}
