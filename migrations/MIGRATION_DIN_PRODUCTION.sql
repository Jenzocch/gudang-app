-- ============================================================
-- DIN (Denikin) 椰果生產系統 — 完全照 DIN_Nata_Production.xlsx 結構
--
-- 流程：復水 (Rehidrasi) → 生產切割 (Production) → 出貨 (Delivery)
-- 產品主檔：每個客戶有專屬產品編號（客戶代碼+規格+KG/袋+壓倍係數）
-- 庫存 = 生產總量 − 出貨總量（View 自動計算）
--
-- ⚠️ 在 gudang 專案執行（網址含 klswfuzuhlowzrbncreu）
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- 1) 產品主檔 (= Excel 的 Products 分頁)
--    編號規則：{客戶代碼}{規格}{KG/袋}p{壓倍}，例如 ab6c4p7
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS din_products (
  code TEXT PRIMARY KEY,              -- 產品編號 ab6c4p7
  customer_name TEXT NOT NULL,        -- AIBM
  customer_code TEXT NOT NULL,        -- ab
  item TEXT,                          -- 6c4p7
  item_name TEXT NOT NULL,            -- 6-8mm Cube P7
  label_item TEXT,                    -- D209350 (4kg/bag)
  pack_ctn INT DEFAULT 4,             -- 每箱袋數
  kg_per_bag NUMERIC DEFAULT 4,       -- 每袋 KG
  press_factor NUMERIC DEFAULT 1,     -- 壓倍係數 (7/5/4/1=Non Press)
  nata_kering_kg NUMERIC,             -- 乾椰果 KG
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- ──────────────────────────────────────────────────────────
-- 2) 復水記錄 (= Excel 的 Rehidrasi 分頁)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS din_rehidrasi (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  drum_in INT DEFAULT 0,              -- 入桶數
  bag_in INT DEFAULT 0,               -- 入袋數
  rehidrasi_kg NUMERIC DEFAULT 0,     -- 復水投入 KG
  jadi_basah_kg NUMERIC DEFAULT 0,    -- 成品濕重 KG
  -- 得率 % 自動算：濕重 / 復水投入
  hasil_pct NUMERIC GENERATED ALWAYS AS (
    CASE WHEN rehidrasi_kg > 0 THEN ROUND(jadi_basah_kg / rehidrasi_kg * 100, 1) ELSE NULL END
  ) STORED,
  note TEXT,
  staff TEXT,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_din_rehidrasi_date ON din_rehidrasi(date);

-- ──────────────────────────────────────────────────────────
-- 3) 生產記錄 (= Excel 的 Production 分頁)
--    Batch_No 例 A2613D4、Lot_No 例 260530A-29、Tank D1~D6
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS din_production (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  product_code TEXT NOT NULL REFERENCES din_products(code),
  batch_no TEXT,                      -- A2613D4
  lot_no TEXT,                        -- 260530A-29
  tank_id TEXT,                       -- D1~D6
  bags INT DEFAULT 0,                 -- 袋數
  kg_per_bag NUMERIC DEFAULT 0,       -- 每袋 KG（帶入產品主檔，可改）
  total_kg NUMERIC GENERATED ALWAYS AS (bags * kg_per_bag) STORED,
  pressed_bags INT,                   -- 壓縮袋數
  pressed_kg_per_bag NUMERIC,         -- 壓縮每袋 KG
  press_factor NUMERIC,               -- 壓倍係數（帶入產品主檔）
  -- 壓縮原始 KG = 壓縮袋數 × 每袋 KG × 壓倍
  pressed_original_kg NUMERIC GENERATED ALWAYS AS (
    COALESCE(pressed_bags,0) * COALESCE(pressed_kg_per_bag,0) * COALESCE(press_factor,0)
  ) STORED,
  staff TEXT,
  note TEXT,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_din_production_date ON din_production(date);
CREATE INDEX IF NOT EXISTS idx_din_production_product ON din_production(product_code);
CREATE INDEX IF NOT EXISTS idx_din_production_lot ON din_production(lot_no);

-- ──────────────────────────────────────────────────────────
-- 4) 出貨記錄 (= Excel 的 Delivery 分頁)
--    lot_no 可逗號分隔多個批號（一次出貨混多批）
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS din_delivery (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  product_code TEXT NOT NULL REFERENCES din_products(code),
  lot_no TEXT,                        -- 260530A-29,260531A-30
  bags INT DEFAULT 0,
  ctn INT DEFAULT 0,                  -- 箱數
  kg NUMERIC DEFAULT 0,
  driver TEXT,
  vehicle_no TEXT,
  note TEXT,
  created_at TIMESTAMP DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_din_delivery_date ON din_delivery(date);
CREATE INDEX IF NOT EXISTS idx_din_delivery_product ON din_delivery(product_code);

-- ──────────────────────────────────────────────────────────
-- 5) 重工記錄 (= Excel 的 Rework 分頁，先建表備用)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS din_rework (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date DATE NOT NULL,
  product_code TEXT REFERENCES din_products(code),
  lot_no TEXT,
  kg NUMERIC DEFAULT 0,
  reason TEXT,
  staff TEXT,
  note TEXT,
  created_at TIMESTAMP DEFAULT now()
);

