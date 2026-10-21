# Schritt-für-Schritt-Anleitung: Baseline, Sampling und MCP/AI Advisor

**Voraussetzung:** `./setup.sh` wurde ausgeführt und `./stack.sh status` zeigt alle Container sowie Shop, Jaeger, Prometheus, Grafana, Load Generator und Feature Flags als erreichbar (siehe `README.md` und `START.md`).

Arbeitsverzeichnis für alle folgenden Schritte ist der **Repo-Root** (dort liegen `setup.sh`, `stack.sh`, `config.sh`, `measure.sh`):

```bash
cd <Pfad-zum-Repo>
```

Die vier Sampling-Varianten liegen fertig im Ordner `collector-configs/` und werden mit `./config.sh use <name>` aktiviert. Die YAML-Ausschnitte in den Phasen 2–4 zeigen, was in den Dateien steht.

---

## Phase 1 — Baseline messen

### Schritt 1.1 — Baseline-Konfiguration aktivieren

`./setup.sh` legt die Ausgangskonfiguration als `otelcol-config.original.yml` (Rückweg) ab und aktiviert sie. Prüfen, dass wirklich die Baseline aktiv ist:

```bash
./config.sh show      # erwartet: Aktive Variante: baseline
```

Zeigt das Skript etwas anderes, zurücksetzen und den Stack neu erstellen:

```bash
./config.sh use baseline
./stack.sh up --no-mcp
```

### Schritt 1.2 — Reproduzierbaren Traffic festlegen

**Wichtigstes Prinzip des gesamten Labs:** Zwischen allen Varianten (Baseline, 50%, 10%, Tail, KI) änderst du ausschließlich die Sampling-Konfiguration. Alles andere bleibt identisch:

- Dieselbe Shop-Journey (Produkt → Warenkorb → Checkout)
- Dieselbe Anzahl Wiederholungen (z. B. 10×) **oder** der laufende Load Generator für genau 5 Minuten
- Derselbe PromQL-Zeitraum beim Ablesen (z. B. immer `[5m]` nach Ende des Tests)

Entscheide dich jetzt für eine Variante und halte sie durch.

### Schritt 1.3 — Metriknamen bestätigen

Die Metriknamen können je nach Demo- und Collector-Version abweichen. Einmalig prüfen:

```bash
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep span
```

In dieser Umgebung sind die Namen bestätigt:
- `traces_span_metrics_calls_total`
- `traces_span_metrics_duration_milliseconds_bucket`

Die folgenden Befehle verwenden diese Namen direkt. Falls deine Umgebung andere Namen liefert, ersetze sie entsprechend.

### Schritt 1.4 — Baseline-Werte messen und aufzeichnen

Führe den festgelegten Traffic aus (Schritt 1.2). Danach sofort alle vier Messungen ausführen.

> **Schnellweg: measure.sh**
> Das Script liegt im Repo-Root und führt alle vier Messungen automatisch nacheinander aus. Es zeigt für jede Zeile der Messtabelle direkt den einzutragenden Wert.
>
> ```bash
> ./measure.sh "Baseline"
> ```
>
> Nach jeder Sampling-Variante einfach denselben Befehl mit dem passenden Namen aufrufen:
> ```bash
> ./measure.sh "50%"
> ./measure.sh "10%"
> ./measure.sh "Tail"
> ./measure.sh "KI-Policy"
> ```
>
> Die Einzelbefehle weiter unten sind zur Erklärung — das Script erledigt alles in einem Durchgang.

---

> **Warum direkt im Terminal statt in der Prometheus-UI?**
> Die Prometheus-UI liefert keine sortierte Tabelle — du siehst die Ergebnisse in zufälliger Reihenfolge und kannst sie nicht direkt vergleichen. Die Terminal-Befehle unten formatieren die Ausgabe sofort als sortierte, lesbare Tabelle. Das spart Zeit und macht die Ergebnisse zwischen den Varianten direkt vergleichbar.

---

#### Messung 1 — Volumen: Top 20 Operationen nach Span-Rate

**Warum diese Messung?**
Sie zeigt, wer den meisten Traffic erzeugt. Das ist der Ausgangspunkt für jede Sampling-Entscheidung: Operationen mit hohem Volumen, die gleichzeitig unkritisch sind, sind die besten Kandidaten für aggressives Sampling. Operationen mit niedrigem Volumen lassen sich kaum weiter reduzieren — sie fallen kaum ins Gewicht.

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=topk(20,sum by (service_name, span_name)(rate(traces_span_metrics_calls_total[5m])))' \
  | python3 -c "
