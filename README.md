# GoldBar — Real-Time Gold Price Menu Bar App

Display the current gold price in RMB per gram on your macOS menu bar.

## Features

- 🟡 **Real-time Gold Price** — Shows the latest gold price (RMB/g) in the menu bar
- 🌐 **Auto Currency Conversion** — Automatically fetches USD/CNY exchange rate, converts USD/oz to RMB/g
- ⚙️ **Configurable** — Change API key, switch exchange rate modes
- 💾 **Low Resource Usage** — Runs silently in the background with periodic polling
- 🔒 **Menu Bar Only** — No Dock icon, lives exclusively in the menu bar

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3/M4) or Intel Mac
- Internet connection

## Installation

### Option 1: Run directly

```bash
cd GoldBar
./build.sh release
open build/GoldBar.app
```

### Option 2: Move to Applications

After building, drag `build/GoldBar.app` to your `/Applications/` folder.

### Auto-launch at Login (optional)

1. Open System Settings → General → Login Items & Extensions
2. Click "+" and add GoldBar.app

## Usage

### Menu Bar Display

After launch, you'll see something like this in the top-right menu bar:

```
Au ¥895.2/g
```

- `Au` — Gold chemical symbol
- `¥895.2/g` — RMB price per gram of gold

### Menu Items

Click the menu bar item to see:

| Item | Description |
|------|-------------|
| Gold: $XXXX.XX/oz | Raw USD per troy ounce price |
| Rate: X.XXXX USD/CNY | Current exchange rate in use |
| Updated: HH:MM:SS | Time of last successful fetch |
| Refresh Now (`⌘R`) | Manually trigger a data refresh |
| Settings... (`⌘,`) | Open the settings window |
| Quit GoldBar (`⌘Q`) | Quit the application |

### Settings

The settings window allows you to configure:

- **API Key** — Your AllTick platform API token. A free key is pre-configured
- **Exchange Rate Mode**
  - *Auto (recommended)* — Fetches USD/CNY rate from free API every hour
  - *Manual* — Use a fixed exchange rate of your choice
- **Manual Rate** — Only enabled in manual mode; enter your desired USD/CNY rate

Click "Save" to apply changes immediately.

## Data Sources

- **Gold Price**: [AllTick](https://alltick.co) Financial Data API — Real-time precious metals quotes
- **USD Exchange Rate**: [Exchange Rate API](https://open.er-api.com) — Free currency exchange rates

## Price Calculation

```
RMB/g = (USD/oz × USD/CNY rate) ÷ 31.1034768
```

Where `31.1034768` is the number of grams in one troy ounce.

## FAQ

### Q: The price shows `--.-/g`. What's wrong?
A: Unable to fetch gold price. Check:
1. Network connection
2. API Key validity in Settings
3. API rate limits (free tier: 10 requests/minute)

### Q: How often does the exchange rate update?
A: In auto mode, once per hour. You can also manually set a fixed rate in Settings.

### Q: How do I get my own API Key?
A: Visit [AllTick official website](https://alltick.co) to register and obtain an API token.
