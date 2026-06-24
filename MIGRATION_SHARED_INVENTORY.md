# 數據庫架構變更：共享庫存（多倉庫商品）

## 背景
三家工廠（SJA、DIN、OLENTIA）共享商品信息，但庫存各自獨立。  
「共同倉庫」取貨到各工廠，需追蹤每件商品在各倉庫的數量。

## 新架構

### 1. items（商品主信息 - 共享）
```sql
DROP TABLE IF EXISTS items CASCADE;

CREATE TABLE items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  supplier_name TEXT,
  supplier_url TEXT,
  unit TEXT DEFAULT 'pcs',
  storage_condition TEXT DEFAULT 'Ambient',
  coa_url TEXT,
  tags JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_items_name ON items(name);
```

### 2. item_variants（各倉庫庫存 - 一對多）
```sql
DROP TABLE IF EXISTS item_variants CASCADE;

CREATE TABLE item_variants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  warehouse_id TEXT NOT NULL,
  qty INT DEFAULT 0,
  critical_qty INT DEFAULT 0,
  storage_photo_url TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(item_id, warehouse_id)
);

CREATE INDEX idx_variants_item ON item_variants(item_id);
CREATE INDEX idx_variants_warehouse ON item_variants(warehouse_id);
```

### 3. item_batches（改為引用 item_id）
```sql
DROP TABLE IF EXISTS item_batches CASCADE;

CREATE TABLE item_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  warehouse_id TEXT NOT NULL,
  qty_remaining INT DEFAULT 0,
  expiry_date DATE,
  lot_no TEXT,
  code_produksi TEXT,
  po_no TEXT,
  do_no TEXT,
  production_date DATE,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE INDEX idx_batches_item ON item_batches(item_id);
CREATE INDEX idx_batches_warehouse ON item_batches(warehouse_id);
CREATE INDEX idx_batches_expiry ON item_batches(expiry_date);
```

### 4. 其他表保持不變
- `people` — 只改 is_admin 欄位（如果還沒加）
- `requests` — 改 item_id 引用新 items
- `transactions` — 改 item_id 引用新 items

```sql
-- 如果 people 還沒有 is_admin 欄位
ALTER TABLE people ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false;

-- 刪掉舊 requests/transactions (或保留歷史)
DROP TABLE IF EXISTS requests;
DROP TABLE IF EXISTS transactions;

-- 重建 requests
CREATE TABLE requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  warehouse_id TEXT,
  qty INT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- 重建 transactions
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT,
  item_id UUID NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  item_name TEXT,
  person_id UUID REFERENCES people(id),
  person_name TEXT,
  warehouse_id TEXT,
  qty INT,
  created_at TIMESTAMP DEFAULT now()
);
```

## SQL 執行順序

1. 在 Supabase → SQL Editor 執行本檔案的所有 SQL
2. 檢查新表結構
3. 重啟 App（自動用新查詢邏輯）

## 備註
- 所有舊數據會被清空（重新建立）
- 新增商品時自動為每個倉庫建 variant 記錄
- 同一商品的修改立即影響所有倉庫（名字、圖片等）
- 庫存管理按 warehouse_id + item_id 查詢

---

**預期時間：** 現在做 App 邏輯改動 → 完成於 2-3 小時內