import json,sys
r=sorted(json.load(sys.stdin)['data']['result'],key=lambda x:float(x['value'][1]),reverse=True)
print(f'{'Rang':<4} {'Service':<30} {'Operation':<40} {'Spans/s':>8}')
print('-'*84)
[print(f'{i:<4} {x[\"metric\"].get(\"service_name\",\"?\"):<30} {x[\"metric\"].get(\"span_name\",\"?\"):<40} {float(x[\"value\"][1]):>8.2f}') for i,x in enumerate(r,1)]
"
```

Notiere die **Top 5** — diese Services werden in den nächsten Schritten als erstes reduziert.

---

#### Messung 2 — Qualität: Top 15 Operationen nach Fehlerquote

**Warum diese Messung?**
Volumen allein reicht nicht. Eine Operation mit 10 Spans/s und 30% Fehlerquote darf **nicht** gesampelt werden — jeder verworfene Span könnte einen Fehler verstecken. Diese Messung schützt dich davor, unwissentlich Fehler-Sichtbarkeit zu opfern. Die Kombination aus Volumen (Messung 1) und Fehlerquote (Messung 2) ist die Grundlage für jede seriöse Sampling-Entscheidung.

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=topk(15,100*sum by(service_name,span_name)(rate(traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m]))/clamp_min(sum by(service_name,span_name)(rate(traces_span_metrics_calls_total[5m])),0.000001))' \
  | python3 -c "
import json,sys
r=sorted(json.load(sys.stdin)['data']['result'],key=lambda x:float(x['value'][1]),reverse=True)
print(f'{'Service':<30} {'Operation':<40} {'Fehler%':>8}')
print('-'*80)
[print(f'{x[\"metric\"].get(\"service_name\",\"?\"):<30} {x[\"metric\"].get(\"span_name\",\"?\"):<40} {float(x[\"value\"][1]):>7.1f}%') for x in r]
"
```

Einstufung (identisch mit `mcp_advisor.sh` in Schritt 5.8):
- Fehlerquote **> 5%** → **KEEP**-Liste
- Fehlerquote **> 0%** → **WATCH** (beobachten, nicht aggressiv sampeln)

---

#### Messung 3 — Latenz: Top 15 Operationen nach p95-Antwortzeit

**Warum diese Messung?**
Langsame Operationen sind oft das, was du im Fehlerfall als erstes brauchst. Wenn eine Operation p95 > 1000ms hat, willst du diese Traces vollständig behalten — sie zeigen dir genau, wo ein Performance-Problem liegt. Ohne diese Messung sammelst du eventuell die falschen 10% und verlierst genau die langsamen Traces, die dir bei der Diagnose helfen würden.

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=topk(15,histogram_quantile(0.95,sum by(le,service_name,span_name)(rate(traces_span_metrics_duration_milliseconds_bucket[5m]))))' \
  | python3 -c "
