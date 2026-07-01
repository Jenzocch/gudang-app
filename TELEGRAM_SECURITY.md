# Telegram 通知安全化（token 移到後端）

## 為什麼

舊版把 `TG_TOKEN` 明文寫在 `index.html`，任何人 F12 看原始碼就能拿到，
可冒充 bot 發訊息。已改成：**token 只存在 Supabase Edge Function 的 secret，
前端完全不持有 token**。

## 部署步驟（一次性）

### 1. 撤銷舊 token、產生新 token
- Telegram 找 **@BotFather** → `/revoke` → 選你的 bot → 取得**新 token**
- 舊 token 立即失效，外洩那個就廢了

### 2. 設定 Supabase secrets
在專案目錄執行（需先 `supabase login` 並 `supabase link`）：

```bash
supabase secrets set TELEGRAM_BOT_TOKEN="貼上新的token"
supabase secrets set TELEGRAM_CHAT_IDS="5003966994,6860586246,8388678925,5097723576"
```

> CHAT_IDS 是原本前端 TG_IDS 那 4 個，用逗號分隔。要增減收訊人改這裡即可。

### 3. 部署 Edge Function

```bash
supabase functions deploy notify-telegram
```

### 4. 完成
前端 `sendTelegram()` 已改成呼叫 `notify-telegram`，部署後低庫存通知照常運作，
但 token 不再出現在任何前端代碼。

## 測試

在瀏覽器 Console：

```js
sb.functions.invoke('notify-telegram', { body: { msg: '✅ 測試訊息' } })
  .then(console.log);
```

收到訊息 = 成功。若回 `TELEGRAM_BOT_TOKEN belum di-set` → secret 沒設好。

## 注意

- 若設好新 token 後，每天 8:21 那種定時通知**還在用舊 token**（會失敗/或仍送出），
  代表另有一個 Google Apps Script 觸發器持有舊 token。撤銷舊 token 後它會失效，
  屆時去 Apps Script 的 Triggers 找出來關掉即可。

---

# Admin PIN 安全化（PIN 移到後端）

## 為什麼

舊版把 `ADMIN_PIN = '123456'` 明文寫在 `index.html`，任何人 F12 就能拿到 admin 密碼。
已改成：**PIN 只存在 Supabase Edge Function `verify-admin` 的 secret，前端只送使用者輸入值。**

> ⚠️ 這移除了「明文洩漏」也擋住一般人，但**真正的資料保護要靠資料表 RLS**（見 audit 第 1 點）。
> 在 RLS 收好之前，這層屬於 UI 閘門，不是最終防線。

## 部署步驟（一次性）

```bash
# 1) 設定 admin PIN secret（換成你要的 6 位數，不要再用 123456）
supabase secrets set ADMIN_PIN="你的6位數PIN"

# 2) 部署函數
supabase functions deploy verify-admin
```

## 測試

在瀏覽器 Console：

```js
sb.functions.invoke('verify-admin', { body: { pin: '你設的PIN' } }).then(console.log);
// 預期 { ok: true }；輸入錯的 PIN 應回 { ok: false }
```

或直接在 App 的 Admin 分頁輸入 PIN，能進入 = 成功。
若回 `ADMIN_PIN belum di-set` → secret 沒設好。
