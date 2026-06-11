# GoldBar 开发者文档

## 项目架构

```
GoldBar/
├── Sources/                          # Swift 源代码
│   ├── main.swift                    # 应用入口点
│   ├── AppDelegate.swift             # NSApplicationDelegate 实现
│   ├── Preferences.swift             # UserDefaults 偏好设置封装
│   ├── GoldPriceService.swift        # AllTick 金价 API 服务
│   ├── CurrencyService.swift         # 汇率 API 服务
│   ├── MenuBarController.swift       # 菜单栏 UI 控制器
│   └── SettingsWindowController.swift # 设置窗口控制器
├── Resources/
│   └── Info.plist                    # 应用 Bundle 元数据
├── build.sh                          # 构建脚本
├── README_CN.md                      # 用户文档（中文）
├── README.md                         # 用户文档（英文）
├── DEVELOPER_CN.md                   # 开发者文档（中文）
├── DEVELOPER.md                      # 开发者文档（英文）
└── alltick-api/                      # AllTick API 文档（仅作参考）
```

## 架构设计

GoldBar 采用简单的 **服务-控制器** 架构：

```
┌─────────────────────────────────────────────────┐
│                   AppDelegate                    │
│         (NSApplicationDelegate)                  │
└─────────────────────┬───────────────────────────┘
                      │ 创建
         ┌────────────▼────────────┐
         │   MenuBarController      │
         │  (状态管理 & UI)          │
         │                         │
         │  • NSStatusItem          │
         │  • NSMenu                │
         │  • Timer (定时轮询)       │
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
              │  (设置 UI)       │
              └────────────────┘
```

### 核心组件

#### 1. `MenuBarController`
应用的「大脑」。负责：
- 创建和管理 NSStatusItem
- 通过 Timer 定时轮询金价（默认每 15 秒）
- 更新菜单栏显示和下拉菜单
- 响应用户交互（刷新、设置、退出）

#### 2. `GoldPriceService`
封装 AllTick 金价 API 调用：
- 端点：`GET https://quote.alltick.co/quote-b-api/trade-tick`
- 参数：`token`（API Key）+ `query`（URL-encoded JSON）
- 返回：`GoldPriceResult`（价格 USD/oz、时间戳、序列号）
- 错误处理：网络、HTTP、API 级别错误分别映射为 `GoldPriceError`

#### 3. `CurrencyService`
封装免费汇率 API 调用：
- 端点：`GET https://open.er-api.com/v6/latest/USD`
- 缓存策略：1 小时内复用缓存值
- 支持 `forceRefresh` 强制刷新

#### 4. `Preferences`
UserDefaults 的强类型封装：
- `apiKey` — AllTick API 密钥
- `exchangeRateMode` — "auto" 或 "manual"
- `manualExchangeRate` — 手动设定的汇率
- `lastExchangeRate` / `lastExchangeRateUpdate` — 缓存的汇率及时间
- `refreshInterval` — 刷新间隔（秒）

#### 5. `SettingsWindowController`
使用纯代码（无 Storyboard/XIB）构建的设置窗口：
- NSLayoutConstraint 自动布局
- 保存/取消操作
- 实时反映设置变更

## 数据流

```
定时器触发 (每 15 秒)
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
    │  auto  → 缓存的汇率 (如过期则先调用 CurrencyService)
    │  manual → 用户手动输入的值
    │
    ▼
计算: RMB/g = USD/oz × rate ÷ 31.1034768
    │
    ▼
更新 UI:
  • statusItem.button?.title = "Au ¥XXX.X/g"
  • 下拉菜单各项信息
```

## 构建

### 前提条件

- macOS 13.0+
- Xcode 15.0+ 或 Command Line Tools（提供 `swiftc`）
- 可通过 `xcode-select --install` 安装 Command Line Tools

### 构建命令

