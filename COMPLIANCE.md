# Lizenz-Compliance

Dieses Projekt ist ausschließlich für das **legale Selbst-Hosten eines
Farming-Simulator-25-Dedicated-Servers** gedacht, für den der Betreiber eine
gültige Lizenz besitzt.

## Was dieses Projekt enthält

- Scripts, Dockerfiles und Konfigurationsvorlagen, um die **unveränderten**
  GIANTS-Server-Binaries unter Wine auszuführen.

## Was dieses Projekt ausdrücklich NICHT enthält / NICHT tut

- ❌ Keine Spiel-Dateien, keine GIANTS-Binaries, keine DLCs.
- ❌ Keine CD-Keys, Keygens, „generischen" oder geteilten Seriennummern.
- ❌ Keine Cracks, keine gepatchten Executables, keine DRM-Umgehung.
- ❌ Keine Blockierung/Umleitung der GIANTS-Aktivierungsserver, keine
  Offline-Aktivierungs-Emulation.

Der Lizenz-Schutz liegt vollständig in GIANTS' eigener Software. Wir führen den
Original-Installer und dessen **Online-Aktivierung unverändert** aus. Eine
ungültige oder raubkopierte Seriennummer wird von GIANTS abgelehnt — dieses
Image umgeht das nicht und soll es nie tun (siehe Policy-Hinweis in
`yolk/lib/install-game.sh`).

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
