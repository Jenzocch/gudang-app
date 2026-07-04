-- ============================================================
-- SJA (珍珠奶茶原料) 生產系統 — 完全照業務流程設計
--
-- 流程：混合 (Mix) → 包裝 (Package) → 檢驗 (QC)
-- 產品主檔：珍珠粉、塊根粉、調味料等原料產品編號
-- 庫存 = 生產總量 − 出貨總量（View 自動計算）
--
-- ⚠️ 在 gudang 專案執行（網址含 klswfuzuhlowzrbncreu）
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- 1) 產品主檔 (SJA 的珍珠奶茶原料產品)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sja_products (
  code TEXT PRIMARY KEY,              -- 產品編號 sja-pearl-1kg 等
  product_name TEXT NOT NULL,         -- 珍珠粉 1kg / 塊根粉 5kg / 調味料標準包
  product_type TEXT,                  -- pearl / tapioca / seasoning / finished
  unit TEXT DEFAULT 'kg',             -- kg / pack / bag
  pack_ctn INT DEFAULT 1,             -- 每箱包數
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- ──────────────────────────────────────────────────────────
-- 2) 生產記錄 (= Mix + Package + QC 一筆記錄)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sja_production (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  batch_lot_no TEXT,                  -- 批號（例如 SJA-2026-07-001，你們自己編）
  formula_version TEXT,               -- 配方版本（例如 V2.1）

  -- 投入原料 (kg)
  pearl_powder_kg NUMERIC DEFAULT 0,  -- 珍珠粉
  tapioca_powder_kg NUMERIC DEFAULT 0,-- 塊根粉
  seasoning_kg NUMERIC DEFAULT 0,     -- 調味料
  total_input_kg NUMERIC GENERATED ALWAYS AS (
    COALESCE(pearl_powder_kg,0) + COALESCE(tapioca_powder_kg,0) + COALESCE(seasoning_kg,0)
  ) STORED,

  -- 混合步驟
  mix_temperature NUMERIC,            -- 混合溫度 (°C)
  mix_time_minutes INT,               -- 混合時間 (分鐘)
  mix_staff TEXT,
  mix_note TEXT,

  -- 包裝步驟
  pack_spec TEXT,                     -- 包裝規格 (1kg / 5kg / 10kg)
  pack_qty INT DEFAULT 0,             -- 包數量
  total_output_kg NUMERIC GENERATED ALWAYS AS (
    CASE WHEN pack_spec LIKE '%5kg%' THEN pack_qty * 5
         WHEN pack_spec LIKE '%10kg%' THEN pack_qty * 10
         ELSE pack_qty * 1 END
  ) STORED,
  pack_staff TEXT,
  pack_note TEXT,

  -- 檢驗步驟
  qc_result TEXT,                     -- 通過 / 不通過
  qc_staff TEXT,
  qc_note TEXT,

  -- 總體
  status TEXT DEFAULT 'in_progress',  -- in_progress / completed / rejected
  staff TEXT,                         -- 主操作人
  note TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sja_production_date ON sja_production(date);
CREATE INDEX IF NOT EXISTS idx_sja_production_batch ON sja_production(batch_lot_no);

-- ──────────────────────────────────────────────────────────
-- 3) 出貨記錄 (SJA 成品出貨)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sja_delivery (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  batch_lot_no TEXT,                  -- 與 sja_production 的 batch_lot_no 對應
  customer_name TEXT,
  pack_spec TEXT,                     -- 1kg / 5kg / 10kg
  qty INT DEFAULT 0,                  -- 出貨包數
  kg NUMERIC DEFAULT 0,               -- 出貨 KG
  driver TEXT,
  vehicle_no TEXT,
  note TEXT,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sja_delivery_date ON sja_delivery(date);
CREATE INDEX IF NOT EXISTS idx_sja_delivery_batch ON sja_delivery(batch_lot_no);

-- ──────────────────────────────────────────────────────────
-- 4) 庫存彙總 View (自動計算)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW sja_stock_summary AS
SELECT
  COALESCE(pr.pack_spec, dl.pack_spec) AS pack_spec,
  COALESCE(pr.produced_qty, 0) AS total_produced_qty,
  COALESCE(pr.produced_kg, 0)  AS total_produced_kg,
  COALESCE(dl.delivered_qty, 0) AS total_delivered_qty,
  COALESCE(dl.delivered_kg, 0) AS total_delivered_kg,
  COALESCE(pr.produced_qty, 0) - COALESCE(dl.delivered_qty, 0) AS stock_qty,
  COALESCE(pr.produced_kg, 0) - COALESCE(dl.delivered_kg, 0) AS stock_kg
FROM (
  SELECT pack_spec, SUM(pack_qty) AS produced_qty, SUM(total_output_kg) AS produced_kg
  FROM sja_production WHERE status='completed' GROUP BY pack_spec
) pr
FULL OUTER JOIN (
  SELECT pack_spec, SUM(qty) AS delivered_qty, SUM(kg) AS delivered_kg
  FROM sja_delivery GROUP BY pack_spec
) dl ON dl.pack_spec = pr.pack_spec;

-- ──────────────────────────────────────────────────────────
-- 5) 月報 View (自動彙總)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW sja_monthly_report AS
SELECT
  to_char(date, 'YYYY-MM') AS bulan,
  SUM(total_input_kg) AS input_kg,
  SUM(total_output_kg) AS output_kg,
  ROUND(SUM(total_output_kg) / NULLIF(SUM(total_input_kg), 0) * 100, 1) AS yield_pct,
  COUNT(CASE WHEN qc_result='通過' THEN 1 END) AS qc_pass,
  COUNT(CASE WHEN qc_result='不通過' THEN 1 END) AS qc_fail
FROM sja_production
GROUP BY to_char(date, 'YYYY-MM')
ORDER BY 1 DESC;

-- ──────────────────────────────────────────────────────────
-- 6) 權限
-- ──────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sja_products    TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sja_production  TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sja_delivery    TO anon, authenticated;
GRANT SELECT ON public.sja_stock_summary  TO anon, authenticated;
GRANT SELECT ON public.sja_monthly_report TO anon, authenticated;

-- ──────────────────────────────────────────────────────────
-- 7) 種子資料：SJA 常見產品（可根據實際情況調整）
-- ──────────────────────────────────────────────────────────
INSERT INTO sja_products (code, product_name, product_type, unit, pack_ctn) VALUES
('sja-pearl-1kg',      '珍珠粉 1kg',           'pearl',    'kg', 1),
('sja-pearl-5kg',      '珍珠粉 5kg',           'pearl',    'kg', 1),
('sja-tapioca-1kg',    '塊根粉 1kg',           'tapioca',  'kg', 1),
('sja-tapioca-5kg',    '塊根粉 5kg',           'tapioca',  'kg', 1),
('sja-seasoning-500g', '調味料標準包 500g',   'seasoning','pack', 10),
('sja-finished-1kg',   '珍珠奶茶粉 1kg (成品)', 'finished', 'pack', 10),
('sja-finished-5kg',   '珍珠奶茶粉 5kg (成品)', 'finished', 'pack', 4)
ON CONFLICT (code) DO NOTHING;

-- ── 驗證 ──
-- SELECT * FROM sja_products ORDER BY product_name;
-- SELECT * FROM sja_stock_summary;
-- SELECT * FROM sja_monthly_report;
