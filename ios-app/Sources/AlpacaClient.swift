import Foundation

enum AlpacaError: Error, LocalizedError {
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "Alpaca API error \(code): \(body)"
        case .decoding(let message): return "Failed to decode Alpaca response: \(message)"
        }
    }
}

struct AlpacaAccount {
    let accountNumber: String
    let equity: Double
    let lastEquity: Double
}

struct AlpacaPosition {
    let qty: Double
    let avgEntryPrice: Double
    let currentPrice: Double
    let marketValue: Double
    let unrealizedPL: Double
    let unrealizedPLPercent: Double
}

/// Talks to Alpaca's market-data and paper-trading REST APIs. Ports the relevant
/// pieces of cmf_spy.py (fetch_bars) and cmf_trader.py (account/position/order calls).
final class AlpacaClient {
    private let dataKey: String
    private let dataSecret: String
    private let tradeKey: String
    private let tradeSecret: String
    private let feed: DataFeed

    private static let dataBaseURL = URL(string: "https://data.alpaca.markets/v2")!
    private static let tradingBaseURL = URL(string: "https://paper-api.alpaca.markets/v2")!

    init(settings: AppSettings) {
        self.dataKey = settings.effectiveDataKey
        self.dataSecret = settings.effectiveDataSecret
        self.tradeKey = settings.tradeKey
        self.tradeSecret = settings.tradeSecret
        self.feed = settings.dataFeed
    }

    private func dataRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(dataKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(dataSecret, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        return request
    }

    private func tradingRequest(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(tradeKey, forHTTPHeaderField: "APCA-API-KEY-ID")
        request.setValue(tradeSecret, forHTTPHeaderField: "APCA-API-SECRET-KEY")
        return request
    }

    private func run(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AlpacaError.http(-1, "no response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AlpacaError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Market data

    /// Mirrors fetch_bars(): fetches 1-min bars for `symbol` between start and end (inclusive-ish, per Alpaca semantics).
    func fetchBars(symbol: String, start: Date, end: Date) async throws -> [Bar] {
        var components = URLComponents(url: Self.dataBaseURL.appendingPathComponent("stocks/\(symbol)/bars"), resolvingAgainstBaseURL: false)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        components.queryItems = [
            URLQueryItem(name: "timeframe", value: "1Min"),
            URLQueryItem(name: "start", value: formatter.string(from: start)),
            URLQueryItem(name: "end", value: formatter.string(from: end)),
            URLQueryItem(name: "feed", value: feed.rawValue),
            URLQueryItem(name: "limit", value: "10000"),
        ]

        var allBars: [Bar] = []
        var pageToken: String? = nil
        repeat {
            if let pageToken {
                components.queryItems?.removeAll { $0.name == "page_token" }
                components.queryItems?.append(URLQueryItem(name: "page_token", value: pageToken))
            }
            let data = try await run(dataRequest(components.url!))
            let decoded = try decodeBarsResponse(data)
            allBars.append(contentsOf: decoded.bars)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return allBars.sorted { $0.timestamp < $1.timestamp }
    }

    private func decodeBarsResponse(_ data: Data) throws -> (bars: [Bar], nextPageToken: String?) {
        struct RawBar: Decodable {
            let t: String
            let o: Double
            let h: Double
            let l: Double
            let c: Double
            let v: Double
        }
        struct RawResponse: Decodable {
            let bars: [RawBar]?
            let next_page_token: String?
        }
        let decoder = JSONDecoder()
        let raw: RawResponse
        do {
            raw = try decoder.decode(RawResponse.self, from: data)
        } catch {
            throw AlpacaError.decoding(error.localizedDescription)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let bars: [Bar] = (raw.bars ?? []).compactMap { rawBar in
            guard let timestamp = formatter.date(from: rawBar.t) ?? fallbackFormatter.date(from: rawBar.t) else { return nil }
            return Bar(timestamp: timestamp, open: rawBar.o, high: rawBar.h, low: rawBar.l, close: rawBar.c, volume: rawBar.v)
        }
        return (bars, raw.next_page_token)
    }

    // MARK: - Trading

    func getAccount() async throws -> AlpacaAccount {
        struct RawAccount: Decodable {
            let account_number: String
            let equity: String
            let last_equity: String
        }
        let data = try await run(tradingRequest(Self.tradingBaseURL.appendingPathComponent("account")))
        let raw = try JSONDecoder().decode(RawAccount.self, from: data)
        return AlpacaAccount(accountNumber: raw.account_number, equity: Double(raw.equity) ?? 0, lastEquity: Double(raw.last_equity) ?? 0)
    }

    /// Returns 0 if there is no open position, matching get_current_qty()'s except-clause behavior.
    func getCurrentQty(symbol: String) async -> Int {
        struct RawPosition: Decodable { let qty: String }
        let request = tradingRequest(Self.tradingBaseURL.appendingPathComponent("positions/\(symbol)"))
        guard let data = try? await run(request),
              let raw = try? JSONDecoder().decode(RawPosition.self, from: data),
              let qty = Double(raw.qty) else {
            return 0
        }
        return Int(qty)
    }

    func getPositionPnL(symbol: String) async -> AlpacaPosition {
        struct RawPosition: Decodable {
            let qty: String
            let avg_entry_price: String
            let current_price: String
            let market_value: String
            let unrealized_pl: String
            let unrealized_plpc: String
        }
        let request = tradingRequest(Self.tradingBaseURL.appendingPathComponent("positions/\(symbol)"))
        guard let data = try? await run(request), let raw = try? JSONDecoder().decode(RawPosition.self, from: data) else {
            return AlpacaPosition(qty: 0, avgEntryPrice: 0, currentPrice: 0, marketValue: 0, unrealizedPL: 0, unrealizedPLPercent: 0)
        }
        return AlpacaPosition(
            qty: Double(raw.qty) ?? 0,
            avgEntryPrice: Double(raw.avg_entry_price) ?? 0,
            currentPrice: Double(raw.current_price) ?? 0,
            marketValue: Double(raw.market_value) ?? 0,
            unrealizedPL: Double(raw.unrealized_pl) ?? 0,
            unrealizedPLPercent: (Double(raw.unrealized_plpc) ?? 0) * 100.0
        )
    }

    /// Submits a market order for `abs(delta)` shares, buying if positive and selling if negative
    /// (mirrors submit_delta_order in cmf_trader.py).
    func submitDeltaOrder(symbol: String, delta: Int) async throws {
        guard delta != 0 else { return }
        let body: [String: Any] = [
            "symbol": symbol,
            "qty": String(abs(delta)),
            "side": delta > 0 ? "buy" : "sell",
            "type": "market",
            "time_in_force": "day",
        ]
        var request = tradingRequest(Self.tradingBaseURL.appendingPathComponent("orders"), method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await run(request)
    }
}
