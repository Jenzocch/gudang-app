-- ============================================================
-- FQMS Phase 1 — Row Level Security（RLS）與角色政策
-- （對應規劃書 §7 角色權限 + RLS_PLAN 路線 B：Supabase Auth + JWT + RLS）
--
-- 4 角色（存在 qc_users.role）：
--   inspector  檢驗員   輸入檢驗、看自己的紀錄、建批號
--   supervisor QC主管   覆核簽核、NCR 處置、設定項目/規格/模板、看全部
--   manager    QA/廠長  儀表板、報表、NCR 放行決定、規格核准
--   admin      管理員   使用者/系統設定
--
-- 設計要點：
--   • 身分來源不是 JWT 的 role claim（那個被 Supabase 固定為 authenticated），
--     而是 qc_users 表 → 用 SECURITY DEFINER 函式 fqms_role() 讀取，避免遞迴。
--   • anon 一律無權（FQMS 沒有公開頁面，全員登入）。
--   • 使用者 CRUD 與 PIN 驗證走 service_role Edge Function（比照 Gudang One 的
--     manage-people / verify-staff），不直接開放 authenticated 寫 qc_users。
--   • release/規格核准「需 Manager 以上」屬業務規則，由 App/Edge Function 把關；
--     RLS 只做到「supervisor 以上可寫」這層粗粒度。
--
-- 執行：01_core_schema.sql 之後執行；可重複執行（先 DROP POLICY IF EXISTS）。
-- Rollback：ALTER TABLE <t> DISABLE ROW LEVEL SECURITY;
-- ============================================================

-- ── 0) 角色 helper（SECURITY DEFINER：讀 qc_users 不受 RLS 遞迴影響）──
CREATE OR REPLACE FUNCTION fqms_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM qc_users WHERE id = auth.uid() AND is_active = true;
$$;

-- 是否為主管以上（可設定/覆核）
CREATE OR REPLACE FUNCTION fqms_is_supervisor()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT fqms_role() IN ('supervisor','manager','admin');
$$;

-- 是否已是 FQMS 有效使用者（任一角色）
CREATE OR REPLACE FUNCTION fqms_is_user()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT fqms_role() IS NOT NULL;
$$;

-- ── 1) 授權基礎：撤 anon+authenticated 的預設廣泛授權、開 RLS，再逐表給回 ──
-- （Supabase 對 public schema 新表預設會 GRANT 給 anon/authenticated，
--   若不先撤，pin_hash 等機密欄可能被讀 → 一律先歸零，再精準給回。）
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'qc_users','products','test_items','customers','suppliers','product_specs',
    'inspection_templates','template_items','batches','inspections',
    'inspection_results','ncr_records','inspection_tasks','fqms_sequences'
  ] LOOP
    EXECUTE format('REVOKE ALL ON %I FROM anon, authenticated;', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
  END LOOP;

  -- 一般營運表：給 authenticated 完整 DML（實際能不能做由 policy 決定）
  FOREACH t IN ARRAY ARRAY[
    'products','test_items','customers','suppliers','product_specs',
    'inspection_templates','template_items','batches','inspections',
    'inspection_results','ncr_records','inspection_tasks'
  ] LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO authenticated;', t);
  END LOOP;
END $$;

-- fqms_sequences：不給 authenticated 直接碰；只由 fqms_next_seq(SECURITY DEFINER) 寫。
-- （上面已 ENABLE RLS 且無 policy → 直接存取一律拒絕，符合預期。）

-- ============================================================
-- 2) qc_users — 使用者/角色
--    • 只讀非機密欄位（pin_hash 永不外流：用欄位級 GRANT 排除）
--    • 自己可改語言偏好；其餘寫入走 service_role Edge Function
-- ============================================================
GRANT SELECT (id, full_name, role, lang, is_active, created_at, updated_at)
  ON qc_users TO authenticated;
GRANT UPDATE (lang) ON qc_users TO authenticated;

DROP POLICY IF EXISTS qc_users_sel ON qc_users;
CREATE POLICY qc_users_sel ON qc_users FOR SELECT
  USING (fqms_is_user());                       -- 全員可看名冊（供指派/顯示 tested_by）

DROP POLICY IF EXISTS qc_users_self_upd ON qc_users;
CREATE POLICY qc_users_self_upd ON qc_users FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());                  -- 只能改自己那列（且欄位級只開放 lang）

-- ============================================================
-- 3) 設定層：讀=全員；寫=主管以上
-- ============================================================
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'products','test_items','customers','suppliers','product_specs',
    'inspection_templates','template_items'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t||'_sel', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I;', t||'_write', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR SELECT USING (fqms_is_user());', t||'_sel', t);
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR ALL USING (fqms_is_supervisor()) WITH CHECK (fqms_is_supervisor());',
      t||'_write', t);
  END LOOP;
END $$;

-- ============================================================
-- 4) batches — 批號（狀態機）
--    讀=全員；建立=全員（檢驗員建批號）；改狀態=主管以上；刪=admin
-- ============================================================
DROP POLICY IF EXISTS batches_sel ON batches;
CREATE POLICY batches_sel ON batches FOR SELECT USING (fqms_is_user());

DROP POLICY IF EXISTS batches_ins ON batches;
CREATE POLICY batches_ins ON batches FOR INSERT WITH CHECK (fqms_is_user());

