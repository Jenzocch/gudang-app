-- ============================================================
-- 分類(categories)改存資料庫：所有人 / 所有裝置共用，依倉庫分開。
--   取代原本存在瀏覽器 localStorage 的做法。
--
-- ⚠️ 一定要在「gudang 專案」執行：網址必須是
--    https://supabase.com/dashboard/project/klswfuzuhlowzrbncreu/sql/...
--    不要在 FAMMS(smthbomkbaywovzddnhj)專案跑！
--
-- 順序：先建表(這段) → 前端新版上線 → 即可在 App 內管理分類。
-- ============================================================

-- 1) 建立 categories 表（每個倉庫一組分類）
CREATE TABLE IF NOT EXISTS public.categories (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  warehouse_id text NOT NULL,
  name         text NOT NULL,
  created_at   timestamptz DEFAULT now(),
  UNIQUE (warehouse_id, name)          -- 同一倉庫不能有重複分類名
);

-- 2) 開啟 RLS，並比照現有其他表給「全開」政策（與 items 等一致的現況）
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS allow_all_categories_select ON public.categories;
DROP POLICY IF EXISTS allow_all_categories_insert ON public.categories;
DROP POLICY IF EXISTS allow_all_categories_update ON public.categories;
DROP POLICY IF EXISTS allow_all_categories_delete ON public.categories;

CREATE POLICY allow_all_categories_select ON public.categories FOR SELECT USING (true);
CREATE POLICY allow_all_categories_insert ON public.categories FOR INSERT WITH CHECK (true);
CREATE POLICY allow_all_categories_update ON public.categories FOR UPDATE USING (true);
CREATE POLICY allow_all_categories_delete ON public.categories FOR DELETE USING (true);

-- 3) 確保前端角色有表權限（Supabase 匿名/登入角色）
GRANT SELECT, INSERT, UPDATE, DELETE ON public.categories TO anon, authenticated;

-- ── 驗證：應回傳 0 rows（空表，正常）──
--   select * from public.categories;

-- ── 如需回復（rollback）──
--   DROP TABLE public.categories;
