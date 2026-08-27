import SwiftUI

/// Ports cmf_spy.py's polling loop: fetch today's session bars every minute, compute CMF, show the signal.
@MainActor
final class SignalViewModel: ObservableObject {
    @Published var result: CMFResult?
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isRunning = false

    private var task: Task<Void, Never>?
    let symbol = "SPY"

    func start(settings: AppSettings) {
        guard !isRunning else { return }
        guard settings.hasDataCredentials else {
            errorMessage = "Enter API credentials in Settings first."
            return
        }
        isRunning = true
        errorMessage = nil
        let client = AlpacaClient(settings: settings)
        task = Task { [weak self] in
            guard let self else { return }
            let start = TradingSession.start()
            let sessionEnd = TradingSession.end(start: start)
            while !Task.isCancelled && Date() < sessionEnd {
                do {
                    let bars = try await client.fetchBars(symbol: symbol, start: start, end: Date())
                    let computed = CMFCalculator.compute(bars: bars)
                    await MainActor.run {
                        self.result = computed
                        self.lastUpdated = Date()
                        self.errorMessage = nil
                    }
                } catch {
                    await MainActor.run { self.errorMessage = error.localizedDescription }
                }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
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

struct SignalView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var viewModel = SignalViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if let result = viewModel.result {
                    Section("Session signal") {
                        signalRow(title: "Session", signal: result.sessionSignal, value: result.sessionCMF)
                        if let latestCMF = result.latestCMF {
                            signalRow(title: "Latest (\(CMFCalculator.period)-min)", signal: result.latestSignal, value: latestCMF)
                        }
                        LabeledContent("Bars loaded", value: "\(result.barCount)")
                        if let bar = result.latestBar {
                            LabeledContent("Last close", value: String(format: "%.2f", bar.close))
                        }
                    }
                } else {
                    Section {
                        Text("No data yet. Tap Start to begin streaming.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastUpdated = viewModel.lastUpdated {
                    Section {
                        Text("Updated \(TradingSession.timeFormatter.string(from: lastUpdated)) ET")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("SPY Signal")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(viewModel.isRunning ? "Stop" : "Start") {
                        viewModel.isRunning ? viewModel.stop() : viewModel.start(settings: settings)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func signalRow(title: String, signal: TradingSignal, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: value.isNaN ? "n/a" : String(format: "%.4f", value))
            Text(signal.label)
                .font(.headline)
                .foregroundStyle(color(for: signal))
            Text(signal.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func color(for signal: TradingSignal) -> Color {
        switch signal {
        case .bullish: return .green
        case .bearish: return .red
        case .neutral: return .secondary
        }
    }
}