DROP POLICY IF EXISTS batches_upd ON batches;
CREATE POLICY batches_upd ON batches FOR UPDATE
  USING (fqms_is_supervisor()) WITH CHECK (fqms_is_supervisor());

DROP POLICY IF EXISTS batches_del ON batches;
CREATE POLICY batches_del ON batches FOR DELETE USING (fqms_role() = 'admin');

-- ============================================================
-- 5) inspections — 檢驗單（表頭）
--    讀=自己的 或 主管以上；建=本人開單；改=本人(未覆核前) 或 主管以上
-- ============================================================
DROP POLICY IF EXISTS inspections_sel ON inspections;
CREATE POLICY inspections_sel ON inspections FOR SELECT
  USING (opened_by = auth.uid() OR fqms_is_supervisor());

DROP POLICY IF EXISTS inspections_ins ON inspections;
CREATE POLICY inspections_ins ON inspections FOR INSERT
  WITH CHECK (fqms_is_user() AND opened_by = auth.uid());

DROP POLICY IF EXISTS inspections_upd ON inspections;
CREATE POLICY inspections_upd ON inspections FOR UPDATE
  USING (
    (opened_by = auth.uid() AND status IN ('draft','partial','submitted'))
    OR fqms_is_supervisor()
  )
  WITH CHECK (
    (opened_by = auth.uid() AND status IN ('draft','partial','submitted'))
    OR fqms_is_supervisor()
  );

DROP POLICY IF EXISTS inspections_del ON inspections;
CREATE POLICY inspections_del ON inspections FOR DELETE USING (fqms_is_supervisor());

-- ============================================================
-- 6) inspection_results — 檢驗結果（明細）
--    可見性隨父檢驗單（EXISTS 子查詢會遵守 inspections 的 RLS）
-- ============================================================
DROP POLICY IF EXISTS results_sel ON inspection_results;
CREATE POLICY results_sel ON inspection_results FOR SELECT
  USING (EXISTS (SELECT 1 FROM inspections i WHERE i.id = inspection_id));

DROP POLICY IF EXISTS results_ins ON inspection_results;
CREATE POLICY results_ins ON inspection_results FOR INSERT
  WITH CHECK (
    fqms_is_user() AND EXISTS (
      SELECT 1 FROM inspections i
      WHERE i.id = inspection_id
        AND (i.opened_by = auth.uid() OR fqms_is_supervisor())
    )
  );

DROP POLICY IF EXISTS results_upd ON inspection_results;
CREATE POLICY results_upd ON inspection_results FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM inspections i
      WHERE i.id = inspection_id
        AND (i.opened_by = auth.uid() OR fqms_is_supervisor())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM inspections i
      WHERE i.id = inspection_id
        AND (i.opened_by = auth.uid() OR fqms_is_supervisor())
    )
  );

DROP POLICY IF EXISTS results_del ON inspection_results;
CREATE POLICY results_del ON inspection_results FOR DELETE USING (fqms_is_supervisor());

-- ============================================================
-- 7) ncr_records — 不合格處理單
--    讀=開單人 或 主管以上；寫=主管以上（放行=Manager 由 App 把關）
-- ============================================================
DROP POLICY IF EXISTS ncr_sel ON ncr_records;
CREATE POLICY ncr_sel ON ncr_records FOR SELECT
  USING (created_by = auth.uid() OR fqms_is_supervisor());

DROP POLICY IF EXISTS ncr_write ON ncr_records;
CREATE POLICY ncr_write ON ncr_records FOR ALL
  USING (fqms_is_supervisor()) WITH CHECK (fqms_is_supervisor());

-- ============================================================
-- 8) inspection_tasks — 今日任務
--    讀=被指派者/未指派/主管；建=主管以上；改=被指派者(打勾) 或 主管
-- ============================================================
DROP POLICY IF EXISTS tasks_sel ON inspection_tasks;
CREATE POLICY tasks_sel ON inspection_tasks FOR SELECT
  USING (assigned_to = auth.uid() OR assigned_to IS NULL OR fqms_is_supervisor());

DROP POLICY IF EXISTS tasks_ins ON inspection_tasks;
CREATE POLICY tasks_ins ON inspection_tasks FOR INSERT WITH CHECK (fqms_is_supervisor());

DROP POLICY IF EXISTS tasks_upd ON inspection_tasks;
CREATE POLICY tasks_upd ON inspection_tasks FOR UPDATE
  USING (assigned_to = auth.uid() OR fqms_is_supervisor())
  WITH CHECK (assigned_to = auth.uid() OR fqms_is_supervisor());

DROP POLICY IF EXISTS tasks_del ON inspection_tasks;
CREATE POLICY tasks_del ON inspection_tasks FOR DELETE USING (fqms_is_supervisor());

-- ============================================================
-- 驗證：以各角色 JWT 實測（RLS_PLAN §5「逐表灰度」）
--   SELECT rowsecurity FROM pg_tables WHERE schemaname='public'
--     AND tablename LIKE ANY (ARRAY['qc_%','products','test_items','batches','inspections%','ncr_%']);
--   -- 建一個 admin：INSERT INTO qc_users(id,full_name,role) VALUES ('<auth.uid>','Admin','admin');
--   -- 再用 inspector 帳號確認看不到別人的 inspections、不能寫 product_specs。
-- 下一步：（選用）執行 03_seed_example.sql 灌入椰果 FQC 範例。
-- ============================================================
