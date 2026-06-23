# Farming Simulator 25 – Pterodactyl / Calagopus Egg

Ein Egg, um einen **headless FS25 Dedicated Server unter Wine** auf
[Pterodactyl](https://pterodactyl.io/) oder [Calagopus](https://calagopus.com/)
zu hosten – ohne Windows und ohne VNC.

> ✅ **Status: funktioniert.** Mit echtem GIANTS-Serial + Installer
> (FS25 1.20.0.0) komplett verifiziert: Silent-Install, automatische
> CD-Key-Aktivierung, headless Spielstart, Server **ONLINE**. Siehe Abschnitt
> „Was mit echtem Spiel verifiziert ist".

## Voraussetzungen / Rechtliches

- Du brauchst eine **eigene FS25-Server-Lizenz** (CD-Key). Host und Mitspielen
  auf derselben Lizenz geht nicht – die Lizenz muss separat gekauft werden.
- Die **Steam-Version funktioniert nicht** als Server (Steam-Spieler können aber
  joinen).
- Spiel-Installer + DLCs lädst **du selbst** aus dem
  [GIANTS Download-Portal](https://eshop.giants-software.com/downloads.php) und
  in den Server hoch. Dieses Egg lädt **nichts Urheberrechtlich-Geschütztes**
  herunter.
- Platz: ~50 GB (Basis) bis ~65 GB (mit allen DLCs).

## Aufbau

```
egg-farming-simulator-25.json   # das Egg (in Pterodactyl/Calagopus importieren)
yolk/                           # das Docker-Image (selbst bauen + pushen)
  Dockerfile
  entrypoint.sh                 # Pterodactyl-Entrypoint (wertet $STARTUP aus)
  start.sh                      # Lifecycle: install -> configure -> run -> log
  lib/
    install-game.sh             # Silent-Install + CD-Key + DLCs
    configure.sh                # rendert die Config-XMLs aus Env-Variablen
    start-game.mjs              # startet/stoppt die Spiel-Session via Web-Portal
  config/
    dedicatedServer.xml.tmpl
    dedicatedServerConfig.xml.tmpl
```

## Wie es funktioniert

FS25 hat keinen nativen Linux-Server. Wir führen die Windows-Binaries unter Wine
aus. Der `dedicatedServer.exe` ist im Kern nur ein **Web-Portal** (Standard-Port
`7999`); die eigentliche Spiel-Session wird über einen HTTP-Request an dieses
Portal gestartet – das übernimmt `start-game.mjs` automatisch.

Beim **ersten Start** installiert sich das Spiel selbst:
`wine FarmingSimulator2025.exe /SILENT /NOCANCEL /NOICONS`, danach DLCs, danach
die einmalige Lizenz-Aktivierung mit deinem `GAME_SERIAL`.

## Setup

### 1. Image bauen & pushen

Es gibt zwei Dockerfiles:

- `Dockerfile` — Debian-Wine (8.0, alt; eher als Referenz/Fallback).
- `Dockerfile.winehq` — **empfohlen**: aktuelles WineHQ (stable = Wine 11.0).
  Branch per Build-Arg wählbar (`stable` / `staging`).

Vorgebaute Images liegen unter
`ghcr.io/nn-home-com/farming-simulator-25-egg` (`:latest` = WineHQ 11,
`:debian` = Wine 8 Fallback) und sind im Egg bereits hinterlegt.

Selbst bauen/pushen:

```bash
cd yolk
docker build -f Dockerfile.winehq --build-arg WINE_BRANCH=stable \
  -t ghcr.io/nn-home-com/farming-simulator-25-egg:latest .
docker push ghcr.io/nn-home-com/farming-simulator-25-egg:latest
```

### 2. Egg importieren

- **Pterodactyl:** Admin → Nests → Import Egg → `egg-farming-simulator-25.json`.
- **Calagopus:** Egg-Repo hinzufügen oder das JSON direkt importieren
  (Pterodactyl-kompatibel).

### 3. Server anlegen & Allocations

- **Primäre Allocation** = Game-Port (Standard **10823**, TCP+UDP). Pterodactyl
  setzt daraus automatisch `SERVER_PORT`.
- **Zweite Allocation** für das Web-Portal, gemappt auf Port **7999**
  (`WEB_PORT`).

### 4. Spiel hochladen

Per SFTP / Dateimanager in die beim Erststellen angelegten Ordner:

- `installer/` → `FarmingSimulator2025.exe` **oder** `FarmingSimulator25_*_ESD.img` / `.zip`
- `dlc/` → `FarmingSimulator25_*.exe` (optional)

### 5. Variablen setzen

Mindestens `GAME_SERIAL` (CD-Key) und `WEB_PASSWORD`. Dann Server starten – der
erste Start dauert mehrere Minuten (Installation).

## Was mit echtem Spiel verifiziert ist

Mit echtem GIANTS-Serial + Installer (v1.20.0.0) lokal getestet:

- ✅ Silent-Install aus `*_ESD.img` (`Setup.exe /SILENT /NOCANCEL /NOICONS /SUPPRESSMSGBOXES`)
- ✅ **CD-Key-Aktivierung vollautomatisch** per xdotool (Feld auto-fokussiert, 5er-Auto-Format, Bindestriche werden ignoriert) → Online-Aktivierung erzeugt die `.dat`-Lizenzdateien
- ✅ GIANTS-Engine läuft **headless mit NULL-Renderer** (`-server`) und erreicht „Entered Gameplay" (kein GPU/DirectX nötig)
- ✅ `dedicatedServer.exe` Web-Portal (bindet an Container-IP, nicht localhost)
- ✅ Login-Flow + Session-Start-POST (`start-game.mjs`)
- ✅ Vulkan-Loader (`libvulkan1` + `mesa-vulkan-drivers`/lavapipe) ist erforderlich

- ✅ **End-to-End**: `start.sh` → Server **ONLINE**, Spiel-Session läuft, Log
  wird auf die Konsole gestreamt. Aus dem finalen Image verifiziert.

Die zwei entscheidenden Stolpersteine (jetzt gelöst):

1. **Web-Start sendet alle Felder** — das Portal verwendet teils `name = "x"`
   (Leerzeichen ums `=`); der Scraper in `start-game.mjs` ist dafür
   whitespace-tolerant, sonst fehlen `max_player`/Wirtschaftswerte und der
   Server startet das Spiel nicht.
2. **Wine-Virtual-Desktop** — der `dedicatedServer.exe` wird via
   `wine explorer /desktop=…` gestartet. Ohne Desktop kann der gespawnte
   Spiel-Kindprozess kein Fenster erstellen und stirbt vor „Entered Gameplay".
   (dbus ist *nicht* nötig, Vulkan schon.)

## Bekannte offene Punkte

- **CD-Key-Automatik** (`xdotool`) ist ungetestet – die Online-Aktivierung von
  GIANTS und der Dialog-Aufbau müssen am echten Spiel verifiziert werden. Siehe
  [ACTIVATION.md](ACTIVATION.md) für den manuellen Fallback.
- **Log-Pfad/Start-Erkennung**: `start.sh` tailt `dedicatedServer.log`; der
  echte Pfad/Inhalt ist noch zu bestätigen.
- **Wine-Version**: Die GIANTS-Tools sind versionsempfindlich. Daher gibt es die
  WineHQ-Variante (Wine 11.0). Falls stable zickt, auf `staging` umbauen.

## Lizenz / Steam

Die **Steam-Version kann keinen Dedicated Server hosten** (nur joinen) und liefert
keinen server-tauglichen CD-Key. Einen allgemeinen/geteilten Server-Key gibt es
nicht. Zum Hosten ist die **GIANTS-Digital-Version mit eigenem Serial** nötig
(separat von der Spiel-Lizenz).

## Credits

Logik und Ablauf orientieren sich stark am hervorragenden
[`wine-gameservers/arch-fs25server`](https://github.com/wine-gameservers/arch-fs25server)
(Docker/VNC-Variante). Dieses Egg ist die Pterodactyl/Calagopus-native,
headless Adaption davon.
