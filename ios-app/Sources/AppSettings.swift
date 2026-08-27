import Foundation
import Combine

enum DataFeed: String, CaseIterable, Identifiable {
    case iex, sip
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// User-configurable settings, persisted via UserDefaults (non-secret) and Keychain (secrets).
final class AppSettings: ObservableObject {
    @Published var dataFeed: DataFeed {
        didSet { UserDefaults.standard.set(dataFeed.rawValue, forKey: "dataFeed") }
    }
    @Published var accountId: String {
        didSet { UserDefaults.standard.set(accountId, forKey: "accountId") }
    }
    @Published var qty: Int {
        didSet { UserDefaults.standard.set(qty, forKey: "qty") }
    }

    @Published var dataKey: String = KeychainStore.get(CredentialKey.dataKey) ?? "" {
        didSet { KeychainStore.set(dataKey, for: CredentialKey.dataKey) }
    }
    @Published var dataSecret: String = KeychainStore.get(CredentialKey.dataSecret) ?? "" {
        didSet { KeychainStore.set(dataSecret, for: CredentialKey.dataSecret) }
    }
    @Published var tradeKey: String = KeychainStore.get(CredentialKey.tradeKey) ?? "" {
        didSet { KeychainStore.set(tradeKey, for: CredentialKey.tradeKey) }
    }
    @Published var tradeSecret: String = KeychainStore.get(CredentialKey.tradeSecret) ?? "" {
        didSet { KeychainStore.set(tradeSecret, for: CredentialKey.tradeSecret) }
    }

    init() {
        let storedFeed = UserDefaults.standard.string(forKey: "dataFeed").flatMap(DataFeed.init) ?? .iex
        dataFeed = storedFeed
        accountId = UserDefaults.standard.string(forKey: "accountId") ?? ""
        let storedQty = UserDefaults.standard.integer(forKey: "qty")
        qty = storedQty > 0 ? storedQty : 1
    }

    /// On the free IEX plan the trading keys double as the market-data keys (matches load_credentials in cmf_spy.py).
    var effectiveDataKey: String { dataFeed == .iex ? tradeKey : dataKey }
    var effectiveDataSecret: String { dataFeed == .iex ? tradeSecret : dataSecret }

    var hasTradeCredentials: Bool { !tradeKey.isEmpty && !tradeSecret.isEmpty }
    var hasDataCredentials: Bool { !effectiveDataKey.isEmpty && !effectiveDataSecret.isEmpty }
}
