// CredentialsStore.swift
// Secure storage for Qingping API credentials using the macOS Keychain.
// Credentials are scoped to the app's bundle ID via the service name, which
// ensures they stay accessible under App Sandbox. Includes a one-time migration
// from the legacy service name used in early development.

import Foundation
import Security

enum CredentialsStore {

    /// Must match the app's bundle identifier for Keychain sandbox compatibility.
    private static let service = "com.andreugordillo.QingpingMenuBar"
    private static let legacyService = "com.qingping.menubar"

    // MARK: - Public Interface

    static var appKey: String? {
        get { read(account: "appKey") }
        set {
            if let value = newValue {
                save(account: "appKey", value: value)
            } else {
                delete(account: "appKey")
            }
        }
    }

    static var appSecret: String? {
        get { read(account: "appSecret") }
        set {
            if let value = newValue {
                save(account: "appSecret", value: value)
            } else {
                delete(account: "appSecret")
            }
        }
    }

    static var hasCredentials: Bool {
        appKey != nil && appSecret != nil
    }

    // ESPHome web_server (Local data source). The host isn't secret but lives here so the
    // connection settings stay together.

    static var esphomeHost: String? {
        get { read(account: "esphomeHost") }
        set { store(account: "esphomeHost", value: newValue) }
    }

    static var esphomeUsername: String? {
        get { read(account: "esphomeUsername") }
        set { store(account: "esphomeUsername", value: newValue) }
    }

    static var esphomePassword: String? {
        get { read(account: "esphomePassword") }
        set { store(account: "esphomePassword", value: newValue) }
    }

    /// Migrates credentials from the legacy service name to the current one.
    /// Called once at app launch. No-op if credentials already exist under the new name.
    static func migrateIfNeeded() {
        guard read(account: "appKey") == nil else { return }

        if let oldKey = read(account: "appKey", service: legacyService),
           let oldSecret = read(account: "appSecret", service: legacyService) {
            save(account: "appKey", value: oldKey)
            save(account: "appSecret", value: oldSecret)
            // Clean up old entries
            delete(account: "appKey", service: legacyService)
            delete(account: "appSecret", service: legacyService)
        }
    }

    // MARK: - Keychain Operations

    /// Saves a non-empty value, deletes the entry otherwise.
    private static func store(account: String, value: String?) {
        if let value, !value.isEmpty {
            save(account: account, value: value)
        } else {
            delete(account: account)
        }
    }

    @discardableResult
    private static func save(account: String, value: String, service svc: String = service) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Keychain doesn't support upsert — delete first, then add
        delete(account: account, service: svc)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func read(account: String, service svc: String = service) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service svc: String = service) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
