# MCP Sampling Advisor — Erklärung für Einsteiger

## Was ist MCP überhaupt?

**MCP** steht für **Model Context Protocol** — ein offenes Protokoll von Anthropic, das festlegt wie ein KI-Modell mit externen Werkzeugen und Datenquellen kommuniziert.

Stell dir MCP wie eine standardisierte Steckdose vor:

```
KI-Client (z.B. Claude, IBM Bob)
    │
    │  spricht MCP — immer gleich, egal welche KI
    │
    ▼
MCP-Server (unser sampling advisor)
    │
    │  fragt Prometheus ab
    │
    ▼
Prometheus (echte Messdaten)
```

Ohne MCP müsste jede KI eine eigene Anbindung an Prometheus haben.
Mit MCP baust du den Server einmal — jede MCP-fähige KI kann ihn benutzen.

---

## Was macht unser MCP-Server konkret?

Der **OTel Sampling Advisor** ist ein read-only MCP-Server. Er:

1. Empfängt Anfragen von einer KI
2. Fragt Prometheus mit PromQL ab
3. Gibt die Ergebnisse strukturiert an die KI zurück

**Read-only** bedeutet: Er verändert nichts. Er liest nur Daten.
Keine Schreibzugriffe auf den Collector, keine automatischen Änderungen.
Die KI empfiehlt — ein Mensch entscheidet und ändert.

---

## Die vier Werkzeuge (Tools)

Der Server stellt der KI vier Werkzeuge bereit:

| Tool | Fragt Prometheus nach | Gibt zurück |
|---|---|---|
| `top_operations` | Welche Operationen erzeugen das meiste Span-Volumen? | Rangliste Service + Operation + Spans/s |
| `error_hotspots` | Welche Operationen haben die höchste Fehlerquote? | Rangliste Service + Operation + Fehler% |
| `slow_operations` | Welche Operationen haben die höchste p95-Latenz? | Rangliste Service + Operation + ms |
| `sampling_candidates` | Alle drei kombiniert | Volumen + Fehler + Latenz + Regeln |

Die KI ruft diese Tools auf, bewertet die Daten und formuliert eine Empfehlung.
Sie erfindet keine Werte — alles basiert auf echten Messdaten aus Prometheus.

---

## Architektur: Wo sitzt der MCP-Server?

```
┌─────────────────────────────────────────────────────────┐
│  macOS                                                  │
│                                                         │
│  KI-Client ──MCP──► http://localhost:8000/mcp           │
│                                │                        │
│  ┌─────────────────────────────▼───────────────────┐    │
│  │  Podman Machine (Linux VM)                      │    │
│  │                                                 │    │
│  │  ┌─────────────────┐    ┌──────────────────┐   │    │
│  │  │  mcp-sampling-  │    │   Prometheus      │   │    │
│  │  │  advisor        │◄───│   :9090           │   │    │
│  │  │  :8000          │    │                   │   │    │
│  │  └─────────────────┘    └──────────────────┘   │    │
│  │                                  ▲              │    │
│  │  ┌─────────────────┐             │              │    │
│  │  │  OTel Collector │─────────────┘              │    │
│  │  │  (Span Metrics) │                            │    │
│  │  └─────────────────┘                            │    │
│  │         ▲                                       │    │
│  │  ┌──────┴──────────┐                            │    │
│  │  │  Astronomy Shop │                            │    │
│  │  │  (Spans/Traces) │                            │    │
│  │  └─────────────────┘                            │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

Der MCP-Server läuft als Container **neben** dem restlichen Stack.
Er hat Zugriff auf Prometheus über das interne Container-Netzwerk (`http://prometheus:9090`).
Von außen (macOS) ist er unter `http://localhost:8000/mcp` erreichbar.

---

## Die drei Dateien des MCP-Servers

### 1. `requirements.txt` — Python-Abhängigkeiten

```
mcp[cli]>=2.2,<3
httpx>=0.27,<1
```

- **`mcp[cli]`** — das MCP Python SDK. Stellt `MCPServer`, `@mcp.tool()` und das HTTP-Transport bereit.
- **`httpx`** — HTTP-Client für die Prometheus-API-Abfragen. Async-fähig, also nicht blockierend.

### 2. `Containerfile` — Bauanleitung für den Container

