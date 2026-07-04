-- ============================================================
-- 多公司生產系統 - 資料庫架構
-- 支援：
--   1. 生產表單自訂（每家公司不同的生產步驟）
--   2. 批號完整追蹤（生產 → 庫存 → 出貨 → 客戶）
--
-- DIN：椰果壓倍→復水→切規格（多步驟）
-- SJA：珍珠奶茶原料（單步或多步）
--
-- 執行順序：
--   1. 先跑本 SQL 檔
--   2. 重新部署前端
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- 1) 客戶表 (共用)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id TEXT NOT NULL,
  name TEXT NOT NULL,
  contact TEXT,
  email TEXT,
  notes TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_customers_warehouse ON customers(warehouse_id);

-- ──────────────────────────────────────────────────────────
-- 2) 生產表單範本定義 (每家公司不同)
-- ──────────────────────────────────────────────────────────
-- 範例：DIN 有「壓倍」「復水」「切割」三個步驟
--      SJA 有「混合」「煮沸」「冷卻」三個步驟
--
-- 結構：
--   production_form_templates = 定義表單欄位（誰能編輯？）
--   production_form_fields = 每個表單的各個欄位（名稱、類型、必填等）
--   production_steps = 定義每家公司的「生產步驟」（壓倍、復水等）

CREATE TABLE IF NOT EXISTS production_form_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id TEXT NOT NULL,
  name TEXT NOT NULL,  -- 例如 "DIN 椰果工藝流"、"SJA 原料混配"
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(warehouse_id, name)
);

CREATE INDEX IF NOT EXISTS idx_form_templates_warehouse ON production_form_templates(warehouse_id);

-- 表單內的欄位定義
CREATE TABLE IF NOT EXISTS production_form_fields (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  form_id UUID NOT NULL REFERENCES production_form_templates(id) ON DELETE CASCADE,
  field_name TEXT NOT NULL,          -- 例如 "temperature", "weight", "duration"
  field_label TEXT NOT NULL,         -- 例如 "溫度 (°C)", "重量 (kg)", "時間 (分鐘)"
  field_type TEXT DEFAULT 'text',    -- text / number / select / date / time
  required BOOLEAN DEFAULT false,
  options JSONB,                     -- 如果 field_type='select'，存 ["選項1", "選項2"]
  order_index INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_form_fields_form ON production_form_fields(form_id);

-- 生產步驟（DIN 的「壓倍」「復水」「切割」）
CREATE TABLE IF NOT EXISTS production_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id TEXT NOT NULL,
  step_name TEXT NOT NULL,           -- 例如 "壓倍", "復水", "切割"
  step_code TEXT NOT NULL,           -- 例如 "din_press", "din_rehydrate"
  description TEXT,
  order_index INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(warehouse_id, step_code)
);

CREATE INDEX IF NOT EXISTS idx_production_steps_warehouse ON production_steps(warehouse_id);

-- ──────────────────────────────────────────────────────────
-- 3) 生產記錄 (核心表)
-- ──────────────────────────────────────────────────────────
-- 每筆生產記錄可能包含多個步驟（例如 DIN 要記錄壓倍→復水→切割）
-- 或單一步驟（例如混合）

CREATE TABLE IF NOT EXISTS production_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id TEXT NOT NULL,
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  batch_lot_no TEXT NOT NULL,        -- 生產批號（例如 "DIN-2026-07-001"）
  production_date DATE NOT NULL,
  shift TEXT,                        -- "早班", "晚班", "夜班"（可選）
  operator_id UUID REFERENCES people(id),
  operator_name TEXT,
  qty_produced INT NOT NULL,         -- 生產數量
  product_spec TEXT,                 -- 例如 DIN 切割後的規格 "8mm", "10mm", "5mm"
  production_form_id UUID REFERENCES production_form_templates(id),
  form_data JSONB,                   -- 該批次的生產參數（溫度、時間等）
  status TEXT DEFAULT 'in_progress', -- in_progress / completed / rejected
  notes TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_production_records_warehouse ON production_records(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_production_records_item ON production_records(item_id);
CREATE INDEX IF NOT EXISTS idx_production_records_lot ON production_records(batch_lot_no);
CREATE INDEX IF NOT EXISTS idx_production_records_date ON production_records(production_date);

-- 生產步驟記錄（記錄該批貨經歷的每個步驟）
-- 例如：生產單 "DIN-2026-07-001"
--       → Step 1: 壓倍 (2026-07-04 09:00, 完成)
--       → Step 2: 復水 (2026-07-04 12:00, 完成)
--       → Step 3: 切割 (2026-07-04 14:00, 未完成)

CREATE TABLE IF NOT EXISTS production_step_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  production_record_id UUID NOT NULL REFERENCES production_records(id) ON DELETE CASCADE,
  step_id UUID REFERENCES production_steps(id),
  step_name TEXT,
  step_order INT,
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  operator_id UUID REFERENCES people(id),
  operator_name TEXT,
  duration_minutes INT,
  step_data JSONB,                   -- 該步驟的詳細參數（例如壓力、時間）
  status TEXT DEFAULT 'pending',     -- pending / in_progress / completed / failed
  notes TEXT,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_step_records_production ON production_step_records(production_record_id);
CREATE INDEX IF NOT EXISTS idx_step_records_step ON production_step_records(step_id);

-- ──────────────────────────────────────────────────────────
-- 4) 出貨管理 (客戶端、出貨單)
-- ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS shipments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  warehouse_id TEXT NOT NULL,
  shipment_no TEXT NOT NULL,         -- 出貨單號（例如 "DIN-SO-2026-07-001"）
  customer_id UUID REFERENCES customers(id),
  customer_name TEXT,
  shipment_date DATE NOT NULL,
  ship_via TEXT,                     -- 運輸方式 "自取", "運送", "快遞"
  status TEXT DEFAULT 'pending',     -- pending / shipped / delivered / cancelled
  notes TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(warehouse_id, shipment_no)
);

