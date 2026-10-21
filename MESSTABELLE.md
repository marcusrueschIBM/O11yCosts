# Messtabelle — Signal Over Noise: Smarter OpenTelemetry Sampling with AI

Messungen aufnehmen mit:
```bash
cd ~/Documents/otel-cost-workshop/opentelemetry-demo
./measure.sh "Baseline"   # dann: "50%", "10%", "Tail", "KI-Policy"
```

---

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
| Collector CPU % | Messung 4 — `podman stats` Spalte CPU | | | | | |
| Collector RAM MiB | Messung 4 — `podman stats` Spalte MEM USAGE | | | | | |

---

## Before / After Auswertung

| KPI | Before (Baseline) | After (KI-Policy) | Ziel |
|---|---|---|---|
| Gesamtrate Spans/s | | | reduziert |
| Top-1-Operation Spans/s | | | reduziert |
| Fehler in Jaeger sichtbar? | | | ja |
| Slow Traces sichtbar? | | | ja |
| Collector CPU % | | | nicht verschlechtert |
| Collector RAM MiB | | | nicht verschlechtert |

**Reduktion % = (Baseline − After) / Baseline × 100**

Baseline Spans/s: ______  |  After Spans/s: ______  |  Reduktion: ______ %
