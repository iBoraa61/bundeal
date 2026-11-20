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
  const status = body.transaction_status === "rejected" || body.transaction_status === "adjusted" || body.transaction_status === "confirmed"
    ? body.transaction_status
    : "";
  const cents = Number.isInteger(body.commission_amount_cents) ? body.commission_amount_cents : -1;
  if (!transactionId || !status || cents < 0) {
    return new Response(JSON.stringify({ error: "reversal" }), { status: 400 });
  }

  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  const call = async (client: ReturnType<typeof createClient>) => {
    const { data, error } = await client.rpc("reverse_commission", {
      p_transaction_id: transactionId,
      p_new_commission_cents: cents,
      p_new_status: status
    });
    if (error) {
      return new Response(JSON.stringify({ error: "reverse_failed" }), { status: 400 });
    }
    return new Response(JSON.stringify(data), { headers: { "content-type": "application/json" } });
  };

  if (bearer === serviceKey) {
    return call(createClient(supabaseUrl, serviceKey));
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } }
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: "auth" }), { status: 401 });
  }
  return call(userClient);
});