import json,sys
r=sorted(json.load(sys.stdin)['data']['result'],key=lambda x:float(x['value'][1]),reverse=True)
print(f'{'Service':<30} {'Operation':<40} {'p95 ms':>8}')
print('-'*80)
[print(f'{x[\"metric\"].get(\"service_name\",\"?\"):<30} {x[\"metric\"].get(\"span_name\",\"?\"):<40} {float(x[\"value\"][1]):>7.0f}') for x in r]
"
```

Einstufung (identisch mit `mcp_advisor.sh` in Schritt 5.8):
- p95 **> 1000ms** → **KEEP**-Liste
- p95 **> 500ms** → **WATCH**

Operationen ohne Fehler und mit p95 ≤ 500ms sind **SAMPLE**-Kandidaten.

---

#### Messung 4 — Collector-Ressourcen

**Warum diese Messung?**
Der Collector-RAM ist besonders bei Tail Sampling relevant — er puffert vollständige Traces im Speicher, bis er eine Entscheidung treffen kann. Der Vergleich vor und nach dem Sampling zeigt, ob die Konfigurationsänderung den Collector entlastet oder belastet.

```bash
docker stats --no-stream otel-collector     # oder: podman stats --no-stream otel-collector
```

`measure.sh` erkennt die Engine selbst und führt diese Messung automatisch mit aus.

---

Trage nach jeder Variante die Werte aus den vier Messungen in diese Tabelle ein:

| Messgröße | Quelle | Baseline | 50% | 10% | Tail | KI-Policy |
|---|---|---|---|---|---|---|
| Testdauer | Uhr / Notiz — wie lange lief der Traffic? | | | | | |
| Gesamtrate Spans/s | Messung 1 — Summe der Spans/s über alle Operationen | | | | | |
| Top-1-Operation Spans/s | Messung 1 — Wert der lautesten einzelnen Operation | | | | | |
| Operationen mit Fehlern | Messung 2 — Anzahl Zeilen mit Fehlerquote > 0% | | | | | |
| Max. Fehlerquote % | Messung 2 — höchster Einzelwert in der Fehler-Tabelle | | | | | |
| Max. p95-Latenz ms | Messung 3 — höchster Einzelwert in der Latenz-Tabelle | | | | | |
| Fehler in Jaeger sichtbar? | Jaeger manuell prüfen — ja / nein | | | | | |
| Slow Traces sichtbar? | Jaeger manuell prüfen — ja / nein | | | | | |
| Collector CPU % | Messung 4 — `docker/podman stats` Spalte CPU | | | | | |
| Collector RAM MiB | Messung 4 — `docker/podman stats` Spalte MEM USAGE | | | | | |

---

## Phase 2 — Probabilistisches Sampling 50%

### Schritt 2.1 — Variante aktivieren

```bash
./config.sh use head-50
```

Das kopiert `collector-configs/head-50.yml` nach `opentelemetry-demo/src/otel-collector/otelcol-config.yml`. Die Datei unterscheidet sich von der Baseline nur durch die beiden Änderungen aus 2.2 und 2.3. Zum Nachvollziehen:

```bash
diff collector-configs/baseline.yml collector-configs/head-50.yml
```

### Schritt 2.2 — Was im Processor-Block steht

Unter `processors:` wurde ergänzt (bestehende Processor-Einträge bleiben unverändert):

```yaml
processors:
  # ... bestehende Konfiguration bleibt unverändert ...
  probabilistic_sampler:
    sampling_percentage: 50
```

### Schritt 2.3 — Processor in der Pipeline

In der Trace-Pipeline steht `probabilistic_sampler` am Ende der `processors`-Liste:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [resource_detection, memory_limiter,
        transform/sanitize_spans, gen_ai_normalizer,
        transform/redact_sensitive_data, redaction,
        probabilistic_sampler]
      exporters: [debug, span_metrics]
```

> **Hinweis:** Die Liste zeigt die Processor-Namen des gepinnten Upstream-Stands (`fdbd62ca`). Wer die Konfiguration von Hand ändert, hängt nur `probabilistic_sampler` ans Ende an und löscht nichts.

### Schritt 2.4 — Stack neu erstellen

Eine geänderte YAML-Datei aktualisiert einen laufenden Collector **nicht automatisch**. Immer neu erstellen:

```bash
./stack.sh up --no-mcp
```

### Schritt 2.5 — Collector auf Fehler prüfen

```bash
./stack.sh check
```

Keine Ausgabe = keine Fehler. Wenn der Collector wegen YAML-Fehler oder einem unbekannten Processor nicht startet: **Konfigurationsfehler zuerst beheben, bevor du weiter misst.**

### Schritt 2.6 — Test durchführen und messen

Führe identischen Traffic wie bei der Baseline aus. Danach messen:

```bash
./measure.sh "50%"
```

Werte in die **50%-Spalte** eintragen. Hinweis: Das Ergebnis wird wegen der probabilistischen Auswahl nicht exakt 50% der Baseline sein — das ist normal.

---

## Phase 3 — Probabilistisches Sampling 10%

### Schritt 3.1 — Variante aktivieren

```bash
./config.sh use head-10
```

Gegenüber `head-50` ändert sich genau eine Zeile im `probabilistic_sampler`-Block:

```yaml
probabilistic_sampler:
  sampling_percentage: 10
```

### Schritt 3.2 — Stack neu starten und prüfen

```bash
./stack.sh up --no-mcp

./stack.sh check
```

