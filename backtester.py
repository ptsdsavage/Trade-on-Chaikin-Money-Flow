"""
Backtests the CMF trading strategy from cmf_trader.py against historical SPY
1-minute bars, simulating a fill at each minute's close (no slippage/fees).

Each minute, the session-wide CMF (expanding since session start) is used to
pick a target position exactly like cmf_trader.py's live loop:
    BULLISH -> long QTY shares
    BEARISH -> short QTY shares
    NEUTRAL -> flat
Orders are only "submitted" during regular market hours (9:30-16:00 ET); the
position is flattened at the last bar of the session.

Usage:
    python backtester.py <iex|sip> <START_DATE> [--end-date END_DATE] [--qty N]

Data plan controls the session window pulled per day:
    iex - 9:30 AM-4:00 PM ET (matches the free IEX plan's market-hours-only data)
    sip - 4:00 AM-8:00 PM ET (matches the paid SIP plan's extended-hours data)
"""

import argparse
import os
from datetime import date, datetime, timedelta

import pandas as pd

from alpaca.data.historical import StockHistoricalDataClient

from cmf_spy import (
    EASTERN,
    app_dir,
    compute_cmf,
    fetch_bars,
    get_data_feed_enum,
    interpret_signal,
    load_credentials,
)
from cmf_trader import SYMBOL, classify_target_qty, is_market_open


def parse_date(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def daterange(start: date, end: date):
    day = start
    while day <= end:
        if day.weekday() < 5:  # skip weekends; Alpaca just returns no bars for market holidays
            yield day
        day += timedelta(days=1)


def session_window(feed: str, day: date) -> tuple[datetime, datetime]:
    start_of_day = datetime.combine(day, datetime.min.time(), tzinfo=EASTERN)
    if feed == "iex":
        return start_of_day.replace(hour=9, minute=30), start_of_day.replace(hour=16)
    return start_of_day.replace(hour=4), start_of_day.replace(hour=20)


def simulate_day(df: pd.DataFrame, qty: int) -> tuple[list[dict], dict]:
    df = df.copy()
    df["cum_mfv"] = df["mf_volume"].cumsum()
    df["cum_vol"] = df["volume"].cumsum()
    df["session_cmf"] = df["cum_mfv"] / df["cum_vol"]
    df["session_signal"] = df["session_cmf"].apply(interpret_signal)

    current_qty = 0
    cash = 0.0
    trades = 0
    rows: list[dict] = []

    for ts, row in df.iterrows():
        price = float(row["close"])
        target_qty = classify_target_qty(row["session_signal"], qty)
        delta = target_qty - current_qty

        action = "hold"
        if delta != 0 and is_market_open(ts):
            cash -= delta * price
            current_qty = target_qty
            trades += 1
            action = f"{'buy' if delta > 0 else 'sell'} {abs(delta)}"
        elif delta != 0:
            action = "signal changed, market closed - not simulated"

        rows.append({
            "timestamp": ts,
            "price": price,
            "session_cmf": row["session_cmf"],
            "session_signal": row["session_signal"],
            "current_qty": current_qty,
            "target_qty": target_qty,
            "action": action,
            "cash": cash,
            "equity": cash + current_qty * price,
        })

    last_price = float(df["close"].iloc[-1])
    if current_qty != 0:
        cash -= -current_qty * last_price
        trades += 1
        rows.append({
            "timestamp": df.index[-1],
            "price": last_price,
            "session_cmf": df["session_cmf"].iloc[-1],
            "session_signal": df["session_signal"].iloc[-1],
            "current_qty": 0,
            "target_qty": 0,
            "action": f"end-of-session flatten {abs(current_qty)}",
            "cash": cash,
            "equity": cash,
        })
        current_qty = 0

    summary = {
        "date": df.index[0].date(),
        "bars": len(df),
        "trades": trades,
        "net_pnl": cash,
    }
    return rows, summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Backtest the CMF trading strategy against historical SPY 1-min bars.")
    parser.add_argument("dataplan", choices=["iex", "sip"], help="Alpaca market data plan controlling the session window.")
    parser.add_argument("start_date", type=parse_date, help="Start date (YYYY-MM-DD).")
    parser.add_argument("--end-date", type=parse_date, default=None, help="End date (YYYY-MM-DD), defaults to start_date.")
    parser.add_argument("--qty", type=int, default=1, help="Shares per position (default: 1).")
    args = parser.parse_args()

    end_date = args.end_date or args.start_date
    api_key, api_secret = load_credentials(args.dataplan)
    client = StockHistoricalDataClient(api_key, api_secret)
    feed_enum = get_data_feed_enum(args.dataplan)

    all_rows: list[dict] = []
    summaries: list[dict] = []

    for day in daterange(args.start_date, end_date):
        start, end = session_window(args.dataplan, day)
        df = fetch_bars(client, SYMBOL, start, end, feed_enum)
        if df.empty:
            print(f"{day}: no bar data (weekend/holiday?), skipping.")
            continue
        df = compute_cmf(df)

        rows, summary = simulate_day(df, args.qty)
        all_rows.extend(rows)
        summaries.append(summary)
        print(f"{summary['date']}: bars={summary['bars']} trades={summary['trades']} net_pnl={summary['net_pnl']:+.2f}")

    if not summaries:
        print("No sessions with data in the given range.")
        return

    out_path = os.path.join(app_dir(), f"spy_backtest_log_{args.dataplan}_{args.start_date}_{end_date}.csv")
    pd.DataFrame(all_rows).to_csv(out_path, index=False)
    print(f"\nSaved backtest log -> {out_path}")

    total_pnl = sum(s["net_pnl"] for s in summaries)
    total_trades = sum(s["trades"] for s in summaries)
    winning_days = sum(1 for s in summaries if s["net_pnl"] > 0)
    print(
        f"\n{len(summaries)} session(s) | qty={args.qty} | trades={total_trades} | "
        f"total P&L={total_pnl:+.2f} | winning days={winning_days}/{len(summaries)}"
    )


if __name__ == "__main__":
    main()
