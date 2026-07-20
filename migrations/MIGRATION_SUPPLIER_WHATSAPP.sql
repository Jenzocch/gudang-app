-- 供應商 WhatsApp 號碼：items（每個品項自己的供應商）與 product_refs（Katalog Supplier
-- 知識庫）都加一欄，跟既有的 supplier_url 並列使用，前端組成 wa.me 深連結一鍵開聊天。
--
-- 在 Supabase Dashboard → SQL Editor 執行一次。IF NOT EXISTS 寫法，可安全重複執行。

ALTER TABLE public.items ADD COLUMN IF NOT EXISTS supplier_whatsapp text;
ALTER TABLE public.product_refs ADD COLUMN IF NOT EXISTS supplier_whatsapp text;
