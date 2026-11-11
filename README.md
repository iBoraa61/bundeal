# BunDeal

Statische Website mit geplanter Supabase-Grundlage. Die öffentliche Seite bleibt auf `main`. Backend-Arbeit liegt auf `feature/bundeal-backend`.

## Phase 1

Diese Phase enthält nur die Entwicklungsgrundlage:

- lokale Supabase-Konfiguration
- erste Migrationen für Profile, Rollen, Händler, Kategorien und Audit-Log
- Row Level Security
- öffentliche Client-Vorbereitung ohne geheime Schlüssel

Es gibt noch keine Registrierung, keine Deals aus der Datenbank und keine Cashback-Berechnung.

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

Die bestehenden HTML-Seiten binden den Client noch nicht ein. Dadurch bleibt die öffentliche Website unverändert, bis Zugangsdaten vorhanden sind.

## Sicherheit

- Der Publishable Key darf im Frontend stehen.
- Der Service-Role-Key darf niemals in Git, GitHub Pages oder JavaScript stehen.
- Nutzer können ihre Rolle nicht selbst ändern.
- Referral-Codes werden serverseitig erzeugt und können nicht verändert werden.
