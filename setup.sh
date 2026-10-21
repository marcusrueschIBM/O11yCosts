#!/usr/bin/env bash
# =============================================================================
# setup.sh — richtet das Lab ein (Linux, macOS, Windows via WSL2)
#
#   1. klont das Upstream-Demo nach ./opentelemetry-demo und pinnt den Commit
#   2. legt die Lab-Dateien aus ./overlay darueber
#   3. legt die Collector-Ausgangskonfiguration (Baseline) ab
#
# Sicher mehrfach ausfuehrbar. Mit --reset-config wird die aktive Collector-
# Konfiguration wieder auf Baseline gesetzt.
# =============================================================================
set -euo pipefail

UPSTREAM_URL="https://github.com/open-telemetry/opentelemetry-demo.git"
UPSTREAM_COMMIT="fdbd62ca1ccd98d1752724315994bd2bf67a68db"   # Demo 3.1.0-48-gfdbd62ca

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEMO="$ROOT/opentelemetry-demo"
RESET_CONFIG=0
[[ "${1:-}" == "--reset-config" ]] && RESET_CONFIG=1

command -v git >/dev/null 2>&1 || { echo "FEHLER: git nicht gefunden."; exit 1; }
command -v python3 >/dev/null 2>&1 || echo "WARNUNG: python3 fehlt — measure.sh und mcp_advisor.sh benoetigen es."

FRESH=0
if [[ ! -d "$DEMO/.git" ]]; then
  echo "==> Klone Upstream nach $DEMO"
  # autocrlf=false: sonst entstehen unter Windows CRLF-Dateien, die in Containern brechen
  git -c core.autocrlf=false clone "$UPSTREAM_URL" "$DEMO"
  FRESH=1
fi

echo "==> Pinne Upstream auf $UPSTREAM_COMMIT"
if ! git -C "$DEMO" cat-file -e "$UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
  git -C "$DEMO" fetch origin
fi
git -C "$DEMO" checkout --quiet -B podman-ai-sampling-lab "$UPSTREAM_COMMIT"

echo "==> Kopiere Lab-Dateien (overlay/) nach opentelemetry-demo/"
cp -R "$ROOT/overlay/." "$DEMO/"

CFG="$DEMO/src/otel-collector"
cp "$ROOT/collector-configs/baseline.yml" "$CFG/otelcol-config.original.yml"
if [[ $FRESH -eq 1 || $RESET_CONFIG -eq 1 ]]; then
  cp "$ROOT/collector-configs/baseline.yml" "$CFG/otelcol-config.yml"
  echo "==> Aktive Collector-Konfiguration: baseline"
else
  echo "==> Aktive Collector-Konfiguration unveraendert (mit --reset-config zuruecksetzen)"
fi

[[ -f "$DEMO/.env.override" ]] || touch "$DEMO/.env.override"

echo
echo "Fertig. Naechste Schritte:"
echo "  ./stack.sh up        # Stack starten (erkennt docker oder podman)"
echo "  ./stack.sh status    # Container und URLs pruefen"
echo "  ./config.sh list     # Collector-Varianten anzeigen"
