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
    @State private var apiKey = KeychainStore.readAPIKey()
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

            Section("API") {
                TextField("Base URL", text: $settingsStore.settings.baseURL)
                HStack {
                    SecureField("API Key", text: $apiKey)
                    Button("粘贴") {
                        pasteAPIKey()
                    }
                    Button("清空") {
                        apiKey = ""
                        KeychainStore.deleteAPIKey()
                        savedMessage = "已清空"
                    }
                }
                TextField("语音转文字模型", text: $settingsStore.settings.sttModel)
                TextField("文本整理模型", text: $settingsStore.settings.textModel)
                Button("保存 API Key") {
                    KeychainStore.saveAPIKey(apiKey)
                    savedMessage = "已保存"
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
    }

    private func testTextModel() {
        KeychainStore.saveAPIKey(apiKey)
        savedMessage = "已保存"
        apiTestMessage = ""
        apiTestSucceeded = nil
        isTestingAPI = true

        Task {
            do {
                let client = ChatRefinementClient(
                    provider: .siliconflow,
                    baseURL: settingsStore.settings.baseURL,
                    model: settingsStore.settings.textModel,
                    apiKey: apiKey,
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

    private func pasteAPIKey() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        apiKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
        savedMessage = apiKey.isEmpty ? "剪贴板没有文本" : "已从剪贴板填入"
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
