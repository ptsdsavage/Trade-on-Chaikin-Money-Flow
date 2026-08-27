"""
Chaikin Money Flow (CMF) signal for SPY using Alpaca SIP 1-minute bars.

Streams 1-minute bars for SPY from 4:00 AM (America/New_York) today through the
current minute, computes the Money Flow Multiplier / Money Flow Volume, rolls
them into a Chaikin Money Flow indicator, and keeps running, refreshing and
printing the expected price movement signal (bullish / bearish / neutral)
once per minute.
"""

import os
import sys
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pandas as pd
from dotenv import load_dotenv

from alpaca.data.historical import StockHistoricalDataClient
from alpaca.data.requests import StockBarsRequest
from alpaca.data.timeframe import TimeFrame
from alpaca.data.enums import DataFeed

# CMF period (in minutes, since we're using 1-min bars)
CMF_PERIOD = 20

EASTERN = ZoneInfo("America/New_York")


def app_dir() -> str:
    # When frozen by PyInstaller, keep the .env next to the executable, not the temp bundle.
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(__file__))


def load_credentials() -> tuple[str, str]:
    env_path = os.path.join(app_dir(), ".env")
    load_dotenv(env_path)
    api_key = os.getenv("apiDataKey")
    api_secret = os.getenv("apiDataSecret")

    if not api_key or not api_secret:
        if not sys.stdin.isatty():
            raise RuntimeError(f"Missing apiDataKey/apiDataSecret in {env_path}")
        print("No Alpaca API credentials found.")
        print("Get a free data key/secret from https://app.alpaca.markets/paper/dashboard/overview")
        api_key = input("Enter your Alpaca API key: ").strip()
        api_secret = input("Enter your Alpaca API secret: ").strip()
        if not api_key or not api_secret:
            raise RuntimeError("Missing apiDataKey/apiDataSecret in .env")
        with open(env_path, "w") as f:
            f.write(f"apiDataKey={api_key}\napiDataSecret={api_secret}\n")
        print(f"Saved credentials to {env_path}\n")

    return api_key, api_secret


def get_session_start() -> datetime:
    today = datetime.now(EASTERN).date()
    return datetime.combine(today, datetime.min.time(), tzinfo=EASTERN).replace(hour=4)


def get_session_end(start: datetime) -> datetime:
    return start.replace(hour=20)


def seconds_until_next_minute() -> float:
    now = datetime.now(EASTERN)
    next_minute = (now + timedelta(minutes=1)).replace(second=0, microsecond=0)
    return (next_minute - now).total_seconds()


def fetch_bars(
    client: StockHistoricalDataClient, symbol: str, start: datetime, end: datetime
) -> pd.DataFrame:
    request = StockBarsRequest(
        symbol_or_symbols=symbol,
        timeframe=TimeFrame.Minute,
        start=start,
        end=end,
        feed=DataFeed.SIP,
    )
    bars = client.get_stock_bars(request)
    df = bars.df
    if df.empty:
        return df

    df = df.reset_index()
    df = df[df["symbol"] == symbol].set_index("timestamp")
    df.index = df.index.tz_convert(EASTERN)
    return df


def compute_cmf(df: pd.DataFrame, period: int = CMF_PERIOD) -> pd.DataFrame:
    high, low, close, volume = df["high"], df["low"], df["close"], df["volume"]

    range_ = (high - low).replace(0, float("nan"))
    money_flow_multiplier = ((close - low) - (high - close)) / range_
    money_flow_multiplier = money_flow_multiplier.fillna(0.0).astype(float)

    money_flow_volume = money_flow_multiplier * volume

    df = df.copy()
    df["mf_multiplier"] = money_flow_multiplier
    df["mf_volume"] = money_flow_volume
    df["cmf"] = (
        money_flow_volume.rolling(period).sum() / volume.rolling(period).sum()
    )
    return df


def interpret_signal(cmf_value: float) -> str:
    if pd.isna(cmf_value):
        return "NEUTRAL (insufficient data)"
    if cmf_value > 0.05:
        return "BULLISH (buying pressure, expect upward movement)"
    if cmf_value < -0.05:
        return "BEARISH (selling pressure, expect downward movement)"
    return "NEUTRAL (no strong directional pressure)"


def write_bars_csv(df: pd.DataFrame, path: str) -> None:
    out = df.copy()
    out["signal"] = out["cmf"].apply(interpret_signal)
    out.to_csv(path, index_label="timestamp")


def append_signal_log(path: str, row: dict) -> None:
    header = not os.path.exists(path)
    pd.DataFrame([row]).to_csv(path, mode="a", header=header, index=False)


def main() -> None:
    symbol = "SPY"
    api_key, api_secret = load_credentials()
    client = StockHistoricalDataClient(api_key, api_secret)
    start = get_session_start()
    session_end = get_session_end(start)

    bars_csv = os.path.join(app_dir(), f"spy_bars_{start.date()}.csv")
    signal_log_csv = os.path.join(app_dir(), f"spy_signal_log_{start.date()}.csv")

    print(f"Streaming {symbol} 1-min SIP bars from {start} until {session_end}. Ctrl+C to stop.")
    print(f"Bars -> {bars_csv}")
    print(f"Signal log -> {signal_log_csv}\n")

    try:
        while datetime.now(EASTERN) < session_end:
            end = datetime.now(EASTERN)
            df = fetch_bars(client, symbol, start, end)
            if df.empty:
                print(f"[{end.strftime('%H:%M:%S')}] no bar data yet, waiting...")
                time.sleep(seconds_until_next_minute())
                continue
            df = compute_cmf(df)

            latest = df.iloc[-1]
            session_cmf = df["mf_volume"].sum() / df["volume"].sum()
            latest_signal = interpret_signal(latest["cmf"])
            session_signal = interpret_signal(session_cmf)

            print(
                f"[{end.strftime('%H:%M:%S')}] bars={len(df)} "
                f"close={latest['close']:.2f} "
                f"CMF({CMF_PERIOD})={latest['cmf']:.4f} -> {latest_signal} | "
                f"session CMF={session_cmf:.4f} -> {session_signal}"
            )

            write_bars_csv(df, bars_csv)
            append_signal_log(
                signal_log_csv,
                {
                    "timestamp": end,
                    "close": latest["close"],
                    "cmf": latest["cmf"],
                    "signal": latest_signal,
                    "session_cmf": session_cmf,
                    "session_signal": session_signal,
                },
            )

            time.sleep(seconds_until_next_minute())
    except KeyboardInterrupt:
        print("\nStopped.")
        return

    print(f"\nReached session end ({session_end}). Stopping.")


if __name__ == "__main__":
    main()
