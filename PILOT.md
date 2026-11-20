# Pilotprüfung

Stand: 18. November 2026, lokale Umgebung `bundeal-dev`.

Ergebnis: die Simulation ist geprüft. Ein Live-Pilot mit echtem Geld ist kein Go.

Eine Auszahlung bleibt aus. Die Seite sagt weiter, dass ein Kauf über BunDeal noch nicht möglich ist. Diese Prüfung ersetzt keine rechtliche, steuerliche oder Advertiser-Freigabe.

## Tests an diesem Stand

Lokal durchgelaufen, alle mit Erfolg:

- `supabase/tests/foundation.sql`
- `supabase/tests/auth.sql`
- `supabase/tests/auth-api.mjs`
- `supabase/tests/check-auth-client.mjs`
- `supabase/tests/deals.sql`
- `supabase/tests/referrals.sql`
- `supabase/tests/tracking.sql`
- `supabase/tests/cashback.sql`
- `supabase/tests/creator.sql`
- `supabase/tests/dashboard.sql`
- `supabase/tests/admin.sql`

Abgedeckt ist damit: Registrierung ohne Rollenwahl, serverseitiger Empfehlungscode, Passwort-Reset nur auf die erlaubte Adresse, Deal-Vorschlag und Freigabe, direkte Empfehlung, Selbstempfehlung ohne Bonus, Clickref nur serverseitig, offener Kauf ohne Cashback-Betrag, bestätigte Buchung, Ablehnung, volle und teilweise Rückbuchung, doppelte Ereignisse, geschlossene Monatsrunde, Gemeinschaftsanteil, Trennung von Simulation und Live, eigene Kontosicht, Admin-Rechte und unveränderbare Buchungszeilen.

Ohne Kampagne bleibt die Buchung 35/15/50. Mit bestätigter Creator-Kampagne 35/15/10/40. Die 10 % kommen aus dem BunDeal-Anteil. Die 15 % ohne Empfehler bleiben ein Gemeinschaftsanteil.

## Bekannte Grenzen

- Es gibt keine Auszahlung und keinen Zahlungsdienst.
- Live-Buchung und Live-Import laufen nicht aus dem Browser.
- Die veröffentlichte Freigabefrist in der Simulation ist 0 Tage. Die vorgesehene Live-Frist von 30 Tagen nach Bestätigung ist noch nicht als neue Regel veröffentlicht.
- Monatsrunden schließen sich nicht von selbst. Ein Admin schließt sie.
- Ein Creator entsteht nur nach bestätigtem Antrag. Die Rolle Admin kann die Oberfläche nicht vergeben.
- Geschätzte Beträge auf einer Dealseite sind kein Guthaben.
- Die lokale Edge-Laufzeit ist nicht der Buchungsweg. Die Buchung sitzt in der Datenbank.
- Ein produktives Monitoring, ein Alarm und eine geprüfte Produktions-Sicherung sind nicht eingerichtet.

## Wenn etwas schiefgeht

Neue Datenbankdateien nur mit `npx supabase@latest migration up` auf die lokale Instanz anwenden. `npx supabase@latest db reset` löscht die lokale Datenbank, einschließlich der Demodaten. Das ist kein Wiederherstellungsbefehl.

Eine falsche Buchung wird nicht durch Ändern der Zeile korrigiert. Buchungszeilen sind angehängt. Eine Korrektur ist eine neue Gegenbuchung über die vorhandene Rückbuchung.

Die lokale Datenbank ist Docker. Ein Dump dieser lokalen Instanz wurde in dieser Prüfung nicht gezogen. Eine Produktionsdatenbank für Geld gibt es nicht.

## Geheimnisse

Im Browser darf nur die Supabase-URL und der öffentliche anon-Schlüssel liegen, in der gitignorierten Datei `js/config.js`.

Nicht in den Browser, nicht nach GitHub Pages und nicht in ein Dokument: Service-Role-Schlüssel, JWT-Geheimnis, Speicher-Schlüssel, Netzwerk-Zugänge. Affiliate-Zugangsdaten liegen nicht in diesem Repository.

## Aufbewahrung

Buchungszeilen bleiben stehen. Eine Löschfrist für Konten, Klicks und Protokolle ist nicht festgelegt. Die ist Teil der offenen rechtlichen Prüfung, keine technische Voreinstellung.

## Monitoring

Es gibt keinen Alarm auf fehlgeschlagene Importe, offene Risiken oder Abweichungen in der Abstimmung. Die Verwaltung zeigt die Abstimmung und das Prüfprotokoll nur, wenn jemand die Seite öffnet.

## Advertiser

Eine schriftliche Zusage zu Cashback und zur Weitergabe eines persönlichen Tracking-Links liegt hier nicht vor. Dieselbe Marke wird nicht parallel bei zwei Netzwerken angefragt. Die Creator-Weitergabe an nachgelagerte Personen ist eine eigene Frage und kommt erst nach einem Ja zu Cashback und persönlichem Link.

## Recht und Steuer, offen

Diese Punkte sind nicht entschieden und hier nicht beantwortet:

- Wer den Cashback auszahlt und auf welcher rechtlichen Grundlage.
- Steuerliche Behandlung von Käufer-Cashback, Empfehlungsbonus und Creator-Beteiligung.
- Ob und wann eine Identitätsprüfung für eine spätere Auszahlung nötig ist.
- Ob Impressum und Datenschutz für Konten, Klicks und eine spätere Auszahlung reichen.
- Welche Aufbewahrungsfristen gelten.

## Go / No-Go

| Punkt | Stand |
| --- | --- |
| Simulation lokal geprüft | Ja |
| Buchung in Cent, ohne stilles Überschreiben | Ja |
| Auszahlung eingebaut | Nein, bleibt so |
| Schriftliches Advertiser-Ja | Nein |
| Live-Frist 30 Tage veröffentlicht | Nein |
| Recht und Steuer geprüft | Nein |
| Produktions-Sicherung und Alarm | Nein |
| Live-Geld | No-Go |
