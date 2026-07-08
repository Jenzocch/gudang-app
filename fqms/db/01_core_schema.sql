-- ============================================================
-- FQMS 食品工廠品管系統 — Phase 1 核心 Schema
-- （對應規劃書 QC_SYSTEM_PLAN v1.3 第四章資料模型 + 第九章 Phase 1）
--
-- ★ 這是「獨立系統」的資料庫（規劃書 §8.7 定案）：
--   獨立 Supabase 專案（專案 C）、獨立帳號、與 Gudang One / FAMMS 不共庫。
--   請勿貼進 Gudang One 的正式庫（ref: klswfuzuhlowzrbncreu）。
--
-- 設計原則（規劃書 §8.1「輕量核心 + 擴充插座」）：
--   核心 5 組表：test_items / product_specs / templates / batches / inspections(+results)
--   其餘（NCR、任務）為 Phase 1 最小可用版；退貨/客訴/參考庫留待 Phase 2。
--
-- 身分/權限：從第一天就走 Supabase Auth + JWT + RLS（RLS_PLAN 路線 B）。
--   本檔只建表與函式；RLS 政策在 02_rls.sql。
--
-- 執行：Supabase SQL Editor 貼上執行一次；全檔 IF NOT EXISTS，可重複執行。
--   執行順序：01_core_schema.sql → 02_rls.sql → (選用) 03_seed_example.sql
-- ============================================================

-- ── 0) 擴充套件 ──
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()

-- ── 0.1) updated_at 自動更新觸發器函式 ──
CREATE OR REPLACE FUNCTION fqms_touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ── 0.2) 每日流水號（inspection_no / ncr_no 自動編號用）──
-- 用一張 counter 表做原子遞增，避免併發下號碼重複（規劃書：系統自動編號）。
CREATE TABLE IF NOT EXISTS fqms_sequences (
  seq_key   TEXT PRIMARY KEY,     -- 例：'QC-20260707'、'NCR-20260707'
  last_seq  INT  NOT NULL DEFAULT 0
);

-- 回傳指定 key 的下一個序號（原子操作）
-- SECURITY DEFINER：以擁有者身分寫入 counter 表，讓 RLS 下的 authenticated
--   透過欄位 DEFAULT 呼叫時也能取號，而不需直接授權 fqms_sequences。
CREATE OR REPLACE FUNCTION fqms_next_seq(p_key TEXT)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_seq INT;
BEGIN
  INSERT INTO fqms_sequences(seq_key, last_seq) VALUES (p_key, 1)
    ON CONFLICT (seq_key)
    DO UPDATE SET last_seq = fqms_sequences.last_seq + 1
  RETURNING last_seq INTO v_seq;
  RETURN v_seq;
END;
$$;

-- 檢驗單號：QC-YYYYMMDD-NNN（規劃書範例 QC-20260707-001）
CREATE OR REPLACE FUNCTION fqms_inspection_no()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_day TEXT := to_char(now(), 'YYYYMMDD');
BEGIN
  RETURN 'QC-' || v_day || '-' || lpad(fqms_next_seq('QC-' || v_day)::text, 3, '0');
END;
$$;

-- NCR 單號：NCR-YYYYMMDD-NN
CREATE OR REPLACE FUNCTION fqms_ncr_no()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE v_day TEXT := to_char(now(), 'YYYYMMDD');
BEGIN
  RETURN 'NCR-' || v_day || '-' || lpad(fqms_next_seq('NCR-' || v_day)::text, 2, '0');
END;
$$;

-- ============================================================
-- 一、使用者 / 角色（RLS 的身分來源）
-- ============================================================

