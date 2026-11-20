import fs from "node:fs";
import vm from "node:vm";

const utilsSource = fs.readFileSync(new URL("../../js/utils.js", import.meta.url), "utf8");
const authSource = fs.readFileSync(new URL("../../js/auth.js", import.meta.url), "utf8");
const clientSource = fs.readFileSync(new URL("../../js/supabase-client.js", import.meta.url), "utf8");
const config = fs.readFileSync(new URL("../config.toml", import.meta.url), "utf8");
const pages = ["login.html", "register.html", "reset-password.html", "dashboard.html"]
  .map((name) => fs.readFileSync(new URL("../../" + name, import.meta.url), "utf8"))
  .join("\n");

const context = { window: {} };
vm.createContext(context);
vm.runInContext(utilsSource, context);
const utils = context.window.bundealUtils;

function assert(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

assert(utils.safeNext("dashboard.html") === "dashboard.html", "dashboard next was rejected");
assert(utils.safeNext("deals.html") === "deals.html", "deals next was rejected");
assert(utils.safeSlug("beispiel-deal") === "beispiel-deal", "deal slug was rejected");
assert(utils.safeSlug("../deal") === "", "unsafe slug was accepted");
assert(utils.safeNext("https://evil.example/dashboard.html") === "dashboard.html", "absolute next was allowed");
assert(utils.safeNext("//evil.example") === "dashboard.html", "protocol-relative next was allowed");
assert(utils.safeNext("../.env") === "dashboard.html", "path traversal was allowed");
assert(utils.safeNext("reset-password.html?next=https://evil.example") === "dashboard.html", "query next was allowed");

const resetCallback = utils.callbackUrl("http://127.0.0.1:4173", "reset-password.html");
assert(resetCallback === "http://127.0.0.1:4173/reset-password.html", "local reset callback is wrong");
assert(utils.callbackUrl("https://evil.example", "reset-password.html") === "", "foreign origin was allowlisted");
assert(utils.callbackUrl("http://127.0.0.1:4173", "dashboard.html") === "", "dashboard was accepted as an auth callback");

for (const url of [
  "http://127.0.0.1:4173/reset-password.html",
  "http://localhost:4173/reset-password.html",
  "https://bundeal.de/reset-password.html",
  "https://www.bundeal.de/reset-password.html",
  "http://127.0.0.1:4173/login.html",
  "https://bundeal.de/login.html"
]) {
  assert(config.includes('"' + url + '"'), "missing allowlisted redirect " + url);
}

const redirectLine = config.split("\n").find((line) => line.trim().startsWith("additional_redirect_urls"));
assert(redirectLine && !redirectLine.includes("*"), "auth redirect list contains a wildcard");
assert(config.includes("minimum_password_length = 8"), "password minimum was not raised");
assert(clientSource.includes("persistSession: true"), "session persistence is disabled");
assert(authSource.includes("callbackUrl"), "reset flow does not use the allowlisted callback helper");
assert(!/service[_-]?role/i.test(authSource + utilsSource + clientSource + pages), "service role appeared in browser files");
assert(utils.usernameError("ab") === "format", "short username was accepted");
assert(utils.usernameError("beta_user") === "", "valid username was rejected");

console.log("auth client checks passed");
