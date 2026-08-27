import Foundation

/// Ports the Chaikin Money Flow logic from `cmf_spy.py` (compute_cmf / interpret_signal).
enum CMFCalculator {
    static let period = 20 // minutes, matches CMF_PERIOD in cmf_spy.py

    static func interpretSignal(_ cmf: Double?) -> TradingSignal {
        guard let cmf, !cmf.isNaN else { return .neutral(insufficientData: true) }
        if cmf > 0.05 { return .bullish }
        if cmf < -0.05 { return .bearish }
        return .neutral(insufficientData: false)
    }

    /// Computes per-bar money-flow values, the latest rolling-window CMF, and the
    /// session-wide CMF (sum of money flow volume / sum of volume across all bars).
    static func compute(bars: [Bar]) -> CMFResult {
        guard !bars.isEmpty else {
            return CMFResult(latestBar: nil, latestCMF: nil, latestSignal: interpretSignal(nil),
                              sessionCMF: .nan, sessionSignal: interpretSignal(nil), barCount: 0)
        }

        var withFlows = bars
        for i in withFlows.indices {
            let bar = withFlows[i]
            let range = bar.high - bar.low
            let multiplier: Double
            if range == 0 {
                multiplier = 0
            } else {
                multiplier = ((bar.close - bar.low) - (bar.high - bar.close)) / range
            }
            withFlows[i].mfMultiplier = multiplier
            withFlows[i].mfVolume = multiplier * bar.volume
        }

        let windowStart = max(0, withFlows.count - period)
        let window = withFlows[windowStart...]
        let windowVolume = window.reduce(0) { $0 + $1.volume }
        let latestCMF: Double? = windowVolume > 0 ? window.reduce(0) { $0 + $1.mfVolume } / windowVolume : nil

        let totalVolume = withFlows.reduce(0) { $0 + $1.volume }
        let sessionCMF = totalVolume > 0 ? withFlows.reduce(0) { $0 + $1.mfVolume } / totalVolume : Double.nan

        return CMFResult(
            latestBar: withFlows.last,
            latestCMF: latestCMF,
            latestSignal: interpretSignal(latestCMF),
            sessionCMF: sessionCMF,
            sessionSignal: interpretSignal(sessionCMF),
            barCount: withFlows.count
        )
    }
}
