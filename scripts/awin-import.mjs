// Local Awin dry-run. Reads the sample file only.
// Live booking stays off. This file has no credentials and does not call the network.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const samplePath = join(dirname(fileURLToPath(import.meta.url)), "..", "supabase", "samples", "awin-transactions.json");
const rows = JSON.parse(readFileSync(samplePath, "utf8"));

if (process.argv.includes("--live")) {
  console.error("Live booking is not enabled.");
  process.exit(1);
}

const money = (value) => /^[0-9]+(\.[0-9]{1,2})?$/.test(String(value))
  ? Math.round(Number(value) * 100)
  : null;
const status = {
  pending: "pending",
  approved: "confirmed",
  declined: "rejected"
};

const summary = { rows: rows.length, ready: 0, invalid: 0 };
for (const row of rows) {
  const cents = money(row.commissionAmount);
  const mapped = status[row.commissionStatus];
  if (!mapped || cents === null || !row.clickRef || !row.id) summary.invalid += 1;
  else summary.ready += 1;
}

console.log(JSON.stringify({
  source: "awin-sample",
  environment: "simulation",
  apply: false,
  live: false,
  tokenUsed: false,
  ...summary
}));
