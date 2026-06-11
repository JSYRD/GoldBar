# GoldBar Developer Documentation

## Project Architecture

```
GoldBar/
├── Sources/                          # Swift source code
│   ├── main.swift                    # App entry point
│   ├── AppDelegate.swift             # NSApplicationDelegate implementation
│   ├── Preferences.swift             # UserDefaults wrapper
│   ├── GoldPriceService.swift        # AllTick gold price API service
│   ├── CurrencyService.swift         # Exchange rate API service
│   ├── MenuBarController.swift       # Menu bar UI controller
│   └── SettingsWindowController.swift # Settings window controller
├── Resources/
│   └── Info.plist                    # App bundle metadata
├── build.sh                          # Build script
├── README.md                         # User docs (English)
├── README_CN.md                      # User docs (Chinese)
├── DEVELOPER.md                      # Developer docs (English)
├── DEVELOPER_CN.md                   # Developer docs (Chinese)
└── alltick-api/                      # AllTick API docs (reference only)
```

## Architecture Design

GoldBar follows a simple **Service-Controller** architecture:

```
┌─────────────────────────────────────────────────┐
│                   AppDelegate                    │
│         (NSApplicationDelegate)                  │
└─────────────────────┬───────────────────────────┘
                      │ Creates
         ┌────────────▼────────────┐
         │   MenuBarController      │
         │  (State & UI)            │
         │                         │
         │  • NSStatusItem          │
         │  • NSMenu                │
         │  • Timer (polling)       │
         └──────┬─────────┬────────┘
                │         │
      ┌─────────▼──┐  ┌──▼──────────┐
      │ GoldPrice  │  │ Currency     │
      │ Service    │  │ Service      │
      │            │  │              │
      │ AllTick    │  │ open.er-api  │
      │ API        │  │ .com         │
      └────────────┘  └──────────────┘
                │         │
      ┌─────────▼──┐  ┌──▼──────────┐
      │ Preferences │  │ Preferences │
      │ (API Key)   │  │ (Rate mode, │
      │             │  │  cached val)│
      └────────────┘  └──────────────┘
                      │
              ┌───────▼────────┐
              │  SettingsWindow │
              │  Controller     │
              │  (Settings UI)  │
              └────────────────┘
```

### Core Components

#### 1. `MenuBarController`
The "brain" of the application. Responsibilities:
- Creates and manages `NSStatusItem`
- Polls gold price via Timer (default: every 15 seconds)
- Updates menu bar display and dropdown menu
- Handles user interactions (refresh, settings, quit)

#### 2. `GoldPriceService`
Encapsulates AllTick gold price API calls:
- Endpoint: `GET https://quote.alltick.co/quote-b-api/trade-tick`
- Params: `token` (API key) + `query` (URL-encoded JSON)
- Returns: `GoldPriceResult` (price in USD/oz, timestamp, sequence)
- Error handling: Network, HTTP, and API-level errors mapped to `GoldPriceError`

#### 3. `CurrencyService`
Encapsulates free exchange rate API calls:
- Endpoint: `GET https://open.er-api.com/v6/latest/USD`
- Cache strategy: Reuses cached value within 1 hour
- Supports `forceRefresh` for immediate update

#### 4. `Preferences`
Type-safe wrapper around UserDefaults:
- `apiKey` — AllTick API token
- `exchangeRateMode` — "auto" or "manual"
- `manualExchangeRate` — User-specified exchange rate
- `lastExchangeRate` / `lastExchangeRateUpdate` — Cached rate + timestamp
- `refreshInterval` — Polling interval in seconds

#### 5. `SettingsWindowController`
Code-only settings window (no Storyboard/XIB):
- NSLayoutConstraint-based auto layout
- Save/cancel operations
- Live reflection of setting changes

## Data Flow

```
Timer fires (every 15 s)
    │
    ▼
GoldPriceService.fetchPrice()
    │
    │  GET /quote-b-api/trade-tick?token=...&query=...
    │
    ▼
GoldPriceResult { priceUSDPerOunce, tickTime, seq }
    │
    ▼
Preferences.effectiveExchangeRate()
    │
    │  auto → cached rate (fetches via CurrencyService if expired)
    │  manual → user-provided value
    │
    ▼
Computation: RMB/g = USD/oz × rate ÷ 31.1034768
    │
    ▼
UI Update:
  • statusItem.button?.title = "Au ¥XXX.X/g"
  • Dropdown menu item details
```

## Building

### Prerequisites

