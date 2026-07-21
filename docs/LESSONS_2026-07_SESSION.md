# Gudang One — 開發教訓合輯（2026-07 session）

> 這輪 session 用真實事故換來的四課。共同主題只有一句話：
> **「工具回報成功」和「你以為的那件事成功了」是兩回事。**
> （repo 內的正式版本在 `.claude/lessons/`，一檔一課；這份是給人讀的合輯。）

---

## 第 1 課：安全包裝函式會把「欄位不存在」永遠吞掉

**一句話**：`sbInsertSafe`/`sbUpdateSafe` 遇到不存在的欄位會自動剔除重試——所以一個從來沒建過的欄位會*永遠靜默失敗*；最後是原生 SQL 讓它現形。

**症狀**：品項表單的「📝 Catatan」（備註）和低庫存「🔕 不要提醒」（`#noalert`）看起來存檔正常好幾個月，但實際上什麼都沒存進去。沒有錯誤、沒有 toast——畫面顯示的值是表單自己的狀態。

**根因**：`items.remark` 從來沒有任何 migration 建過。安全包裝函式的本意是撐過 schema 落差（新程式先上線、使用者晚點才跑 migration）：遇到「column does not exist」就把那個欄位從資料裡刪掉重試（最多 8 次）。對*其他*欄位這是正確的救援，但對永久缺失的欄位，等於每一次寫入都無聲丟棄。直到手寫的 seed SQL（`MIGRATION_SEED_DIN_MATERIALS.sql`）直接引用 `remark`——原生 SQL 沒有這種降級機制——才大聲報錯 `column "remark" does not exist`。

**修法**：`MIGRATION_ITEMS_REMARK.sql`（`ADD COLUMN IF NOT EXISTS remark text`）。

**預防**：
- 前端要讀寫某個 DB 欄位前，先 grep `migrations/` 確認真的有 migration 建過它——「程式能跑、存檔看起來成功」不算證據
- 把安全包裝函式當成「部署空窗期的橋」，不是「隨便引用不存在欄位的許可證」
- 原生 SQL 的 seed／backfill 檔順便就是免費的 schema 檢查——它報錯的欄位，App 一直在偷偷丟

---

## 第 2 課：`items` 新欄位要同時加進兩個 flatten 白名單

**一句話**：每個新 `items` 欄位都必須同時加進 `flattenItems()` **和** `preloadAllWarehouses()` 裡那份複製的 inline flatten——漏一邊，欄位進得了 DB 卻到不了 UI。

**症狀**：新欄位存檔正常、目前倉庫顯示正常，但**切倉之後莫名變空白**（或任何吃預載快取的功能——例如首頁全倉搜尋——讀不到）。

**根因**：`item_variants.select('*, items(*)')` 的原始查詢結果，是透過**明列欄位白名單**壓平成 `DATA.items` 的，而這份白名單存在**兩個地方**：`flattenItems()`（即時載入）和 `preloadAllWarehouses()` 裡面複製的一份（切倉用的 localStorage 快取）。只加一邊的欄位「某些畫面正常、某些畫面消失」——比全面壞掉更陰險，因為看起來像做完了。

**同一輪 session 踩了兩次**：`supplier_whatsapp` 一次、`pcs_per_ctn` 一次——每次都是欄位在 DB 裡好好的、存檔正常，但某個渲染路徑就是顯示空白。

**預防**：加任何 `items`/`item_variants` 欄位時，grep 一個既有的壓平欄位（例如 `supplier_whatsapp:`）——每個命中的位置都是需要補新欄位的白名單。如果踩到第三次，就該把兩處抽成一個共用的 flatten 函式（見 `single-source-of-truth`）。

---

## 第 3 課：deploy 上傳的是資料夾現狀，不是 git 上的版本

**一句話**：`supabase functions deploy` 上傳的是本機資料夾裡的檔案——`git pull` **失敗**之後看到的「Deployed ✓」，是把舊版無聲送上線。

