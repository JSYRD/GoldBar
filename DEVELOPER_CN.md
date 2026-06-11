[English](./DEVELOPER.md) | [中文](./DEVELOPER_CN.md) | [用户文档](./README_CN.md)

# GoldBar 开发者文档

## 项目结构

```
GoldBar/
├── Sources/
│   ├── main.swift                        # 应用入口 (NSApplication + .accessory)
│   ├── AppDelegate.swift                 # NSApplicationDelegate + 主菜单构建
│   ├── Preferences.swift                 # UserDefaults 类型安全封装
│   ├── GoldPriceService.swift            # AllTick HTTP: GET /trade-tick
│   ├── WebSocketService.swift            # AllTick WebSocket: wss:// 推送 + 心跳
│   ├── KLineService.swift                # AllTick POST /batch-kline (日线基准价)
│   ├── CurrencyService.swift             # 免费汇率 API (open.er-api.com)
│   ├── MenuBarController.swift           # NSStatusItem + 菜单 + 双模式调度
│   ├── SettingsWindowController.swift     # 纯代码设置窗口 (NSStackView 布局)
│   ├── SetupWindowController.swift       # 首次启动 API Key 配置
│   └── SingleLineFormatter.swift         # 过滤换行符的 Formatter
├── Resources/
│   └── Info.plist                        # LSUIElement=true, bundle 元数据
├── build.sh                              # swiftc → .app 打包 → ad-hoc 签名
├── README.md / README_CN.md             # 用户文档
└── DEVELOPER.md / DEVELOPER_CN.md        # 开发者文档
```

## 架构图

```
┌─────────────────────────────────────────────────────────┐
│                     AppDelegate                          │
│   • setupMainMenu() — 构建 Edit 菜单以支持 ⌘V 粘贴       │
│   • 创建 MenuBarController                              │
└──────────────────────┬──────────────────────────────────┘
                       │
          ┌────────────▼──────────────┐
          │    MenuBarController       │
          │  ┌─────────────────────┐  │
          │  │ NSStatusItem         │  │
          │  │ NSMenu + 二级子菜单   │  │
          │  │ Timer (HTTP 模式)    │  │
          │  └─────────────────────┘  │
          │                           │
          │  startDataFetching()       │
          │    ├─ HTTP → Timer → GoldPriceService
          │    └─ WS   → WebSocketService.connect()
          │                           │
          │  refreshKLineReference()   │
          │    └─ KLineService (30分钟)│
          └──────┬─────────┬──────────┘
                 │         │
    ┌────────────▼──┐  ┌──▼─────────────┐  ┌─────────────┐
    │ GoldPriceService│  │ WebSocketService│  │ KLineService │
    │ GET /trade-tick │  │ wss:// + 22004  │  │ POST /batch- │
    │ → 当前价 USD/oz │  │ → push 22998    │  │ kline type=8  │
    └────────────────┘  └────────────────┘  │ → 昨日收盘价  │
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

## 核心组件

### `MenuBarController`
应用的中枢控制器。管理 NSStatusItem、构建菜单层级（含数据源和涨跌配色子菜单）、协调两种数据获取模式：
- **HTTP 模式**: `Timer` → `GoldPriceService.fetchPrice()` 每 15 秒
- **WebSocket 模式**: `WebSocketService.connect()` → 推送驱动更新

同时管理 K 线基准价的定时刷新（每 30 分钟）。

### `GoldPriceService`
AllTick `/trade-tick` 的 REST 客户端。获取 GOLD 当前价格 (USD/oz)。API Key 缺失时抛 `.missingAPIKey`。

### `WebSocketService`
基于 `URLSessionWebSocketTask` 的实时推送客户端：
- 连接: `wss://quote.alltick.co/quote-b-ws-api?token=<key>`
- 心跳: `{"cmd_id":22000}` 每 10 秒
- 订阅: `{"cmd_id":22004, "symbol_list":[{"code":"GOLD"}]}`
- 数据推送: `{"cmd_id":22998, "data":{"price":"...", ...}}`
- 断线自动重连，指数退避 (2s → 60s)

