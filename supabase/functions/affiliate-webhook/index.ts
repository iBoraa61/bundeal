// Webgains signature rules are not verified yet. The endpoint stays closed.
Deno.serve(async (req) => {
  const configured = Deno.env.get("AFFILIATE_WEBHOOK_SECRET") ?? "";
  const provided = req.headers.get("x-bundeal-signature") ?? "";
  if (!configured || provided !== configured) {
    return new Response(JSON.stringify({ error: "rejected" }), {
      status: 401,
      headers: { "content-type": "application/json" }
    });
  }

  return new Response(JSON.stringify({ error: "webhook_not_enabled" }), {
    status: 501,
    headers: { "content-type": "application/json" }
  });
});
