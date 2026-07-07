-- ============================================================
-- 擋住 people 寫入提權（風險清單第 1 點）
--   撤掉 anon/authenticated 對 people 的 INSERT/UPDATE/DELETE，
--   讓任何人都無法再用公開 anon key 直接把自己設成 is_admin、
--   或竄改別人的 pin。所有 people 變更改走 Edge Function manage-people
--   （service_role + 6 位數 admin PIN 授權）。
--
-- ⚠️ 執行順序很重要，一定要「先部署 + 前端上線」再跑這段：
--   1) supabase secrets set ADMIN_PIN="你的6位數PIN"   （若尚未設過）
--   2) supabase functions deploy manage-people
--   3) 前端新版（addPerson/savePin/toggleAdmin… 改走 managePeople）已部署上線
--   4) 才在 Supabase → SQL Editor 執行這一整段
--
--   若順序顛倒（權限先撤、但前端還在直接 sb.from('people').update）：
--   新增/改 PIN/設 admin/刪員工 都會壞掉。
-- ============================================================

BEGIN;

-- 讀取權限不動（讀取收斂由 MIGRATION_PROTECT_PIN.sql 處理）；這裡只收「寫」。
REVOKE INSERT, UPDATE, DELETE ON public.people FROM anon, authenticated;

COMMIT;

-- ── 驗證：以下應「失敗」(permission denied for table people)，代表寫入已鎖 ──
--   set role anon;
--   update public.people set is_admin = true where id = (select id from public.people limit 1);
--   -- 預期報錯 permission denied
--   reset role;
--
--   同時：登入 App 用 6 位數 admin PIN → 員工列表新增/改 PIN/設 admin 應正常
--   （這些會走 manage-people，service_role 不受本次 REVOKE 影響）。

-- ── 如需回復原狀（rollback）──
--   GRANT INSERT, UPDATE, DELETE ON public.people TO anon, authenticated;
