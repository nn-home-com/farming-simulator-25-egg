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
- Spiel-Installer + DLCs holt der Server beim ersten Start **automatisch** aus
  dem [GIANTS Download-Portal](https://eshop.giants-software.com/downloads.php) –
  und zwar **mit deiner eigenen Seriennummer** (genau wie im Browser). Ohne
  gültigen Key liefert das Portal keinen Link. Du kannst den Installer auch
  weiterhin selbst hochladen (`AUTO_DOWNLOAD=false`). Es wird **nichts
  gebündelt, gehostet oder weiterverteilt**.
- Platz: **~41 GB** nach der Installation (nur das installierte Spiel). Während
  der Installation kurzzeitig mehr (Download + Entpacken); die ~40+ GB
  Installer-Dateien werden danach automatisch gelöscht (`KEEP_INSTALLER=true`
  behält sie). Auf Hosting-Panels, die nur deine Spieldaten zählen
  (Savegames/Mods), wirkt der Server viel kleiner – die Basis-Spieldateien sind
  dort oft geteilt.

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

Beim **ersten Start** lädt der Server das Spiel selbst aus dem offiziellen
GIANTS-Portal herunter (mit deinem `GAME_SERIAL`, siehe
`lib/download-game.sh`) – sofern du nicht selbst einen Installer hochgeladen
hast. Danach installiert es sich silent
(`wine Setup.exe /SILENT /NOCANCEL /NOICONS /SUPPRESSMSGBOXES`), gefolgt von den
DLCs und der einmaligen Lizenz-Aktivierung mit deinem `GAME_SERIAL`.

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

### 4. Spiel bereitstellen

**Einfachster Weg (automatisch):** nichts hochladen – einfach `GAME_SERIAL`
setzen. Beim ersten Start lädt der Server deine Kopie aus dem GIANTS-Portal,
installiert sie und aktiviert den Key.

**Manuell (optional):** wenn du `AUTO_DOWNLOAD=false` setzt, lade per SFTP /
Dateimanager selbst hoch:

- `installer/` → `FarmingSimulator2025.exe` **oder** `FarmingSimulator25_*_ESD.img` / `.zip`
- `dlc/` → `FarmingSimulator25_*.exe` (optional)

### 5. Variablen setzen

Mindestens `GAME_SERIAL` (CD-Key) und `WEB_PASSWORD`. Optional: `AUTO_DOWNLOAD`
(Standard `true`) und `DOWNLOAD_DLC` (Standard `true`). Dann Server starten – der
erste Start dauert mehrere Minuten (bei Auto-Download länger: ~21 GB Basisspiel).

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
- ✅ **DLC-Installation** (New Holland CR11 Gold Edition): headless in ~31 s
  installiert; die erzeugte `.dlc` ist **byte-identisch** (SHA256) zu der eines
  von Hand vollständig durchgeklickten Installers, und die Engine meldet in der
  laufenden Session `ExtraContent: Unlocked 'CR11GOLD'` ohne jede DLC-Warnung.

Die zwei entscheidenden Stolpersteine (jetzt gelöst):

1. **Web-Start sendet alle Felder** — das Portal verwendet teils `name = "x"`
   (Leerzeichen ums `=`); der Scraper in `start-game.mjs` ist dafür
   whitespace-tolerant, sonst fehlen `max_player`/Wirtschaftswerte und der
   Server startet das Spiel nicht.
2. **Wine-Virtual-Desktop** — der `dedicatedServer.exe` wird via
   `wine explorer /desktop=…` gestartet. Ohne Desktop kann der gespawnte
   Spiel-Kindprozess kein Fenster erstellen und stirbt vor „Entered Gameplay".
   (dbus ist *nicht* nötig, Vulkan schon.)
3. **Kein HTTP-Keep-Alive gegen das Portal** — der GIANTS-Webserver bedient eine
   Verbindung zur Zeit und verwirft alles, was offengehalten wird; eine
   wiederverwendete Verbindung lässt den *nächsten* Request als `socket hang up`
   scheitern. Node aktiviert Keep-Alive im globalen Agent **ab v19
   standardmäßig**, deshalb setzt `start-game.mjs` explizit `agent: false` und
   `Connection: close`. Auf dem Bookworm-Image (Node 18) fällt das nicht auf –
   auf jedem neueren Node wäre der Session-Start sonst tot.

## Daten: Savegames, Mods, Logs, Config

Diese liegen unter **`data/`** im Server-Wurzelverzeichnis (direkt im
Dateimanager sichtbar):

```
data/savegame1/                         # Savegames
data/mods/                              # Mods (.zip)
data/log_<datum>.txt                   # Spiel-Log
data/dedicated_server/logs/            # Server-Manager- & Web-Logs
data/dedicated_server/dedicatedServerConfig.xml
```

Technisch ist `data/` ein Symlink-Ziel des sonst tief im (versteckten)
Wine-Prefix vergrabenen `…/My Games/FarmingSimulator2025`-Ordners. Die
Config-XMLs werden bei jedem Start aus den Panel-Variablen **neu generiert** –
dauerhafte Änderungen daher über die Egg-Variablen, nicht durch direktes
Editieren.

## DLC-Installation

**`DOWNLOAD_DLC` ist standardmäßig `true`.** DLCs installieren sich headless in
etwa 30 Sekunden pro Stück – ohne VNC, ohne manuellen Eingriff.

### DLC hinzufügen

**Automatisch (Standard):** Bei **jedem** Serverstart fragt das Egg das
GIANTS-Portal mit deinem `GAME_SERIAL` ab und lädt DLCs herunter, die deine
Lizenz abdeckt und die noch fehlen; anschließend werden sie installiert. Ein
neu gekauftes DLC braucht also nur einen **Neustart**. Das Basisspiel wird dabei
nicht erneut geladen. Schlägt Portal oder Download fehl, startet der Server
trotzdem – es gibt nur eine Warnung in der Konsole.

**Manuell:** DLC-Installer (`FarmingSimulator25_*.exe`) vom
[GIANTS-Portal](https://eshop.giants-software.com/downloads.php) laden, im
Dateimanager bzw. per SFTP nach **`dlc/`** im Server-Wurzelverzeichnis
hochladen, Server neu starten. Nötig, wenn `AUTO_DOWNLOAD=false` ist oder das
DLC nicht an deiner Server-Lizenz hängt.

In beiden Fällen gilt: Bereits installierte DLCs werden übersprungen, ein
Neustart ist also gefahrlos wiederholbar.

GIANTS' DLC-Installer haben **keinen Silent-Modus** (`/SILENT` wird ignoriert)
und verlangen eine **Online-Aktivierung mit Produktschlüssel**. Headless
entpacken ist deshalb nicht möglich: Im NSIS-Installer steckt nur ein
`<dlcStub>`-XML, die eigentliche `.dlc` entsteht erst durch die Aktivierung. Das
Egg steuert den Installer daher per `xdotool`.

**Ablauf:**

1. **Nur bei der Erstaktivierung** eines DLCs auf dieser Maschine erscheint das
   Fenster `FarmingSimulator2025` mit „Please enter your … Product Key". Das Egg
   tippt `GAME_SERIAL` ein und klickt **Activate >**. Bei einer Neuinstallation
   eines bereits aktivierten DLCs **entfällt dieser Schritt komplett** – der
   Installer legt sofort los.
2. Das Installationsfenster `Farming Simulator 25 – <Produkt>` öffnet sich und
   schreibt die `.dlc` nach `pdlc/`.
3. Zum Schluss erscheint eine kleine Box **„Installation successful."** mit
   OK-Button. Sie hat **keinen eigenen Fenstertitel** und taucht zu einem nicht
   vorhersagbaren Zeitpunkt auf – deshalb wartet das Egg nicht darauf, sondern
   klickt die OK-Position periodisch an (ein Klick dorthin ist wirkungslos,
   solange der Installer noch arbeitet). Danach beendet er sich selbst.

**Abbruchbedingungen** – ein DLC blockiert den Serverstart nie:

| Variable | Standard | Bedeutung |
|---|---|---|
| `DLC_TIMEOUT` | `900` | harte Obergrenze pro DLC in Sekunden |
| `DLC_STABLE_WAIT` | `30` | `.dlc` so lange unverändert ⇒ fertig |

Sauberer Abschluss ist das **Ende des Installer-Prozesses** – nicht das
Auftauchen der Datei (die existiert ab dem ersten Byte; genau darauf hatte eine
frühere Fassung gewartet und dann mitten hinein gekillt). Greift der
Stabilitäts-Fallback, wird der Installer beendet; das ist unbedenklich, weil das
Ergebnis nachweislich byte-identisch ist. Welches `.dlc` neu dazugekommen ist,
wird per Verzeichnisvergleich von `pdlc/` ermittelt und nicht aus dem
Installer-Dateinamen abgeleitet.

### Der Web-Manager zeigt DLCs rot an – das ist normal

Im MODS-Tab erscheinen installierte DLCs **rot** mit dem Hinweis
**„One or more mods are corrupted"**. Das ist eine **Anzeige-Eigenheit von
GIANTS' Mod-Scanner**, kein Installationsfehler:

- Die erzeugte `.dlc` ist **byte-identisch** zu der eines von Hand komplett
  durchgeklickten Installers (verifiziert per SHA256).
- Die Engine lädt und entsperrt sie im laufenden Spiel einwandfrei – im
  Spiel-Log steht dann z. B.:

  ```
  Available dlc: (Hash: 2b9007b3…) (Version: 1.0.0.0) pdlc_extraContentNewHollandCR11
  ExtraContent: Unlocked 'CR11GOLD'
  ```

- In der Spalte „Issues" steht **kein** konkreter Fehler.

Der Eintrag steht außerdem auf `Active: No` – DLCs werden nicht wie Mods
aktiviert, das ist ebenfalls normal.

**Es liegt nicht an Wine und nicht an diesem Egg.** Das Problem betrifft
GIANTS' Dedicated Server allgemein und ist seit Jahren bekannt:

- FS25-Spieler, die die *New Holland CR11 Gold Edition* regulär auf Steam
  gekauft haben und im Spiel besitzen, berichten dasselbe: „it still shows as
  corrupted when trying to run the dedicated server"
  ([Steam-Diskussion](https://steamcommunity.com/app/2300320/discussions/0/4634861275507089861/?ctp=3)).
- Schon unter FS22 wurden kleine DLCs rot angezeigt (72 KB) und große grün
  (114 MB); als Ursache wurde dort „the paid DLC is not compatible with
  dedicated servers" genannt, ohne Lösung
  ([Steam-Diskussion](https://steamcommunity.com/app/1248130/discussions/0/3203744275156367896/)).

Der Zusammenhang ist die **Größe**: DLCs wie CR11 Gold sind reine
Freischalt-Container von ~130 KB (die Inhalte stecken im Basisspiel), und
genau die stuft der Mod-Scanner als korrupt ein. Der Installer selbst ist nur
9,4 MB groß und kann gar nichts Größeres erzeugen – eine „vollständigere"
Datei existiert nicht.

Auswirkungen hat das keine: Der Server startet, die Session läuft, die Engine
entsperrt den Inhalt. Wen die Meldung stört, kann das DLC weglassen
(`DOWNLOAD_DLC=false` und `data/pdlc/*.dlc` löschen) – dann steht es aber auch
im Spiel nicht zur Verfügung.

### Einschränkungen

- **Steam-Spieler**, die einen DLC nicht besitzen, sehen ihn als fehlend. Das
  ist Lizenzlogik und nicht behebbar. Wenn nicht alle Mitspieler die DLCs auf
  GIANTS besitzen, `DOWNLOAD_DLC=false` setzen.
- **Getestet wurde bisher nur mit einem DLC**: New Holland CR11 Gold Edition –
  ein „Stub"-DLC, dessen `.dlc` nur ~131 KB groß ist (die Inhalte stecken im
  Basisspiel). Ein großes Inhalts-DLC (z. B. eine Karte mit mehreren GB) ist
  **ungetestet**. Die Abbruchlogik ist darauf ausgelegt, aber falls ein solcher
  DLC länger als `DLC_TIMEOUT` braucht, muss der Wert hochgesetzt werden.
- Der **Erstaktivierungs-Pfad** (Key-Dialog, Schritt 1 oben) wurde von Hand
  verifiziert, aber nicht automatisiert – auf einer Maschine mit bereits
  aktiviertem DLC lässt er sich nicht mehr auslösen.

## Bekannte offene Punkte

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
