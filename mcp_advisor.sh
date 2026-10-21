#!/usr/bin/env bash
# =============================================================================
# mcp_advisor.sh — MCP Sampling Advisor: Empfehlungen als lesbare Liste
#
# Verwendung:
#   chmod +x mcp_advisor.sh
#   ./mcp_advisor.sh
# =============================================================================

# --- Container-Engine erkennen (docker oder podman; ueberschreibbar mit CONTAINER_ENGINE) ---
if [[ -n "${CONTAINER_ENGINE:-}" ]]; then ENGINE="$CONTAINER_ENGINE"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ENGINE=docker
elif command -v podman >/dev/null 2>&1; then ENGINE=podman
else ENGINE=docker; fi

MCP="http://localhost:8000/mcp"

echo ""
echo "============================================================"
echo "  MCP SAMPLING ADVISOR"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# Session aufbauen
SESSION=$(curl -s -X POST "$MCP" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -D - \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp_advisor.sh","version":"1.0"}}}' \
  2>/dev/null | grep -i "mcp-session-id" | awk '{print $2}' | tr -d '\r')

if [[ -z "$SESSION" ]]; then
  echo "FEHLER: MCP-Server nicht erreichbar unter $MCP"
  echo "  → $ENGINE ps | grep mcp"
  exit 1
fi

# Daten abrufen
RESULT=$(curl -s -X POST "$MCP" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"sampling_candidates","arguments":{"window":"5m","limit":20}}}' \
  2>/dev/null | grep "^data:" | sed 's/^data: //')

if [[ -z "$RESULT" ]]; then
  echo "FEHLER: Keine Daten vom MCP-Server erhalten."
  exit 1
fi

# Ausgabe formatieren
echo "$RESULT" | python3 -c "
import json, sys

raw = json.load(sys.stdin)
data = json.loads(raw['result']['content'][0]['text'])

volume  = data.get('volume', [])
errors  = {f\"{r['labels'].get('service_name','?')}/{r['labels'].get('span_name','?')}\": r['value'] for r in data.get('errors', [])}
slow    = {f\"{r['labels'].get('service_name','?')}/{r['labels'].get('span_name','?')}\": r['value'] for r in data.get('slow', [])}

print()
print('------------------------------------------------------------')
print('  EMPFEHLUNG PRO OPERATION')
print('  Legende: KEEP=behalten  SAMPLE=reduzieren  WATCH=beobachten')
print('------------------------------------------------------------')
print(f\"  {'Empfehlung':<10} {'Service':<22} {'Operation':<38} {'Spans/s':>7} {'Fehler%':>8} {'p95ms':>7}\")
print('  ' + '-'*96)

keep_count   = 0
sample_count = 0
watch_count  = 0

for r in volume:
    svc  = r['labels'].get('service_name', '?')
    span = r['labels'].get('span_name', '?')
    key  = f'{svc}/{span}'
    val  = r['value']
    err  = errors.get(key, 0.0)
    lat  = slow.get(key, 0.0)

    if err > 5 or lat > 1000:
        tag = '🔴 KEEP  '
        keep_count += 1
    elif err > 0 or lat > 500:
        tag = '🟡 WATCH '
        watch_count += 1
    else:
        tag = '🟢 SAMPLE'
        sample_count += 1

    err_str = f'{err:.1f}%' if err > 0 else '  0.0%'
    lat_str = f'{lat:.0f}' if lat > 0 else '    -'
    print(f\"  {tag}  {svc:<22} {span:<38} {val:>7.2f} {err_str:>8} {lat_str:>7}\")

print()
print(f'  Zusammenfassung: {keep_count}x KEEP  |  {watch_count}x WATCH  |  {sample_count}x SAMPLE')

# Fehler-Hotspots separat
hot = [(f\"{r['labels'].get('service_name','?')}/{r['labels'].get('span_name','?')}\", r['value'])
       for r in data.get('errors', []) if r['value'] > 5]
if hot:
    print()
    print('------------------------------------------------------------')
    print('  FEHLER-HOTSPOTS (> 5%) — immer KEEP')
    print('------------------------------------------------------------')
    for key, val in sorted(hot, key=lambda x: -x[1]):
        print(f\"  {val:>6.1f}%  {key}\")

# Slow-Hotspots separat
slow_hot = [(f\"{r['labels'].get('service_name','?')}/{r['labels'].get('span_name','?')}\", r['value'])
            for r in data.get('slow', []) if r['value'] > 1000]
if slow_hot:
    print()
    print('------------------------------------------------------------')
    print('  SLOW TRACES (p95 > 1000ms) — immer KEEP')
    print('------------------------------------------------------------')
    for key, val in sorted(slow_hot, key=lambda x: -x[1]):
        print(f\"  {val:>7.0f}ms  {key}\")

print()
print('------------------------------------------------------------')
print('  EMPFOHLENE TAIL-SAMPLING-KONFIGURATION')
print('------------------------------------------------------------')
print('''
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
''')
print('  ⚠️  Human Review erforderlich vor jeder Änderung am Collector.')
print()
"
