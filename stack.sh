#!/usr/bin/env bash
# =============================================================================
# stack.sh — Stack starten/stoppen/pruefen (docker oder podman, automatisch)
#
#   ./stack.sh up [--no-mcp]   Stack erstellen und starten (force-recreate)
#   ./stack.sh down            Stack stoppen und Container entfernen
#   ./stack.sh status          Container und URLs pruefen
#   ./stack.sh logs <dienst>   Logs eines Dienstes
#   ./stack.sh build-mcp       MCP-Image nach Code-Aenderung neu bauen
#   ./stack.sh check           Collector-Fehler anzeigen (ohne bekanntes Kafka-Rauschen)
#   ./stack.sh engine          erkannte Engine anzeigen
#
# Engine erzwingen:  CONTAINER_ENGINE=podman ./stack.sh up
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEMO="$ROOT/opentelemetry-demo"
[[ -d "$DEMO" ]] || { echo "FEHLER: $DEMO fehlt. Zuerst ./setup.sh ausfuehren."; exit 1; }

# --- Engine erkennen ---------------------------------------------------------
if [[ -n "${CONTAINER_ENGINE:-}" ]]; then ENGINE="$CONTAINER_ENGINE"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then ENGINE=docker
elif command -v podman >/dev/null 2>&1; then ENGINE=podman
else echo "FEHLER: weder docker noch podman gefunden."; exit 1; fi

compose() {
  local files=(-f compose.yaml -f compose.observability.yaml -f compose.extras.yaml -f compose.lab.yaml)
  [[ "$WITH_MCP" == 1 ]] && files+=(-f compose.mcp.yaml)
  ( cd "$DEMO" && "$ENGINE" compose --project-name otel-demo \
      --env-file .env --env-file .env.override "${files[@]}" "$@" )
}

CMD="${1:-}"; shift || true
WITH_MCP=1
[[ "${1:-}" == "--no-mcp" ]] && { WITH_MCP=0; shift; }

case "$CMD" in
  engine) echo "$ENGINE" ;;
  up) compose up --force-recreate --remove-orphans --detach ;;
  down) compose down ;;
  check)
    out="$("$ENGINE" logs otel-collector 2>&1 | grep -iE "error|invalid|failed|unknown" | grep -v kafka | cut -c1-220 | tail -20 || true)"
    if [[ -z "$out" ]]; then echo "Keine Collector-Fehler (Kafka-Meldungen ausgeblendet)."; else echo "$out"; fi ;;
  build-mcp) compose build mcp-sampling-advisor ;;
  logs) compose logs --tail 100 "${1:?Dienstname angeben, z.B. otel-collector}" ;;
  status)
    "$ENGINE" ps --format "table {{.Names}}\t{{.Status}}"
    echo
    for u in http://localhost:8080/ http://localhost:8080/jaeger/ui/ http://localhost:8080/grafana/ \
             http://localhost:8080/loadgen/ http://localhost:8080/feature http://localhost:9090/-/healthy; do
      printf "%-40s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 10 "$u" || true)"
    done ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
