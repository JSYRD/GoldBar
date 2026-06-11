English | [中文](./DEVELOPER_CN.md) | [用户文档](./README.md)

# GoldBar Developer Documentation

## Project Architecture

```
GoldBar/
├── Sources/
│   ├── main.swift                        # App entry point (NSApplication + .accessory)
│   ├── AppDelegate.swift                 # NSApplicationDelegate + main menu setup
│   ├── Preferences.swift                 # UserDefaults type-safe wrapper
│   ├── GoldPriceService.swift            # AllTick HTTP REST: GET /trade-tick
│   ├── WebSocketService.swift            # AllTick WebSocket: wss:// push + heartbeat
│   ├── KLineService.swift                # AllTick POST /batch-kline (daily reference)
│   ├── CurrencyService.swift             # Free exchange rate API (open.er-api.com)
│   ├── MenuBarController.swift           # NSStatusItem + menu + dual-mode orchestration
│   ├── SettingsWindowController.swift     # Code-only settings window (NSStackView)
│   ├── SetupWindowController.swift       # First-launch API key configuration
│   └── SingleLineFormatter.swift         # Formatter that strips newlines
├── Resources/
│   └── Info.plist                        # LSUIElement=true, bundle metadata
├── build.sh                              # swiftc → .app bundle → ad-hoc sign
├── README.md / README_CN.md             # User documentation
└── DEVELOPER.md / DEVELOPER_CN.md        # Developer documentation
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     AppDelegate                          │
│   • setupMainMenu() — Edit menu for ⌘V paste support    │
│   • Creates MenuBarController                           │
└──────────────────────┬──────────────────────────────────┘
                       │
          ┌────────────▼──────────────┐
          │    MenuBarController       │
          │  ┌─────────────────────┐  │
          │  │ NSStatusItem         │  │
          │  │ NSMenu + submenus    │  │
          │  │ Timer (HTTP mode)    │  │
          │  └─────────────────────┘  │
          │                           │
          │  startDataFetching()       │
          │    ├─ HTTP → Timer → GoldPriceService
          │    └─ WS   → WebSocketService.connect()
          │                           │
          │  refreshKLineReference()   │
          │    └─ KLineService (30min) │
          └──────┬─────────┬──────────┘
                 │         │
    ┌────────────▼──┐  ┌──▼─────────────┐  ┌─────────────┐
    │ GoldPriceService│  │ WebSocketService│  │ KLineService │
    │ GET /trade-tick │  │ wss:// + 22004  │  │ POST /batch- │
    │ → price USD/oz  │  │ → push 22998    │  │ kline type=8  │
    └────────────────┘  └────────────────┘  │ → prev close  │
                                            └─────────────┘
                       │
    ┌──────────────────▼──────────────────┐
    │          Preferences                 │
    │  apiKey, dataSourceMode, fontSize,   │
    │  baselineOffset, colorScheme,        │
    │  previousClose, exchangeRate…        │
    └─────────────────────────────────────┘
                       │
    ┌──────────────────▼──────────────────┐
    │   SettingsWindowController           │
    │   SetupWindowController              │
    └─────────────────────────────────────┘
```

## Core Components

### `MenuBarController`
Central orchestrator. Manages NSStatusItem, builds the menu hierarchy (including data source and color scheme submenus), and coordinates two data-fetching modes:
- **HTTP mode**: `Timer` → `GoldPriceService.fetchPrice()` every 15s
- **WebSocket mode**: `WebSocketService.connect()` → push-driven updates

Also manages periodic K-line reference fetches (every 30 min) for change calculation.

### `GoldPriceService`
REST client for AllTick `/trade-tick`:
- Endpoint: `GET https://quote.alltick.co/quote-b-api/trade-tick`
- Query: `?token=<key>&query=<url-encoded JSON with GOLD code>`
- Returns: `GoldPriceResult { priceUSDPerOunce, tickTime, seq }`
- Errors mapped to `GoldPriceError` (including `.missingAPIKey`)

### `WebSocketService`
Real-time push client using `URLSessionWebSocketTask`:
- Connect: `wss://quote.alltick.co/quote-b-ws-api?token=<key>`
- Heartbeat: `{"cmd_id":22000}` every 10s (server disconnects after 30s silence)
- Subscribe: `{"cmd_id":22004, "symbol_list":[{"code":"GOLD"}]}`
- Push data: `{"cmd_id":22998, "data":{"price":"...", "tick_time":"...", ...}}`
- Auto-reconnect with exponential backoff (2s → 60s max)
- Callbacks: `onPriceUpdate`, `onConnectionStateChange`

