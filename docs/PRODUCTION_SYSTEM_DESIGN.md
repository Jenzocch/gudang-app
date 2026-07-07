# 🏭 多公司生產系統 - 設計文檔

## 概述

一套系統支持三家公司（DIN、SJA、OLENTIA）的生產→倉庫→出貨流程：
- **生產模組**：每家公司自訂生產步驟和參數
- **共用倉庫**：三家公司的貨物匯聚到同一個倉庫
- **出貨模組**：按客戶打包出貨，完整批號追蹤

---

## 業務流程

### DIN — 椰果加工流

```
椰果原料 (採購)
    ↓
生產步驟 1: 壓倍 (PRESS)
  - 溫度、壓力、時間
  - 結果：脫水椰果
    ↓
生產步驟 2: 復水 (REHYDRATE)
  - 水溫、浸泡時間、水質
  - 結果：復水椰果
    ↓
生產步驟 3: 切割 (CUT)
  - 切割規格（8mm、10mm、5mm）
  - 切割速度、刀具
  - 結果：規格椰果
    ↓
入倉 (同一批號追蹤)
    ↓
出貨給客戶
```

**生產表單（DIN 自訂）：**
- 溫度（°C）
- 壓力（bar）
- 時間（分鐘）
- 復水時長（小時）
- 水溫（°C）
- 切割規格（8mm / 10mm / 5mm）
- 品質評級（優 / 中 / 差）
- 備註

### SJA — 珍珠奶茶原料混配

```
原料採購 (珍珠粉、塊根粉、調味料)
    ↓
生產步驟 1: 混合 (MIX)
  - 配方版本
  - 各原料比例
  - 混合溫度、時間
    ↓
生產步驟 2: 包裝 (PACKAGE)
  - 包裝規格 (1kg / 5kg / 10kg)
  - 包數
    ↓
生產步驟 3: 檢驗 (QC)
  - 抽樣檢驗結果
  - 通過 / 不通過
    ↓
入倉 (同一批號追蹤)
    ↓
出貨給客戶
```

**生產表單（SJA 自訂）：**
- 配方版本
- 珍珠粉 (kg)
- 塊根粉 (kg)
- 調味料 (kg)
- 混合溫度（°C）
- 混合時間（分鐘）
- 包裝規格
- 包數量
- 檢驗結果（通過 / 不通過）
- 備註

---

## 資料庫架構

### 核心表設計

#### 1️⃣ **customers** — 客戶管理
```
id | warehouse_id | name | contact | email | notes | created_at | updated_at
```
- 每家公司自己管理客戶
- 出貨時直接選客戶

#### 2️⃣ **production_form_templates** — 生產表單定義
```
id | warehouse_id | name | description | is_active | created_at | updated_at
```
例如：
- warehouse_id = "DIN" → name = "椰果加工表"
- warehouse_id = "SJA" → name = "珍珠原料混配表"

#### 3️⃣ **production_form_fields** — 表單欄位
```
id | form_id | field_name | field_label | field_type | required | options | order_index
```
例如（DIN 椰果加工表的欄位）：
```json
[
  {field_name: "temperature", field_label: "溫度 (°C)", field_type: "number", required: true},
  {field_name: "pressure", field_label: "壓力 (bar)", field_type: "number", required: true},
  {field_name: "spec", field_label: "切割規格", field_type: "select", options: ["8mm", "10mm", "5mm"]}
]
```

#### 4️⃣ **production_steps** — 生產步驟
```
id | warehouse_id | step_name | step_code | description | order_index | is_active
```
DIN 的步驟：
```
Step 1: "壓倍" (din_press)
Step 2: "復水" (din_rehydrate)
Step 3: "切割" (din_cut)
```

SJA 的步驟：
```
Step 1: "混合" (sja_mix)
Step 2: "包裝" (sja_package)
Step 3: "檢驗" (sja_qc)
```

#### 5️⃣ **production_records** — 生產記錄（核心）
```
id | warehouse_id | item_id | batch_lot_no | production_date | shift |
operator_id | qty_produced | product_spec | production_form_id | form_data |
status | notes | created_at
```

例如（DIN 生產批號 "DIN-2026-07-001"）：
```json
{
  batch_lot_no: "DIN-2026-07-001",
  production_date: "2026-07-04",
  shift: "早班",
  qty_produced: 500,
  product_spec: "8mm",
  form_data: {
    temperature: 85,
    pressure: 3.5,
    time: 45,
    rehydrate_duration: 2,
    water_temp: 60,
    spec: "8mm",
    quality: "優"
  },
  status: "completed"
}
```

#### 6️⃣ **production_step_records** — 步驟詳細記錄
```
id | production_record_id | step_id | step_name | step_order |
started_at | completed_at | operator_id | duration_minutes | step_data | status
```

例如（DIN-2026-07-001 的壓倍步驟）：
```
step_order: 1
step_name: "壓倍"
started_at: 2026-07-04 08:00:00
completed_at: 2026-07-04 08:45:00
duration_minutes: 45
status: "completed"
step_data: {temperature: 85, pressure: 3.5}
```

#### 7️⃣ **shipments** — 出貨單
```
id | warehouse_id | shipment_no | customer_id | customer_name |
shipment_date | ship_via | status | notes
```

例如：
```
shipment_no: "DIN-SO-2026-07-005"
customer_name: "奶茶店 A"
shipment_date: "2026-07-05"
ship_via: "運送"
status: "shipped"
```

#### 8️⃣ **shipment_items** — 出貨明細
```
id | shipment_id | item_id | production_record_id | qty | unit_price | notes
```