### `KLineService`
获取昨日收盘价作为涨跌计算基准：
- `POST /batch-kline`，`kline_type=8`（日线），`query_kline_num=2`
- 取 `kline_data[0].close_price` = 昨日收盘
- 结果缓存到 `Preferences.previousClose`

### `Preferences`
UserDefaults 的类型安全封装。所有配置持久化到 `~/Library/Preferences/com.goldbar.app.plist`。

### `SetupWindowController`
首次启动 API Key 输入窗口。临时提升 `activationPolicy` 为 `.regular` 以确保 ⌘V 粘贴可用。保存后降回 `.accessory`。

### `SingleLineFormatter`
自定义 `Formatter`，通过 `isPartialStringValid` 过滤 `\n` 和 `\r`，打字和粘贴均生效。

## 数据流

### HTTP 轮询模式
```
Timer (15s)
  → GoldPriceService.fetchPrice()       // GET /trade-tick
  → GoldPriceResult (USD/oz)
  → Preferences.effectiveExchangeRate() // 汇率转换
  → KLineService 缓存的 previousClose   // 涨跌计算
  → updateDisplay()                     // NSAttributedString 着色
  → NSStatusItem.button.attributedTitle
```

### WebSocket 推送模式
```
WebSocketService.connect()
  → [心跳循环]
  → 订阅 (cmd_id=22004)
  → 收到推送 (cmd_id=22998)
  → onPriceUpdate 回调
  → MenuBarController.updateDisplay()
```

### K 线基准价（两种模式共用）
```
Timer (30min) 或启动时
  → KLineService.fetchReference()       // POST /batch-kline
  → DailyReference { previousClose }
  → changePercent = (当前 - 昨收) / 昨收 × 100%
```

## 构建

### 前提
- macOS 13.0+, Xcode 15.0+ 或 Command Line Tools (`swiftc`)

### 命令
```bash
./build.sh          # Debug 构建
./build.sh release  # 优化构建
./build.sh run      # 构建并启动
```

## API 参考

### AllTick `/trade-tick` (REST)
```
GET https://quote.alltick.co/quote-b-api/trade-tick?token=<key>&query=<url-encoded JSON>
```
Query JSON: `{"trace":"...","data":{"symbol_list":[{"code":"GOLD"}]}}`
返回: `{ ret: 200, data: { tick_list: [{ price: "4101.91", ... }] } }`

### AllTick `/batch-kline` (REST)
```
POST https://quote.alltick.co/quote-b-api/batch-kline?token=<key>
Body: { data: { data_list: [{ code: "GOLD", kline_type: 8, query_kline_num: 2 }] } }
```
返回 2 根日 K 线，`kline_data[0].close_price` = 昨日收盘（涨跌基准）。

### AllTick WebSocket
```
wss://quote.alltick.co/quote-b-ws-api?token=<key>
  发送: { cmd_id: 22000, ... }    // 心跳，10 秒间隔
  发送: { cmd_id: 22004, data: { symbol_list: [{ code: "GOLD" }] } }
  接收: { cmd_id: 22998, data: { price: "4101.91", ... } }  // 数据推送
```

### 汇率 API
```
GET https://open.er-api.com/v6/latest/USD → { rates: { CNY: 6.789317 } }
```
缓存 1 小时。

## Preferences 参考

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `apiKey` | String? | `nil` | AllTick API Token |
| `dataSourceMode` | String | `"http"` | `"http"` 或 `"websocket"` |
| `colorScheme` | String | `"western"` | `"western"`(绿涨) 或 `"chinese"`(红涨) |
| `fontSize` | Double | 11 | 菜单栏字号 (8–18 pt) |
| `baselineOffset` | Double | -0.5 | 垂直偏移 (-4.0–+4.0) |
| `exchangeRateMode` | String | `"auto"` | `"auto"` 或 `"manual"` |
| `previousClose` | Double? | `nil` | 昨日金价收盘 (USD/oz) |

## 扩展指南

- **添加更多贵金属**：在 GoldPriceService/WebSocketService 的 `symbol_list` 中增加 code
- **更换显示单位**：修改 `MenuBarController.updateDisplay()` 中的转换公式
- **价格提醒**：接入 `UserNotifications` 在价格达到阈值时推送通知
- **其他 K 线周期**：修改 KLineService 中的 `kline_type`（如 9=周线）
