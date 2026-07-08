-- ============================================================
-- 線③：Gudang → FAMMS 叫料狀態回寫
-- requests 表加兩欄，記住「這筆是不是 FAMMS 送來的、FAMMS 那邊的 id 是誰」
-- 才能在狀態變動（已購買/拒絕）時回呼 FAMMS 的 parts_requests 更新它
-- 執行：Supabase SQL Editor 貼上執行一次（可重複）
-- ============================================================
ALTER TABLE requests ADD COLUMN IF NOT EXISTS source TEXT;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS famms_request_id TEXT;

CREATE INDEX IF NOT EXISTS idx_req_famms ON requests(famms_request_id) WHERE famms_request_id IS NOT NULL;

-- 驗證：
-- SELECT id, person_name, status, source, famms_request_id FROM requests WHERE source='famms' ORDER BY created_at DESC LIMIT 10;
