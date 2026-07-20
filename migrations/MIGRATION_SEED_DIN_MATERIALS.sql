-- DENIKIN 倉庫：原物料（食品）+ 包裝材料 一次性建檔（21 項）。
--
-- 每項資料分兩步寫入：
--   1) items：品名/代碼/單位/規格(spec)/備註(remark)/標籤(tags) —— 全倉庫共用的主檔
--   2) item_variants：DENIKIN 倉的庫存列 —— 初始庫存故意設 0、最低警戒線設 10（跟 App
--      本身「新增品項」表單的預設值一致），之後由現場人員用「Masuk」實際收貨/盤點填入
--      真實數量，不用猜測的數字污染庫存記錄。
--
-- items.code 這張表不在追蹤的 migration 歷史裡（更早建的舊表），沒有唯一限制，所以用
-- WHERE NOT EXISTS 而非 ON CONFLICT 判斷是否已存在 —— 可安全重複執行，不會造出重複品項。
-- categories 表有 UNIQUE(warehouse_id, name)，用 ON CONFLICT DO NOTHING 即可。
--
-- ⚠️ 待確認（先用合理預設值填入，之後可在 App 裡手動修正）：
--   · pwrap（Plastic Wrap）：來源資料被截斷，只有 Code/Item，Unit 先假設 PCS，
--     沒有 Category/Description。
--   · pail25（Ember Putih 25kg）：來源資料 Category 留空，先不掛標籤（Tanpa Kategori）。

-- ──────────────────────────────────────────────────────────
-- 0) 分類標籤（DENIKIN 倉專用）
-- ──────────────────────────────────────────────────────────
INSERT INTO public.categories (warehouse_id, name) VALUES
  ('DENIKIN','Carton'),
  ('DENIKIN','Bag'),
  ('DENIKIN','Seal/Label'),
  ('DENIKIN','Jar/Jerigen'),
  ('DENIKIN','Ingredient')
ON CONFLICT (warehouse_id, name) DO NOTHING;

-- ──────────────────────────────────────────────────────────
-- 1) 包裝材料（Packaging）12 項
-- ──────────────────────────────────────────────────────────

INSERT INTO items (name, code, unit, spec, remark, tags)
SELECT 'CTN Nata Bag 5kg', 'ctn-din5', 'PCS', '12 PCS/CTN', 'UK 440X275X189', ARRAY['Carton']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'ctn-din5');

INSERT INTO items (name, code, unit, spec, remark, tags)
SELECT 'Plastic 5KG', 'BAG5', 'PCS', '2000 PCS/CTN', 'Bag 5kg L 32cmxT 52cm NY15/LLDPE80 1w (biru)', ARRAY['Bag']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'BAG5');

INSERT INTO items (name, code, unit, tags)
SELECT 'Plastic PE (80X06)x 170cm', 'bag170', 'PCS', ARRAY['Bag']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'bag170');

INSERT INTO items (name, code, unit, tags)
SELECT 'Plastic PE (80X06)x 140cm', 'bag140', 'PCS', ARRAY['Bag']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'bag140');

INSERT INTO items (name, code, unit, tags)
SELECT 'Lakban 48mm x 90 Y FRAGILE', 'lakbanfrag', 'PCS', ARRAY['Seal/Label']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'lakbanfrag');

INSERT INTO items (name, code, unit, remark, tags)
SELECT 'Drum 150L', 'drum150', 'PCS', 'Drum Biru 150 L', ARRAY['Jar/Jerigen']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'drum150');

INSERT INTO items (name, code, unit, tags)
SELECT 'Label 10 x 8cm Removable', 'label10x8r', 'PCS', ARRAY['Seal/Label']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'label10x8r');

INSERT INTO items (name, code, unit, tags)
SELECT 'Ribbon Bardcode 110x74', 'ribbon110x74', 'PCS', ARRAY['Seal/Label']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'ribbon110x74');

INSERT INTO items (name, code, unit, tags)
SELECT 'Label 3 x 5cm', 'label3x5', 'PCS', ARRAY['Seal/Label']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'label3x5');

INSERT INTO items (name, code, unit, tags)
SELECT 'Ribbon Bardcode 55mm x 75M', 'ribbon55x75', 'PCS', ARRAY['Seal/Label']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'ribbon55x75');

-- Category 來源留空 → 不掛標籤（Tanpa Kategori）
INSERT INTO items (name, code, unit)
SELECT 'Ember Putih 25kg', 'pail25', 'PCS'
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'pail25');

-- 來源資料被截斷（只有 Code/Item），Unit 先假設 PCS，待確認
INSERT INTO items (name, code, unit)
SELECT 'Plastic Wrap', 'pwrap', 'PCS'
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'pwrap');

-- ──────────────────────────────────────────────────────────
-- 2) 食品原料（Ingredient）9 項
-- ──────────────────────────────────────────────────────────

INSERT INTO items (name, code, unit, tags)
SELECT 'Acetic Acid Ex Singapura', 'CUKA-SINGA', 'Jerigen', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'CUKA-SINGA');

INSERT INTO items (name, code, unit, spec, tags)
SELECT 'CMC', 'cmc', 'ZAK', 'F1501P', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'cmc');

INSERT INTO items (name, code, unit, spec, tags)
SELECT 'Citric Acid', 'ctac', 'ZAK', 'Mono', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'ctac');

INSERT INTO items (name, code, unit, tags)
SELECT 'Nata Lembaran Import', 'nataimport', 'Drum', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'nataimport');

INSERT INTO items (name, code, unit, remark, tags)
SELECT 'ProCop B SPN', 'pbspn', 'Jerigen', 'Sabun pembersih', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'pbspn');

INSERT INTO items (name, code, unit, tags)
SELECT 'Sodium Metabisulfit', 'sdmmeta', 'ZAK', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'sdmmeta');

INSERT INTO items (name, code, unit, tags)
SELECT 'Kaporit 60%', 'kapo60', 'ZAK', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'kapo60');

INSERT INTO items (name, code, unit, tags)
SELECT 'Sodium Bicarbonate', 'sdmbicarbon', 'ZAK', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'sdmbicarbon');

INSERT INTO items (name, code, unit, tags)
SELECT 'Caustic Soda', 'soda', 'ZAK', ARRAY['Ingredient']
WHERE NOT EXISTS (SELECT 1 FROM items WHERE code = 'soda');

-- ──────────────────────────────────────────────────────────
-- 3) 幫上面 21 項全部開 DENIKIN 倉的庫存列（qty=0, critical_qty=10）
--    一次性 join items.code 對照，不用每項再重複打一次 INSERT
-- ──────────────────────────────────────────────────────────
INSERT INTO item_variants (item_id, warehouse_id, qty, critical_qty)
SELECT i.id, 'DENIKIN', 0, 10
FROM items i
WHERE i.code IN (
  'ctn-din5','BAG5','bag170','bag140','lakbanfrag','drum150','label10x8r',
  'ribbon110x74','label3x5','ribbon55x75','pail25','pwrap',
  'CUKA-SINGA','cmc','ctac','nataimport','pbspn','sdmmeta','kapo60','sdmbicarbon','soda'
)
AND NOT EXISTS (
  SELECT 1 FROM item_variants iv WHERE iv.item_id = i.id AND iv.warehouse_id = 'DENIKIN'
);