-- ──────────────────────────────────────────────────────────
-- 6) 庫存彙總 View (= Excel 的 Stock_Summary 分頁，自動計算)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW din_stock_summary AS
SELECT
  p.code AS product_code,
  p.customer_name,
  p.customer_code,
  p.item_name,
  COALESCE(pr.produced_kg, 0)  AS total_produced_kg,
  COALESCE(pr.produced_bags, 0) AS total_produced_bags,
  COALESCE(dl.delivered_kg, 0) AS total_delivered_kg,
  COALESCE(dl.delivered_bags, 0) AS total_delivered_bags,
  COALESCE(pr.produced_kg, 0) - COALESCE(dl.delivered_kg, 0) AS stock_kg,
  COALESCE(pr.produced_bags, 0) - COALESCE(dl.delivered_bags, 0) AS stock_bags
FROM din_products p
LEFT JOIN (
  SELECT product_code, SUM(total_kg) AS produced_kg, SUM(bags) AS produced_bags
  FROM din_production GROUP BY product_code
) pr ON pr.product_code = p.code
LEFT JOIN (
  SELECT product_code, SUM(kg) AS delivered_kg, SUM(bags) AS delivered_bags
  FROM din_delivery GROUP BY product_code
) dl ON dl.product_code = p.code
WHERE p.is_active;

-- ──────────────────────────────────────────────────────────
-- 7) 月報 View (= Excel 的 Monthly Report 分頁，自動計算)
--    復水KG、濕重KG、得率%、生產KG、損耗KG、損耗%
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW din_monthly_report AS
SELECT
  COALESCE(r.bulan, pr.bulan) AS bulan,
  COALESCE(r.rehidrasi_kg, 0) AS rehidrasi_kg,
  COALESCE(r.basah_kg, 0)     AS basah_kg,
  CASE WHEN COALESCE(r.rehidrasi_kg,0) > 0
    THEN ROUND(r.basah_kg / r.rehidrasi_kg * 100, 1) ELSE NULL END AS hasil_pct,
  COALESCE(pr.produksi_kg, 0) AS produksi_kg,
  COALESCE(pr.produksi_kg, 0) - COALESCE(r.basah_kg, 0) AS susut_kg,
  CASE WHEN COALESCE(r.basah_kg,0) > 0
    THEN ROUND((pr.produksi_kg - r.basah_kg) / r.basah_kg * 100, 1) ELSE NULL END AS susut_pct
FROM (
  SELECT to_char(date, 'YYYY-MM') AS bulan,
         SUM(rehidrasi_kg) AS rehidrasi_kg, SUM(jadi_basah_kg) AS basah_kg
  FROM din_rehidrasi GROUP BY 1
) r
FULL OUTER JOIN (
  SELECT to_char(date, 'YYYY-MM') AS bulan, SUM(total_kg) AS produksi_kg
  FROM din_production GROUP BY 1
) pr ON pr.bulan = r.bulan
ORDER BY 1 DESC;

-- ──────────────────────────────────────────────────────────
-- 8) 權限
-- ──────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.din_products   TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.din_rehidrasi  TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.din_production TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.din_delivery   TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.din_rework     TO anon, authenticated;
GRANT SELECT ON public.din_stock_summary  TO anon, authenticated;
GRANT SELECT ON public.din_monthly_report TO anon, authenticated;

