# gudang-app 資安風險清單

> 盤點日期：2026-07-01
> 範圍：資料庫存取權限（RLS）與前端權限模型

## 重要前提：問題不在 anon key 外洩

`SUPA_KEY`（anon key）出現在前端 `index.html`（約第 295 行）是 **Supabase 設計上正常的**——
這把 key 本來就是公開的。**問題不在 key 外洩，而在於「RLS 政策全開」讓這把公開的 key 變成萬能鑰匙。**

👉 **不要去 rotate anon key，那沒有用。** 真正要修的是資料表的 RLS 政策。

---

## 資料表清單

共 7 張表，先前診斷顯示**全部都是 `allow_all_*` 政策** =
任何人拿著前端那把公開 key，就能對每張表隨意讀 / 寫 / 刪。

| 表 | 讀 | 寫 | 刪 | 最嚴重後果 |
|---|:-:|:-:|:-:|---|
| `people` | 🔴 | 🔴 | 🔴 | 管理員接管 / PIN 全洩 |
| `items` | 🟡 | 🟠 | 🟠 | 庫存竄改 / 進價外洩 |
| `item_variants` | 🟡 | 🟠 | 🟠 | 數量歸零 / 刪品項 |
| `item_batches` | 🟡 | 🟠 | 🟠 | FIFO / 效期資料破壞 |
| `transactions` | 🟡 | 🟠 | 🟠 | 稽核軌跡偽造 |
| `transaction_edits` | 🟡 | 🟠 | — | 竄改紀錄的紀錄也可假造 |
| `requests` | 🟢 | 🟡 | 🟡 | 請求灌水 / 刪除 |

---

## 🔴 CRITICAL —— 會直接被接管

### 1. `people` 表寫入全開 → 任何人可變成管理員

> ✅ **已備妥修復（待部署）**：新增 Edge Function `manage-people`（service_role + 6 位數
> admin PIN 授權），前端 people 的新增/改 PIN/設 admin/刪除全改走它；搭配
> `MIGRATION_LOCK_PEOPLE_WRITE.sql` 撤掉 anon 對 people 的 INSERT/UPDATE/DELETE。
> 部署順序：先 `deploy manage-people` + 前端上線 → 再跑該 SQL。

攻擊者不用密碼，直接對 REST API 發請求：

```
POST .../people   { "name":"x", "is_admin":true, "pin":"1234" }
```

或改掉別人的 PIN：

```
PATCH .../people?id=eq.<某管理員>   { "pin":"0000" }
```

然後用自己設的 PIN 登入 → **完整管理員權限**。

> ⚠️ 這就是為什麼「只部署 PIN 保護」擋不住 —— 讀被擋了，但寫還開著，攻擊者改寫就繞過了。

### 2. `people` 表讀取全開 → 全公司 PIN 一次撈光

舊版前端用 `select('*')`，任何人打開 console 就下載到所有人的 PIN + 權限。

> 🟡 這條由 `verify-staff` + `MIGRATION_PROTECT_PIN.sql` 處理，
> **但要配合第 1 點的寫入收緊才有意義**。

### 3. 權限旗標在瀏覽器端判定 → 開 console 就能提權

`IS_ADMIN` / `IS_SUPER` 是前端變數（`index.html` 約 566-567、605-606 行）。
攻擊者在 console 打 `IS_SUPER=true` 就進管理面板。

> 這類前端旗標**永遠不是安全邊界**，真正的門必須在資料庫層（RLS）。

---

## 🟠 HIGH —— 資料被破壞 / 竄改

### 4. 庫存三表（`items` / `item_variants` / `item_batches`）寫入 + 刪除全開

任何人可以：

- 把所有庫存數量歸零 / 亂改
- 刪掉全部產品、批次（FIFO 資料整組壞掉）
- → **營運層級的破壞**，且你不會知道是誰做的

### 5. `transactions` / `transaction_edits`（異動紀錄）可偽造 / 刪除

稽核軌跡本身可被任意 INSERT 假紀錄或 DELETE 真紀錄
→ **出事後查不到、也信不過歷史**。

---

## 🟡 MEDIUM —— 商業情報外洩

### 6. 讀取全開 → 供應商、進價、庫存量全都看得到

`items` 帶 `supplier_name` / `supplier_url` / 價格 / `can_view_pricing`。
競爭對手拿公開 key 就能把你的供應鏈和成本結構抓下來。

---

## 判讀：取決於威脅模型

- **內部信任團隊**（倉庫同事，大家認識）：真實威脅主要是第 2 點（手滑 / 好奇看到密碼）。
  部署 PIN 保護大致夠用，其餘接受風險。
- **在意離職報復 / 外部攻擊 / 競爭對手**：第 1、3、4、5 點才是重點。
  光部署 PIN 保護等於沒做，一定要收緊 RLS 寫入 / 刪除權限。

---

## 建議修復優先序

1. **第 1 點（people 寫入）** —— 最痛、成本最低，先擋管理員接管。
2. **第 4、5 點（庫存 / 異動表寫入刪除）** —— 防營運破壞與稽核造假。
3. **第 2 點（people 讀取）** —— 搭配已備好的 `verify-staff` + `MIGRATION_PROTECT_PIN.sql`。
4. **第 6 點（讀取收斂）** —— 依業務需要決定哪些欄位對匿名開放。
5. **第 3 點（前端旗標）** —— 在 RLS 收好後自然失去攻擊價值；治本仍是 RLS。

> 附註：任何 RLS 收緊都要「先改前端 → 再收權限」，順序顛倒會讓登入 / 載入壞掉。
