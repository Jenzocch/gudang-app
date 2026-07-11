// Supabase Edge Function: qc-checks-lookup
// FQMS（品管系統）→ Gudang One 的「QC 檢查紀錄」唯讀查詢入口。
//
// 目的：倉庫人員在 Gudang One 的 ✅ QC/Kualiti 分頁做的檢查（qc_checks，含
// inspector_name 檢查人姓名），讓 FQMS 那邊看得到——檢驗員開單時知道「這批倉庫
// 已經檢過了、誰檢的、結果如何」，兩邊分工不重複輸入；倉庫沒空檢的批次，FQMS
// 檢驗員照原本流程檢，互為備援。
//
// 兩種查法：
//   { ref_type, ref_id }        ← 查某一批/某筆生產記錄的檢查（FQMS 開單/追溯用；
//                                  ref_id 就是 FQMS source_ref 裡存的 gudang_batch_id）
//   { date, warehouse? }        ← 查某天（WIB）的全部檢查（FQMS 每日報表用）
//
// 部署：
//   supabase functions deploy qc-checks-lookup
//   （QC_WEBHOOK_SECRET 沿用 qc-lookup/qc-status/qc-production-summary 同一把）
//
// 呼叫（FQMS 的 Next.js 伺服器端，src/lib/gudang.ts 的 callGudang()）：
//   POST /functions/v1/qc-checks-lookup
//   headers: { "x-qc-secret": <QC_WEBHOOK_SECRET>, "Content-Type": "application/json" }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-qc-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const REF_TYPES = ["item_batch", "din_production", "sja_production"];
const WAREHOUSES = ["DENIKIN", "SJA", "HARDWARE", "OLENTIA"];
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// 回應欄位白名單：FQMS 只拿得到這些（data 明細/照片先不外流，要看細節去 Gudang 看）
function pick(c: Record<string, unknown>) {
  return {
    id: c.id,
    warehouse_id: c.warehouse_id ?? "",
    scope: c.scope ?? "",
    ref_type: c.ref_type ?? "",
    ref_id: c.ref_id ?? "",
    ref_label: c.ref_label ?? "",
    inspector_name: c.inspector_name ?? "",
    result: c.result ?? "pending",
    ccp_fail: c.ccp_fail ?? false,
    note: c.note ?? "",
    checked_at: c.checked_at ?? null,
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const secret = Deno.env.get("QC_WEBHOOK_SECRET");
    if (!url || !serviceKey) return json({ ok: false, error: "server not configured" }, 500);
    if (!secret) return json({ ok: false, error: "QC_WEBHOOK_SECRET belum di-set" }, 500);

    const given = (req.headers.get("x-qc-secret") || "").trim();
    if (!given || !safeEqual(given, secret)) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const refType = (body.ref_type == null ? "" : String(body.ref_type)).trim();
    const refId = (body.ref_id == null ? "" : String(body.ref_id)).slice(0, 60).trim();
    const date = (body.date == null ? "" : String(body.date)).trim();
    const warehouse = (body.warehouse == null ? "" : String(body.warehouse)).slice(0, 20).trim().toUpperCase();

    const admin = createClient(url, serviceKey);
    const SELECT =
      "id, warehouse_id, scope, ref_type, ref_id, ref_label, inspector_name, result, ccp_fail, note, checked_at";

    // 模式一：查某一批/某筆生產記錄
    if (refType && refId) {
      if (!REF_TYPES.includes(refType)) {
        return json({ ok: false, error: "ref_type harus salah satu: " + REF_TYPES.join("/") }, 400);
      }
      const { data, error } = await admin
        .from("qc_checks")
        .select(SELECT)
        .eq("ref_type", refType)
        .eq("ref_id", refId)
        .order("checked_at", { ascending: false })
        .limit(10);
      if (error) return json({ ok: false, error: error.message }, 500);
      return json({ ok: true, checks: (data || []).map(pick) });
    }

    // 模式二：查某天（WIB，UTC+7 全年無日光節約）的全部檢查
    if (DATE_RE.test(date)) {
      // checked_at 由前端 toISOString() 寫入（UTC），把 WIB 當天換算成 UTC 範圍過濾。
      const start = new Date(`${date}T00:00:00+07:00`);
      const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
      let q = admin
        .from("qc_checks")
        .select(SELECT)
        .gte("checked_at", start.toISOString())
        .lt("checked_at", end.toISOString());
      if (warehouse && WAREHOUSES.includes(warehouse)) q = q.eq("warehouse_id", warehouse);
      const { data, error } = await q.order("checked_at", { ascending: false }).limit(200);
      if (error) return json({ ok: false, error: error.message }, 500);
      return json({ ok: true, checks: (data || []).map(pick) });
    }

    return json({ ok: false, error: "butuh ref_type+ref_id atau date (YYYY-MM-DD)" }, 400);
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