-- ──────────────────────────────────────────────────────────
-- 9) 種子資料：現有 31 個產品主檔（來自 Excel Products 分頁）
-- ──────────────────────────────────────────────────────────
INSERT INTO din_products (code, customer_name, customer_code, item, item_name, label_item, pack_ctn, kg_per_bag, press_factor, nata_kering_kg) VALUES
('ab3s4p7',    'AIBM',               'ab',    '3s4p7',    '0.3 Serut P7',   'D273501 (4kg/bag)',                            4, 4, 7, 4),
('ab6c4p7',    'AIBM',               'ab',    '6c4p7',    '6-8mm Cube P7',  'D209350 (4kg/bag)',                            4, 4, 7, 4),
('ab3c4p7',    'AIBM',               'ab',    '3c4p7',    '0.3 Cube P7',    'D271801 (4kg/bag)',                            4, 4, 7, 4),
('ab3s5p7',    'AIBM-Palembang',     'abplb', '3s5p7',    '0.3 Serut P7',   NULL,                                           5, 5, 7, 5),
('id3c5p7',    'Indolakto',          'id',    '3c5p7',    '0.3 Cube P7',    'D271801 (5kg/bag)',                            4, 5, 7, 5),
('id3c4p7',    'Indolakto',          'id',    '3c4p7',    '0.3 Cube P7',    'D271801 (4kg/bag)',                            4, 4, 7, 4),
('gabgr3c5p5', 'Garuda-Bogor',       'gabgr', '3c5p5',    '0.3 Cube P5',    'NDC 21 (5KG/Bag)',                             4, 5, 5, 5),
('gabgr3c4p5', 'Garuda-Bogor',       'gabgr', '3c4p5',    '0.3 Cube P5',    'NDC 21 (4KG/Bag)',                             4, 4, 5, 4),
('gapti3c5p5', 'Garuda-Pati',        'gapti', '3c5p5',    '0.3 Cube P5',    'NDC 21 (5KG/Bag)',                             4, 5, 5, 5),
('gapti3c4p5', 'Garuda-Pati',        'gapti', '3c4p5',    '0.3 Cube P5',    'NDC 21 (4KG/Bag)',                             4, 4, 5, 4),
('gasdj3c5p5', 'Garuda-Sidoarjo',    'gasdj', '3c5p5',    '0.3 Cube P5',    'NDC 21 (5KG/Bag)',                             4, 5, 5, 5),
('gasdj3c4p5', 'Garuda-Sidoarjo',    'gasdj', '3c4p5',    '0.3 Cube P5',    'NDC 21 (4KG/Bag)',                             4, 4, 5, 4),
('gagwa3c5p5', 'Garuda-Gowa',        'gagwa', '3c5p5',    '0.3 Cube P5',    'NDC 21 (5KG/Bag)',                             4, 5, 5, 5),
('gagwa3c4p5', 'Garuda-Gowa',        'gagwa', '3c4p5',    '0.3 Cube P5',    'NDC 21 (4KG/Bag)',                             4, 4, 5, 4),
('gabjr3c5p5', 'Garuda-Banjarmasin', 'gabjr', '3c5p5',    '0.3 Cube P5',    'NDC 21 (5KG/Bag)',                             4, 5, 5, 5),
('gabjr3c4p5', 'Garuda-Banjarmasin', 'gabjr', '3c4p5',    '0.3 Cube P5',    'NDC 21 (4KG/Bag)',                             4, 4, 5, 4),
('gapkb3c5p5', 'Garuda-Pekanbaru',   'gapkb', '3c5p5',    '0.3 Cube P5',    'NDC 21 (5KG/Bag)',                             4, 5, 5, 5),
('gapkb3c4p5', 'Garuda-Pekanbaru',   'gapkb', '3c4p5',    '0.3 Cube P5',    'NDC 21 (4KG/Bag)',                             4, 4, 5, 4),
('dm3c5p1',    'Diamond',            'dm',    '3c5p1',    '0.3 Cube Non P', 'Nata de Coco 3x3x3 (3.75kg/bag)',              4, 5, 1, 4),
('dm5c5p1',    'Diamond',            'dm',    '5c5p1',    '0.5 Cube Non P', 'Nata de Coco 5x5mm (3.75kg/bag)',              4, 5, 1, 3.8),
('dm3c4p1',    'Diamond',            'dm',    '3c4p1',    '0.3 Cube Non P', 'Nata de Coco 3x3x3 (3kg/bag)',                 4, 3, 1, 3),
('dm5c4p1',    'Diamond',            'dm',    '5c4p1',    '0.5 Cube Non P', 'Nata de Coco 5x5mm (3kg/bag)',                 4, 3, 1, 3),
('cm3c5p1',    'Cimory',             'cm',    '3c5p1',    '0.3 Cube Non P', 'RM100118 Nata De Coco 3mm (5kg/bag)',          4, 5, 1, 4),
('cm3c4p1',    'Cimory',             'cm',    '3c4p1',    '0.3 Cube Non P', 'RM100118 Nata De Coco 3mm (4kg/bag)',          5, 4, 1, 3),
('cotg12c5p5', 'COTG',               'cotg',  '12c5p5',   '1.2 Cube P5',    'Nata De Coco Press 5 1.2x1.1x1.0cm (5kg/bag)', 4, 5, 5, 5),
('cotg3c5p5',  'COTG',               'cotg',  '3c5p5',    '0.3 Cube P5',    'Nata De Coco Press 5 3mm-4mm',                 4, 5, 5, 5),
('cotg12c4p5', 'COTG',               'cotg',  '12c4p5',   '1.2 Cube P5',    'Nata De Coco Press 5 1.2x1.3x1.0cm (4kg/bag)', 4, 4, 5, 4),
('cotg3c4p5',  'COTG',               'cotg',  '3c4p5',    '0.3 Cube P5',    'Nata De Coco Press 5 3mm-4mm',                 4, 4, 5, 4),
('ex6st25p4',  'Export',             'expor', '6st25p4',  '6 Star 25 P4',   NULL,                                           6, 5, 4, 5),
('exhati25p4', 'Export',             'expor', 'hati25p4', 'Hati 25 P4',     NULL,                                           6, 5, 4, 5),
('exstar25p4', 'Export',             'expor', 'star25p4', 'Star 25 P4',     NULL,                                           6, 5, 4, 5)
ON CONFLICT (code) DO NOTHING;

-- ── 驗證 ──
-- SELECT * FROM din_products ORDER BY customer_name, code;
-- SELECT * FROM din_stock_summary;
-- SELECT * FROM din_monthly_report;
