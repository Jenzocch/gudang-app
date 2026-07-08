# FQMS — 食品工廠品管系統 (Phase 1 資料庫)

> 對應規劃書 `QC_SYSTEM_PLAN.md` v1.3。這裡目前只放 **Phase 1 資料庫 schema**（SQL）。

## 這是什麼、不是什麼

FQMS 是**獨立系統**（規劃書 §8.7、三系統整合計劃 §一 定案）：

- ⚠️ **獨立的 Supabase 專案**（規劃書代號「專案 C」），**不是** Gudang One 的正式庫
  （`klswfuzuhlowzrbncreu`）。這批 SQL 請貼進 **FQMS 專屬的新 Supabase 專案**，
  不要跑到 Gudang One 或 FAMMS 的資料庫。
- 與 Gudang One / FAMMS **不共庫、不共帳號**，只透過「編號 + 事件」串接。
- 與 Gudang One 的串接插座已在 schema 內預埋（見下方「串接插座」），實作走
  現有的 `qc-lookup` / `qc-status` Edge Functions（見 `docs/PLAN_3SYSTEM_INTEGRATION.md`）。

## 檔案與執行順序

在 FQMS 新專案的 **Supabase Dashboard → SQL Editor** 依序貼上執行（皆可重複執行）：

| 順序 | 檔案 | 內容 |
|---|---|---|
| 1 | `db/01_core_schema.sql` | 建表、索引、`updated_at` 觸發器、自動編號函式 |
| 2 | `db/02_rls.sql` | 啟用 RLS、角色 helper、4 角色政策、保護 `pin_hash` |
| 3 | `db/03_seed_example.sql` | （選用）附錄A 椰果 FQC 13 項範例，方便馬上試點 |

## 資料表一覽（對應規劃書 §4）

**設定層（主管維護，低頻）**

| 表 | 用途 |
|---|---|
| `qc_users` | 使用者 + 角色（掛 `auth.users`）；語言偏好、共用平板 PIN |
| `products` | 產品主檔（含 BPOM MD 號、Halal 效期） |
| `test_items` | 檢驗項目庫（`result_type` = numeric/pass_fail/select/text ★核心彈性） |
| `customers` | 客戶主檔（CoA 語言偏好） |
| `suppliers` | 供應商主檔（Halal 效期、評分） |
| `product_specs` | 產品規格標準（**版本化**；客戶專屬 `customer_id`；`is_ccp`；抽樣數與判定規則） |
| `inspection_templates` | 檢驗模板（產品 × 階段 + `frequency` 供任務自動生成） |
| `template_items` | 模板明細（項目排序） |

**執行層（檢驗員操作，高頻）**

| 表 | 用途 |
|---|---|
| `batches` | 批號主檔 + **批次狀態機**（released/hold/…）+ 追溯 `parent_batch_ids` |
| `inspections` | 檢驗單表頭（`partial` 部分完成；自動編號 `QC-YYYYMMDD-NNN`） |
| `inspection_results` | 檢驗結果明細（`spec_id` 鎖版本、`sample_values` 多樣品、`tested_by` 多人分工） |
| `ncr_records` | 不合格處理單（Phase 1 最小版，進料驗退第一天可記） |
| `inspection_tasks` | 今日任務清單（按人排、由模板 frequency 生成） |

## 角色與權限（RLS，規劃書 §7）

| 角色 (`qc_users.role`) | 主要權限 |
|---|---|
| `inspector` | 輸入檢驗、看**自己的**紀錄、建批號 |
| `supervisor` | 覆核簽核、NCR 處置、設定項目/規格/模板、看全部 |
| `manager` | 儀表板/報表、NCR 放行決定、規格核准 |
| `admin` | 使用者/系統設定 |

- 身分來源是 `qc_users` 表（用 `SECURITY DEFINER` 的 `fqms_role()` 讀取），
  **不是** JWT 的 `role` claim（Supabase 已把它固定為 `authenticated`）。
- `anon` 一律無權：FQMS 沒有公開頁面，全員登入。
- 「release / 規格核准需 Manager 以上」屬**業務規則**，由 App / Edge Function 把關；
  RLS 只做到「supervisor 以上可寫」的粗粒度。

## 啟用後：建第一個使用者

RLS 開啟後，`qc_users` 只能靠 service_role 寫入（比照 Gudang One 的 `manage-people`）。
最快的引導方式：

1. Supabase Dashboard → Authentication → 建一個帳號（email / 密碼），複製其 `user id`。
2. SQL Editor（以 service 身分，bypass RLS）執行：
   ```sql
   INSERT INTO qc_users (id, full_name, role)
   VALUES ('<貼上 auth user id>', 'Admin', 'admin');
   ```
3. 之後的使用者建立、PIN 驗證，改由 FQMS 端的 Edge Function（service_role）處理。

## 自動編號

- 檢驗單號 `inspection_no`：欄位 DEFAULT = `fqms_inspection_no()` → `QC-YYYYMMDD-NNN`
- NCR 單號 `ncr_no`：DEFAULT = `fqms_ncr_no()` → `NCR-YYYYMMDD-NN`
- 批號 `batch_no`：由 App 依規則產生（`{產品}-{YYMMDD}-{線別}{序}` / `RM-{YYMMDD}-{序}`），
  schema 只保證唯一。取號可用 `fqms_next_seq('<自訂前綴>')`。

## 串接 / 擴充插座（Phase 1 就埋好，之後不改核心）

| 欄位 | 表 | 用途 |
|---|---|---|
| `source_ref` (JSONB) | `batches` | 存 `{gudang_batch_id, lot_no, warehouse}`，IQC「從倉庫帶入」用 |
| `entry_source` + `source_ref` | `inspection_results` | 資料來源（manual/excel_import/instrument/lab_import/api），規劃書 §8.2 |
| `machine_code` | `ncr_records` | 疑似設備造成的品質問題記機台碼，Phase 2 一鍵開 FAMMS 工單 |

## 尚未納入（留待 Phase 2+，見規劃書 §9）

供應商退貨、客訴/客戶退貨、檢驗標準參考庫（限度樣品照）、CoA 生成、
輸出中心 + 機密分級、結果 Excel/CSV 匯入、儀表板、儀器校正、SPC。
核心 5 組表不會因為加這些而改結構（規劃書 §8.1「輕量核心 + 擴充插座」）。

## 判定邏輯放哪

`inspection_results.judgment` 由 **App** 依 `spec_id` 鎖定的規格即時算：
- numeric：多樣品依 `product_specs.judgment_rule`（`average` 平均合格 / `each` 逐樣品合格）
  比對 `spec_min`/`spec_max`；
- pass_fail / select：比對 `spec_text` / `select_options`。

schema 只負責**存**判定結果與**鎖**當時規格版本（稽核用），不在資料庫層硬算，
維持「檢驗項目 = 資料，不是程式碼」。
