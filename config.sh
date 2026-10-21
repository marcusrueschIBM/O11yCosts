#!/usr/bin/env bash
# =============================================================================
# config.sh — Collector-Sampling-Variante anzeigen und wechseln
#
#   ./config.sh list            verfuegbare Varianten
#   ./config.sh show            welche Variante ist aktiv?
#   ./config.sh use <name>      Variante aktivieren (danach ./stack.sh up)
#   ./config.sh use <name> --apply   aktivieren und Stack direkt neu erstellen
#
# Varianten: baseline | head-50 | head-10 | tail
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/collector-configs"
ACTIVE="$ROOT/opentelemetry-demo/src/otel-collector/otelcol-config.yml"
[[ -d "$ROOT/opentelemetry-demo" ]] || { echo "FEHLER: zuerst ./setup.sh ausfuehren."; exit 1; }

case "${1:-}" in
  list)
    for f in "$SRC"/*.yml; do basename "$f" .yml; done ;;
  show)
    found=""
    for f in "$SRC"/*.yml; do
      if cmp -s "$f" "$ACTIVE"; then found="$(basename "$f" .yml)"; fi
    done
    if [[ -n "$found" ]]; then echo "Aktive Variante: $found"
    else echo "Aktive Variante: eigene/geaenderte Konfiguration (entspricht keiner Variante)"; fi
    echo "Hinweis: gilt fuer die Datei auf der Platte. Wirksam ist sie erst nach ./stack.sh up." ;;
  use)
    name="${2:?Variante angeben: baseline | head-50 | head-10 | tail}"
    [[ -f "$SRC/$name.yml" ]] || { echo "FEHLER: unbekannte Variante '$name'"; exit 1; }
    cp "$SRC/$name.yml" "$ACTIVE"
    echo "Variante '$name' nach otelcol-config.yml kopiert."
    if [[ "${3:-}" == "--apply" ]]; then "$ROOT/stack.sh" up
    else echo "Jetzt: ./stack.sh up   (Collector uebernimmt die Datei nur bei force-recreate)"; fi ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
