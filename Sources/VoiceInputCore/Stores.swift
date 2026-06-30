import Foundation
import Security

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let key = "voiceInput.settings"

    init() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            settings = .defaults
            return
        }
        settings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var items: [HistoryItem] = []

    private let key: String

    public init(storageKey: String = "voiceInput.history") {
        key = storageKey
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data)
        else { return }
        items = decoded
    }

    public func add(rawText: String, refinedText: String, limit: Int) {
        let item = HistoryItem(id: UUID(), createdAt: Date(), rawText: rawText, refinedText: refinedText)
        items.insert(item, at: 0)
        items = Array(items.prefix(max(1, limit)))
        save()
    }

    public func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum KeychainStore {
    private static let service = "cn.local.voiceinput"
    private static let legacyAccount = "siliconflow-api-key"

    private static func account(for provider: LLMProvider) -> String { provider.keychainAccount }

    // Provider-keyed API
    static func readAPIKey(for provider: LLMProvider) -> String {
        migrateLegacyIfNeeded()
        return read(account: account(for: provider))
    }

    static func saveAPIKey(_ value: String, for provider: LLMProvider) {
        if value.isEmpty {
            delete(account: account(for: provider))
            return
        }
        write(value, account: account(for: provider))
    }

    static func deleteAPIKey(for provider: LLMProvider) {
        delete(account: account(for: provider))
    }

    private static func migrateLegacyIfNeeded() {
        let target = account(for: .siliconflow)
        guard read(account: target).isEmpty else { return }
        let legacy = read(account: legacyAccount)
        guard !legacy.isEmpty else { return }
        write(legacy, account: target)
    }

    private static func read(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
