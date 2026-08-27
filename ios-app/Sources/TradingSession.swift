import Foundation

/// Eastern-time trading session helpers, mirroring get_session_start/get_session_end/seconds_until_next_minute in cmf_spy.py.
enum TradingSession {
    static let eastern = TimeZone(identifier: "America/New_York")!

    static func start(now: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .hour, value: 4, to: startOfDay)!
    }

    static func end(start: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let startOfDay = calendar.startOfDay(for: start)
        return calendar.date(byAdding: .hour, value: 20, to: startOfDay)!
    }

    static func isMarketOpen(now: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let startOfDay = calendar.startOfDay(for: now)
        let open = calendar.date(byAdding: .init(hour: 9, minute: 30), to: startOfDay)!
        let close = calendar.date(byAdding: .hour, value: 16, to: startOfDay)!
        return now >= open && now < close
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = eastern
        return formatter
    }()
}
