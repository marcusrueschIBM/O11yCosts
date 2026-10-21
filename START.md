**Deutsch** | [English](START.en.md)

# Start-Anleitung: Stack, Container, URLs und Ports

Läuft mit **Docker** oder **Podman** auf Linux, macOS und Windows (nur über WSL2). Getestet ist bisher nur macOS (Apple Silicon) mit Podman 6.1.1 und Docker Compose 5.5.1 als Provider. Die Erstinstallation steht in `TEILNEHMER.md`. Diese Datei ist die Kurzfassung für den täglichen Start.

Alle Befehle laufen im **Repo-Root** (dort liegen `setup.sh`, `stack.sh`, `config.sh`).

---

## 1. Einmalig: Setup

```bash
./setup.sh
```

Klont das Upstream-Demo nach `opentelemetry-demo/` (fest auf Commit `fdbd62ca`), legt die Lab-Dateien darüber und aktiviert die Baseline-Konfiguration. Mehrfach ausführbar.

Falls die Podman Machine nicht läuft (nur macOS und Windows mit Podman):

```bash
podman machine list
podman machine start podman-machine-default   # nur falls nicht "Currently running"
```

Nicht erneut `podman machine init` ausführen, wenn die Machine schon existiert.

---

## 2. Stack starten, stoppen, prüfen

```bash
./stack.sh up              # Shop + Observability + MCP Advisor
./stack.sh up --no-mcp     # ohne MCP (Phase 1-4 der ANLEITUNG.md)
./stack.sh down            # stoppen und Container entfernen (Volumes bleiben)
./stack.sh status          # Container und URLs prüfen
./stack.sh check           # Collector-Fehler anzeigen (Kafka-Rauschen ausgeblendet)
./stack.sh logs <dienst>   # z. B. otel-collector
./stack.sh engine          # erkannte Engine (docker oder podman)
```

Engine erzwingen: `CONTAINER_ENGINE=podman ./stack.sh up`.

Wichtig:
- Der Start dauert ca. 1–2 Minuten, weil `frontend` erst nach mehreren Abhängigkeiten startet.
- Eine geänderte Collector-Konfiguration wirkt erst nach `./stack.sh up` (force-recreate).
- `stack.sh` verwendet immer `compose.yaml`, `compose.observability.yaml`, `compose.extras.yaml` und `compose.lab.yaml`, bei MCP zusätzlich `compose.mcp.yaml`. Nur `compose.yaml` allein startet weder Jaeger noch Prometheus noch Grafana.

### Inhalt von `compose.lab.yaml`

Datei: `overlay/compose.lab.yaml` (wird nach `opentelemetry-demo/` kopiert).

```yaml
services:
  grafana:
    deploy: {resources: {limits: {memory: 512M}}}
  checkout:
    deploy: {resources: {limits: {memory: 128M}}}
  product-catalog:
    deploy: {resources: {limits: {memory: 128M}}}
  recommendation:
    healthcheck:
      test: ["CMD-SHELL", "bash -c '</dev/tcp/127.0.0.1/${RECOMMENDATION_PORT}'"]
```

Der `recommendation`-Eintrag ersetzt den Healthcheck `nc -z ...`. Das aktuelle `latest-recommendation`-Image enthält kein `nc`. Ohne ihn bleibt `recommendation` dauerhaft `unhealthy`, und `frontend`, `frontend-proxy` und `load-generator` bleiben im Status `Created`. Der Shop ist dann nicht erreichbar.

---

## 3. Sampling-Variante wechseln

```bash
./config.sh list           # baseline, head-50, head-10, tail, ai-policy
./config.sh show           # welche Variante liegt aktiv auf der Platte?
./config.sh use tail       # Variante aktivieren
./stack.sh up              # erst jetzt übernimmt der Collector sie
```

Eine Variante ist erst nach `./stack.sh up` wirksam. `config.sh show` prüft nur die Datei, nicht den laufenden Collector.

---

## 4. URLs und feste Ports

| Komponente | Adresse | Host-Port |
|---|---|---|
| Astronomy Shop | http://localhost:8080/ | 8080 |
| Jaeger | http://localhost:8080/jaeger/ui/ | 8080 |
| Grafana | http://localhost:8080/grafana/ | 8080 |
| Load Generator (Locust) | http://localhost:8080/loadgen/ | 8080 |
| Feature Flags | http://localhost:8080/feature | 8080 |
| Prometheus | http://localhost:9090/ | 9090 |
| MCP Sampling Advisor | http://localhost:8000/mcp | 8000 |
| Envoy-Admin des frontend-proxy | – | 10000 |

