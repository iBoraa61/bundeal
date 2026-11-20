import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method" }), { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!authHeader || !supabaseUrl || !anonKey) {
    return new Response(JSON.stringify({ error: "unavailable" }), { status: 503 });
  }

  const body = await req.json().catch(() => ({}));
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });
  const { data, error } = await userClient.rpc("begin_affiliate_click", {
    p_deal_slug: body.deal_slug ?? "",
    p_referrer_code: body.referrer_code ?? null
  });
  if (error || !data || typeof data.outbound_url !== "string" || !data.outbound_url.startsWith("https://")) {
    return new Response(JSON.stringify({ error: "click_failed" }), {
      status: 400,
      headers: { "content-type": "application/json" }
    });
  }

  return new Response(JSON.stringify(data), {
    headers: { "content-type": "application/json" }
  });
});