```dockerfile
FROM python:3.12-slim        # Basis: minimales Python 3.12 Image
WORKDIR /app                 # Arbeitsverzeichnis im Container
COPY requirements.txt .      # Abhängigkeiten kopieren
RUN pip install --no-cache-dir -r requirements.txt  # installieren
COPY server.py .             # Server-Code kopieren
EXPOSE 8000                  # Port dokumentieren (nicht öffnen)
CMD ["python", "server.py"]  # Startbefehl
```

### 3. `server.py` — der eigentliche Server

```python
import os, httpx
from mcp.server import MCPServer

# Server erstellen mit einem Namen
mcp = MCPServer("OTel Sampling Advisor")

# Konfiguration aus Umgebungsvariablen lesen
# (Defaults passen für die Demo-Umgebung)
PROM   = os.getenv("PROM_URL",  "http://prometheus:9090")
CALLS  = os.getenv("CALLS_METRIC", "traces_span_metrics_calls_total")
DUR    = os.getenv("DURATION_BUCKET_METRIC",
                   "traces_span_metrics_duration_milliseconds_bucket")
SVC    = os.getenv("SERVICE_LABEL",  "service_name")
SPAN   = os.getenv("SPAN_LABEL",     "span_name")
STATUS = os.getenv("STATUS_LABEL",   "status_code")
ERR    = os.getenv("ERROR_VALUE",    "STATUS_CODE_ERROR")
```

**Warum Umgebungsvariablen?** Die Metriknamen können je nach
Collector-Version abweichen. Über `.env.override` kannst du sie
anpassen ohne den Code zu ändern.

```python
# Hilfsfunktion: Prometheus HTTP API aufrufen
async def q(expr):
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.get(f"{PROM}/api/v1/query", params={"query": expr})
        r.raise_for_status()
        return r.json()["data"]["result"]
```

Diese Funktion sendet eine PromQL-Query an Prometheus und gibt die
Rohergebnisse zurück. `async` bedeutet: während Prometheus antwortet,
kann der Server andere Anfragen bearbeiten.

```python
# Ergebnisse in ein lesbares Format umwandeln
def out(rows):
    return [{"labels": r.get("metric", {}),
             "value": float(r["value"][1])} for r in rows]
```

Wandelt die Prometheus-Rohantwort in eine einfache Liste um:
`[{"labels": {"service_name": "frontend", ...}, "value": 8.92}, ...]`

```python
# Tool 1: Top-Operationen nach Volumen
@mcp.tool()
async def top_operations(window: str = "5m", limit: int = 15):
    return out(await q(
        f"topk({limit},sum by ({SVC},{SPAN})(rate({CALLS}[{window}])))"
    ))
```

`@mcp.tool()` registriert die Funktion als MCP-Werkzeug. Die KI kann
es mit `top_operations(window="10m", limit=20)` aufrufen.

```python
# Tool 4: Alle drei kombiniert — das Hauptwerkzeug für die KI
@mcp.tool()
async def sampling_candidates(window: str = "5m", limit: int = 20):
    return {
        "volume": await top_operations(window, limit),
        "errors": await error_hotspots(window, limit),
        "slow":   await slow_operations(window, limit),
        "rules":  ["keep errors", "keep slow",
                   "protect critical", "human review"]
    }
```

`sampling_candidates` ist das wichtigste Tool — es ruft alle drei
anderen auf und liefert alles auf einmal. Die `rules`-Liste gibt der KI
explizite Leitlinien mit.

```python
# Server starten
if __name__ == "__main__":
    mcp.run("streamable-http", host="0.0.0.0", port=8000)
```

**Streamable HTTP** ist das MCP-Transport-Protokoll für Netzwerk-Verbindungen.
`0.0.0.0` bedeutet: auf allen Netzwerk-Interfaces lauschen (nötig im Container).

---

## Installation Schritt für Schritt

### Voraussetzung

Der Astronomy Shop Stack läuft bereits (Prometheus erreichbar unter
`http://localhost:9090`). Prüfen:

```bash
curl -s http://localhost:9090/-/healthy
# Erwartung: Prometheus Server is Healthy.
```

### Schritt 1 — Dateien bereitstellen

Nichts abtippen: `./setup.sh` legt alle Dateien im Demo-Verzeichnis an. Sie liegen im Repo unter `overlay/`:

- `overlay/mcp-sampling-advisor/server.py`
- `overlay/mcp-sampling-advisor/requirements.txt`
- `overlay/mcp-sampling-advisor/Containerfile`
- `overlay/compose.mcp.yaml`

