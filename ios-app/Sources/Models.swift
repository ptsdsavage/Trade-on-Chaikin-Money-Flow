import Foundation

/// One minute bar as returned by Alpaca's market data API.
struct Bar: Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    /// Chaikin money-flow multiplier for this single bar, filled in by `CMFCalculator`.
    var mfMultiplier: Double = 0
    var mfVolume: Double = 0
}

enum TradingSignal: Equatable {
    case bullish
    case bearish
    case neutral(insufficientData: Bool)

    var label: String {
        switch self {
        case .bullish: return "BULLISH"
        case .bearish: return "BEARISH"
        case .neutral(let insufficient): return insufficient ? "NEUTRAL (insufficient data)" : "NEUTRAL"
        }
    }

    var description: String {
        switch self {
        case .bullish: return "buying pressure, expect upward movement"
        case .bearish: return "selling pressure, expect downward movement"
        case .neutral(let insufficient): return insufficient ? "not enough bars yet" : "no strong directional pressure"
        }
    }
}

/// Result of computing CMF over a session of bars.
struct CMFResult {
    let latestBar: Bar?
    let latestCMF: Double?
    let latestSignal: TradingSignal
    let sessionCMF: Double
    let sessionSignal: TradingSignal
    let barCount: Int
}
