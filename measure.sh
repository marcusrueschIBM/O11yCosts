#!/usr/bin/env bash
# =============================================================================
# measure.sh — Baseline und Sampling-Vergleichsmessungen
#
# Verwendung:
#   chmod +x measure.sh
#   ./measure.sh              # interaktiv: fragt nach Variante und Dauer
#   ./measure.sh "Baseline"   # Variante direkt als Argument übergeben
#   ./measure.sh "50%"
#   ./measure.sh "Tail"
#
# Ausgabe: Ergebnisse im Terminal + Zeile für die Messtabelle
# =============================================================================

# --- Container-Engine erkennen (docker oder podman; ueberschreibbar mit CONTAINER_ENGINE) ---
if [[ -n "${CONTAINER_ENGINE:-}" ]]; then ENGINE="$CONTAINER_ENGINE"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ENGINE=docker
elif command -v podman >/dev/null 2>&1; then ENGINE=podman
else ENGINE=docker; fi

PROM="http://localhost:9090"
CALLS="traces_span_metrics_calls_total"
DURATION_BUCKET="traces_span_metrics_duration_milliseconds_bucket"
WINDOW="5m"

# --- Variante bestimmen ------------------------------------------------------
VARIANT="${1:-}"
if [[ -z "$VARIANT" ]]; then
  echo ""
  echo "Für welche Variante misst du gerade?"
  echo "  1) Baseline"
  echo "  2) 50% Probabilistic Sampling"
  echo "  3) 10% Probabilistic Sampling"
  echo "  4) Tail Sampling"
  echo "  5) KI-Policy"
  echo ""
  read -rp "Nummer oder eigener Name: " choice
  case "$choice" in
    1) VARIANT="Baseline" ;;
    2) VARIANT="50%" ;;
    3) VARIANT="10%" ;;
    4) VARIANT="Tail" ;;
    5) VARIANT="KI-Policy" ;;
    *) VARIANT="$choice" ;;
  esac
fi

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo ""
echo "============================================================"
echo "  MESSUNG: $VARIANT"
echo "  Zeitstempel: $TIMESTAMP"
echo "  Zeitfenster: $WINDOW"
echo "============================================================"

# --- Hilfsfunktion: Prometheus abfragen --------------------------------------
prom_query() {
  curl -s "${PROM}/api/v1/query" --data-urlencode "query=${1}"
}

# --- Prometheus erreichbar? --------------------------------------------------
health=$(curl -s --max-time 3 "${PROM}/-/healthy" 2>/dev/null)
if [[ "$health" != *"Healthy"* ]]; then
  echo ""
  echo "FEHLER: Prometheus ist nicht erreichbar unter ${PROM}"
  echo "  Stack läuft? → $ENGINE ps | grep prometheus"
  exit 1
fi

# =============================================================================
# MESSUNG 1 — Volumen: Top 20 Operationen nach Span-Rate
# =============================================================================
echo ""
echo "------------------------------------------------------------"
echo "  MESSUNG 1 — Volumen: Top 20 Operationen (Spans/s)"
echo "  Quelle für Tabelle: Gesamtrate + Top-1-Operation"
echo "------------------------------------------------------------"

prom_query "topk(20,sum by (service_name, span_name)(rate(${CALLS}[${WINDOW}])))" \
| python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
if not results:
    print('  Keine Daten — läuft der Load Generator? → $ENGINE ps | grep load')
    sys.exit(0)