**症狀（2026-07-21 真實事故）**：使用者跑 `git pull origin main`（**中止了**——「local changes would be overwritten … Aborting」），接著跑 `supabase functions deploy qc-lookup qc-status`。指令回報成功——但它上傳的是幾個月前的本機舊檔，把幾分鐘前才透過 Dashboard 部署好的新版蓋掉了。

**根因**：部署工具讀的是磁碟上的檔案，完全不管 git 狀態。「部署成功」的意思是「資料夾裡有什麼就上傳了什麼」，不是「上傳了 main 上的版本」。過期的 checkout ＋ 舊 Codex session 留下的未提交修改，讓資料夾落後了大家以為要上線的版本兩個狀態。

**當時有效的修法**：
```
git stash push -m backup     ← 先把本機殘留收起來（可找回，不是刪除）
git pull origin main         ← 必須真的看到 Fast-forward／檔案清單，沒有 Aborting
supabase functions deploy qc-lookup qc-status
```

**預防**：
- 給使用者的部署指示必須是**帶檢查點的流程**：先 pull → **確認 pull 成功**（有更新檔案清單、沒有 Aborting）→ 才 deploy。要把「失敗長什麼樣子」講清楚——人會把「指令有印東西」當成成功
- 重要部署完成後驗**內容**而非狀態：打開 Dashboard 的 Code 分頁，找只有新版才有的標記（例如某行特徵註解）
- 跟第 4 課同一家族：成功訊息只保證「*某個*東西出去了」，從不保證「出去的是你要的那個」

---

## 第 4 課：合併 API 回報成功 ≠ 你最新的 commit 進了 main

**一句話**：push 之後立刻用 API 合併 PR，可能抓到**舊的分支狀態**——每次合併後都要用 `git merge-base --is-ancestor <sha> origin/main` 獨立驗證。

**同一輪 session 發生兩次，都是靠 git 獨立驗證才發現**：

1. **Stacked-PR 時序（PR #28→#29）**：PR #28 的 base 是另一個 PR 的功能分支；base PR 先合進了 main，於是 #28 的「合併」把 commit 折進一個已經合併過的分支引用——什麼都沒真正進 main。
2. **Push 後立刻合併（PR #36→#37）**：先 push 一個 commit、更新 PR 說明、然後呼叫 `merge_pull_request`——但 GitHub 合併的是 PR 的*前一個* head；剛 push 的 commit 靜靜留在 main 外面，而 push 和合併都回報成功。

**為什麼嚴重**：兩次合併 API 都回傳成功、PR 都顯示「Merged」。相信那個狀態，等於相信一個沒上線的修復已經上線。UI/API 的「merged」指的是*某個* head，不必然是你剛 push 的那個。

**預防**：任何合併之後（或使用者說「已合併」時），跑
```
git fetch origin main
git merge-base --is-ancestor <你最新的-sha> origin/main   ← exit 0 = 真的在 main 裡
```
可疑時再用 `git cat-file -p <merge-sha>` 看合併 commit 的 parent。如果 commit 被留在外面：功能分支上還有它——從同一條分支對 main 再開一個 PR，帶的就正好是缺的那段差異。

---

## 總結：四課其實是同一課

| 課 | 「成功」訊息說的是 | 實際上發生的是 |
|---|---|---|
| 1 | 存檔成功（toast ✓） | 欄位被靜默剔除，資料丟了 |
| 2 | 存檔成功、目前畫面正常 | 另一條渲染路徑根本讀不到 |
| 3 | Deployed ✓ | 上傳的是舊版檔案 |
| 4 | Pull Request successfully merged | 最新 commit 沒進 main |

**每一次「完成」都要用獨立的方法驗證內容本身**——grep migration 確認欄位存在、兩條渲染路徑都實測、Code 分頁找新版標記、`merge-base --is-ancestor` 驗 commit。狀態訊息是別人的結論，不是你的證據。
