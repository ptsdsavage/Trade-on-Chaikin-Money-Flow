"""
Real-time P&L monitor for the CMF paper-trading account.

Polls the Alpaca paper account every REFRESH_SECONDS and prints/logs:
    - open SPY position (qty, avg entry, current price, unrealized P&L)
    - account day P&L (equity vs. previous close equity)

Uses the same apiTradeKey/apiTradeSecret credentials and account-id safety
check as cmf_trader.py.
"""

import os
import time
from datetime import datetime

import pandas as pd

from alpaca.trading.client import TradingClient

from cmf_spy import EASTERN, app_dir, get_session_end, get_session_start
from cmf_trader import ACCOUNT_ID, SYMBOL, load_trading_credentials, verify_account

REFRESH_SECONDS = 10


def get_position_pnl(trading_client: TradingClient, symbol: str) -> dict:
    try:
        position = trading_client.get_open_position(symbol)
    except Exception:
        return {
            "qty": 0,
            "avg_entry_price": None,
            "current_price": None,
            "market_value": 0.0,
            "unrealized_pl": 0.0,
            "unrealized_plpc": 0.0,
        }
    return {
        "qty": float(position.qty),
        "avg_entry_price": float(position.avg_entry_price),
        "current_price": float(position.current_price),
        "market_value": float(position.market_value),
        "unrealized_pl": float(position.unrealized_pl),
        "unrealized_plpc": float(position.unrealized_plpc) * 100.0,
    }


def append_pnl_log(path: str, row: dict) -> None:
    header = not os.path.exists(path)
    pd.DataFrame([row]).to_csv(path, mode="a", header=header, index=False)


def main() -> None:
    trade_key, trade_secret = load_trading_credentials()
    trading_client = TradingClient(trade_key, trade_secret, paper=True)
    verify_account(trading_client, ACCOUNT_ID)

    start = get_session_start()
    session_end = get_session_end(start)
    pnl_log_csv = os.path.join(app_dir(), f"spy_pnl_log_{start.date()}.csv")

    print(f"Monitoring {SYMBOL} paper P&L every {REFRESH_SECONDS}s until {session_end}. Ctrl+C to stop.")
    print(f"P&L log -> {pnl_log_csv}\n")

    try:
        while datetime.now(EASTERN) < session_end:
            now = datetime.now(EASTERN)
            account = trading_client.get_account()
            equity = float(account.equity)
            last_equity = float(account.last_equity)
            day_pl = equity - last_equity
            day_plpc = (day_pl / last_equity * 100.0) if last_equity else 0.0

            position = get_position_pnl(trading_client, SYMBOL)

            print(
                f"[{now.strftime('%H:%M:%S')}] "
                f"pos={position['qty']:.0f} @ {position['avg_entry_price']} "
                f"px={position['current_price']} "
                f"unrealized={position['unrealized_pl']:+.2f} ({position['unrealized_plpc']:+.2f}%) | "
                f"equity={equity:,.2f} day P&L={day_pl:+.2f} ({day_plpc:+.2f}%)"
            )

            append_pnl_log(
                pnl_log_csv,
                {
                    "timestamp": now,
                    "qty": position["qty"],
                    "avg_entry_price": position["avg_entry_price"],
                    "current_price": position["current_price"],
                    "market_value": position["market_value"],
                    "unrealized_pl": position["unrealized_pl"],
                    "unrealized_plpc": position["unrealized_plpc"],
                    "equity": equity,
                    "day_pl": day_pl,
                    "day_plpc": day_plpc,
                },
            )

            time.sleep(REFRESH_SECONDS)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
