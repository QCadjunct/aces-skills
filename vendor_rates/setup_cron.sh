#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# setup_cron.sh — Install midnight rate refresh cron on FreedomTower
# Run once: bash setup_cron.sh
# ═══════════════════════════════════════════════════════════════════════════════

SCRIPT="$HOME/projects/aces-skills/vendor_rates/refresh_rates.sh"
LOG="$HOME/.config/fabric/rate_refresh.log"
CRON_LINE="0 0 * * * $SCRIPT >> $LOG 2>&1"

# Add to crontab if not already present
( crontab -l 2>/dev/null | grep -v "refresh_rates.sh" ; echo "$CRON_LINE" ) | crontab -

echo "✓ Cron installed:"
crontab -l | grep refresh_rates
echo ""
echo "  Runs at: midnight daily"
echo "  Script : $SCRIPT"
echo "  Log    : $LOG"
echo ""
echo "  Test immediately (without waiting for midnight):"
echo "  bash $SCRIPT"
