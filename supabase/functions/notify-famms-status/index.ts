// Supabase Edge Function: notify-famms-status
// 線③（Gudang → FAMMS）：叫料單狀態變動時回呼 FAMMS，讓 incident 頁的
// 追蹤清單顯示「到貨了/被拒絕了」。只處理 source='famms' 的請求；本地手動
// 建立的請求（source 為 NULL）一律略過，不通知。
//
// 由前端在 updReq()/confirmApproveReqBuy() 之後呼叫，走 sb.functions.invoke()
// （帶 anon key，跟 notify-telegram 同一種呼叫方式，不需 --no-verify-jwt）。
// FAMMS 那邊的密鑰只存在這個函式的 secret，前端永遠看不到。
//
// 部署：
//   supabase secrets set FAMMS_SYNC_URL="https://<famms網域>/api/external/parts-requests"
//   supabase secrets set GUDANG_SYNC_SECRET="一段長隨機字串"   （與 FAMMS 端 GUDANG_SYNC_SECRET 相同）
//   supabase functions deploy notify-famms-status
//
// 呼叫（Gudang 前端）：
//   sb.functions.invoke('notify-famms-status', { body: { request_id: <requests.id> } })

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Gudang 本地狀態 → FAMMS parts_requests 的狀態字彙
// （Gudang 沒有「已訂購 ordered」這個中間態，approved=已購買入庫 直接視同 received）
const STATUS_MAP: Record<string, string> = {
  approved: "received",
  rejected: "rejected",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const fammsSyncUrl = Deno.env.get("FAMMS_SYNC_URL");
    const secret = Deno.env.get("GUDANG_SYNC_SECRET");
    if (!url || !serviceKey) return json({ ok: false, error: "server not configured" }, 500);

    const body = await req.json().catch(() => ({}));
    const requestId = body.request_id;
    if (requestId == null) return json({ ok: false, error: "request_id wajib" }, 400);

    const admin = createClient(url, serviceKey);
    const { data: r, error } = await admin
      .from("requests")
      .select("id, status, source, famms_request_id")
      .eq("id", requestId)
      .single();
    if (error || !r) return json({ ok: false, error: "request tidak ditemukan" }, 404);

    // 不是 FAMMS 送來的，或這筆沒有 FAMMS 端的 id → 沒有東西可通知，安靜結束
    if (r.source !== "famms" || !r.famms_request_id) {
      return json({ ok: true, skipped: "not a famms-origin request" });
    }

    const mapped = STATUS_MAP[String(r.status)];
    if (!mapped) {
      // 還在 pending 之類的中間態，還沒有值得回報的結果
      return json({ ok: true, skipped: "status not terminal" });
    }

    if (!fammsSyncUrl || !secret) {
      return json({ ok: false, error: "FAMMS_SYNC_URL / GUDANG_SYNC_SECRET belum di-set" }, 500);
    }

    const resp = await fetch(fammsSyncUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${secret}`,
      },
      body: JSON.stringify({
        request_id: r.famms_request_id,
        status: mapped,
        external_ref: String(r.id),
      }),
    });
    const out = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      return json({ ok: false, error: out.error || `FAMMS menolak (${resp.status})` }, 502);
    }
    return json({ ok: true, famms: out });
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
