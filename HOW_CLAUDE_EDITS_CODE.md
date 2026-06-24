# 為什麼 Claude 可以直接修改程式碼並推送到 GitHub？

## 這不是普通的 Claude Chat

這是 **Claude Code**（`claude.ai/code`），不是一般的聊天介面。  
Claude Code 是 Anthropic 的 CLI 工具，運行在一個雲端容器（remote execution environment）裡。

---

## 環境架構

```
你（瀏覽器）
    ↕ 對話
Claude Code（雲端容器）
    ├── 工具：Read / Edit / Write / Grep / Glob / Bash
    ├── 已克隆的 Git repo（e.g. gudang-app）
    └── 已設定好的 Git 憑證（可直接 push）
```

當 session 建立時：
1. Anthropic 的雲端啟動一個隔離容器
2. 目標 repo 自動 `git clone` 進容器
3. Git credentials 已預先配置好
4. Claude Code 拿到這些工具的使用權限

---

## Claude Code 有哪些工具？

| 工具 | 作用 |
|------|------|
| `Read` | 讀取任何檔案（含行號） |
| `Edit` | 精確字串替換（old → new） |
| `Write` | 新建或完整覆寫檔案 |
| `Grep` | 在所有檔案中搜尋關鍵字 |
| `Glob` | 依路徑 pattern 找檔案 |
| `Bash` | 執行任何 shell 指令（git、npm、python...） |
| `Agent` | 派出子 agent 做複雜任務 |

---

## 修改程式碼的完整流程

### 第一步：理解現有程式碼
```
Grep → 找關鍵字在哪幾行
Read → 讀取那幾行的實際內容（確認縮排、變數名稱）
```

### 第二步：修改檔案
```
Edit → 把 old_string 換成 new_string
       （必須完全精確，包括空格）
```

### 第三步：推送到 GitHub
```bash
git add index.html
git commit -m "清楚的 commit message"
git push -u origin main
```

Bash 工具直接執行這些指令，結果回傳給 Claude 確認成功。

---

## 給另一個 Claude Code session 的操作說明

如果你是在新 session 裡讀到這份文件，以下是你需要做的事：

### 確認你在正確的 repo
```bash
git remote -v
# 應該看到 jenzocch/gudang-app
```

### 確認分支
```bash
git branch
git status
```

### 修改前一定要先 Read
```
不能憑記憶改程式碼。
每次 Edit 之前，先 Read 目標行數，
確認 old_string 和檔案內容完全一致（含空格、縮排）。
```

### Edit 工具的注意事項
```
old_string 必須在檔案中唯一存在。
如果同樣的字串出現兩次，需要加更多上下文來區分。
改完不需要 Read 回來確認，Edit 失敗會直接報錯。
```

### 批量修改的順序
```
1. 先用 Grep 找出所有需要改的地方
2. 按行號順序，由上到下 Edit
3. 全部 Edit 完成後，一次 commit + push
```

---

## 為什麼用戶只需要「對話」？

因為 Claude Code 把以下三件事合在一起：

```
理解需求（對話）
    +
執行修改（工具）
    +
版本控制（Bash + Git）
    =
用戶只要說「我要什麼」，其他全部自動完成
```

使用者不需要：
- 打開編輯器
- 手動 copy-paste 程式碼
- 執行 git 指令
- 知道哪個檔案的哪一行

---

## 這個 Session 的具體資訊

- **環境**：Claude Code 雲端容器（Remote Execution Environment）
- **主要檔案**：`/home/user/gudang_app/index.html`
- **GitHub Repo**：`jenzocch/gudang-app`（main branch）
- **後端**：Supabase（PostgreSQL）
- **部署**：Vercel（自動從 main branch 部署）
- **模型**：claude-sonnet-4-6

---

## 總結

> 這不是 Claude 有什麼神奇魔法。  
> 這是 **工具 + 雲端環境** 的組合。  
> Claude Code = Claude 大腦 + 檔案系統工具 + Shell 執行權限。  
> 在有這些工具的 session 裡，任何 Claude Code 實例都能做同樣的事。