例如：
```
shipment_no: DIN-SO-2026-07-005
  ├─ Item 1: 椰果 (8mm) × 100 個 → 來自批號 DIN-2026-07-001
  ├─ Item 2: 椰果 (10mm) × 50 個 → 來自批號 DIN-2026-07-002
  └─ Item 3: 椰果 (5mm) × 200 個 → 來自批號 DIN-2026-07-001
```

---

## 批號追蹤流程

### 完整追蹤鏈

```
生產記錄
  ↓
batch_lot_no: "DIN-2026-07-001"
production_date: "2026-07-04"
form_data: {temperature: 85, ...}
  ↓
自動入倉 (item_batches)
  lot_no = "DIN-2026-07-001"
  warehouse_id = "DIN"
  qty_remaining = 500
  ↓
出貨時選擇
  shipment_items.production_record_id = "DIN-2026-07-001"
  qty = 100
  ↓
完整追蹤
  - 「批號 DIN-2026-07-001 的椰果（8mm）100 個出給奶茶店 A」
  - 反查：「這批是 2026-07-04 早班生產，溫度 85°C，品質優」
  - 品管：「有問題可追蹤生產人員和詳細工藝參數」
```

---

## UI 設計（前端）

### 1. 生產頁面 (PRODUKSI)

#### 新增生產記錄
```
選擇公司 (DIN / SJA / OLENTIA)
  ↓
選擇商品 (例如 "椰果")
  ↓
選擇表單 (例如 "椰果加工表")
  ↓
填寫表單欄位
  - 溫度 (°C): [  ]
  - 壓力 (bar): [  ]
  - 時間 (分鐘): [  ]
  - ... (DIN 自訂欄位)
  ↓
記錄生產步驟進度
  Step 1: 壓倍 [開始] [完成]
  Step 2: 復水 [開始] [完成]
  Step 3: 切割 [開始] [完成]
  ↓
產量、規格、品質
  ↓
確認生成批號 "DIN-2026-07-001"
  ↓
完成 ✓
```

#### 生產記錄列表
```
日期 | 批號 | 商品 | 產量 | 規格 | 操作人 | 狀態
2026-07-04 | DIN-2026-07-001 | 椰果 | 500 | 8mm | 王小明 | ✓ 完成
2026-07-03 | DIN-2026-06-999 | 椰果 | 300 | 10mm | 李工 | ✓ 完成
```

### 2. 出貨頁面 (SHIPMENT)

#### 新增出貨單
```
選擇公司 (DIN / SJA)
  ↓
選擇客戶 (例如 "奶茶店 A")
  或 新增客戶
  ↓
選擇商品 + 批號
  - 椰果 (8mm) × 100 個 → 批號 DIN-2026-07-001 ✓
  - 椰果 (10mm) × 50 個 → 批號 DIN-2026-07-002 ✓
  ↓
選擇運輸方式 (自取 / 運送 / 快遞)
  ↓
確認出貨 → 生成出貨單 "DIN-SO-2026-07-005"
  ↓
完成 ✓
```

#### 出貨記錄
```
出貨單號 | 客戶 | 日期 | 商品 | 批號 | 數量 | 狀態
DIN-SO-2026-07-005 | 奶茶店 A | 2026-07-05 | 椰果 8mm | DIN-2026-07-001 | 100 | 已出貨
```

### 3. 管理頁面 (ADMIN) - 新增「表單設定」

#### 生產表單管理
```
選擇公司 (DIN / SJA)
  ↓
表單列表
  - 椰果加工表
  - 珍珠原料混配表
  ↓
[+ 新增表單]
  ↓
編輯表單欄位
  - [+ 新增欄位]
  - 欄位名稱: [  ]
  - 標籤: [  ]
  - 類型: [文字 / 數字 / 選擇]
  - 必填: [是 / 否]
  - 順序: [  ]
  ↓
保存 ✓
```

#### 生產步驟管理
```
選擇公司 (DIN / SJA)
  ↓
步驟列表
  - 壓倍 (din_press)
  - 復水 (din_rehydrate)
  - 切割 (din_cut)
  ↓
[+ 新增步驟]
  ↓
編輯步驟
  - 步驟名稱: [  ]
  - 步驟代碼: [  ]
  - 順序: [  ]
  ↓
保存 ✓
```

---

## 實現順序

### Phase 1: 後端架構
1. ✅ 資料庫表設計（本文檔）
2. 在 Supabase 執行 MIGRATION_PRODUCTION_SYSTEM.sql
3. 寫 Supabase Edge Functions：
   - `manage-production-form` — 表單 CRUD
   - `manage-production-records` — 生產記錄 CRUD
   - `manage-shipments` — 出貨單 CRUD

### Phase 2: 前端 UI
1. 新增「生產 (PRODUKSI)」頁面
2. 新增「出貨 (SHIPMENT)」頁面
3. 擴展「管理 (ADMIN)」頁面 → 新增「表單設定」

### Phase 3: 整合
1. 生產完成 → 自動入倉
2. 出貨時綁定批號
3. 完整追蹤查詢

---

## 批號命名規則

| 公司 | 格式 | 範例 |
|------|------|------|
| DIN | DIN-YYYY-MM-NNN | DIN-2026-07-001 |
| SJA | SJA-YYYY-MM-NNN | SJA-2026-07-042 |
| OLENTIA | OL-YYYY-MM-NNN | OL-2026-07-015 |

出貨單號：`{公司}-SO-YYYY-MM-NNN`
- DIN-SO-2026-07-001
- SJA-SO-2026-07-008

---

## 備註

- **生產時的「多步驟」**: DIN 壓倍→復水→切割，系統支持記錄每步的開始/完成時間和操作人
- **靈活欄位**: 每家公司可自訂表單欄位，不用改程式
- **批號追蹤**: 從生產 → 庫存 → 出貨，完整追溯
- **權限**: 員工只能看自己公司的生產/出貨；管理員可改表單設定