- macOS 13.0+
- Xcode 15.0+ or Command Line Tools (provides `swiftc`)
- Install Command Line Tools: `xcode-select --install`

### Build Commands

```bash
# Debug build (with symbols)
./build.sh

# Release build (optimized)
./build.sh release

# Build and launch
./build.sh run
```

### Build Script Details

`build.sh` performs the following steps:

1. **Compile** — Uses `swiftc` to compile all `.swift` files into a single binary
2. **Bundle** — Creates the `.app` bundle structure:
   ```
   GoldBar.app/
   └── Contents/
       ├── Info.plist
       ├── PkgInfo
       └── MacOS/
           └── GoldBar          # Executable
   ```
3. **Sign** — Ad-hoc code signing (required for local execution)
4. **Launch** (optional) — `./build.sh run`

### Build Options

| Mode | Swift Flags | Output |
|------|------------|--------|
| debug | `-Onone -g` | `build/GoldBar.app` |
| release | `-O -whole-module-optimization` | `build/GoldBar.app` |

## API Reference

### AllTick Gold Price API

```
GET https://quote.alltick.co/quote-b-api/trade-tick
  ?token=<api_key>
  &query=<url_encoded_json>
```

**Query JSON format:**
```json
{
  "trace": "<uuid>",
  "data": {
    "symbol_list": [{"code": "GOLD"}]
  }
}
```

**Success response (200):**
```json
{
  "ret": 200,
  "msg": "ok",
  "data": {
    "tick_list": [{
      "code": "GOLD",
      "seq": "24618487",
      "tick_time": "1781166146694",   // Millisecond timestamp
      "price": "4101.91",             // USD/troy ounce
      "volume": "8.00",
      "turnover": "32815.28",
      "trade_direction": 1
    }]
  }
}
```

**Error codes:**
| ret | Meaning |
|-----|---------|
| 200 | Success |
| 202 | Invalid parameter |
| 403 | Invalid token |
| 429 | Rate limited |
| 604 | Code unauthorized |

### Free Exchange Rate API

```
GET https://open.er-api.com/v6/latest/USD
```

**Response:**
```json
{
  "result": "success",
  "time_last_update_utc": "Thu, 11 Jun 2026 00:02:31 +0000",
  "rates": {
    "CNY": 6.789317,
    ...
  }
}
```

## Extension Guide

### Adding New Precious Metals

1. Add the new symbol to the query in `GoldPriceService.swift` (e.g., `SILVER`, `PLATINUM`)
2. Or support batch queries with multiple codes:
   ```swift
   "symbol_list": [{"code": "GOLD"}, {"code": "SILVER"}]
   ```
3. Update `MenuBarController` display logic accordingly

### Adding Other Display Units

Modify the conversion formula in `MenuBarController.updateDisplay(with:)`:
```swift
// Current: RMB/gram
let value = result.priceUSDPerOunce * rate / troyOunceToGrams

// Optional: RMB/oz
let value = result.priceUSDPerOunce * rate

// Optional: USD/g
let value = result.priceUSDPerOunce / troyOunceToGrams
```

### Adding WebSocket Support

AllTick also provides WebSocket real-time streaming. For faster updates:
1. Reference the docs in `alltick-api/websocket_interface/`
2. Create `WebSocketService.swift` using `URLSessionWebSocketTask`
3. Replace the Timer in `MenuBarController` with WebSocket subscription

## Testing

### API Test Scripts

```bash
# Test gold price API
QUERY=$(python3 -c "
import json, urllib.parse
data = {
    'trace': 'test-001',
    'data': {
        'symbol_list': [{'code': 'GOLD'}]
    }
}
print(urllib.parse.quote(json.dumps(data)))
")
curl -s "https://quote.alltick.co/quote-b-api/trade-tick?token=YOUR_API_KEY&query=$QUERY" | python3 -m json.tool

# Test exchange rate API
curl -s "https://open.er-api.com/v6/latest/USD" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'USD/CNY: {d[\"rates\"][\"CNY\"]}')
"
```

### Manual Test Checklist

- [ ] App launches and displays gold price in menu bar
- [ ] Dropdown menu shows price, rate, and time correctly
- [ ] "Refresh Now" triggers a data update
- [ ] Settings window opens correctly
- [ ] Changing API key takes effect
- [ ] Switching exchange rate mode (auto ↔ manual) works
- [ ] Manual exchange rate value produces correct price conversion
- [ ] "Quit GoldBar" exits cleanly

## License

This project is for personal use.
