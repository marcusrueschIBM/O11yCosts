**Deutsch** | [English](PARTICIPANT_GUIDE.en.md)

# Teilnehmer-Anleitung: Das Lab zu Hause nachbauen

Diese Anleitung führt dich von einem leeren Rechner bis zur ersten Messung. Plane großzügig Zeit ein (grobe Schätzung: 60–90 Minuten, davon viel für die Downloads). Die Dauer hängt von deiner Internetleitung ab und wurde nicht gemessen.

Repository: https://github.com/marcusrueschIBM/O11yCosts

> **Wichtig vorab:** Das Lab wurde bisher nur auf **macOS (Apple Silicon) mit Podman** vollständig getestet. Linux, Windows und Docker sind vorbereitet, aber **nicht getestet**. Wenn dort etwas klemmt, steht die Fehlersuche am Ende (Abschnitt 8).

---

## 1. Was du bekommst

Ein lokaler Online-Shop (der *OpenTelemetry Astronomy Shop*) mit 26 Containern: Shop-Services, Load Generator, OpenTelemetry Collector, Jaeger, Prometheus, Grafana und ein MCP-Server. Du misst, wie viel Telemetrie bei verschiedenen Sampling-Varianten anfällt, und prüfst, ob Fehler und langsame Traces sichtbar bleiben.

---

## 2. Voraussetzungen

### Hardware

| Ressource | Mindestens | Gemessen im Lab |
|---|---|---|
| RAM für die Container-Engine | 8 GB (VM) bzw. 8 GB freier Rechner-RAM | Container nutzen im Betrieb ca. 4 GB, die Podman-VM war mit 8 GB und 5 CPUs eingerichtet |
| CPUs | 4 | 5 |
| Freier Plattenplatz | **ca. 25 GB** | Images der 26 Container: ca. 9 GB, dazu Volumes und Build-Cache |
| Internet | ja | Images kommen aus `ghcr.io`, `quay.io` und `docker.io` |

Das Lab wurde auf einem Rechner mit **16 GB RAM** getestet. Mit weniger RAM habe ich es nicht ausprobiert. Es kann dann instabil werden.

### Software

| Werkzeug | Wofür | Prüfen mit |
|---|---|---|
| **Docker** (mit Compose) **oder Podman** | Container | `docker compose version` oder `podman compose version` |
| **git** | Repo holen | `git --version` |
| **bash** | alle Skripte | `bash --version` |
| **python3** | Auswertung der Messungen | `python3 --version` |
| **curl** | Statusprüfung | `curl --version` |
| Node.js mit `npx` | nur für den MCP Inspector (optional) | `npx --version` |

Du brauchst **eines** von Docker oder Podman, nicht beides.

### Freie Ports

Diese Ports dürfen auf deinem Rechner nicht belegt sein:

| Port | Wofür |
|---|---|
| 8080 | Shop, Jaeger, Grafana, Load Generator, Feature Flags |
| 9090 | Prometheus |
| 8000 | MCP-Server |
| 10000 | Admin-Port des Frontend-Proxys (Envoy) |

Prüfen (macOS und Linux):

```bash
lsof -i :8080 -i :9090 -i :8000 -i :10000
```

Keine Ausgabe heißt: alles frei.

---

## 3. Plattform vorbereiten

Wähle den Abschnitt für dein System.

### 3a. macOS

**Docker Desktop** (einfachster Weg):
1. Docker Desktop installieren und starten: https://www.docker.com/products/docker-desktop/
2. In Docker Desktop unter *Settings → Resources* mindestens **5 CPUs und 8 GB Memory** einstellen.
3. Prüfen: `docker info` zeigt keine Fehlermeldung.

**Oder Podman** (so wurde das Lab getestet):
1. Podman Desktop installieren: https://podman-desktop.io/
2. Docker Compose als Compose-Provider einrichten (in Podman Desktop: *Settings → Resources → Compose → Setup*).
3. Podman Machine anlegen und starten:
   ```bash
   podman machine init --cpus 5 --memory 8192 --disk-size 100
   podman machine start
   ```
   Wenn schon eine Machine existiert, **nicht** erneut `init`, nur `podman machine start`.
4. Prüfen: `podman run --rm quay.io/podman/hello` gibt eine Begrüßung aus.

### 3b. Linux

1. Docker Engine mit Compose-Plugin installieren: https://docs.docker.com/engine/install/ (oder Podman über den Paketmanager).
2. Deinen Benutzer in die Gruppe `docker` aufnehmen, damit `sudo` nicht nötig ist, danach neu anmelden.
3. Prüfen: `docker compose version` und `docker run --rm hello-world`.

### 3c. Windows

Ein natives Windows ohne Linux-Umgebung funktioniert **nicht**, weil die Skripte Bash brauchen.

