import SwiftUI

/// Mirrors the .env credentials + data-feed prompt in cmf_spy.py / cmf_trader.py, plus the ACCOUNT_ID safety check.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Market data plan") {
                    Picker("Data feed", selection: $settings.dataFeed) {
                        ForEach(DataFeed.allCases) { feed in
                            Text(feed.label).tag(feed)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.dataFeed == .iex
                         ? "Free plan: reuses your trading API keys for market data."
                         : "Paid plan: requires its own market-data API keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Alpaca trading API (paper)") {
                    SecureField("Trade API key", text: $settings.tradeKey)
                    SecureField("Trade API secret", text: $settings.tradeSecret)
                }

                if settings.dataFeed == .sip {
                    Section("Alpaca market data API") {
                        SecureField("Data API key", text: $settings.dataKey)
                        SecureField("Data API secret", text: $settings.dataSecret)
                    }
                }

                Section("Safety check") {
                    TextField("Expected paper account number", text: $settings.accountId)
                    Text("Trading/monitoring refuses to run if the keys resolve to a different account.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Trade size") {
                    Stepper("Shares to trade: \(settings.qty)", value: $settings.qty, in: 1...10_000)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
