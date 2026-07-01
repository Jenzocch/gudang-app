-- ============================================================
-- 保護 people.pin 欄位：不再讓匿名(anon)前端讀到任何人的 PIN
--   PIN 驗證改由 Edge Function verify-staff / verify-admin（service_role）處理
--
-- ⚠️ 執行順序很重要，一定要「先部署 + 前端上線」再跑這段：
--   1) supabase functions deploy verify-staff
--   2) supabase functions deploy verify-admin
--   3) 前端新版（select 改成明確欄位、不再 select *）已部署上線
--   4) 才在 Supabase → SQL Editor 執行這一整段
--
--   若順序顛倒（欄位權限先撤、但前端還在 select('*')），登入/載入會壞掉。
-- ============================================================

BEGIN;

-- 撤掉整張表的 SELECT（原本 Supabase 預設給 anon/authenticated 全欄位可讀）
REVOKE SELECT ON public.people FROM anon, authenticated;

-- 只放行「非機密」欄位；pin 不在清單內 → 前端永遠讀不到 pin
GRANT SELECT (id, name, is_admin, warehouses, can_view_pricing)
  ON public.people TO anon, authenticated;

-- 寫入權限維持不變（savePin/insert 仍可寫 pin；只有「讀」被收斂）
-- 前端已改為 .update()/.insert() 不帶 .select()，不會觸發回讀 pin。

COMMIT;

-- ── 驗證：以下查詢應「失敗」(permission denied for column pin)，代表 pin 已保護 ──
--   set role anon;
--   select pin from public.people limit 1;   -- 預期報錯
--   reset role;

-- ── 如需回復原狀（rollback）──
--   GRANT SELECT ON public.people TO anon, authenticated;
