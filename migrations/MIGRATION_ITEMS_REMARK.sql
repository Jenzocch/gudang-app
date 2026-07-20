-- ============================================================
-- items 補建 remark（備註）欄位
--
-- 前端很多地方早就假設這欄存在：品項表單的「📝 Catatan」欄位、
-- 低庫存「🔕 Jangan Ingatkan」(#noalert 標記) 都是讀/寫 items.remark，
-- 但這欄從來沒有被建過。sbInsertSafe()/sbUpdateSafe() 遇到「欄位不存在」
-- 的錯誤時會自動把該欄位從寫入內容裡拿掉再重試——這是為了讓其他欄位
-- 還能救回來，代價是 remark 從頭到尾都被靜默丟掉，使用者填了「備註」
-- 卻從來沒有真的存進資料庫，也看不到任何錯誤訊息。
--
-- 這欄位補上後，Catatan／#noalert 才會真的開始生效；不會動到既有資料。
--
-- 在 Supabase Dashboard → SQL Editor 執行一次。IF NOT EXISTS 寫法，可安全重複執行。
-- ⚠️ 需要在 MIGRATION_SEED_DIN_MATERIALS.sql 之前執行（那個 seed 檔案有幾筆資料寫 remark）。

ALTER TABLE public.items ADD COLUMN IF NOT EXISTS remark text;