### Schritt 3.3 — Test durchführen und messen

Identischen Traffic ausführen. Danach messen:

```bash
./measure.sh "10%"
```

Werte in die **10%-Spalte** eintragen.

---

## Phase 4 — Tail Sampling

### Schritt 4.1 — Variante aktivieren

```bash
./config.sh use tail
```

Gegenüber `head-10` fehlt der `probabilistic_sampler` (Block und Pipeline-Eintrag), stattdessen steht `tail_sampling` in der Konfiguration.

### Schritt 4.2 — Was der Tail Sampler enthält

Unter `processors:` steht:

```yaml
processors:
  # ... bestehende Processor bleiben ...
  tail_sampling:
    decision_wait: 10s
    num_traces: 5000
    expected_new_traces_per_sec: 100
    policies:
      - name: keep-errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: keep-slow
        type: latency
        latency: {threshold_ms: 1000}
      - name: sample-normal
        type: probabilistic
        probabilistic: {sampling_percentage: 10}
```

In der Trace-Pipeline steht `tail_sampling` am Ende der Liste:

```yaml
processors: [resource_detection, memory_limiter,
  transform/sanitize_spans, gen_ai_normalizer,
  transform/redact_sensitive_data, redaction,
  tail_sampling]
```

### Schritt 4.3 — Stack neu starten und prüfen

```bash
./stack.sh up --no-mcp

./stack.sh check
```

### Schritt 4.4 — Drei Verkehrsszenarien testen

Teste nacheinander:

**Normal-Traffic:** Load Generator läuft oder manuelle Shop-Journeys.

**Fehler-Szenario:** Feature Flag aktivieren unter http://localhost:8080/feature. Ein Flag für einen simulierten Fehler einschalten. Einige Journeys ausführen. Flag danach zurücksetzen.

**Slow-Szenario:** Feature Flag für eine simulierte Verlangsamung aktivieren. Einige Journeys ausführen. Flag zurücksetzen.

> **Wichtig:** Nach dem Neustart mindestens `decision_wait` (10 Sekunden) abwarten, bevor du Jaeger nach Ergebnissen durchsuchst. Tail Sampling puffert erst den vollständigen Trace, bevor es entscheidet.

### Schritt 4.5 — Ergebnisse prüfen

In Jaeger prüfen:
- Fehler-Traces: Sind ERROR-Traces vollständig vorhanden?
- Slow-Traces: Sind Traces mit Latenz > 1000ms vollständig vorhanden?
- Normal-Traces: Sind diese auf ~10% reduziert?

Danach messen:

```bash
./measure.sh "Tail"
```

Werte in die **Tail-Spalte** eintragen.

---

## Phase 5 — MCP Sampling Advisor aufbauen

### Schritt 5.1 — Prometheus-Metriknamen bestätigen

Bevor der MCP-Server konfiguriert wird, die tatsächlichen Namen aus Schritt 1.3 nochmals bestätigen:

```bash
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep span
```

Falls die Namen von den Defaults abweichen, in `opentelemetry-demo/.env.override` eintragen (mit einem beliebigen Editor):

Beispiel falls deine Namen anders heißen:
```
CALLS_METRIC=dein_tatsaechlicher_metrikname_calls
DURATION_BUCKET_METRIC=dein_tatsaechlicher_metrikname_bucket
```

### Schritt 5.2 — Die MCP-Dateien (liegen bereits im Repo)

`./setup.sh` hat die Dateien des MCP-Servers schon angelegt. Nichts abtippen. Sie liegen in `overlay/` und landen im Demo-Verzeichnis:

| Datei im Repo | Zweck |
|---|---|
| `overlay/mcp-sampling-advisor/server.py` | Der MCP-Server mit den vier Tools |
| `overlay/mcp-sampling-advisor/requirements.txt` | Python-Abhängigkeiten (`mcp[cli]`, `httpx`) |
| `overlay/mcp-sampling-advisor/Containerfile` | Container-Image (Python 3.12) |
| `overlay/compose.mcp.yaml` | Startet den MCP-Container neben dem Stack (Port 8000) |

Aufbau und Code des Servers sind in `MCP_SERVER_ERKLAERUNG.md` Zeile für Zeile erklärt.

### Schritt 5.3 — Änderungen am Server

