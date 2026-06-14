# Gudang App — Setup Instructions

## File yang ada di sini
- index.html  → upload ke Vercel
- Code.gs     → copy paste ke Apps Script
- README.md   → panduan ini

## Langkah Setup

### Step 1 — Apps Script
1. Buka Google Sheet: https://docs.google.com/spreadsheets/d/1cyyNcaF_eQwdgytsG-U2UGkni8ibgjj4F4Uo2Kgbm-8
2. Extensions → Apps Script
3. Hapus semua kode lama (Ctrl+A → Delete)
4. Copy semua isi Code.gs → Paste → Ctrl+S
5. Pilih function "initSheets" → Run (izinkan akses)
6. Deploy → New deployment → Web App
   - Execute as: Me
   - Who has access: Anyone
7. Copy URL yang didapat

### Step 2 — Update index.html
Buka index.html dengan Notepad
Cari: AKfycbyRpfaUvwJRPV5IQhQohC7s9VbhR3qSNvWm7cdDbaUhxie8R1jrOwOid0i-cucR9NUPlg
Ganti dengan URL baru kamu (bagian panjang di tengah URL)

### Step 3 — Vercel
Upload index.html ke vercel.com

## Info Penting
- Sheet ID: 1cyyNcaF_eQwdgytsG-U2UGkni8ibgjj4F4Uo2Kgbm-8
- Apps Script URL lama: https://script.google.com/macros/s/AKfycbyRpfaUvwJRPV5IQhQohC7s9VbhR3qSNvWm7cdDbaUhxie8R1jrOwOid0i-cucR9NUPlg/exec
- Vercel: https://gudanginventory-zeta.vercel.app
