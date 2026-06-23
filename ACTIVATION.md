# CD-Key-Aktivierung (der wackelige Schritt)

Der Basis-Installer von FS25 läuft vollständig **silent**. Was sich *nicht*
sauber per Kommandozeile lösen lässt, ist die **einmalige Lizenz-Aktivierung**:
Beim ersten Start von `FarmingSimulator2025.exe` verlangt das Spiel den CD-Key
und erzeugt daraufhin `*.dat`-Lizenzdateien unter:

```
.fs25prefix/drive_c/users/container/Documents/My Games/FarmingSimulator2025/
```

Solange diese `.dat`-Dateien existieren, startet der Server ohne weitere
Interaktion.

## Weg A – automatisch (Standard, experimentell)

`lib/install-game.sh` startet das Spiel unter Xvfb und tippt den `GAME_SERIAL`
per `xdotool` in den Dialog:

```sh
xdotool type "$GAME_SERIAL"
xdotool key Tab
xdotool key Return
```

Das ist **ungetestet** und hängt vom konkreten Dialog-Layout der jeweiligen
Spielversion ab (Feld-Fokus, Anzahl Tab-Sprünge, evtl. „Akzeptieren"-Checkbox).
Passt die Tastensequenz in `activate_license()` an, sobald ihr den echten Dialog
gesehen habt (z.B. einmal per `x11vnc` auf das Xvfb-Display schauen).

## Weg B – manuell, einmalig (zuverlässiger Fallback)

1. Spiel **einmal woanders** in Wine installieren und aktivieren (lokaler PC mit
   GUI, oder das Referenz-Image
   [`wine-gameservers/arch-fs25server`](https://github.com/wine-gameservers/arch-fs25server)
   per VNC).
2. Die erzeugten `*.dat`-Dateien aus dem `My Games/FarmingSimulator2025`-Ordner
   sichern.
3. Diese Dateien per SFTP in den Server-Container hochladen, nach:
   ```
   .fs25prefix/drive_c/users/container/Documents/My Games/FarmingSimulator2025/
   ```
4. Server starten – `activate_license()` erkennt die vorhandenen `.dat`-Dateien
   und überspringt die Aktivierung.

## Weg C – temporäres VNC nur zum Aktivieren (Kompromiss)

Falls Weg A nicht klappt und Weg B zu umständlich ist, kann man dem Yolk
optional `x11vnc` beilegen und beim ersten Start (nur wenn `.dat` fehlt) einen
VNC-Server an das Xvfb-Display hängen, einmalig den Key eingeben, danach wieder
abschalten. Das ist bewusst **nicht** im Standard-Image, weil ihr euch
ausdrücklich für den Silent-/Headless-Weg entschieden habt – es ist hier nur als
Notnagel dokumentiert.
