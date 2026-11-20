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
  const environment = body.environment === "live" || body.environment === "simulation"
    ? body.environment
    : "";
  if (!environment) {
    return new Response(JSON.stringify({ error: "environment" }), { status: 400 });
  }

  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  if (environment === "live") {
    if (bearer !== serviceKey) {
      return new Response(JSON.stringify({ error: "live imports are server-only" }), { status: 403 });
    }
    const serviceClient = createClient(supabaseUrl, serviceKey);
    const { data, error } = await serviceClient.rpc("import_affiliate_events", {
      p_events: Array.isArray(body.events) ? body.events : [],
      p_environment: "live"
    });
    if (error) {
      return new Response(JSON.stringify({ error: "import_failed" }), { status: 400 });
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
  const { data, error } = await userClient.rpc("import_affiliate_events", {
    p_events: Array.isArray(body.events) ? body.events : [],
    p_environment: "simulation"
  });
  if (error) {
    return new Response(JSON.stringify({ error: "import_failed" }), { status: 400 });
  }
  return new Response(JSON.stringify(data), { headers: { "content-type": "application/json" } });
});
