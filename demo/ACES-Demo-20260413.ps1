# ACES-Demo-20260325-v2.ps1
# ACES POC Demo - Monday launcher (HTML deck only)
# Mind Over Metadata LLC 2026 - Peter Heller
# Marimo: run bash demo/demo_04_marimo.sh in WSL terminal
# Run from: E:\Projects\aces-skills\demo\

Write-Host ""
Write-Host "  ACES POC Demo - Monday Launcher" -ForegroundColor Cyan
Write-Host "  Mind Over Metadata LLC 2026 - Peter Heller" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [1] Opening HTML deck in browser..." -ForegroundColor Yellow
Start-Process "E:\Projects\aces-skills\demo\ACES-Demo-20260413.html"
Write-Host "      Browser opening - navigate to Cheat Sheet tab" -ForegroundColor Green
Write-Host ""
Write-Host "  [2] For Marimo monitor - open WSL terminal and run:" -ForegroundColor Yellow
Write-Host "      cd /mnt/e/Projects/aces-skills" -ForegroundColor Cyan
Write-Host "      bash demo/demo_04_marimo.sh" -ForegroundColor Cyan
Write-Host "      URL: http://localhost:2718 - D4 MDLC tab" -ForegroundColor Green
Write-Host ""
