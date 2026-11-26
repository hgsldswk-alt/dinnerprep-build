import Foundation
import Security

actor LocalStorage {
    private let isolated: Bool
    private let reset: Bool

    init(isolated: Bool, reset: Bool) {
        self.isolated = isolated
        self.reset = reset
    }

    private func file() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("DinnerPrep", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory.appendingPathComponent(isolated ? "dinner-ui.json" : "dinner.json")
    }

    func load() throws -> DinnerData? {
        let url = try file()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if reset {
            try FileManager.default.removeItem(at: url)
            return nil
        }
        return try JSONDecoder().decode(DinnerData.self, from: Data(contentsOf: url))
    }

    func save(_ data: DinnerData) throws {
        try JSONEncoder().encode(data).write(to: file(), options: .atomic)
    }
}

actor EntitlementVault {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Launch.appID,
        kSecAttrAccount as String: "entitlement-v1",
        kSecAttrSynchronizable as String: false
    ]

    struct KeychainError: Error { let status: OSStatus }

    func load() throws -> Entitlement? {
        var request = query
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw KeychainError(status: status) }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    func save(_ entitlement: Entitlement) throws {
        let data = try JSONEncoder().encode(entitlement)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(entry as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
