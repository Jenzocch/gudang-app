// Supabase Edge Function: qc-lookup
// FQMS（品管系統）→ Gudang One 的批號查詢入口（唯讀）。
// QC 開進料檢驗單時「從倉庫帶入」：查單一批號，或列出某倉最近 N 天的批次。
//
// 部署：
//   supabase secrets set QC_WEBHOOK_SECRET="一段長隨機字串"   （與 FQMS 端共享）
//   supabase functions deploy qc-lookup
//
// 呼叫（FQMS 的 Next.js 伺服器端）：
//   POST /functions/v1/qc-lookup
//   headers: { "x-qc-secret": <QC_WEBHOOK_SECRET>, "Content-Type": "application/json" }
//   body: { lot_no } 或 { warehouse, days? }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-qc-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// 常數時間比較，避免時序側漏（與 famms-request 相同做法）
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const WAREHOUSES = ["DENIKIN", "SJA", "HARDWARE", "OLENTIA"];

// 回應欄位白名單：FQMS 只拿得到這些
function pick(b: Record<string, unknown>) {
  const item = (b.items ?? null) as
    | { name?: string; unit?: string; supplier_name?: string }
    | null;
  return {
    id: b.id,
    lot_no: b.lot_no ?? "",
    item_name: item?.name ?? "",
    unit: item?.unit ?? "",
    supplier_name: item?.supplier_name ?? "",
    po_no: b.po_no ?? "",
    production_date: b.production_date ?? null,
    expiry_date: b.expiry_date ?? null,
    qty_initial: b.qty_initial ?? 0,
    qty_remaining: b.qty_remaining ?? 0,
    qc_status: b.qc_status ?? "Pending",
    warehouse_id: b.warehouse_id ?? "",
    received_date: b.received_date ?? null,
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
    const lotNo = (body.lot_no == null ? "" : String(body.lot_no)).slice(0, 60).trim();
    const warehouse = (body.warehouse == null ? "" : String(body.warehouse)).slice(0, 20).trim().toUpperCase();

    const admin = createClient(url, serviceKey);
    const SELECT = "id, lot_no, po_no, production_date, expiry_date, qty_initial, qty_remaining, qc_status, warehouse_id, received_date, items(name, unit, supplier_name)";

    if (lotNo) {
      // 精確查一筆（可選加 warehouse 過濾）
      let q = admin.from("item_batches").select(SELECT).eq("lot_no", lotNo);
      if (warehouse && WAREHOUSES.includes(warehouse)) q = q.eq("warehouse_id", warehouse);
      const { data, error } = await q.order("received_date", { ascending: false }).limit(5);
      if (error) return json({ ok: false, error: error.message }, 500);
      if (!data || !data.length) return json({ ok: false, error: "lot_no tidak ditemukan" }, 404);
      return json({ ok: true, batches: data.map(pick) });
    }

    // 清單模式：某倉最近 N 天（1~90，預設 14）
    if (!WAREHOUSES.includes(warehouse)) {
      return json({ ok: false, error: "warehouse harus salah satu: " + WAREHOUSES.join("/") }, 400);
    }
    let days = Number(body.days) || 14;
    days = Math.max(1, Math.min(90, Math.floor(days)));
    const cutoff = new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);

    const { data, error } = await admin
      .from("item_batches")
      .select(SELECT)
      .eq("warehouse_id", warehouse)
      .gte("received_date", cutoff)
      .order("received_date", { ascending: false })
      .limit(100);
    if (error) return json({ ok: false, error: error.message }, 500);
    return json({ ok: true, batches: (data || []).map(pick) });
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
