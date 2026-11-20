# BunDeal

Statische Website mit geplanter Supabase-Grundlage. Die öffentliche Seite bleibt auf `main`. Backend-Arbeit liegt auf `feature/bundeal-backend`.

## Phase 1

Diese Phase enthält nur die Entwicklungsgrundlage:

- lokale Supabase-Konfiguration
- erste Migrationen für Profile, Rollen, Händler, Kategorien und Audit-Log
- Row Level Security
- öffentliche Client-Vorbereitung ohne geheime Schlüssel

## Phase 2

Diese Phase ergänzt Kontozugang auf demselben Branch:

- `login.html`, `register.html`, `reset-password.html`, `dashboard.html`
- Sitzung über den öffentlichen Supabase-Client
- serverseitiger Empfehlungscode und feste Nutzerrolle
- Tests: `supabase/tests/auth.sql`, `supabase/tests/check-auth-client.mjs`, `supabase/tests/auth-api.mjs`

Die Seiten auf `main` bleiben die öffentliche Website.

## Phase 3 bis 5

- Deals, Vorschläge und Admin-Freigabe
- direkte Empfehlung nach Regel `direct-v1` (siehe `ATTRIBUTION_RULES.md`)
- serverseitiger Clickref und idempotenter Transaktionsimport
- Tests: `supabase/tests/deals.sql`, `supabase/tests/referrals.sql`, `supabase/tests/tracking.sql`

Phase 6 bucht bestätigte Provision in Cent. Ohne Kampagne bleibt die Verteilung 35/15/50. Eine Creator-Kampagne bucht 35/15/10/40; die 10 % kommen aus dem BunDeal-Anteil und gelten nur für Käufe innerhalb der 90 Tage. Nur ein Konto mit der Rolle Creator kann eine Kampagne starten. Eine neue Regel gilt nur für spätere Buchungen. Nicht zugeordnete 15 % bleiben ein Gemeinschaftsanteil. Die Freigabeverzögerung steht in der Cashback-Verwaltung. Eine Auszahlung gibt es nicht. Live-Buchung und Live-Import laufen nur mit dem serverseitigen Schlüssel. Tests: `supabase/tests/cashback.sql` und `supabase/tests/creator.sql`.

Phase 7 zeigt auf dem Konto nur die eigenen Beträge: ausstehend, verfügbar und storniert, getrennt nach Simulation und Live. Ein offener Kauf ist kein Cashback. Eine Schätzung auf der Dealseite ist kein Guthaben. Eine Creator-Rolle entsteht erst, wenn die Verwaltung den Antrag bestätigt. Test: `supabase/tests/dashboard.sql`.

Phase 8 zeigt in der Verwaltung Runden, Käufe, Ereignisse ohne Rohdaten, Risiken und das Prüfprotokoll. Die Auszahlungsvorbereitung listet nur verfügbare Beträge geschlossener Runden und zahlt nicht aus. Ein normales Konto kommt an diese Daten nicht heran, auch nicht durch einen direkten Aufruf. Buchungszeilen bleiben unveränderbar. Test: `supabase/tests/admin.sql`.

Phase 9 ist die Pilotprüfung in `PILOT.md`. Die lokalen Tests sind durchgelaufen. Live-Geld bleibt ein No-Go, bis Advertiser, Recht, Steuer, die 30-Tage-Frist und eine echte Sicherung geklärt sind. Eine Auszahlung wird dafür nicht eingebaut.

Lokal die statische Seite auf dem in `supabase/config.toml` hinterlegten Ursprung öffnen:

```powershell
npx supabase@latest db reset
npx supabase@latest db query --local -f supabase/tests/foundation.sql
npx supabase@latest db query --local -f supabase/tests/auth.sql
node supabase/tests/check-auth-client.mjs
python -m http.server 4173
```

`auth-api.mjs` braucht eine lokale `js/config.js` und einen neu gestarteten Supabase-Stack, damit die erlaubten Rücksprungadressen gelten. Der Service-Role-Key bleibt außerhalb von JavaScript.

## Entwicklung

1. In Supabase ein separates Projekt anlegen, zum Beispiel `bundeal-dev`. Nicht das spätere Produktivprojekt verwenden.
2. Docker Desktop installieren.
3. Im Projektordner ausführen:

```powershell
npx supabase@latest start
npx supabase@latest db reset
```

`db reset` wendet die Migrationen und `supabase/seed.sql` an. Danach den SQL-Test ausführen:

```powershell
npx supabase@latest db query --local -f supabase/tests/foundation.sql
```

4. Die lokale URL und den Publishable Key aus `npx supabase@latest status` in eine ignorierte Datei `js/config.js` kopieren. Vorlage: `js/config.example.js`.
5. Den Service-Role-Key nur in einer lokalen `.env` speichern. Vorlage: `.env.example`.

Die Kopfzeile liest die Sitzung nur, wenn eine lokale `js/config.js` vorhanden ist. Ohne diese Datei bleibt der Link „Anmelden“ und es gibt keinen Backend-Aufruf.

## Sicherheit

- Der Publishable Key darf im Frontend stehen.
- Der Service-Role-Key darf niemals in Git, GitHub Pages oder JavaScript stehen.
- Nutzer können ihre Rolle nicht selbst ändern.
- Referral-Codes werden serverseitig erzeugt und können nicht verändert werden.
