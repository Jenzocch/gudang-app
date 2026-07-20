// Supabase Edge Function: notify-telegram
// Telegram Bot Token disimpan sebagai secret di backend; frontend tidak pernah melihat token.
//
// PENTING (model keamanan): fungsi ini dipanggil dari frontend zero-trust (anon key ADA di
// browser), jadi rahasia apa pun yang dititip ke frontend tidak memberi perlindungan nyata.
// Karena itu fungsi ini TIDAK menerima teks pesan bebas. Ia hanya menerima {type, params}
// terstruktur dan MENYUSUN sendiri teks pesan dari template tetap di sisi server. Dengan begitu
// pihak lain yang punya anon key hanya bisa memicu bentuk pesan yang sudah ditentukan (mengisi
// parameternya sendiri), bukan menyiarkan pesan palsu berwibawa (mis. "QC GAGAL" karangan) ke
// grup staf. Semua nilai dari client di-escape untuk HTML Telegram, dan waktu dibuat di server.
//
// Deploy (set secret sekali, lalu deploy):
//   supabase secrets set TELEGRAM_BOT_TOKEN="token-baru"
//   supabase secrets set TELEGRAM_CHAT_IDS="5003966994,6860586246,8388678925,5097723576"
//   supabase functions deploy notify-telegram

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Escape untuk HTML Telegram (parse_mode=HTML) + potong panjang agar tidak bisa dipakai spam.
function esc(v: unknown): string {
  return String(v == null ? "" : v)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .slice(0, 300);
}

// Angka aman (untuk qty/min) — hanya digit/desimal/minus, bukan teks bebas.
function num(v: unknown): string {
  const s = String(v == null ? "" : v).replace(/[^\d.,-]/g, "").slice(0, 20);
  return s || "0";
}

// Waktu dibuat di server (WIB = UTC+7), bukan dari client.
function nowWIB(): string {
  const d = new Date(Date.now() + 7 * 3600 * 1000);
  return d.toISOString().replace("T", " ").slice(0, 16) + " WIB";
}

// ── Template pesan (satu-satunya sumber teks yang boleh dikirim) ──
function composeMessage(type: string, p: Record<string, unknown>): string | null {
  if (type === "low_stock") {
    const empty = p.empty === true || String(p.qty) === "0";
    const lines = [
      (empty ? "❌" : "🟠") + " Stok rendah: " + esc(p.name),
    ];
    if (p.taken_by) {
      lines.push("👤 Diambil oleh: " + esc(p.taken_by) + " (" + num(p.taken_qty) + " " + esc(p.unit) + ")");
    }
    lines.push("📦 Sisa stok: " + num(p.qty) + " " + esc(p.unit) + " (min: " + num(p.critical) + ")");
    if (p.supplier_url) lines.push("🔗 " + esc(p.supplier_url));
    lines.push("🕐 " + nowWIB());
    return lines.join("\n");
  }
  if (type === "qc_fail") {
    const lines = [
      "🔴 <b>QC GAGAL" + (p.ccp === true ? " — CCP!" : "") + "</b> (" + esc(p.warehouse) + ")",
      "📋 " + esc(p.label),
      "👤 " + esc(p.inspector),
    ];
    if (p.corrective) lines.push("🛠 Koreksi: " + esc(p.corrective));
    if (p.note) lines.push("📝 " + esc(p.note));
    lines.push("🕐 " + nowWIB());
    return lines.join("\n");
  }
  return null; // tipe tak dikenal → tidak mengirim apa pun
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
    const chatIdsRaw = Deno.env.get("TELEGRAM_CHAT_IDS") || "";
    if (!token) {
      return json({ ok: false, error: "TELEGRAM_BOT_TOKEN belum di-set" }, 500);
    }
    const chatIds = chatIdsRaw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    if (!chatIds.length) {
      return json({ ok: false, error: "TELEGRAM_CHAT_IDS belum di-set" }, 500);
    }

    const body = await req.json().catch(() => ({}));
    const type = body && body.type ? String(body.type) : "";
    const params = (body && body.params && typeof body.params === "object") ? body.params : {};

    // Teks disusun di server dari template — teks bebas (body.msg) sengaja diabaikan total.
    const text = composeMessage(type, params as Record<string, unknown>);
    if (!text) return json({ ok: false, error: "tipe pesan tidak dikenal" }, 400);

    const results = await Promise.allSettled(
      chatIds.map((cid) =>
        fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ chat_id: cid, text, parse_mode: "HTML" }),
        }),
      ),
    );

    const sent = results.filter((r) => r.status === "fulfilled").length;
    return json({ ok: true, sent, total: chatIds.length });
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