Der Inhalt entspricht den Auszügen im Abschnitt „Die drei Dateien des MCP-Servers“ oben.

### Schritt 2 — compose.mcp.yaml

**Was bedeutet `${CALLS_METRIC:-traces_span_metrics_calls_total}` in `compose.mcp.yaml`?**
"Nimm den Wert aus `.env.override`, falls gesetzt — sonst den Default."
So kannst du Namen überschreiben ohne den Code zu ändern.

### Schritt 3 — Container bauen und starten

```bash
./stack.sh up
```

Nach Änderungen an `server.py` das Image neu bauen und den Stack neu erstellen:

```bash
./stack.sh build-mcp
./stack.sh up
```

### Schritt 4 — Logs prüfen

```bash
./stack.sh logs mcp-sampling-advisor
```

Erwartete Ausgabe (sinngemäß):
```
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

Fehler hier bedeuten meistens: pip-Install fehlgeschlagen oder
Python-Syntax-Fehler in `server.py`.

### Schritt 5 — MCP-Server ohne KI testen (MCP Inspector)

Der MCP Inspector ist ein Browser-Tool zum manuellen Testen von MCP-Servern.

```bash
npx -y @modelcontextprotocol/inspector
```

Browser öffnet sich automatisch. Dort:
1. Transport: **Streamable HTTP** auswählen
2. URL eingeben: `http://localhost:8000/mcp`
3. **Connect** klicken
4. Im Reiter **Tools** die vier Werkzeuge testen:
   - `top_operations` — liefert Rangliste nach Volumen?
   - `error_hotspots` — liefert Fehlerquoten?
   - `slow_operations` — liefert Latenzen?
   - `sampling_candidates` — liefert alle drei kombiniert?

**Wenn ein Tool leere Ergebnisse zurückgibt:**
- Läuft Prometheus? → `curl -s http://localhost:9090/-/healthy`
- Gibt es Span-Metriken? → `curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep span`
- Stimmen die Metriknamen? → Prüfen ob `traces_span_metrics_calls_total` existiert

### Schritt 6 — KI-Client verbinden

Nutze einen KI-Client der **Streamable HTTP MCP** unterstützt.
Konfiguriere ihn mit dem Endpunkt: `http://localhost:8000/mcp`

**System-Prompt für die KI:**

```
You are an Observability Sampling Advisor.
Use only MCP data — do not invent values.
Preserve errors, slow traces, and business-critical flows.
Recommend aggressive sampling only for high volume,
low error rate, and low latency operations.
Deliver evidence, risk, policy idea, validation, and rollback plan.
Do not execute any change — a human decides.
```

**Fragen an die KI:**

1. Ruf `sampling_candidates` auf und analysiere die Ergebnisse.
2. Welche Operationen haben hohes Volumen aber niedrige Fehlerquote und niedrige Latenz?
3. Schlage eine Tail-Sampling-Policy vor — mit Begründung pro Operation.

---

## Häufige Fehler und Lösungen

| Fehler | Ursache | Lösung |
|---|---|---|
| `Connection refused` auf Port 8000 | Container nicht gestartet | `./stack.sh status` prüfen |
| Tools geben leere Liste zurück | Prometheus hat keine Daten | Load Generator läuft? `./stack.sh status` |
| `ModuleNotFoundError: mcp` | pip-Install fehlgeschlagen | Container neu bauen: `--build` Flag |
| `Connection refused` auf Prometheus | Falscher PROM_URL | Ist `http://prometheus:9090` erreichbar? Nur intern im Container-Netz |
| MCP Inspector zeigt "No tools" | Falsches Transport-Protokoll | **Streamable HTTP** wählen, nicht SSE |

---

## Zusammenfassung in einem Satz pro Komponente

- **`server.py`** — liest Prometheus, stellt 4 Tools bereit, läuft auf Port 8000
- **`Containerfile`** — verpackt server.py in ein Python 3.12 Container-Image
- **`requirements.txt`** — MCP SDK + httpx, sonst nichts
- **`compose.mcp.yaml`** — startet den Container neben dem restlichen Stack
- **MCP Inspector** — Browser-Tool zum Testen der Tools ohne KI
- **KI-Client** — stellt Fragen, bekommt echte Messdaten, empfiehlt Policy
