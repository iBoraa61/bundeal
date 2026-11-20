import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method" }), { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!authHeader || !supabaseUrl || !anonKey || !serviceKey) {
    return new Response(JSON.stringify({ error: "unavailable" }), { status: 503 });
  }

  const body = await req.json().catch(() => ({}));
  const transactionId = typeof body.transaction_id === "string" ? body.transaction_id : "";
  if (!transactionId) {
    return new Response(JSON.stringify({ error: "transaction" }), { status: 400 });
  }

  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  if (bearer === serviceKey) {
    const serviceClient = createClient(supabaseUrl, serviceKey);
    const { data, error } = await serviceClient.rpc("process_commission", {
      p_transaction_id: transactionId
    });
    if (error) {
      return new Response(JSON.stringify({ error: "process_failed" }), { status: 400 });
    }
    return new Response(JSON.stringify(data), { headers: { "content-type": "application/json" } });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: "auth" }), { status: 401 });
  }
  const { data, error } = await userClient.rpc("process_commission", {
    p_transaction_id: transactionId
  });
  if (error) {
    return new Response(JSON.stringify({ error: "process_failed" }), { status: 400 });
  }
  return new Response(JSON.stringify(data), { headers: { "content-type": "application/json" } });
});
