import { execFileSync } from "node:child_process";
import fs from "node:fs";

const configSource = fs.readFileSync(new URL("../../js/config.js", import.meta.url), "utf8");
const url = configSource.match(/url:\s*"([^"]+)"/)[1];
const key = configSource.match(/publishableKey:\s*"([^"]+)"/)[1];

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exitCode = 1;
    throw new Error(message);
  }
}

async function authPost(path, body) {
  const response = await fetch(url + path, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: key,
      authorization: "Bearer " + key
    },
    body: JSON.stringify(body)
  });
  const text = await response.text();
  let payload = {};
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (error) {
      payload = { raw: text };
    }
  }
  return { response, payload };
}

async function rest(path, token, options) {
  const response = await fetch(url + path, {
    method: options.method,
    headers: {
      "content-type": "application/json",
      apikey: key,
      authorization: "Bearer " + token,
      prefer: "return=representation"
    },
    body: options.body ? JSON.stringify(options.body) : undefined
  });
  const text = await response.text();
  let payload = text ? JSON.parse(text) : null;
  return { response, payload };
}

function cleanup() {
  execFileSync("docker", [
    "exec",
    "supabase_db_bundeal-dev",
    "psql",
    "-U",
    "postgres",
    "-d",
    "postgres",
    "-v",
    "ON_ERROR_STOP=1",
    "-c",
    "delete from auth.users where email like 'phase2-%@example.com';"
  ], { stdio: "inherit" });
}

function localServiceKey() {
  const output = execFileSync("npx", ["--yes", "supabase@latest", "status", "-o", "env"], {
    encoding: "utf8",
    shell: true,
    stdio: ["ignore", "pipe", "pipe"]
  });
  const match = output.match(/SERVICE_ROLE_KEY="([^"]+)"/);
  if (!match) throw new Error("local service key missing");
  return match[1];
}

async function recoveryRedirect(serviceKey, email, redirectTo) {
  const response = await fetch(url + "/auth/v1/admin/generate_link", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: serviceKey,
      authorization: "Bearer " + serviceKey
    },
    body: JSON.stringify({
      type: "recovery",
      email: email,
      redirect_to: redirectTo
    })
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error("generate_link failed with status " + response.status + " " + String(payload.msg || payload.error_code || payload.error || ""));
  }
  return String(payload.redirect_to || "");
}

const password = "phase2-pass";

try {
  cleanup();

  const first = await authPost("/auth/v1/signup", {
    email: "phase2-api-a@example.com",
    password: password,
    data: {
      username: "phase2_api",
      display_name: "Phase Zwei",
      role: "admin",
      referral_code: "hijacked01"
    }
  });
  assert(first.response.ok, "signup failed: " + JSON.stringify(first.payload));
  const token = first.payload.access_token;
  const userId = first.payload.user && first.payload.user.id;
  assert(token && userId, "signup did not return a session");

  const ownProfile = await rest("/rest/v1/profiles?select=username,display_name,referral_code&id=eq." + userId, token, { method: "GET" });
  assert(ownProfile.response.ok, "own profile read failed");
  assert(ownProfile.payload.length === 1, "own profile was not created");
  assert(ownProfile.payload[0].username === "phase2_api", "username from signup was lost");
  assert(/^([a-z0-9]{10})$/.test(ownProfile.payload[0].referral_code), "referral code was not server-generated");
  assert(ownProfile.payload[0].referral_code !== "hijacked01", "client supplied the referral code");

  const ownRoles = await rest("/rest/v1/user_roles?select=role&user_id=eq." + userId, token, { method: "GET" });
  assert(ownRoles.response.ok && ownRoles.payload.length === 1 && ownRoles.payload[0].role === "user", "signup metadata changed the role");

  const duplicate = await authPost("/auth/v1/signup", {
    email: "phase2-api-b@example.com",
    password: password,
    data: { username: "phase2_api" }
  });
  assert(!duplicate.response.ok, "duplicate username signup succeeded");

  const second = await authPost("/auth/v1/signup", {
    email: "phase2-api-b@example.com",
    password: password,
    data: { username: "phase2_other" }
  });
  assert(second.response.ok, "second signup failed");
  const otherId = second.payload.user.id;
  const otherToken = second.payload.access_token;

  const hidden = await rest("/rest/v1/profiles?select=id&id=eq." + userId, otherToken, { method: "GET" });
  assert(hidden.response.ok && hidden.payload.length === 0, "another user read a private profile");

  const roleWrite = await rest("/rest/v1/user_roles", token, {
    method: "POST",
    body: { user_id: userId, role: "admin" }
  });
  assert(!roleWrite.response.ok, "user inserted an admin role");

  const codeWrite = await rest("/rest/v1/profiles?id=eq." + userId, token, {
    method: "PATCH",
    body: { referral_code: "zzzzzzzzzz" }
  });
  assert(!codeWrite.response.ok, "user changed the referral code");

  // GoTrue answers the public recover call with an empty 200 and, when the
  // requested redirect is not allowed, substitutes the configured site URL.
  const serviceKey = localServiceKey();
  const foreignRedirect = "https://evil.example/reset-password.html";
  const allowedRedirect = "http://127.0.0.1:4173/reset-password.html";
  const foreignResult = await recoveryRedirect(serviceKey, "phase2-api-a@example.com", foreignRedirect);
  assert(!foreignResult.includes("evil.example"), "foreign password reset redirect was kept");
  assert(foreignResult === "http://127.0.0.1:4173", "foreign redirect did not fall back to the site URL");
  const allowedResult = await recoveryRedirect(serviceKey, "phase2-api-a@example.com", allowedRedirect);
  assert(allowedResult === allowedRedirect, "allowlisted reset callback was replaced");

  console.log("auth api checks passed");
} finally {
  cleanup();
}
