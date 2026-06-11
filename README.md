# GoldBar — Real-Time Gold Price Menu Bar App

Display the current gold price in RMB per gram on your macOS menu bar, with daily change.

## Features

- 🟡 **Real-time Gold Price** — Latest price in RMB/g with ↑↓ change arrow and percentage
- 📈 **Color Customization** — Western (green↑/red↓) or Chinese (red↑/green↓) convention
- 🔄 **Dual Data Source** — HTTP polling (efficient) or WebSocket push (real-time)
- 🌐 **Auto Currency Conversion** — Fetches USD/CNY rate, converts USD/oz to RMB/g
- 🔤 **Adjustable Display** — Font size and baseline offset sliders
- ⚙️ **No Hardcoded Key** — First-launch window prompts user for their own API key
- 💾 **Low Resource Usage** — Silent background operation
- 🔒 **Menu Bar Only** — No Dock icon

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac
- Internet connection

## Installation

```bash
cd GoldBar
./build.sh release
open build/GoldBar.app
```

Optionally drag `build/GoldBar.app` to `/Applications/`.

## Usage

### First Launch

A setup window will appear. Paste your AllTick API key (get one free at [alltick.co](https://alltick.co)) and click "开始使用". The key is stored locally — you won't need to enter it again.

### Menu Bar Display

```
Au ¥895.2/g ↑0.50%    ← colored: green(up) / red(down), or swap via settings
```

### Dropdown Menu

| Item | Description |
|------|-------------|
| Gold: $XXXX.XX/oz | Raw USD/oz price |
| Change: ↑↓X.XX% (prev close $XXXX) | Daily change vs previous close |
| Rate: X.XXXX USD/CNY | Current exchange rate |
| Updated: HH:MM:SS | Last successful fetch time |
| **Data Source** ▸ | Submenu: HTTP Polling / WebSocket Push |
| **Color Scheme** ▸ | Submenu: Green↑Red↓ (Western) / Red↑Green↓ (Chinese) |
| Refresh Now (`⌘R`) | Force refresh |
| Settings... (`⌘,`) | Open settings window |
| Quit GoldBar (`⌘Q`) | Quit |

### Settings

| Setting | Description |
|---------|-------------|
| API Key | Your AllTick API token |
| Data Source | HTTP (every 15s) or WebSocket (real-time push) |
| Font Size | Menu bar text size (8–18 pt) |
| Baseline Offset | Vertical alignment tweak (-4.0–+4.0 pt) |
| Rate Mode | Auto-fetch (hourly) or manual fixed rate |
| Manual Rate | Only used in manual mode |

## Data Sources

- **Gold Price**: [AllTick](https://alltick.co) — Real-time precious metals API
- **Previous Close**: Same API, daily K-line (`kline_type=8`) for change calculation
- **Exchange Rate**: [Exchange Rate API](https://open.er-api.com) — Free currency data

## Price Calculation

```
RMB/g     = (USD/oz × USD/CNY rate) ÷ 31.1034768
Change %  = (current - prev_close) ÷ prev_close × 100%
```

## FAQ

### Q: Why does it ask for an API key on first launch?
A: GoldBar does not ship with a built-in key. Register for free at [alltick.co](https://alltick.co) and paste your token.

### Q: The price shows `--.-/g`. What's wrong?
A: Check your network, API key validity, and rate limits (free tier: 10 req/min).

### Q: HTTP vs WebSocket?
A: HTTP polls every 15 seconds (lower resource usage). WebSocket maintains a persistent connection for near-instant updates. Switch anytime via the "Data Source" submenu.

### Q: No change percentage showing?
A: The previous day's close needs to be fetched first. It should appear within seconds of the first price update.

### Q: The up/down colors look wrong?
A: Toggle between Western (green↑) and Chinese (red↑) convention in the "Color Scheme" submenu.