results = sorted(results, key=lambda x: float(x['value'][1]), reverse=True)
total = sum(float(r['value'][1]) for r in results)
print(f\"  {'Rang':<4} {'Service':<28} {'Operation':<38} {'Spans/s':>8}\")
print('  ' + '-'*80)
for i, r in enumerate(results, 1):
    svc  = r['metric'].get('service_name', '?')[:27]
    span = r['metric'].get('span_name', '?')[:37]
    val  = float(r['value'][1])
    print(f\"  {i:<4} {svc:<28} {span:<38} {val:>8.2f}\")
print()
print(f'  Gesamtrate (alle Operationen): {total:.2f} Spans/s')
print(f'  Top-1-Operation:               {float(results[0][\"value\"][1]):.2f} Spans/s  ({results[0][\"metric\"].get(\"service_name\",\"?\")}/{results[0][\"metric\"].get(\"span_name\",\"?\")})')
print()
print(f'  --> Tabelle: Gesamtrate Spans/s = {total:.1f}')
print(f'  --> Tabelle: Top-1-Operation Spans/s = {float(results[0][\"value\"][1]):.1f}')
"

# =============================================================================
# MESSUNG 2 — Qualität: Fehlerquote pro Operation
# =============================================================================
echo ""
echo "------------------------------------------------------------"
echo "  MESSUNG 2 — Fehlerquote: Top 15 Operationen (%)"
echo "  Quelle für Tabelle: Anzahl Zeilen > 0% + Max. Fehlerquote"
echo "------------------------------------------------------------"

prom_query "topk(15,100*sum by(service_name,span_name)(rate(${CALLS}{status_code=\"STATUS_CODE_ERROR\"}[${WINDOW}]))/clamp_min(sum by(service_name,span_name)(rate(${CALLS}[${WINDOW}])),0.000001))" \
| python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
results = sorted(results, key=lambda x: float(x['value'][1]), reverse=True)
with_errors = [r for r in results if float(r['value'][1]) > 0]
if not results or not with_errors:
    print('  Keine Fehler-Operationen gefunden — Feature Flag aktiviert?')
    print('  --> Tabelle: Operationen mit Fehlern = 0')
    print('  --> Tabelle: Max. Fehlerquote % = 0.0%')
    sys.exit(0)
print(f\"  {'Service':<28} {'Operation':<38} {'Fehler%':>8}\")
print('  ' + '-'*76)
for r in results:
    val = float(r['value'][1])
    if val <= 0:
        continue
    svc  = r['metric'].get('service_name', '?')[:27]
    span = r['metric'].get('span_name', '?')[:37]
    marker = '  <-- KEEP' if val > 1 else ''
    print(f\"  {svc:<28} {span:<38} {val:>7.1f}%{marker}\")
print()
max_err = float(results[0]['value'][1])
print(f'  Operationen mit Fehlern (> 0%): {len(with_errors)}')
print(f'  Höchste Fehlerquote:            {max_err:.1f}%  ({results[0][\"metric\"].get(\"service_name\",\"?\")}/{results[0][\"metric\"].get(\"span_name\",\"?\")})')
print()
print(f'  --> Tabelle: Operationen mit Fehlern = {len(with_errors)}')
print(f'  --> Tabelle: Max. Fehlerquote % = {max_err:.1f}%')
"

# =============================================================================
# MESSUNG 3 — Latenz: p95 pro Operation
# =============================================================================
echo ""
echo "------------------------------------------------------------"
echo "  MESSUNG 3 — Latenz: Top 15 Operationen (p95 ms)"
echo "  Quelle für Tabelle: Max. p95-Latenz"
echo "------------------------------------------------------------"

prom_query "topk(15,histogram_quantile(0.95,sum by(le,service_name,span_name)(rate(${DURATION_BUCKET}[${WINDOW}]))))" \
| python3 -c "
import json, sys
data = json.load(sys.stdin)
results = data.get('data', {}).get('result', [])
if not results:
    print('  Keine Latenzdaten gefunden.')
    sys.exit(0)
results = sorted(results, key=lambda x: float(x['value'][1]), reverse=True)
print(f\"  {'Service':<28} {'Operation':<38} {'p95 ms':>8}\")
print('  ' + '-'*76)
for r in results:
    val  = float(r['value'][1])
    svc  = r['metric'].get('service_name', '?')[:27]
    span = r['metric'].get('span_name', '?')[:37]
    marker = '  <-- KEEP (>1000ms)' if val > 1000 else ''
    print(f\"  {svc:<28} {span:<38} {val:>7.0f}{marker}\")
print()
max_lat = float(results[0]['value'][1])
slow_count = sum(1 for r in results if float(r['value'][1]) > 1000)
print(f'  Höchste p95-Latenz: {max_lat:.0f} ms  ({results[0][\"metric\"].get(\"service_name\",\"?\")}/{results[0][\"metric\"].get(\"span_name\",\"?\")})')
print(f'  Operationen > 1000ms: {slow_count}')
print()
print(f'  --> Tabelle: Max. p95-Latenz ms = {max_lat:.0f}')
"

# =============================================================================
# MESSUNG 4 — Collector-Ressourcen
# =============================================================================
echo ""
echo "------------------------------------------------------------"
echo "  MESSUNG 4 — Collector CPU und RAM"
echo "  Quelle für Tabelle: CPU % + MEM USAGE"
echo "------------------------------------------------------------"

collector_stats=$("$ENGINE" stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}}" otel-collector 2>/dev/null)
if [[ -z "$collector_stats" ]]; then
  echo "  FEHLER: otel-collector Container nicht gefunden."
  echo "  → $ENGINE ps | grep collector"
else
  cpu=$(echo "$collector_stats" | awk '{print $1}')
  mem=$(echo "$collector_stats" | awk '{print $2}')
  echo "  CPU:  $cpu"
  echo "  RAM:  $mem"
  echo ""
  echo "  --> Tabelle: Collector CPU % = $cpu"
  echo "  --> Tabelle: Collector RAM MiB = $mem"
fi

# =============================================================================
# ZUSAMMENFASSUNG — Tabellenzeile
# =============================================================================
echo ""
echo "============================================================"
echo "  ZUSAMMENFASSUNG für Variante: $VARIANT"
echo "  (Werte manuell in die Messtabelle übertragen)"
echo "============================================================"
echo ""
echo "  Messgröße                  | Wert"
echo "  ---------------------------+--------------------------------"
echo "  Variante                   | $VARIANT"
echo "  Zeitstempel                | $TIMESTAMP"
echo "  Zeitfenster                | $WINDOW"
echo ""
echo "  Gesamtrate Spans/s         | → siehe MESSUNG 1"
echo "  Top-1-Operation Spans/s    | → siehe MESSUNG 1"
echo "  Operationen mit Fehlern    | → siehe MESSUNG 2"
echo "  Max. Fehlerquote %         | → siehe MESSUNG 2"
echo "  Max. p95-Latenz ms         | → siehe MESSUNG 3"
echo "  Fehler in Jaeger sichtbar? | manuell prüfen: http://localhost:8080/jaeger/ui/"
echo "  Slow Traces sichtbar?      | manuell prüfen: http://localhost:8080/jaeger/ui/"
echo "  Collector CPU %            | → siehe MESSUNG 4"
echo "  Collector RAM MiB          | → siehe MESSUNG 4"
echo ""
echo "============================================================"
echo ""
