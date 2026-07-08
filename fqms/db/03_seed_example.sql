-- ============================================================
-- FQMS Phase 1 — 範例種子資料（選用）
-- 內容：規劃書「附錄A 椰果成品 FQC 模板」的 13 個檢驗項目，
--       建立 1 個產品 + 1 張成品(final)模板 + 對應規格。
--
-- 目的：讓團隊裝好 schema 後立刻有一組能點的資料，驗證
--       「模板 → 檢驗單 → 逐項判定」整條路走得通。
--
-- ⚠ 規格限值皆為「示意值」，實際限值以導入時最新 SNI/BPOM/客戶規格為準，
--    由規格版本化機制（product_specs.version / effective_from）管理。
--
-- 冪等：以 product_code='NC-10MM' 是否存在為守門，重複執行不會重覆灌。
-- 前置：01_core_schema.sql（本檔可在 02_rls.sql 前或後執行；以 SQL Editor
--       的 service 身分執行會 bypass RLS）。
-- ============================================================

-- 檢驗項目字典（全廠共用，冪等）
INSERT INTO test_items (item_code, name_id, name_zh, name_en, category, result_type, unit, select_options, test_method, is_external) VALUES
  ('WARNA_001',   'Warna',              '色澤',          'Color',            'sensory',   'select',    NULL,     '["正常白","半透明","偏黃","異常"]'::jsonb, 'SNI 01-4317', false),
  ('BAU_001',     'Bau',                '氣味',          'Odor',             'sensory',   'pass_fail', NULL,     NULL,                                        'SNI 01-4317', false),
  ('ASING_001',   'Benda Asing',        '異物',          'Foreign Matter',   'sensory',   'pass_fail', NULL,     NULL,                                        'CPPOB',       false),
  ('UKURAN_001',  'Ukuran',             '尺寸',          'Size',             'physical',  'numeric',   'mm',     NULL,                                        '客戶規格',     false),
  ('PH_001',      'pH',                 'pH 值',         'pH',               'physical',  'numeric',   NULL,     NULL,                                        '內部SOP',      false),
  ('BRIX_001',    'Brix',               'Brix 糖度',     'Brix',             'physical',  'numeric',   '°Brix',  NULL,                                        '客戶規格',     false),
  ('DRAINED_001', 'Berat Tuntas',       '固形物比',       'Drained Weight',   'physical',  'numeric',   '%',      NULL,                                        'SNI 01-4317', false),
  ('BENZOAT_001', 'Na-Benzoat',         '苯甲酸鈉',       'Sodium Benzoate',  'chemical',  'numeric',   'mg/kg',  NULL,                                        'BPOM',         false),
  ('TPC_001',     'ALT / TPC',          '總生菌數',       'Total Plate Count','micro',     'numeric',   'CFU/g',  NULL,                                        'BPOM',         false),
  ('COLIFORM_001','Coliform',           '大腸桿菌群',     'Coliform',         'micro',     'numeric',   'APM/g',  NULL,                                        'BPOM',         false),
  ('KAPANG_001',  'Kapang & Khamir',    '酵母菌與黴菌',   'Yeast & Mold',     'micro',     'numeric',   'CFU/g',  NULL,                                        'BPOM',         false),
  ('SEAL_001',    'Kekencangan Segel',  '封口完整性',     'Seal Integrity',   'packaging', 'pass_fail', NULL,     NULL,                                        '內部SOP',      false),
  ('LABEL_001',   'Label',              '標籤',          'Label',            'packaging', 'pass_fail', NULL,     NULL,                                        'BPOM',         false)
ON CONFLICT (item_code) DO NOTHING;

-- 產品 + 模板 + 規格 + 模板明細（一次建立）
DO $$
DECLARE
  v_prod UUID;
  v_tpl  UUID;
  r RECORD;