-- qc_users：對應 auth.users，掛角色與偏好。
-- 角色（規劃書 §7）：inspector / supervisor / manager / admin
-- 訪談定案：6 位檢驗員、共用平板 PIN 快速切換 → pin_hash 供 Edge Function 驗證
--          （PIN 明碼絕不入前端；驗證比照 Gudang One 的 verify-staff 模式）
CREATE TABLE IF NOT EXISTS qc_users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'inspector'
              CHECK (role IN ('inspector','supervisor','manager','admin')),
  pin_hash    TEXT,                                   -- 共用平板 PIN（雜湊後，僅後端可讀）
  lang        TEXT NOT NULL DEFAULT 'id'
              CHECK (lang IN ('id','zh','en')),        -- 介面語言（檢驗員預設 Bahasa）
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_qc_users_touch ON qc_users;
CREATE TRIGGER trg_qc_users_touch BEFORE UPDATE ON qc_users
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ============================================================
-- 二、設定層（QC 主管維護，低頻）— 規劃書 §4.1
-- ============================================================

-- ── products：產品主檔 ──
CREATE TABLE IF NOT EXISTS products (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_code      TEXT UNIQUE NOT NULL,
  name_id           TEXT NOT NULL,                    -- Bahasa 為主
  name_zh           TEXT,
  name_en           TEXT,
  category          TEXT NOT NULL DEFAULT 'other'
                    CHECK (category IN ('nata_de_coco','tapioca_pearl','syrup','other')),
  md_number         TEXT,                             -- BPOM MD 註冊號
  halal_cert_no     TEXT,
  halal_expiry      DATE,
  shelf_life_days   INT,
  storage_condition TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT true,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_products_touch ON products;
CREATE TRIGGER trg_products_touch BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── test_items：檢驗項目庫（全廠共用字典）★核心彈性 ──
-- result_type 是「檢驗項目=資料不是程式碼」的關鍵：四種結果型態全支援。
CREATE TABLE IF NOT EXISTS test_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_code      TEXT UNIQUE NOT NULL,                -- 如 PH_001 / BRIX_001 / TPC_001
  name_id        TEXT NOT NULL,
  name_zh        TEXT,
  name_en        TEXT,
  category       TEXT NOT NULL
                 CHECK (category IN ('sensory','physical','chemical','micro','packaging','hygiene')),
  result_type    TEXT NOT NULL
                 CHECK (result_type IN ('numeric','pass_fail','select','text')),  -- ★
  unit           TEXT,                                -- %, mm, °Brix, CFU/g, APM/g ...
  select_options JSONB,                               -- result_type='select' 的選項清單
  test_method    TEXT,                                -- 檢驗方法：SNI xx / AOAC / 內部SOP
  is_external    BOOLEAN NOT NULL DEFAULT false,      -- 是否委外（重金屬/Salmonella）
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_test_items_cat ON test_items(category);
DROP TRIGGER IF EXISTS trg_test_items_touch ON test_items;
CREATE TRIGGER trg_test_items_touch BEFORE UPDATE ON test_items
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── customers：客戶主檔（客戶有專屬規格）──
CREATE TABLE IF NOT EXISTS customers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  country       TEXT,
  contact       TEXT,
  coa_language  TEXT NOT NULL DEFAULT 'id'
                CHECK (coa_language IN ('en','id')),   -- CoA 輸出語言偏好
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_customers_touch ON customers;
CREATE TRIGGER trg_customers_touch BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── suppliers：供應商主檔 ──
CREATE TABLE IF NOT EXISTS suppliers (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  material_types JSONB,                               -- 供應的原料類型清單
  halal_cert_no  TEXT,
  halal_expiry   DATE,                                -- 到期預警
  rating         NUMERIC(4,2),                        -- 進料合格率+退貨率自動計算（Phase 2）
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_suppliers_touch ON suppliers;
CREATE TRIGGER trg_suppliers_touch BEFORE UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── product_specs：產品規格標準（版本化）★合規核心 ──
-- 規格解析順序：客戶專屬(customer_id NOT NULL) → 通用(customer_id NULL)
-- 舊檢驗紀錄靠 inspection_results.spec_id 鎖定當時版本，法規變只建新版不改舊。
CREATE TABLE IF NOT EXISTS product_specs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id     UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  test_item_id   UUID NOT NULL REFERENCES test_items(id),
  customer_id    UUID REFERENCES customers(id),        -- NULL=通用規格；有值=客戶專屬（覆蓋通用）
  stage          TEXT NOT NULL
                 CHECK (stage IN ('incoming','in_process','final','water','environment','hygiene','re_inspection')),
  spec_min       NUMERIC,                              -- numeric 用
  spec_max       NUMERIC,
  spec_target    NUMERIC,
  spec_text      TEXT,                                 -- pass_fail/select 標準描述，如「不得檢出」
  sample_count   INT NOT NULL DEFAULT 1,               -- 預設抽樣數（一批抽 N 桶）
  judgment_rule  TEXT NOT NULL DEFAULT 'average'
                 CHECK (judgment_rule IN ('average','each')),  -- 多樣品判定：平均合格 / 逐樣品合格
  is_mandatory   BOOLEAN NOT NULL DEFAULT true,
  is_ccp         BOOLEAN NOT NULL DEFAULT false,       -- HACCP 關鍵管制點
  regulation_ref TEXT,                                 -- 依據：SNI 01-4317 / BPOM No.13/2019 / 客戶規格
  version        INT NOT NULL DEFAULT 1,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to   DATE,                                 -- NULL = 目前生效中
  created_by     UUID REFERENCES qc_users(id),
  approved_by    UUID REFERENCES qc_users(id),         -- 規格變更要主管核准
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_specs_product ON product_specs(product_id, stage);
CREATE INDEX IF NOT EXISTS idx_specs_item    ON product_specs(test_item_id);
-- 同一 (產品×項目×客戶×階段) 只能有一個「生效中」版本（effective_to IS NULL）
CREATE UNIQUE INDEX IF NOT EXISTS uq_specs_active ON product_specs (
  product_id, test_item_id, stage,
  COALESCE(customer_id, '00000000-0000-0000-0000-000000000000'::uuid)
) WHERE effective_to IS NULL;

-- ── inspection_templates：檢驗模板（產品×階段 → 一張表單）──
-- frequency 供「今日任務清單」自動生成（規劃書流程B）。
CREATE TABLE IF NOT EXISTS inspection_templates (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_name  TEXT NOT NULL,
  product_id     UUID REFERENCES products(id),         -- 進料/水質/環境類可為 NULL（非特定產品）
  stage          TEXT NOT NULL
                 CHECK (stage IN ('incoming','in_process','final','water','environment','hygiene','re_inspection')),
  sampling_note  TEXT,                                 -- 抽樣規則描述：每批抽3桶、每2小時1次
  frequency      TEXT NOT NULL DEFAULT 'per_batch'
                 CHECK (frequency IN ('per_batch','per_shift','daily','weekly','monthly','event')),
  is_active      BOOLEAN NOT NULL DEFAULT true,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS trg_templates_touch ON inspection_templates;
CREATE TRIGGER trg_templates_touch BEFORE UPDATE ON inspection_templates
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── template_items：模板明細（檢驗項目排序）──
CREATE TABLE IF NOT EXISTS template_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id    UUID NOT NULL REFERENCES inspection_templates(id) ON DELETE CASCADE,
  test_item_id   UUID NOT NULL REFERENCES test_items(id),
  sort_order     INT NOT NULL DEFAULT 0,
  default_value  TEXT,                                 -- 預設值，加速輸入
  UNIQUE (template_id, test_item_id)
);
CREATE INDEX IF NOT EXISTS idx_tpl_items_tpl ON template_items(template_id);

-- ============================================================
-- 三、執行層（檢驗員操作產生，高頻）— 規劃書 §4.2
-- ============================================================

-- ── batches：批號主檔（追溯核心）★批次狀態機 ──
-- 狀態：released(正常) ⇄ hold(暫扣) → returned/rejected/downgraded
-- source_ref：★與 Gudang One 串接的插座（存 gudang_batch_id/lot_no/warehouse）
--             — 見 docs/PLAN_3SYSTEM_INTEGRATION.md §5.3
CREATE TABLE IF NOT EXISTS batches (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_no           TEXT UNIQUE NOT NULL,             -- {產品}-{YYMMDD}-{線別}{序} 或 RM-{YYMMDD}-{序}
  batch_type         TEXT NOT NULL
                     CHECK (batch_type IN ('incoming_lot','production_batch')),
  product_id         UUID REFERENCES products(id),     -- 成品批用
  material_name      TEXT,                             -- 進料批用（未必有 product_id）
  supplier_id        UUID REFERENCES suppliers(id),    -- 進料批
  production_date    DATE,
  line               TEXT,
  shift              TEXT,
  status             TEXT NOT NULL DEFAULT 'released'
                     CHECK (status IN ('released','hold','returned','rejected','downgraded')),
  status_reason      TEXT,
  status_changed_by  UUID REFERENCES qc_users(id),
  status_changed_at  TIMESTAMPTZ,
  parent_batch_ids   JSONB,                            -- 成品批 ← 用了哪些原料批（追溯）
  source_ref         JSONB,                            -- ★串接插座：{gudang_batch_id, lot_no, warehouse}
  created_by         UUID REFERENCES qc_users(id),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_batches_status  ON batches(status);
CREATE INDEX IF NOT EXISTS idx_batches_product ON batches(product_id);
DROP TRIGGER IF EXISTS trg_batches_touch ON batches;
CREATE TRIGGER trg_batches_touch BEFORE UPDATE ON batches
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── inspections：檢驗單（表頭）──
-- status：draft/partial/submitted/reviewed/approved/rejected
--   ★partial=現場項已填、微生物/委外待補（訪談定案：多人分工）
CREATE TABLE IF NOT EXISTS inspections (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_no  TEXT UNIQUE NOT NULL DEFAULT fqms_inspection_no(),  -- QC-YYYYMMDD-NNN 自動編號
  template_id    UUID REFERENCES inspection_templates(id),
  batch_id       UUID REFERENCES batches(id),
  customer_id    UUID REFERENCES customers(id),        -- 出給哪個客戶（決定套哪套規格與 CoA）
  stage          TEXT NOT NULL,
  opened_by      UUID REFERENCES qc_users(id),
  opened_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  status         TEXT NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft','partial','submitted','reviewed','approved','rejected')),
  overall_result TEXT CHECK (overall_result IN ('pass','fail','conditional')),  -- 結果到齊才彙總
  reviewed_by    UUID REFERENCES qc_users(id),         -- 主管覆核=電子簽核
  reviewed_at    TIMESTAMPTZ,
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inspections_batch  ON inspections(batch_id);
CREATE INDEX IF NOT EXISTS idx_inspections_status ON inspections(status);
CREATE INDEX IF NOT EXISTS idx_inspections_opened ON inspections(opened_by);
DROP TRIGGER IF EXISTS trg_inspections_touch ON inspections;
CREATE TRIGGER trg_inspections_touch BEFORE UPDATE ON inspections
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── inspection_results：檢驗結果（明細）──
-- spec_id：★鎖定當時生效的規格版本（稽核關鍵）
-- sample_values：★多樣品原始值 [4.2,4.3,4.1]（SPC 黃金數據）
-- entry_source/source_ref：★資料來源插座（規劃書 §8.2；Phase 1 只用 manual）
CREATE TABLE IF NOT EXISTS inspection_results (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inspection_id  UUID NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  test_item_id   UUID NOT NULL REFERENCES test_items(id),
  spec_id        UUID REFERENCES product_specs(id),    -- ★鎖定規格版本
  tested_by      UUID REFERENCES qc_users(id),         -- ★每項記誰測的（多人分工）
  tested_at      TIMESTAMPTZ,
  sample_values  JSONB,                                -- ★多樣品原始值陣列
  value_numeric  NUMERIC,                              -- 代表值（多樣品平均/單樣品直接值）
  value_bool     BOOLEAN,
  value_option   TEXT,
  value_text     TEXT,
  judgment       TEXT CHECK (judgment IN ('pass','fail','na')),  -- 依 spec 由 App 判定
  photo_urls     JSONB,                                -- 異常照片
  remark         TEXT,
  entry_source   TEXT NOT NULL DEFAULT 'manual'
                 CHECK (entry_source IN ('manual','excel_import','instrument','lab_import','api')),  -- ★插座
  source_ref     JSONB,                                -- ★插座：匯入檔名/儀器ID/外部單號
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (inspection_id, test_item_id)
);
CREATE INDEX IF NOT EXISTS idx_results_inspection ON inspection_results(inspection_id);
CREATE INDEX IF NOT EXISTS idx_results_item       ON inspection_results(test_item_id);
DROP TRIGGER IF EXISTS trg_results_touch ON inspection_results;
CREATE TRIGGER trg_results_touch BEFORE UPDATE ON inspection_results
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ============================================================
-- 四、Phase 1 最小版：NCR + 今日任務
-- ============================================================

-- ── ncr_records：不合格處理單（Phase 1 最小版）──
-- Phase 1 目標：進料驗退從第一天就能記（規劃書 §9 Phase 1 第6項）。
-- 完整流程（CCP 強制、複驗才 close）留 Phase 2。
-- machine_code：★預留欄位（整合計劃 §5.5），Phase 2 一鍵開 FAMMS 工單用，現在只收資料。
CREATE TABLE IF NOT EXISTS ncr_records (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ncr_no             TEXT UNIQUE NOT NULL DEFAULT fqms_ncr_no(),
  inspection_id      UUID REFERENCES inspections(id),
  batch_id           UUID REFERENCES batches(id),
  source             TEXT NOT NULL
                     CHECK (source IN ('incoming','in_process','final','customer')),
  description        TEXT,
  severity           TEXT CHECK (severity IN ('minor','major','critical')),
  disposition        TEXT
                     CHECK (disposition IN ('release','rework','reject','hold','downgrade','return_to_supplier','sorting')),
  root_cause         TEXT,
  corrective_action  TEXT,
  preventive_action  TEXT,
  machine_code       TEXT,                             -- ★預留：疑似設備造成時記機台碼
  decided_by         UUID REFERENCES qc_users(id),     -- 放行決定要主管以上（App/RLS 把關）
  decided_at         TIMESTAMPTZ,
  reinspection_id    UUID REFERENCES inspections(id),  -- 重工/換貨後的複驗單
  status             TEXT NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open','in_progress','closed')),
  created_by         UUID REFERENCES qc_users(id),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ncr_status ON ncr_records(status);
CREATE INDEX IF NOT EXISTS idx_ncr_batch  ON ncr_records(batch_id);
DROP TRIGGER IF EXISTS trg_ncr_touch ON ncr_records;
CREATE TRIGGER trg_ncr_touch BEFORE UPDATE ON ncr_records
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ── inspection_tasks：今日任務清單（規劃書流程B）──
-- 由模板 frequency 自動生成；訪談定案：任務「按人排」（assigned_to），一人跑多線。
CREATE TABLE IF NOT EXISTS inspection_tasks (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id    UUID NOT NULL REFERENCES inspection_templates(id) ON DELETE CASCADE,
  product_id     UUID REFERENCES products(id),
  scheduled_date DATE NOT NULL DEFAULT CURRENT_DATE,
  scheduled_time TIME,
  line           TEXT,
  assigned_to    UUID REFERENCES qc_users(id),         -- 指派給特定人（NULL=全員可認領）
  status         TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','done','overdue','skipped')),
  inspection_id  UUID REFERENCES inspections(id),      -- 完成後連結到實際檢驗單
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_date     ON inspection_tasks(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON inspection_tasks(assigned_to, scheduled_date);
DROP TRIGGER IF EXISTS trg_tasks_touch ON inspection_tasks;
CREATE TRIGGER trg_tasks_touch BEFORE UPDATE ON inspection_tasks
  FOR EACH ROW EXECUTE FUNCTION fqms_touch_updated_at();

-- ============================================================
-- 驗證查詢（執行後可逐條檢查）：
--   SELECT tablename FROM pg_tables WHERE schemaname='public'
--     AND tablename IN ('qc_users','products','test_items','customers','suppliers',
--       'product_specs','inspection_templates','template_items','batches',
--       'inspections','inspection_results','ncr_records','inspection_tasks');
--   SELECT fqms_inspection_no();   -- 應回 QC-YYYYMMDD-001
--   SELECT fqms_ncr_no();          -- 應回 NCR-YYYYMMDD-01
-- 下一步：執行 02_rls.sql 開啟 RLS 與角色政策。
-- ============================================================
