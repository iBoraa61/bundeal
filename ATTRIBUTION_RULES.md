# Attributionsregel direct-v1

Das ist die versionierte Pilotregel. Eine Änderung bekommt eine neue Version und ersetzt diese Zeile nicht stillschweigend.

- Ein Klick ist kein Kauf und erzeugt kein Cashback.
- Der Klick entsteht nur für ein angemeldetes Konto. Den Clickref baut der Server.
- Der direkte Empfehler kommt ausschließlich aus dem Deal-Link. Es gibt keine zweite Ebene.
- Eigenempfehlung wird verworfen.
- Der Empfehler muss auf demselben Deal bereits einen zugeordneten Kauf haben, der noch offen oder bestätigt ist.
- Vor dem ersten zugeordneten Kauf des Käufers gilt der letzte zulässige direkte Empfehler. Danach bleibt die Zuordnung stehen.
- Die Zuordnung gilt bis zum Ende der offenen Monatsrunde. Die Runde folgt dem UTC-Kalendermonat.
- Gerätwechsel läuft über dasselbe BunDeal-Konto, nicht über ein Browser-Cookie.
- Eine Netzwerkmeldung ohne bekannten Clickref bleibt ein Ereignis und wird keine Transaktion.
- Im Clickref stehen nur pseudonyme IDs: Klick, Deal, Monat und Empfehlungscode. Keine Namen und keine E-Mail-Adressen.

## Kampagne creator-v1

Die direkte Empfehlung bleibt direct-v1. Eine Creator-Kampagne hängt zusätzlich am Klick und überschreibt den Empfehler nicht.

- Eine Kampagne startet nur ein Konto mit der Rolle Creator. Ein Admin vergibt diese Rolle. Ein normales Konto kann keine Kampagne anlegen.
- Die Kampagne läuft 90 Tage ab Start und kann über mehrere Monatsrunden gehen. Der direkte Empfehler gilt weiter nur bis zum Ende der offenen Monatsrunde.
- Der Kampagnencode reist im Deal-Link mit. Ein späterer Klick ohne Kampagne beendet sie für die nächste Weitergabe.
- Die 10 % Creator-Beteiligung kommen aus dem bisherigen BunDeal-Anteil. Ohne Kampagne entsteht daraus wieder 35/15/50.
- Fehlt der direkte Empfehler, bleiben seine 15 % ein Gemeinschaftsanteil. Der Creator bekommt sie nicht.
- Der Kampagneninhaber gilt auf seinem eigenen Kampagnenlink als direkter Empfehler, auch ohne eigenen Kauf. Jede weitere Weitergabe braucht weiterhin einen eigenen zugeordneten Kauf.
- Ein Kauf über die eigene Kampagne bringt weder Empfehlungsbonus noch Creator-Beteiligung.
- Im Clickref steht die Kampagne nicht. Sie liegt nur serverseitig am Klick.
