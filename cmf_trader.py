"""
Long/short SPY paper-trading bot driven by the session-wide CMF signal from
cmf_spy.py.

Each minute it recomputes the session CMF over today's 1-min bars (4:00 AM ET
onward) and moves the SPY position to match:
    BULLISH -> long QTY shares
    BEARISH -> short QTY shares
    NEUTRAL -> flat

Orders are only submitted during regular market hours (9:30-16:00 ET); before
the open the signal is only monitored. The position is flattened at the
close. Paper trading only (TradingClient(paper=True)) - a separate order
history log is appended to spy_trade_log_<date>.csv.
"""

import os
import sys
import time
from datetime import datetime, timedelta

import pandas as pd

from alpaca.trading.client import TradingClient
from alpaca.trading.enums import OrderSide, TimeInForce
from alpaca.trading.requests import MarketOrderRequest
from alpaca.data.historical import StockHistoricalDataClient

from cmf_spy import (
    EASTERN,
    app_dir,
    compute_cmf,
    fetch_bars,
    get_data_feed_enum,
    get_session_end,
    get_session_start,
    interpret_signal,
    load_credentials,
    load_data_feed,
    seconds_until_next_minute,
)

SYMBOL = "SPY"
QTY = 1
MARKET_OPEN_HOUR = 9
MARKET_OPEN_MINUTE = 30
MARKET_CLOSE_HOUR = 16
ACCOUNT_ID = "PA38A272SBF7"


def load_trading_credentials() -> tuple[str, str]:
    env_path = os.path.join(app_dir(), ".env")
    from dotenv import load_dotenv

    load_dotenv(env_path)
    api_key = os.getenv("apiTradeKey")
    api_secret = os.getenv("apiTradeSecret")

    if not api_key or not api_secret:
        if not sys.stdin.isatty():
            raise RuntimeError(f"Missing apiTradeKey/apiTradeSecret in {env_path}")
        print("No Alpaca paper-trading API credentials found.")
        print("Get a free paper key/secret from https://app.alpaca.markets/paper/dashboard/overview")
        api_key = input("Enter your Alpaca paper-trading API key: ").strip()
        api_secret = input("Enter your Alpaca paper-trading API secret: ").strip()
        if not api_key or not api_secret:
            raise RuntimeError("Missing apiTradeKey/apiTradeSecret in .env")
        with open(env_path, "a") as f:
            f.write(f"apiTradeKey={api_key}\napiTradeSecret={api_secret}\n")
        print(f"Saved trading credentials to {env_path}\n")

    return api_key, api_secret


def classify_target_qty(signal: str, qty: int) -> int:
    if signal.startswith("BULLISH"):
        return qty
    if signal.startswith("BEARISH"):
        return -qty
    return 0


def get_current_qty(trading_client: TradingClient, symbol: str) -> int:
    try:
        position = trading_client.get_open_position(symbol)
    except Exception:
        return 0
    return int(float(position.qty))


def is_market_open(now: datetime) -> bool:
    open_time = now.replace(hour=MARKET_OPEN_HOUR, minute=MARKET_OPEN_MINUTE, second=0, microsecond=0)
    close_time = now.replace(hour=MARKET_CLOSE_HOUR, minute=0, second=0, microsecond=0)
    return open_time <= now < close_time


def submit_delta_order(trading_client: TradingClient, symbol: str, delta: int) -> None:
    side = OrderSide.BUY if delta > 0 else OrderSide.SELL
    order = MarketOrderRequest(
        symbol=symbol,
        qty=abs(delta),
        side=side,
        time_in_force=TimeInForce.DAY,
    )
    trading_client.submit_order(order)


def append_trade_log(path: str, row: dict) -> None:
    header = not os.path.exists(path)
    pd.DataFrame([row]).to_csv(path, mode="a", header=header, index=False)


def verify_account(trading_client: TradingClient, expected_account_id: str) -> None:
    account = trading_client.get_account()
    if account.account_number != expected_account_id:
        raise RuntimeError(
            f"Trading credentials resolve to account {account.account_number}, "
            f"expected {expected_account_id}. Refusing to trade."
        )


def main() -> None:
    trade_key, trade_secret = load_trading_credentials()
    feed = load_data_feed()
    api_key, api_secret = load_credentials(feed)

    data_client = StockHistoricalDataClient(api_key, api_secret)
    trading_client = TradingClient(trade_key, trade_secret, paper=True)
    verify_account(trading_client, ACCOUNT_ID)

    start = get_session_start()
    session_end = get_session_end(start)
    trade_log_csv = os.path.join(app_dir(), f"spy_trade_log_{start.date()}.csv")

    print(f"Trading {SYMBOL} on session CMF signal (paper account) until {session_end}. Ctrl+C to stop.")
    print(f"Trade log -> {trade_log_csv}\n")

    try:
        while datetime.now(EASTERN) < session_end:
            now = datetime.now(EASTERN)
            end = now
            df = fetch_bars(data_client, SYMBOL, start, end, get_data_feed_enum(feed))
            if df.empty:
                print(f"[{end.strftime('%H:%M:%S')}] no bar data yet, waiting...")
                time.sleep(seconds_until_next_minute())
                continue
            df = compute_cmf(df)

            session_cmf = df["mf_volume"].sum() / df["volume"].sum()
            session_signal = interpret_signal(session_cmf)
            target_qty = classify_target_qty(session_signal, QTY)

            current_qty = get_current_qty(trading_client, SYMBOL)
            delta = target_qty - current_qty

            action = "hold"
            if delta != 0 and is_market_open(now):
                submit_delta_order(trading_client, SYMBOL, delta)
                action = f"{'buy' if delta > 0 else 'sell'} {abs(delta)}"
            elif delta != 0:
                action = "signal changed, market closed - not submitted"

            print(
                f"[{end.strftime('%H:%M:%S')}] session CMF={session_cmf:.4f} -> {session_signal} "
                f"| current={current_qty} target={target_qty} | {action}"
            )

            append_trade_log(
                trade_log_csv,
                {
                    "timestamp": end,
                    "session_cmf": session_cmf,
                    "session_signal": session_signal,
                    "current_qty": current_qty,
                    "target_qty": target_qty,
                    "action": action,
                },
            )

            time.sleep(seconds_until_next_minute())
    except KeyboardInterrupt:
        print("\nStopped.")

    final_qty = get_current_qty(trading_client, SYMBOL)
    if final_qty != 0:
        print(f"Flattening end-of-session position ({final_qty} shares)...")
        submit_delta_order(trading_client, SYMBOL, -final_qty)

    print(f"\nReached session end ({session_end}). Stopping.")


if __name__ == "__main__":
    main()
