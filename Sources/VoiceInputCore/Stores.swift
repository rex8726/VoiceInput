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
    private static let account = "siliconflow-api-key"

    static func readAPIKey() -> String {
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

    static func saveAPIKey(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