1. **WSL2 mit Ubuntu** einrichten (PowerShell als Administrator): `wsl --install -d Ubuntu`, danach neu starten.
2. **Docker Desktop** installieren und unter *Settings → General* „Use the WSL 2 based engine“ aktivieren. Unter *Settings → Resources → WSL Integration* deine Ubuntu-Distribution einschalten.
3. Alle weiteren Befehle in der **Ubuntu-Konsole** ausführen, nicht in PowerShell.
4. Das Repo **im Linux-Dateisystem** ablegen (zum Beispiel `~/lab`), nicht unter `/mnt/c/...`. Sonst ist es sehr langsam und Zeilenenden können Probleme machen.

---

## 4. Repo holen und einrichten

```bash
git clone https://github.com/marcusrueschIBM/O11yCosts.git
cd O11yCosts
./setup.sh
```

`setup.sh` macht vier Dinge:
1. Es klont das OpenTelemetry-Demo von GitHub in den Ordner `opentelemetry-demo/`.
2. Es stellt das Demo auf den festen Stand (Commit `fdbd62ca`), damit alle denselben Code haben.
3. Es kopiert die Lab-Dateien aus `overlay/` hinein (MCP-Server, Anpassungen).
4. Es aktiviert die Baseline-Konfiguration (kein Sampling).

Erwartete Ausgabe am Ende:

```
Fertig. Naechste Schritte:
  ./stack.sh up        # Stack starten (erkennt docker oder podman)
  ...
```

Wenn `./setup.sh` „Permission denied“ meldet: `chmod +x *.sh` und nochmal.

Prüfen, welche Engine erkannt wurde:

```bash
./stack.sh engine       # docker oder podman
```

Bei Bedarf erzwingen: `CONTAINER_ENGINE=podman ./stack.sh up`.

---

## 5. Stack starten

```bash
./stack.sh up
```

- Beim **ersten Start** werden ca. 9 GB Images geladen und der MCP-Container gebaut. Das dauert 10–30 Minuten, je nach Leitung.
- Spätere Starts brauchen 1–2 Minuten.
- Meldungen wie `Container frontend Waiting` sind normal. Warte, bis die Ausgabe zu Ende ist.

Dann prüfen:

```bash
./stack.sh status
```

**Erwartet:**
- Alle Container zeigen `Up`. Die meisten zusätzlich `(healthy)`.
- Alle URLs am Ende zeigen `200`.

Wenn Container im Status `Created` bleiben oder `unhealthy` sind, siehe Abschnitt 8.

### Die Oberflächen

| Was | Adresse |
|---|---|
| Shop | http://localhost:8080/ |
| Jaeger (Traces) | http://localhost:8080/jaeger/ui/ |
| Grafana | http://localhost:8080/grafana/ |
| Load Generator | http://localhost:8080/loadgen/ |
| Feature Flags | http://localhost:8080/feature |
| Prometheus | http://localhost:9090/ |
| MCP-Server | http://localhost:8000/mcp |

Grafana und Jaeger nur über diese Adressen öffnen, nicht über die zufälligen Ports, die `docker ps` zeigt.

### Go/No-Go: Läuft alles?

- [ ] Der Shop öffnet sich und zeigt Produkte
- [ ] In Jaeger erscheinen nach einigen Klicks im Shop Services wie `frontend` und `checkout`
- [ ] Prometheus meldet: `curl -s http://localhost:9090/-/healthy` → `Prometheus Server is Healthy.`
- [ ] `./stack.sh check` zeigt keine Collector-Fehler (Kafka-Meldungen werden ausgeblendet)

Erst wenn alles abgehakt ist, weiter.

---

## 6. Die erste Messung (Baseline)

Der Load Generator startet automatisch und erzeugt Last. Du musst nichts klicken.

1. Prüfen, dass die Baseline aktiv ist:
   ```bash
   ./config.sh show        # erwartet: Aktive Variante: baseline
   ```
2. **Mindestens 5 Minuten warten.** Vorher sind die Werte nicht aussagekräftig, weil Prometheus ein 5-Minuten-Fenster auswertet.
3. Messen:
   ```bash
   ./measure.sh "Baseline"
   ```
4. Die mit `-->` markierten Werte in die Tabelle in `MESSTABELLE.md` eintragen.

Die Ausgabe zeigt vier Messungen: Volumen (Spans pro Sekunde), Fehlerquote, p95-Latenz und Ressourcen des Collectors.

---

## 7. Die weiteren Varianten

Pro Variante dasselbe Muster. Alles außer dem Sampling bleibt gleich: gleiche Last, gleiche Wartezeit (5 Minuten), gleicher Messbefehl.

```bash
./config.sh list                  # baseline, head-50, head-10, tail, ai-policy
./config.sh use head-50           # Variante aktivieren
./stack.sh up                     # Collector neu erstellen (sonst wirkt die Änderung nicht!)
./stack.sh check                  # keine Fehler?
# 5 Minuten warten
./measure.sh "50%"
```