BEGIN
  IF EXISTS (SELECT 1 FROM products WHERE product_code = 'NC-10MM') THEN
    RAISE NOTICE 'NC-10MM 已存在，略過種子。';
    RETURN;
  END IF;

  INSERT INTO products (product_code, name_id, name_zh, name_en, category, shelf_life_days, storage_condition)
    VALUES ('NC-10MM', 'Nata de Coco 10mm', '椰果 10mm', 'Nata de Coco 10mm', 'nata_de_coco', 365, '室溫陰涼乾燥')
    RETURNING id INTO v_prod;

  INSERT INTO inspection_templates (template_name, product_id, stage, sampling_note, frequency)
    VALUES ('椰果成品 FQC', v_prod, 'final', '每批抽 5 桶；pH / Brix 逐桶量測取平均', 'per_batch')
    RETURNING id INTO v_tpl;

  -- 逐項：(項目碼, 排序, 必檢, CCP, 下限, 上限, 目標, 標準描述, 依據)
  FOR r IN
    SELECT * FROM (VALUES
      ('WARNA_001',    1, true,  false, NULL::numeric, NULL::numeric, NULL::numeric, '正常白/半透明', 'SNI 01-4317'),
      ('BAU_001',      2, true,  false, NULL,          NULL,          NULL,          '無異味',        'SNI 01-4317'),
      ('ASING_001',    3, true,  false, NULL,          NULL,          NULL,          '不得檢出',      'CPPOB'),
      ('UKURAN_001',   4, true,  false, 8,             12,            10,            '10 ± 2 mm',    '客戶規格'),
      ('PH_001',       5, true,  false, 3.8,           4.5,           4.1,           NULL,           '內部SOP'),
      ('BRIX_001',     6, true,  false, 11,            13,            12,            NULL,           '客戶規格'),
      ('DRAINED_001',  7, true,  false, 50,            NULL,          NULL,          '≥ 50%',        'SNI 01-4317'),
      ('BENZOAT_001',  8, true,  false, NULL,          600,           NULL,          '≤ 600 mg/kg',  'BPOM'),
      ('TPC_001',      9, true,  true,  NULL,          10000,         NULL,          '≤ 1×10⁴ CFU/g','BPOM'),
      ('COLIFORM_001',10, true,  true,  NULL,          10,            NULL,          '≤ 10 APM/g',   'BPOM'),
      ('KAPANG_001',  11, true,  false, NULL,          50,            NULL,          '≤ 50 CFU/g',   'BPOM'),
      ('SEAL_001',    12, true,  false, NULL,          NULL,          NULL,          '無滲漏',        '內部SOP'),
      ('LABEL_001',   13, true,  false, NULL,          NULL,          NULL,          '齊全正確',      'BPOM')
    ) AS s(code, ord, mand, ccp, smin, smax, starget, stext, reg)
  LOOP
    -- 模板明細
    INSERT INTO template_items (template_id, test_item_id, sort_order)
      SELECT v_tpl, ti.id, r.ord FROM test_items ti WHERE ti.item_code = r.code;

    -- 規格（v1，生效中）— pH/Brix 抽樣 5 桶取平均，其餘 1 樣
    INSERT INTO product_specs
      (product_id, test_item_id, stage, spec_min, spec_max, spec_target, spec_text,
       sample_count, judgment_rule, is_mandatory, is_ccp, regulation_ref)
      SELECT v_prod, ti.id, 'final', r.smin, r.smax, r.starget, r.stext,
             CASE WHEN r.code IN ('PH_001','BRIX_001') THEN 5 ELSE 1 END,
             'average', r.mand, r.ccp, r.reg
      FROM test_items ti WHERE ti.item_code = r.code;
  END LOOP;

  RAISE NOTICE '已建立範例：產品 NC-10MM + 模板「椰果成品 FQC」(13 項) + 規格。';
END $$;

-- 驗證：
--   SELECT p.product_code, t.template_name, count(ti.*) AS items
--     FROM products p
--     JOIN inspection_templates t ON t.product_id = p.id
--     JOIN template_items ti ON ti.template_id = t.id
--    WHERE p.product_code='NC-10MM'
--    GROUP BY 1,2;    -- 應為 13
--   SELECT ti.item_code, s.spec_min, s.spec_max, s.spec_text, s.is_ccp
--     FROM product_specs s JOIN test_items ti ON ti.id=s.test_item_id
--     JOIN products p ON p.id=s.product_id
--    WHERE p.product_code='NC-10MM' ORDER BY ti.item_code;