### `KLineService`
Fetches previous trading day's closing price for change calculation:
- Endpoint: `POST https://quote.alltick.co/quote-b-api/batch-kline`
- Body: `kline_type=8` (daily), `query_kline_num=2` (last 2 bars)
- Extracts `kline_data[0].close_price` = yesterday's close (reference)
- Caches result to `Preferences.previousClose`

### `Preferences`
Type-safe UserDefaults wrapper. All properties persist locally in `~/Library/Preferences/com.goldbar.app.plist`.

### `SetupWindowController`
First-launch API key entry. Promotes the app to `.regular` activation policy temporarily so ⌘V paste works. On save, demotes back to `.accessory` and triggers data fetching.

### `SingleLineFormatter`
Custom `Formatter` that strips `\n` and `\r` from both typed and pasted text via `isPartialStringValid`. Applied to all single-line text fields.

## Data Flow

### HTTP Polling Mode
```
Timer (15s)
  → GoldPriceService.fetchPrice()       // GET /trade-tick
  → GoldPriceResult (USD/oz)
  → Preferences.effectiveExchangeRate() // USD→RMB conversion
  → KLineService cached previousClose   // change calculation
  → updateDisplay()                     // NSAttributedString with color
  → NSStatusItem.button.attributedTitle
```

### WebSocket Push Mode
```
WebSocketService.connect()
  → [heartbeat loop]
  → subscribe (cmd_id=22004)
  → push received (cmd_id=22998)
  → onPriceUpdate callback
  → MenuBarController.updateDisplay()
```

### K-Line Reference (shared by both modes)
```
Timer (30min) or startup
  → KLineService.fetchReference()       // POST /batch-kline
  → DailyReference { previousClose }
  → Preferences.previousClose = close
  → changePercent = (current - prevClose) / prevClose × 100%
```

## Build

### Prerequisites
- macOS 13.0+, Xcode 15.0+ or Command Line Tools (`swiftc`)

### Commands
```bash
./build.sh          # Debug build
./build.sh release  # Optimized build
./build.sh run      # Build + launch
```

### Build Script Steps
1. `swiftc` compiles all `.swift` files → single `GoldBar` binary (arm64)
2. Creates `.app` bundle structure with Info.plist + PkgInfo
3. Ad-hoc code sign (`codesign --sign -`)

## API Reference

### AllTick `/trade-tick` (REST)
```
GET https://quote.alltick.co/quote-b-api/trade-tick
  ?token=<api_key>
  &query=%7B%22trace%22%3A%22...%22%2C%22data%22%3A%7B%22symbol_list%22%3A%5B%7B%22code%22%3A%22GOLD%22%7D%5D%7D%7D
```
Returns: `{ ret: 200, data: { tick_list: [{ price: "4101.91", ... }] } }`

### AllTick `/batch-kline` (REST)
```
POST https://quote.alltick.co/quote-b-api/batch-kline?token=<key>
Body: { data: { data_list: [{ code: "GOLD", kline_type: 8, query_kline_num: 2 }] } }
```
Returns: 2 daily K-lines → `[0].close_price` = previous close (benchmark).

### AllTick WebSocket
```
wss://quote.alltick.co/quote-b-ws-api?token=<key>
  → send: { cmd_id: 22000, ... }  // heartbeat every 10s
  → send: { cmd_id: 22004, data: { symbol_list: [{ code: "GOLD" }] } }
  → recv: { cmd_id: 22998, data: { price: "4101.91", ... } }  // push
```

### Exchange Rate API
```
GET https://open.er-api.com/v6/latest/USD
→ { rates: { CNY: 6.789317 } }
```
Cached for 1 hour.

## Preferences Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `apiKey` | String? | `nil` | AllTick API token |
| `dataSourceMode` | String | `"http"` | `"http"` or `"websocket"` |
| `colorScheme` | String | `"western"` | `"western"` (green↑) or `"chinese"` (red↑) |
| `fontSize` | Double | 11 | Menu bar font size (8–18 pt) |
| `baselineOffset` | Double | -0.5 | Vertical alignment offset (-4.0–+4.0) |
| `exchangeRateMode` | String | `"auto"` | `"auto"` or `"manual"` |
| `previousClose` | Double? | `nil` | Yesterday's gold close (USD/oz) |

## Extension Points

- **Add more metals**: add codes to `symbol_list` in GoldPriceService / WebSocketService
- **Change display units**: modify the conversion formula in `MenuBarController.updateDisplay()`
- **Add notification**: use `NSUserNotification` or `UserNotifications` framework on price threshold
- **Custom K-line type**: change `kline_type` in KLineService (e.g., weekly = 9 for weekly change)