CREATE INDEX IF NOT EXISTS idx_shipments_warehouse ON shipments(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_shipments_customer ON shipments(customer_id);
CREATE INDEX IF NOT EXISTS idx_shipments_date ON shipments(shipment_date);

-- 出貨明細（一個出貨單包含多個商品）
-- 每筆明細綁定生產批號，可完全追蹤「這批商品是哪批生產的」
CREATE TABLE IF NOT EXISTS shipment_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shipment_id UUID NOT NULL REFERENCES shipments(id) ON DELETE CASCADE,
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE RESTRICT,
  production_record_id UUID REFERENCES production_records(id),  -- 綁定生產批號
  qty INT NOT NULL,
  unit_price NUMERIC(12, 2),         -- 出貨單價
  notes TEXT,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shipment_items_shipment ON shipment_items(shipment_id);
CREATE INDEX IF NOT EXISTS idx_shipment_items_item ON shipment_items(item_id);
CREATE INDEX IF NOT EXISTS idx_shipment_items_production ON shipment_items(production_record_id);

-- ──────────────────────────────────────────────────────────
-- 5) 生產批號到庫存的銜接
-- ──────────────────────────────────────────────────────────
-- 當生產記錄完成 → 自動新增到 item_batches
-- item_batches 的 lot_no = production_records 的 batch_lot_no
-- 這樣就能完整追蹤：生產 → 庫存 → 出貨

-- 注意：item_batches 已存在（在 MIGRATION_SHARED_INVENTORY.md）
-- 只需確保 item_batches 和 production_records 共用批號

-- ──────────────────────────────────────────────────────────
-- 6) 權限控制（擴展 people 表）
-- ──────────────────────────────────────────────────────────
-- 假設 people 表已有 perms JSONB 欄位
-- 擴展權限定義：
--   perms[warehouse_id].production_record = true/false
--   perms[warehouse_id].shipment = true/false

-- 若尚未有 perms 欄位，執行：
-- ALTER TABLE people ADD COLUMN IF NOT EXISTS perms jsonb DEFAULT '{}'::jsonb;
-- GRANT SELECT (perms) ON public.people TO anon, authenticated;

-- ──────────────────────────────────────────────────────────
-- 7) 驗證及索引權限
-- ──────────────────────────────────────────────────────────

GRANT SELECT ON public.customers TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.customers TO authenticated;

GRANT SELECT ON public.production_form_templates TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.production_form_templates TO authenticated;

GRANT SELECT ON public.production_form_fields TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.production_form_fields TO authenticated;

GRANT SELECT ON public.production_steps TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.production_steps TO authenticated;

GRANT SELECT ON public.production_records TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.production_records TO authenticated;

GRANT SELECT ON public.production_step_records TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.production_step_records TO authenticated;

GRANT SELECT ON public.shipments TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.shipments TO authenticated;

GRANT SELECT ON public.shipment_items TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.shipment_items TO authenticated;

-- ──────────────────────────────────────────────────────────
-- 驗證新表
-- ──────────────────────────────────────────────────────────
-- SELECT * FROM customers;
-- SELECT * FROM production_form_templates;
-- SELECT * FROM production_steps;
-- SELECT * FROM production_records;
-- SELECT * FROM shipments;