Wer `overlay/mcp-sampling-advisor/server.py` ändert, kopiert die Datei neu ins Demo-Verzeichnis und baut das Image neu:

```bash
./setup.sh
./stack.sh build-mcp
./stack.sh up
```

### Schritt 5.4 — Überschreibbare Einstellungen

`compose.mcp.yaml` liest Metrik- und Labelnamen aus Umgebungsvariablen mit Defaults. Nur nötig, wenn Schritt 5.1 abweichende Namen gezeigt hat (`CALLS_METRIC`, `DURATION_BUCKET_METRIC`, `SERVICE_LABEL`, `SPAN_LABEL`, `STATUS_LABEL`, `ERROR_VALUE`).

### Schritt 5.5 — MCP-Container bauen und starten

```bash
./stack.sh up
```

### Schritt 5.6 — MCP-Logs prüfen

```bash
./stack.sh logs mcp-sampling-advisor
```

Erwartete Ausgabe: Server startet auf Port 8000, keine Fehler.

### Schritt 5.7 — MCP-Tools mit dem Inspector testen

MCP Inspector starten:

```bash
npx -y @modelcontextprotocol/inspector
```

Im Browser öffnet sich der Inspector. Dort:
1. Transport: **Streamable HTTP** auswählen (nicht SSE — sonst zeigt der Inspector „No tools“)
2. URL eingeben:
   ```
   http://localhost:8000/mcp
   ```
3. **Connect** klicken, dann den Reiter **Tools** öffnen

Teste nacheinander alle vier Tools:
1. `top_operations` — liefert Operationen mit hohem Call-Volumen?
2. `error_hotspots` — liefert Operationen mit hoher Fehlerquote?
3. `slow_operations` — liefert Operationen mit hoher p95-Latenz?
4. `sampling_candidates` — liefert alle drei kombiniert?

### Schritt 5.8 — Empfehlungen als Liste anzeigen (mcp_advisor.sh)

Das Script `mcp_advisor.sh` liegt im Repo-Root. Es ruft `sampling_candidates` über MCP ab und zeigt pro Operation eine Empfehlung — ohne KI-Client und ohne Browser:

```bash
./mcp_advisor.sh
```

Einstufung pro Operation:

| Empfehlung | Bedingung |
|---|---|
| 🔴 **KEEP** | Fehlerquote > 5% **oder** p95 > 1000ms |
| 🟡 **WATCH** | Fehlerquote > 0% **oder** p95 > 500ms |
| 🟢 **SAMPLE** | alles andere — Kandidat für aggressives Sampling |

Zusätzlich gibt das Script die Fehler-Hotspots (> 5%), die Slow-Operationen (p95 > 1000ms) und eine empfohlene Tail-Sampling-Konfiguration aus. Die Werte sind eine regelbasierte Vorschau dessen, was die KI in Phase 6 begründet empfiehlt — **Human Review** ist trotzdem Pflicht.

Falls `FEHLER: MCP-Server nicht erreichbar` erscheint: `./stack.sh status` prüfen.

> **Stopp:** Erst wenn alle vier Tools und `mcp_advisor.sh` plausible Daten zurückgeben, weiter zu Phase 6. Leere Ergebnisse bedeuten: PromQL-Abfrage stimmt nicht, Metriknamen falsch, oder Prometheus hat noch keine Daten.

---

## Phase 6 — KI-gestützte Sampling-Policy

### Schritt 6.1 — KI-Client mit MCP verbinden

Nutze einen KI-Client der Streamable HTTP MCP unterstützt (z. B. IBM Bob, Claude Desktop, oder ein anderer MCP-fähiger Client). Verbinde ihn mit:

```
http://localhost:8000/mcp
```

### Schritt 6.2 — System-Prompt setzen

Gib dem KI-Client diesen System-Prompt:

```
You are an Observability Sampling Advisor.
Use only MCP data — do not invent values.
Preserve errors, slow traces, and business-critical flows.
Recommend aggressive sampling only for high volume, low error rate, and low latency operations.
Deliver evidence, risk, policy idea, validation, and rollback plan.
Do not execute any change — a human decides.
```

### Schritt 6.3 — Analyse anfordern

Stelle der KI folgende Fragen (nacheinander oder kombiniert):

