import SwiftUI

struct TradeLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sessionCMF: Double
    let sessionSignal: TradingSignal
    let currentQty: Int
    let targetQty: Int
    let action: String
}

/// Ports cmf_trader.py's main loop: recompute session CMF, diff target vs. current position, submit delta orders.
@MainActor
final class TraderViewModel: ObservableObject {
    @Published var log: [TradeLogEntry] = []
    @Published var errorMessage: String?
    @Published var isRunning = false
    @Published var verifiedAccount: String?

    private var task: Task<Void, Never>?
    let symbol = "SPY"

    func classifyTargetQty(signal: TradingSignal, qty: Int) -> Int {
        switch signal {
        case .bullish: return qty
        case .bearish: return -qty
        case .neutral: return 0
        }
    }

    func start(settings: AppSettings) {
        guard !isRunning else { return }
        guard settings.hasTradeCredentials, settings.hasDataCredentials else {
            errorMessage = "Enter API credentials in Settings first."
            return
        }
        guard !settings.accountId.isEmpty else {
            errorMessage = "Enter the expected paper account number in Settings first."
            return
        }

        isRunning = true
        errorMessage = nil
        let client = AlpacaClient(settings: settings)
        let qty = settings.qty
        let expectedAccountId = settings.accountId

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await client.getAccount()
                guard account.accountNumber == expectedAccountId else {
                    await MainActor.run {
                        self.errorMessage = "Trading keys resolve to account \(account.accountNumber), expected \(expectedAccountId). Refusing to trade."
                        self.isRunning = false
                    }
                    return
                }
                await MainActor.run { self.verifiedAccount = account.accountNumber }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isRunning = false
                }
                return
            }

            let start = TradingSession.start()
            let sessionEnd = TradingSession.end(start: start)

            while !Task.isCancelled && Date() < sessionEnd {
                let now = Date()
                do {
                    let bars = try await client.fetchBars(symbol: symbol, start: start, end: now)
                    if bars.isEmpty {
                        try? await Task.sleep(nanoseconds: 60_000_000_000)
                        continue
                    }
                    let computed = CMFCalculator.compute(bars: bars)
                    let targetQty = classifyTargetQty(signal: computed.sessionSignal, qty: qty)
                    let currentQty = await client.getCurrentQty(symbol: symbol)
                    let delta = targetQty - currentQty

                    var action = "hold"
                    if delta != 0 && TradingSession.isMarketOpen(now: now) {
                        try await client.submitDeltaOrder(symbol: symbol, delta: delta)
                        action = "\(delta > 0 ? "buy" : "sell") \(abs(delta))"
                    } else if delta != 0 {
                        action = "signal changed, market closed - not submitted"
                    }

                    let entry = TradeLogEntry(
                        timestamp: now, sessionCMF: computed.sessionCMF, sessionSignal: computed.sessionSignal,
                        currentQty: currentQty, targetQty: targetQty, action: action
                    )
                    await MainActor.run {
                        self.log.insert(entry, at: 0)
                        self.errorMessage = nil
                    }
                } catch {
                    await MainActor.run { self.errorMessage = error.localizedDescription }
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }

            let finalQty = await client.getCurrentQty(symbol: symbol)
            if finalQty != 0 {
                try? await client.submitDeltaOrder(symbol: symbol, delta: -finalQty)
            }
            await MainActor.run { self.isRunning = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }
}

struct TraderView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = TraderViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if let account = viewModel.verifiedAccount {
                    Section { LabeledContent("Verified account", value: account) }
                }
                Section("Log") {
                    ForEach(viewModel.log) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(TradingSession.timeFormatter.string(from: entry.timestamp)) ET  ·  \(entry.sessionSignal.label)")
                                .font(.subheadline).bold()
                            Text("CMF=\(String(format: "%.4f", entry.sessionCMF))  current=\(entry.currentQty) target=\(entry.targetQty)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.action).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("SPY Trader")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(viewModel.isRunning ? "Stop" : "Start") {
                        viewModel.isRunning ? viewModel.stop() : viewModel.start(settings: settings)
                    }
                }
            }
        }
    }
}
