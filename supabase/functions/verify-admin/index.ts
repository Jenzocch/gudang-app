// Supabase Edge Function: verify-admin
// Admin PIN 留在後端 secret，前端只送使用者輸入的 PIN，永遠看不到真正的 PIN。
//
// 部署前先設定 secret（在專案目錄執行一次，換成你要的 6 位數）：
//   supabase secrets set ADMIN_PIN="123456"
// 部署：
//   supabase functions deploy verify-admin
//
// 注意：這只是「移除前端明文洩漏 + UI 閘門」。真正的資料保護要靠資料表 RLS。

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 常數時間字串比較，避免用 === 造成的時序側漏
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const expected = Deno.env.get("ADMIN_PIN");
    if (!expected) {
      return json({ ok: false, error: "ADMIN_PIN belum di-set" }, 500);
    }
    const body = await req.json().catch(() => ({}));
    const pin = (body && body.pin ? String(body.pin) : "").trim();
    if (!pin) return json({ ok: false, error: "pin kosong" }, 400);
    return json({ ok: safeEqual(pin, expected) });
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