```bash
# 调试构建（含符号信息）
./build.sh

# 发布构建（优化）
./build.sh release

# 构建并启动
./build.sh run
```

### 构建脚本详解

`build.sh` 执行以下步骤：

1. **编译** — 使用 `swiftc` 将所有 `.swift` 文件编译为单一可执行文件
2. **Bundle** — 创建 `.app` Bundle 结构：
   ```
   GoldBar.app/
   └── Contents/
       ├── Info.plist
       ├── PkgInfo
       └── MacOS/
           └── GoldBar          # 可执行文件
   ```
3. **签名** — 执行 ad-hoc code signing（本地运行必需）
4. **启动**（可选）— `./build.sh run`

### 编译选项

| 模式 | Swift 标志 | 产物位置 |
|------|-----------|---------|
| debug | `-Onone -g` | `build/GoldBar.app` |
| release | `-O -whole-module-optimization` | `build/GoldBar.app` |

## API 参考

### AllTick 金价 API

```
GET https://quote.alltick.co/quote-b-api/trade-tick
  ?token=<api_key>
  &query=<url_encoded_json>
```

**Query JSON 格式：**
```json
{
  "trace": "<uuid>",
  "data": {
    "symbol_list": [{"code": "GOLD"}]
  }
}
```

**成功响应 (200)：**
```json
{
  "ret": 200,
  "msg": "ok",
  "data": {
    "tick_list": [{
      "code": "GOLD",
      "seq": "24618487",
      "tick_time": "1781166146694",   // 毫秒时间戳
      "price": "4101.91",             // USD/盎司
      "volume": "8.00",
      "turnover": "32815.28",
      "trade_direction": 1
    }]
  }
}
```

**错误码：**
| ret | 含义 |
|-----|------|
| 200 | 成功 |
| 202 | 参数无效 |
| 403 | Token 无效 |
| 429 | 频率限制 |
| 604 | 代码未授权 |

### 免费汇率 API

```
GET https://open.er-api.com/v6/latest/USD
```

**响应：**
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

## 扩展指南

### 添加新的贵金属品种

1. 在 `GoldPriceService.swift` 中添加新的 symbol（如 `SILVER`、`PLATINUM`）
2. 或支持批量查询多个 code：
   ```swift
   "symbol_list": [{"code": "GOLD"}, {"code": "SILVER"}]
   ```
3. 相应更新 `MenuBarController` 的显示逻辑

### 添加其他显示单位

修改 `MenuBarController.updateDisplay(with:)` 中的转换公式：
```swift
// 当前：人民币/克
let value = result.priceUSDPerOunce * rate / troyOunceToGrams

// 可选：人民币/盎司
let value = result.priceUSDPerOunce * rate

// 可选：美元/克
let value = result.priceUSDPerOunce / troyOunceToGrams
```

### 添加 WebSocket 支持

AllTick 也提供 WebSocket 实时推送。如需更快的更新速度：
1. 参考 `alltick-api/websocket_interface/` 下的文档
2. 创建 `WebSocketService.swift` 使用 `URLSessionWebSocketTask`
3. 在 `MenuBarController` 中替换 Timer 为 WebSocket 订阅

## 测试

### API 测试脚本

```bash
# 测试金价 API
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

# 测试汇率 API
curl -s "https://open.er-api.com/v6/latest/USD" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'USD/CNY: {d[\"rates\"][\"CNY\"]}')
"
```

### 手动功能测试清单

- [ ] 应用启动后菜单栏是否显示金价
- [ ] 下拉菜单是否正确显示价格、汇率、时间
- [ ] "立即刷新" 是否触发数据更新
- [ ] 设置窗口能否正常打开
- [ ] 修改 API Key 后是否正确生效
- [ ] 修改汇率模式（自动↔手动）是否正常切换
- [ ] 手动输入汇率后价格是否正确换算
- [ ] "退出 GoldBar" 是否正常退出

## 许可证

本项目仅供个人使用。
