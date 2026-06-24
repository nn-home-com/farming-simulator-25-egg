# Lizenz-Compliance

Dieses Projekt ist ausschließlich für das **legale Selbst-Hosten eines
Farming-Simulator-25-Dedicated-Servers** gedacht, für den der Betreiber eine
gültige Lizenz besitzt.

## Was dieses Projekt enthält

- Scripts, Dockerfiles und Konfigurationsvorlagen, um die **unveränderten**
  GIANTS-Server-Binaries unter Wine auszuführen.
- Eine **Lizenz-gebundene Download-Automatik** (`yolk/lib/download-game.sh`):
  Sie schickt die **eigene Seriennummer des Betreibers** an das offizielle
  GIANTS-Portal (`eshop.giants-software.com/downloads.php`) und lädt die vom
  Portal zurückgegebenen Original-Dateien vom offiziellen GIANTS-CDN — exakt
  derselbe Ablauf wie im Browser.

## Was dieses Projekt ausdrücklich NICHT enthält / NICHT tut

- ❌ Keine Spiel-Dateien, keine GIANTS-Binaries, keine DLCs werden **gebündelt,
  gehostet oder weiterverteilt**. Heruntergeladen wird ausschließlich vom
  offiziellen GIANTS-Server, und nur mit gültiger eigener Seriennummer.
- ❌ Keine CD-Keys, Keygens, „generischen" oder geteilten Seriennummern.
- ❌ Keine Cracks, keine gepatchten Executables, keine DRM-Umgehung.
- ❌ Keine Blockierung/Umleitung der GIANTS-Aktivierungsserver, keine
  Offline-Aktivierungs-Emulation.
- ❌ **Keine fest verdrahteten Download-URLs**, die die Serien-Prüfung des
  Portals umgehen. Ohne gültigen Key liefert das Portal keinen Link und der
  Download bricht ab.

Der Lizenz-Schutz liegt vollständig in GIANTS' eigener Software. Wir führen den
Original-Installer und dessen **Online-Aktivierung unverändert** aus, und der
Download ist durch dieselbe Serien-Prüfung gesichert, die GIANTS selbst auf der
Portal-Seite verwendet. Eine ungültige oder raubkopierte Seriennummer wird von
GIANTS abgelehnt — dieses Image umgeht das nicht und soll es nie tun (siehe
Policy-Hinweise in `yolk/lib/install-game.sh` und `yolk/lib/download-game.sh`).

## Verantwortung des Betreibers

Wer dieses Image betreibt, ist **allein verantwortlich** dafür,
- eine **legitim gekaufte** FS25-Server-Lizenz zu besitzen,
- den GIANTS-EULA einzuhalten,
- den Server bereitgestellten Installer/DLCs rechtmäßig zu beziehen.

## Hinweis zur Steam-Version

Die Steam-Version **kann keinen Dedicated Server hosten** und liefert keinen
server-tauglichen Key. Zum Hosten ist die GIANTS-Digital-Version mit eigener
Seriennummer nötig. Es existiert **kein** allgemeiner/öffentlicher Server-Key.

## Wenn dir eine Umgehungsmöglichkeit auffällt

Sollte dir auffallen, dass dieses Repo (versehentlich) etwas enthält, das
Lizenz-/Kopierschutz umgehen könnte, gilt das als Bug — bitte als Issue melden
oder entfernen. Pull Requests, die Schutzmechanismen schwächen, werden
abgelehnt.
