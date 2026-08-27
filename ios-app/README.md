# CMF Signal Trader (iOS)

A SwiftUI iPhone app version of the CMF signal viewer + paper trader from the
project root (`cmf_spy.py` / `cmf_trader.py`). Talks directly to Alpaca's
market-data and paper-trading REST APIs — no server component needed.

## What's included

| Screen | Mirrors | Purpose |
|---|---|---|
| Signal | `cmf_spy.py` | Streams SPY 1-min bars, computes Chaikin Money Flow, shows BULLISH/BEARISH/NEUTRAL. |
| Trader | `cmf_trader.py` | Long/shorts SPY (configurable share qty) based on the session CMF signal via Alpaca paper trading. |
| Settings | `.env` prompts | Enter Alpaca API keys (stored in the iOS Keychain), pick data feed (`iex`/`sip`), set expected paper account number, set share quantity. |

## Prerequisites

- macOS with Xcode 15+ installed.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`:
  ```bash
  brew install xcodegen
  ```

## Generate and open the Xcode project

```bash
cd ios-app
xcodegen generate
open CMFSignalTrader.xcodeproj
```

Then in Xcode: select a simulator or your iPhone as the run destination and
hit Run (⌘R). For running on a physical device you'll need to set your Apple
Developer team under the target's "Signing & Capabilities" tab.

## Credentials

Enter your Alpaca keys in the app's Settings tab (stored in the iOS Keychain,
never written to disk in plaintext):

- **Data feed**: `iex` (free, reuses trading keys) or `sip` (paid, needs its
  own market-data keys).
- **Trade API key/secret**: Alpaca **paper** trading keys.
- **Expected paper account number**: safety check before any order is
  submitted — matches the `ACCOUNT_ID` constant in `cmf_trader.py`.
- **Shares to trade**: quantity used for long/short sizing.

Get free paper-trading keys at https://app.alpaca.markets/paper/dashboard/overview.

## Notes

- Session window is 4:00 AM–8:00 PM America/New_York, matching the Python
  scripts; orders are only submitted during 9:30–16:00 ET.
- This app has no backend — regenerate/rebuild via Xcode/XcodeGen as you
  would any other iOS project. It does not affect the Python scripts in the
  repo root.
