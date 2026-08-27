# Trade on Chaikin Money Flow

Tools to stream SPY 1-minute bars, compute a Chaikin Money Flow (CMF) signal,
paper-trade on that signal, monitor P&L, and check how accurate the signal
has been.

## What's included

| Script | Purpose |
|---|---|
| `cmf_spy.py` | Streams SPY 1-min bars (Alpaca SIP), computes CMF, prints/logs a BULLISH/BEARISH/NEUTRAL signal every minute. |
| `cmf_trader.py` | Long/short paper-trades SPY (1 share) based on the session CMF signal, via Alpaca's paper trading API. |
| `pnl_monitor.py` | Polls the paper account every 10s and prints/logs unrealized position P&L and account day P&L. |
| `check_accuracy.py` | Scores a day's signal log against what price actually did afterward. |
| `build_app.sh` | Builds standalone macOS binaries for `cmf_spy.py` and `cmf_trader.py` and packages them into `Trade on Chaikin Money Flow.zip`. |
| `build_app_windows.bat` | Builds a standalone Windows exe for `cmf_spy.py` and `cmf_trader.py` (run on Windows) and packages them into `Trade on Chaikin Money Flow.zip`. |

## Install

Requires Python 3.10+.

```bash
git clone https://github.com/ptsdsavage/Trade-on-Chaikin-Money-Flow.git
cd Trade-on-Chaikin-Money-Flow
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Credentials

Create a `.env` file in the project root (scripts will also prompt and save
it for you on first run if missing):

```
apiDataFeed=<'iex' or 'sip'>
apiDataKey=<Alpaca market data API key>       # only needed if apiDataFeed=sip
apiDataSecret=<Alpaca market data API secret> # only needed if apiDataFeed=sip
apiTradeKey=<Alpaca PAPER trading API key>
apiTradeSecret=<Alpaca PAPER trading API secret>
```

`apiDataFeed` selects your Alpaca market data plan:
- `iex` - free plan. Only the trading API keys need to be entered; the
  trading keys (`apiTradeKey`/`apiTradeSecret`) are reused for market data too.
- `sip` - paid plan with full consolidated market data. Requires its own
  `apiDataKey`/`apiDataSecret`.

Get free keys at https://app.alpaca.markets/paper/dashboard/overview.
`.env` is gitignored — never commit it.

`cmf_trader.py` and `pnl_monitor.py` also verify the trading keys resolve to
a specific paper account number (`ACCOUNT_ID` constant in `cmf_trader.py`) as
a safety check before placing any orders. Update that constant to your own
paper account number.

## Usage

Run each from the project root (session runs 4:00 AM-8:00 PM America/New_York):

```bash
# Stream signal only, no trading
python cmf_spy.py

# Paper-trade on the CMF signal (long/short 1 share of SPY)
python cmf_trader.py

# Watch live P&L while cmf_trader.py runs
python pnl_monitor.py

# Score today's (or a past day's) signal accuracy
python check_accuracy.py 2026-08-27 --horizon 5 --threshold 0.0
```

Each script writes its own CSV log for the day (`spy_bars_*.csv`,
`spy_signal_log_*.csv`, `spy_trade_log_*.csv`, `spy_pnl_log_*.csv`,
`spy_accuracy_*.csv`) - these are gitignored.

## Building the standalone Mac app

```bash
bash build_app.sh
```

Produces `Trade on Chaikin Money Flow.zip` containing arm64 + x86_64
binaries and double-clickable launchers (`Run SPY Signal.command`,
`Run CMF Trader.command`). The zip is gitignored (too large for git) - keep
it locally or distribute separately.

## Building the standalone Windows app

Run on a Windows machine with Python 3.10+ installed:

```bat
build_app_windows.bat
```

Produces `Trade on Chaikin Money Flow.zip` containing `SPY-CMF-Signal.exe`,
`CMF-Trader.exe`, and double-clickable launchers (`Run SPY Signal.bat`,
`Run CMF Trader.bat`). PyInstaller can't cross-compile, so this must be run
on Windows itself, not on macOS/Linux.
