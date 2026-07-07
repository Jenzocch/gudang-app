# RLS 安全計畫書 — Gudang One

> 目的：把「anon key 可繞過 App 讀寫全部資料」這個根本漏洞關掉。
> 本文件**只是計畫**，不碰線上資料庫。看過後再決定要不要動工。

---

## 1. 核心問題（為什麼不能一鍵開 RLS）

- App 用 **PIN 登入**（6 位數 admin / 4 位數員工），前端只是把 `IS_ADMIN` 這種旗標打開。
- 對 Supabase 來說，**每個請求都是同一個匿名角色 `anon`**（用網頁裡公開的 anon key）。資料庫**看不到「這是誰、什麼角色」**。
- 所以 RLS 政策沒有身分可以判斷——你不能寫「只有 super admin 能讀出貨」，因為資料庫眼中大家都是 `anon`。
- 結論：**RLS 要真正有效，必須先給資料庫一個「可驗證的身分」**。有兩條路（見第 3 節）。

---

## 2. 資料表分類（依機密程度）

| 分類 | 資料表 | 誰該讀 | 誰該寫 |
|---|---|---|---|
| **A. 公開讀取**（App 基本運作需要，anon 可讀） | `items`/`item_variants`/`item_batches`、`categories`、`din_products`/`sja_products`、`app_config` | 全部（含未登入，讓登入畫面/庫存能顯示） | 只有管理員（經後端） |
| **B. 營運機密**（不該給一般人讀） | `din_delivery`/`sja_delivery`（出貨）、`sja_customers`（客戶）、`din_production`/`sja_production`/`din_rehidrasi`/`din_rework`、月報/庫存 view、`transactions`、`transaction_edits` | 只有 admin/office/授權員工 | 只有授權角色（經後端） |
| **C. 高度機密** | `people`（員工＋PIN）、`qc_checks`/`qc_templates`/`qc_template_items`（食安記錄，稽核用不可竄改） | 只有管理員 | 只有管理員（經後端） |
| **D. 已保護** | `people` 寫入已鎖、PIN 欄不可讀（現況 OK） | — | — |

---

## 3. 兩條可行路線

### 路線 A：維持 PIN，寫入全走 Edge Function（較快，讀取仍需另解）
- **撤銷 anon 的 INSERT/UPDATE/DELETE**（`REVOKE ... FROM anon, authenticated`）於所有 B/C 類表。
- 前端所有寫入改呼叫 Edge Function（像現有 `manage-people` 那樣），函式用 **service_role** 執行、先驗 PIN。
- **讀取**：B/C 類表仍需限制。因為沒有身分，只能靠「讀取也走 Edge Function 驗 PIN 後回傳」——等於大改前端的每個讀取點。
- 優點：不用改登入方式。缺點：**讀取保護很麻煩**，且要重寫大量前端 `sb.from().select()`。適合「先止血寫入」。

### 路線 B：導入 Supabase Auth（email 登入）+ JWT RLS（正解，賣多公司必走）
- Admin/office 改用 **email + 密碼（或 magic-link / MFA）** 登入 → 拿到帶身分的 JWT（`auth.uid()`、role claim）。
- 員工可用 Supabase Auth 的「匿名登入」或保留輕量 PIN（經函式換發 JWT）。
- RLS 政策直接依 JWT 判斷：
  ```sql
  -- 範例：出貨資料只有 authenticated 的管理員能讀
  ALTER TABLE sja_delivery ENABLE ROW LEVEL SECURITY;
  CREATE POLICY sja_delivery_read ON sja_delivery FOR SELECT
    USING ( (auth.jwt() ->> 'role') IN ('super','office','admin') );
  CREATE POLICY sja_delivery_write ON sja_delivery FOR ALL
    USING ( (auth.jwt() ->> 'role') IN ('super','admin') )
    WITH CHECK ( (auth.jwt() ->> 'role') IN ('super','admin') );
  ```
- 優點：**讀寫都真的鎖住**，且是多租戶的基礎。缺點：要改登入流程、建 auth 使用者、逐表測試。

**建議：若近期要賣多公司 → 直接做 B。A 之後還是要重做，等於白工。**

---

## 4. SQL 骨架（路線 B，草稿，勿直接上線）

```sql
-- (1) 公開讀取表：開 RLS、只允許讀、撤寫入
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
CREATE POLICY items_read ON items FOR SELECT USING (true);
REVOKE INSERT, UPDATE, DELETE ON items FROM anon, authenticated;
-- 寫入交給 service_role 的 Edge Function（bypass RLS）

-- (2) 機密表：只有帶對的 role claim 才能讀/寫
ALTER TABLE sja_delivery ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON sja_delivery FROM anon;
CREATE POLICY d_read  ON sja_delivery FOR SELECT USING ((auth.jwt()->>'role') IN ('super','office','admin'));
CREATE POLICY d_write ON sja_delivery FOR ALL    USING ((auth.jwt()->>'role') IN ('super','admin'))
                                                 WITH CHECK ((auth.jwt()->>'role') IN ('super','admin'));

-- (3) QC 食安記錄：可讀（管理員）、可新增，但禁改禁刪（稽核完整性）
ALTER TABLE qc_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY qc_read   ON qc_checks FOR SELECT USING ((auth.jwt()->>'role') IN ('super','office','admin'));
CREATE POLICY qc_insert ON qc_checks FOR INSERT WITH CHECK ((auth.jwt()->>'role') IS NOT NULL);
-- 不建 UPDATE/DELETE policy → 預設拒絕，記錄不可竄改

-- (4) 多租戶（路線 C）：每表加 company_id，政策再加 AND company_id = (auth.jwt()->>'company_id')
```

---

## 5. 上線步驟與風險

**逐表灰度上線（絕不一次全開）：**
1. 先在**一張非關鍵表**（例如 `categories`）試開 RLS + 政策，確認 App 讀寫正常。
2. 再一張一張開，每開一張就**用各角色（guest/staff/office/super）實測**該表相關功能。
3. 全綠後才收掉 anon 的廣泛授權。

**主要風險：** 開錯或漏開一條政策 → 某功能「讀不到資料」而壞掉（不會洩漏，只會壞功能，可快速 rollback：`ALTER TABLE x DISABLE ROW LEVEL SECURITY;`）。

**Rollback：** 每張表都能單獨 `DISABLE ROW LEVEL SECURITY` 立即恢復，風險可控。

---

## 6. 工時估計

| 路線 | 我的工時 | 你要配合 |
|---|---|---|
| A 快速止血（撤寫入 + 寫入走函式） | 0.5~1 天 | 跑 SQL、測試寫入 |
| **B 完整（RLS + email 登入）** | **2~4 天** | 建 auth 使用者、逐表測試（約 2~3 小時） |
| C 多租戶（B + company_id 隔離） | B + 3~5 天 | 較多測試 |

---

## 7. 建議

- **自家員工用** → 現狀（UI 權限）堪用，RLS 不急。
- **近期賣多公司** → 直接做 **B**，一次到位。
- 動工前這份計畫先讓你確認每張表的「誰讀誰寫」是否符合你實際需求（第 2 節表格），改好再寫正式 migration。