1. Welche Operationen erzeugen hohes Volumen, sind gleichzeitig fehlerarm und schnell?
2. Welche Operationen sollten wegen Fehlern, Latenz oder Business-Kritikalität vollständig erhalten bleiben?
3. Schlage eine Tail-Sampling-Policy vor — führe aber keine Änderung aus.

Erwartetes Ausgabeformat der KI pro Operation:

| Operation | Volumen | Fehler | p95 | Empfehlung | Begründung |
|---|---|---|---|---|---|
| service/span | hoch/mittel/niedrig | % | ms | KEEP / SAMPLE / DROP | Evidenz aus MCP |

### Schritt 6.4 — KI-Policy menschlich prüfen (Human Review)

**Vor jeder Änderung am Collector prüfen:**

- Werden alle Fehler-Traces behalten? (`keep-errors`)
- Werden alle langsamen Traces behalten? (`keep-slow`)
- Sind business-kritische Flows explizit geschützt?
- Sind die empfohlenen Routen/Attribute tatsächlich in deinen Traces vorhanden?

> **Wichtig:** Die Routen `/api/checkout` und `/api/payment` in der Beispiel-Policy unten sind **Platzhalter**. Verwende nur Attribute, die du in Jaeger wirklich gesehen hast.

### Schritt 6.5 — Policy in die Variante `ai-policy` übertragen

`collector-configs/ai-policy.yml` ist eine Kopie der Variante `tail` mit einem **auskommentierten** Platzhalter für kritische Routen. Trage dort (mit einem beliebigen Editor) die vom Menschen geprüfte KI-Policy ein. Der `tail_sampling`-Block soll danach so aussehen:

```yaml
tail_sampling:
  decision_wait: 10s
  num_traces: 5000
  expected_new_traces_per_sec: 100
  policies:
    - name: keep-errors
      type: status_code
      status_code: {status_codes: [ERROR]}
    - name: keep-slow
      type: latency
      latency: {threshold_ms: 1000}
    - name: keep-critical-routes        # NUR wenn Route tatsächlich in Traces vorhanden
      type: string_attribute
      string_attribute:
        key: http.route
        values: [/api/checkout, /api/payment]   # DURCH ECHTE ROUTEN ERSETZEN
    - name: sample-normal
      type: probabilistic
      probabilistic: {sampling_percentage: 10}
```

### Schritt 6.6 — Variante aktivieren, Stack neu erstellen und prüfen

```bash
./config.sh use ai-policy
./stack.sh up

./stack.sh check
```

Identischen Traffic ausführen (alle drei Szenarien: normal, Fehler, langsam).

---

## Phase 7 — Before / After dokumentieren

### Schritt 7.1 — After-Werte messen

Identischen Traffic wie bei der Baseline ausführen. Danach messen:

```bash
./measure.sh "KI-Policy"
```

Werte in die **KI-Policy-Spalte** eintragen.

### Schritt 7.2 — Reduktion berechnen

```
Reduktion % = (Baseline - After) / Baseline × 100
```

Beispiel: Baseline = 1000 Calls/s, After = 120 Calls/s → Reduktion = 88%

### Schritt 7.3 — Sichtbarkeit der wertvollen Signale prüfen

Checkliste:
- [ ] Fehler-Traces in Jaeger sichtbar?
- [ ] Slow-Traces in Jaeger sichtbar?
- [ ] Kritische Flows nachverfolgbar?
- [ ] MTTD/MTTR nicht verschlechtert?

### Schritt 7.4 — Rollback testen

Stelle sicher, dass der Rollback funktioniert:

```bash
./config.sh use baseline
./stack.sh up

./stack.sh check
```

Nach dem Rollback: Jaeger und Prometheus kurz prüfen, Collector-Logs auf Fehler kontrollieren.

---

## Zusammenfassung der Geschichte für den Vortrag

1. **Wir messen zuerst** — keine Schätzungen, echte Daten aus Prometheus
2. **Pauschales Sampling** reduziert Volumen, kann aber Kontext kosten
3. **Tail Sampling schützt wertvolle Signale** — Fehler und langsame Traces bleiben erhalten
4. **MCP gibt der KI echte Telemetriedaten** — kein Raten, nur Evidenz
5. **Die KI schlägt vor, ein Mensch entscheidet** — Rollback ist jederzeit möglich
6. **Wir messen erneut** und belegen die Reduktion mit denselben Metriken