Shop, Jaeger, Grafana, Load Generator und Feature Flags laufen alle über den Frontend Proxy auf Port 8080. Alle übrigen Container (z. B. `grafana`, `jaeger`, `cart`) bekommen von Podman dynamische Host-Ports. Öffne Grafana und Jaeger nur über die Adressen oben, nicht über die dynamischen Ports aus `podman ps`.

---

## 5. Container (26 Stück)

| Gruppe | Container |
|---|---|
| Einstieg | `frontend-proxy`, `frontend`, `load-generator` |
| Shop-Services | `ad`, `cart`, `checkout`, `currency`, `email`, `image-provider`, `payment`, `product-catalog`, `quote`, `recommendation`, `shipping` |
| Feature Flags | `flagd`, `flagd-ui` |
| Datenbanken | `astronomy-db` (PostgreSQL), `valkey-cart`, `opensearch` |
| Telemetrie | `otel-collector`, `jaeger`, `prometheus`, `grafana` |
| Hilfsdienste | `opamp-server`, `telemetry-docs` |
| MCP (nur mit `compose.mcp.yaml`) | `otel-demo-mcp-sampling-advisor-1` |

Ohne MCP sind es 25 Container.

---

## 6. Status prüfen

```bash
./stack.sh status
```

Alle Container sollen `Up` sein. Container mit Healthcheck zeigen zusätzlich `(healthy)`. `flagd`, `jaeger`, `prometheus`, `grafana`, `cart`, `otel-collector` und der MCP-Container haben keinen Healthcheck und zeigen nur `Up`.

Schnelltest der URLs (alle sollen `200` liefern):

```bash
for u in http://localhost:8080/ http://localhost:8080/jaeger/ui/ \
         http://localhost:8080/grafana/ http://localhost:8080/loadgen/ \
         http://localhost:8080/feature http://localhost:9090/-/healthy; do
  printf "%-40s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 10 $u)"
done
```

Weitere Prüfungen:

```bash
curl -s http://localhost:9090/-/healthy                                   # Prometheus
docker exec grafana curl -s http://127.0.0.1:3000/api/health              # Grafana (bei Podman: podman exec)
./stack.sh check                                                          # Collector
```

---

## 7. Häufige Probleme

| Symptom | Ursache | Lösung |
|---|---|---|
| Port 8080 nicht erreichbar, `frontend`, `frontend-proxy`, `load-generator` im Status `Created` | `recommendation` ist `unhealthy` (`nc: not found`) | `recommendation`-Healthcheck in `compose.lab.yaml` (in `overlay/`, Abschnitt 2) prüfen, Stack neu starten |
| Keine Verbindung zu Podman (macOS/Windows) | Podman Machine gestoppt | `podman machine start` |
| Collector-Log: `lookup kafka ... no such host` | Der Collector scrapt Kafka, im Stack gibt es keinen Kafka-Container | Dauer-Rauschen, kein Einfluss auf Shop und Sampling |
| Collector-Log: Export an Prometheus `HTTP Status Code 500` | Prometheus war beim Start noch nicht bereit | Nach einer Minute prüfen, ob der Fehler wieder auftritt |
| Collector startet nicht | YAML-Fehler oder unbekannter Processor in `otelcol-config.yml` | `./stack.sh logs otel-collector`, Fehler beheben, Stack neu erstellen |
| Spans/s in den Messungen nahe 0 | Kein Traffic | `load-generator` läuft? `./stack.sh status`, mindestens 5 Minuten Traffic abwarten |
| `Connection refused` auf Port 8000 | MCP-Container fehlt | Stack mit `./stack.sh up` starten (MCP ist Standard, nicht mit `--no-mcp`) |

---

## 8. Hinweis zur Baseline

Vor jeder Baseline-Messung prüfen, welche Variante aktiv ist:

```bash
./config.sh show
```

Steht dort etwas anderes als `baseline`, ist es keine Baseline mehr:

```bash
./config.sh use baseline
./stack.sh up
```
