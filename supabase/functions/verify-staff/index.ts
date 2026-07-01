// Supabase Edge Function: verify-staff
// 員工 PIN 留在後端驗證，前端不再把整張 people（含 pin）下載到瀏覽器。
//
// 用 service_role 讀 people、比對 pin，成功回傳該員工資料（不含 pin）。
// service_role 會略過 RLS，所以即使把 people.pin 欄位對 anon 撤權，這裡仍讀得到。
//
// 部署（SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 由平台自動注入，不用自己設）：
//   supabase functions deploy verify-staff

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 常數時間比較，避免時序側漏
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
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !serviceKey) {
      return json({ ok: false, error: "server not configured" }, 500);
    }
    const body = await req.json().catch(() => ({}));
    const personId = body && body.person_id;
    const pin = (body && body.pin ? String(body.pin) : "").trim();
    if (personId === undefined || personId === null || personId === "") {
      return json({ ok: false, error: "person_id kosong" }, 400);
    }
    if (!pin) return json({ ok: false, error: "pin kosong" }, 400);

    const admin = createClient(url, serviceKey);
    const { data, error } = await admin
      .from("people")
      .select("*")
      .eq("id", personId)
      .limit(1);
    if (error) return json({ ok: false, error: error.message }, 500);
    if (!data || !data.length) return json({ ok: false, error: "not found" }, 404);

    const person = data[0] as Record<string, unknown>;
    const expected = person.pin ? String(person.pin) : "1234";
    if (!safeEqual(pin, expected)) return json({ ok: false });

    delete person.pin; // 永遠不回傳 pin
    return json({ ok: true, person });
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
