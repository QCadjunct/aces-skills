#!/usr/bin/env bash
# demo_04_marimo.sh — Marimo monitor launcher (WSL)
# Mind Over Metadata LLC © 2026 — Peter Heller
# ─────────────────────────────────────────────────────────────────────────────
REPO="/mnt/e/WSLData/Projects/aces-skills"
MONITOR="/mnt/e/WSLData/Projects/aces-repo/ui/aces_monitor.py"
PORT=2718

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║  ACES POC — Section 4: Marimo Monitor                  ║"
echo "  ║  Mind Over Metadata LLC © 2026 — Peter Heller          ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  URL: http://127.0.0.1:${PORT}"
echo "  Navigate to: D4 MDLC tab → live cost_audit.log data"
echo ""
echo "  Press Enter to launch..."
read -r

cd "$REPO"
PYTHONPATH="/mnt/e/WSLData/Projects/aces-repo:/mnt/e/WSLData/Projects/aces-skills" \
    marimo run "$MONITOR" --port $PORT