| Variante | Befehl | Messname |
|---|---|---|
| Baseline | `./config.sh use baseline` | `"Baseline"` |
| Head 50 % | `./config.sh use head-50` | `"50%"` |
| Head 10 % | `./config.sh use head-10` | `"10%"` |
| Tail Sampling | `./config.sh use tail` | `"Tail"` |
| KI-Policy | `./config.sh use ai-policy` | `"KI-Policy"` |

Zusätzlich:
- **Fehler und langsame Traces prüfen:** Unter http://localhost:8080/feature ein Feature Flag für einen simulierten Fehler einschalten, einige Minuten warten, in Jaeger nach Fehler-Traces suchen, Flag wieder ausschalten.
- **MCP-Advisor:** `./mcp_advisor.sh` zeigt pro Operation eine Empfehlung (KEEP / WATCH / SAMPLE).
- **Die vollständige Schritt-für-Schritt-Erklärung** mit KI-Client steht in `ANLEITUNG.md`.

### Aufräumen

```bash
./stack.sh down                   # Container stoppen und entfernen
```

Die geladenen Images bleiben erhalten, ein erneuter Start geht dadurch schnell. Zum vollständigen Löschen siehe Abschnitt 9.

---

## 8. Wenn etwas nicht klappt

| Symptom | Mögliche Ursache | Lösung |
|---|---|---|
| `./setup.sh`: `git: command not found` | git fehlt | git installieren |
| `weder docker noch podman gefunden` | keine Engine installiert oder nicht gestartet | Docker Desktop bzw. Podman Machine starten |
| Port 8080 nicht erreichbar, `frontend`, `frontend-proxy`, `load-generator` im Status `Created` | `recommendation` ist `unhealthy` | Der Fix steckt in `overlay/compose.lab.yaml`. Hast du `./setup.sh` ausgeführt? Danach `./stack.sh up` |
| `bind: address already in use` | Port belegt | Anderes Programm beenden (`lsof -i :8080`) |
| Container werden mit `Killed` beendet, Stack bricht ab | zu wenig RAM | Mehr RAM für die Engine einstellen (Abschnitt 2) |
| `no space left on device` | Platte voll | Platz schaffen, `docker system df` zeigt den Verbrauch |
| Messung zeigt fast nur 0 | zu wenig Traffic | Prüfen, ob `load-generator` läuft (`./stack.sh status`), 5 Minuten warten |
| Messung zeigt „Keine Daten“ | Prometheus ohne Span-Metriken | `./stack.sh check`, 2–3 Minuten warten |
| Collector-Log: `lookup kafka ... no such host` | Der Stack enthält kein Kafka | Ignorieren, harmlos |
| Collector-Log: `host_metrics ... permission denied` | Zugriff auf Host-Prozesse eingeschränkt | Ignorieren, betrifft nur Host-Metriken |
| `./measure.sh`: `Prometheus ist nicht erreichbar` | Stack läuft nicht | `./stack.sh status` |
| Skript bricht mit seltsamen Zeichen (`\r`) ab (Windows) | falsche Zeilenenden | Repo neu in WSL klonen, nicht unter `/mnt/c` |
| Ein Image lässt sich nicht laden | Netzwerk, Proxy oder Anmeldelimit | Verbindung prüfen, hinter Firmenproxy diesen in der Engine eintragen |

Für alles andere: `./stack.sh logs <containername>` zeigt die Logs eines Dienstes.

### Bekannte Einschränkungen

- Die Demo-Images werden mit dem Tag `latest` geladen. Der Quellcode ist fest auf einen Stand gepinnt, die Container-Images nicht. Wenn Upstream neue Images veröffentlicht, kann sich das Verhalten ändern.
- Der Collector bindet das Host-Dateisystem ein (`/hostfs`). Unter Docker Desktop, Windows und Linux kann das abweichen. Es betrifft nur Host-Metriken, nicht die Sampling-Messungen.
- Die gemessenen Zahlen hängen von deinem Rechner ab. **Vergleiche nur Varianten untereinander, nicht mit den Zahlen anderer.**

---

## 9. Alles wieder entfernen

```bash
./stack.sh down                       # Container entfernen
docker system prune -a --volumes      # ACHTUNG: löscht ALLE nicht genutzten Images und Volumes, auch fremde
```

Mit Podman `podman system prune -a --volumes`. Der Befehl betrifft **alle** Container-Daten auf deinem Rechner, nicht nur dieses Lab. Wenn du Docker oder Podman noch für anderes nutzt, lass ihn weg und lösche gezielt über Docker Desktop bzw. Podman Desktop.

Das Verzeichnis `O11yCosts/` samt `opentelemetry-demo/` kannst du normal löschen.
