# O11y Costs Lab — Sampling, Kosten und KI-Advisor

Reproduzierbares Lab für den Vortrag *Signal Over Noise: Smarter OpenTelemetry Sampling with AI*. Es baut auf dem
[OpenTelemetry Astronomy Shop](https://github.com/open-telemetry/opentelemetry-demo) auf und vergleicht fünf Sampling-Varianten
(Baseline, Head 50 %, Head 10 %, Tail Sampling, KI-Policy) mit denselben Messungen. Ein MCP-Server gibt einer KI Zugriff auf die
Prometheus-Daten, damit sie eine Sampling-Policy vorschlagen kann. Ein Mensch entscheidet.

Dieses Repo enthält **nur die Lab-Dateien**. Das Upstream-Demo wird beim Setup geklont (fest auf Commit `fdbd62ca`, Demo 3.1.0-48).

## Voraussetzungen

**Software**

| Werkzeug | Zweck | Hinweis |
|---|---|---|
| Docker **oder** Podman mit `compose` | Container | Wird automatisch erkannt |
| git | Upstream klonen | |
| bash | alle Skripte | Windows: nur über WSL2 (nicht getestet) |
| python3 | Auswertung in `measure.sh` und `mcp_advisor.sh` | |
| curl | Statusprüfung | |
| Node.js (`npx`) | nur für den MCP Inspector | optional |

**Ressourcen** (der Stack besteht aus 26 Containern)

| Ressource | Wert | Quelle |
|---|---|---|
| RAM und CPUs | getestet mit 5 CPUs und 8 GB RAM für die Container-Engine auf einem Rechner mit 16 GB RAM | gemessen |
| Container im Betrieb | ca. 4 GB RAM | gemessen |
| Freier Plattenplatz | ca. 25 GB (Images der Container: ca. 9 GB, dazu Volumes und Build-Cache) | Images gemessen, Gesamtwert Richtwert |
| Internet | nötig, Images kommen von `ghcr.io`, `quay.io` und `docker.io` | |
| Freie Ports | 8080, 9090, 8000, 10000 | |

Mit weniger RAM wurde das Lab nicht ausprobiert.

> **Teilnehmer:** Die ausführliche Anleitung zum Nachbauen zu Hause (Plattform-Vorbereitung, Go/No-Go, Fehlersuche) steht in [`TEILNEHMER.md`](TEILNEHMER.md).

## Schnellstart

```bash
./setup.sh              # Upstream klonen, Lab-Dateien anlegen, Baseline aktivieren
./stack.sh up           # Stack starten (1-2 Minuten)
./stack.sh status       # Container und URLs prüfen
```

| Komponente | Adresse |
|---|---|
| Astronomy Shop | http://localhost:8080/ |
| Jaeger | http://localhost:8080/jaeger/ui/ |
| Grafana | http://localhost:8080/grafana/ |
| Load Generator | http://localhost:8080/loadgen/ |
| Feature Flags | http://localhost:8080/feature |
| Prometheus | http://localhost:9090/ |
| MCP Advisor | http://localhost:8000/mcp |

## Ablauf des Labs

```bash
./config.sh use baseline && ./stack.sh up    # 1. Variante aktivieren, Stack neu erstellen
# mindestens 5 Minuten identischen Traffic abwarten
./measure.sh "Baseline"                      # 2. messen, Werte in MESSTABELLE.md eintragen

./config.sh use head-50 && ./stack.sh up     # dann dasselbe für head-50, head-10, tail, ai-policy
./measure.sh "50%"
```

Zwischen den Varianten ändert sich ausschließlich das Sampling. Last, Dauer, Journey und Zeitfenster bleiben gleich.
Die vollständige Anleitung steht in [`ANLEITUNG.md`](ANLEITUNG.md).

## Struktur

| Pfad | Inhalt |
|---|---|
| `setup.sh` | klont Upstream, pinnt den Commit, kopiert `overlay/` |
| `stack.sh` | starten, stoppen, Status, Logs, Collector-Fehlerprüfung (Docker oder Podman) |
| `config.sh` | Sampling-Variante anzeigen und wechseln |
| `measure.sh` | vier Messungen (Volumen, Fehler, Latenz, Collector-Ressourcen) |
| `mcp_advisor.sh` | Empfehlungen KEEP / WATCH / SAMPLE aus dem MCP-Server |
| `collector-configs/` | die Varianten `baseline`, `head-50`, `head-10`, `tail`, `ai-policy` |
| `overlay/` | Dateien, die ins Demo kopiert werden (MCP-Server, `compose.lab.yaml`, `compose.mcp.yaml`) |
| `TEILNEHMER.md` | Nachbau zu Hause: Voraussetzungen, Setup, erste Messung, Fehlersuche |
| `ANLEITUNG.md` | Schritt-für-Schritt-Anleitung, Phasen 1–7 |
| `START.md` | Kurzfassung Start, Stopp, URLs, Fehlerbehebung |
| `MCP_SERVER_ERKLAERUNG.md` | MCP-Server für Einsteiger |
| `MESSTABELLE.md` | Vorlage für die Messwerte |

`opentelemetry-demo/` entsteht durch `setup.sh` und ist nicht Teil des Repos (siehe `.gitignore`).

## Unterschiede zum Upstream

- `compose.lab.yaml`: höhere Speicherlimits für `grafana`, `checkout`, `product-catalog` und ein **Healthcheck-Fix für `recommendation`**.
  Das Image enthält kein `nc` mehr, ohne den Fix starten `frontend`, `frontend-proxy` und `load-generator` nie.
- `otelcol-config-full.yml` und alle Collector-Varianten: `docker_stats` ist aus der Metrics-Pipeline entfernt.
  Der Receiver liest über den Docker-Socket. Ob er unter Podman oder anderen Plattformen funktioniert, wurde nicht geprüft (siehe Hinweis in `.env.override`).
- `compose.mcp.yaml` und `mcp-sampling-advisor/`: der MCP-Server.

## Plattformen

| Plattform | Status |
|---|---|
| macOS (Apple Silicon) mit Podman | getestet |
| macOS / Linux mit Docker | **nicht getestet**, Skripte erkennen Docker automatisch |
| Linux mit Podman | nicht getestet |
| Windows (WSL2) | nicht getestet |

Bekannte Einschränkungen:
- Der Collector bindet `/` als `/hostfs` ein (`HOST_FILESYSTEM` in `.env`). Unter Docker Desktop und Windows kann das abweichen.
  Dann `HOST_FILESYSTEM` in `opentelemetry-demo/.env.override` setzen. Das `host_metrics`-Rauschen im Collector-Log betrifft nur Host-Metriken, nicht das Sampling.
- Die Demo-Images laufen mit `DEMO_VERSION=latest`. Der Upstream-Quellcode ist gepinnt, die Container-Images nicht. Neuere Images können
  Verhalten ändern (so wie beim `recommendation`-Healthcheck).
- Der Collector meldet dauerhaft `kafkametrics`-Fehler (`lookup kafka`), weil der Stack keinen Kafka-Container enthält. Das ist harmlos.

## Lizenz

Die Lab-Dateien in diesem Repo stehen unter der Lizenz, die du für dein Repo wählst. Das geklonte Upstream-Demo steht unter Apache-2.0.
