# demo_04_monitor.ps1
# ACMS POC Demo — Section 4: Marimo Monitor — D4 MDLC Tab
# Mind Over Metadata LLC © 2026 — Peter Heller
# Run from: Z:\VSCODE Projects\PythonProjects\acms-repo
# ─────────────────────────────────────────────────────────────────────────────

param([int]$Port = 2718)

function Write-Banner {
    param([string]$Title)
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║  $($Title.PadRight(54))║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  --- $Title ---" -ForegroundColor Yellow
    Write-Host ""
}

Write-Banner "ACMS POC - Section 4: Marimo Monitor"

Write-Section "4.1 - ACMS Monitor Architecture"
Write-Host "  The ACMS Monitor is the DECforms equivalent in the ACMS POC."
Write-Host "  Built with Marimo — a reactive Python notebook framework."
Write-Host ""
Write-Host "  7 Tabs:"
Write-Host "    1. Audit Trail    - session + step entries + aggregations" -ForegroundColor White
Write-Host "    2. Registry       - skill/task registry analytics" -ForegroundColor White
Write-Host "    3. Pipeline       - per-session Mermaid execution graph" -ForegroundColor White
Write-Host "    4. Cost           - aggregate KPIs by vendor/agent/session" -ForegroundColor White
Write-Host "    5. Cost Detail    - row-level drill-down + CSV export" -ForegroundColor White
Write-Host "    6. D4 MDLC        - LIVE data from cost_audit.log (ADR-009)" -ForegroundColor Green
Write-Host "    7. About          - documentation, rate card, roadmap" -ForegroundColor White
Write-Host ""
Write-Host "  Tabs 1-5, 7 run on deterministic mock data (seed-controlled)."
Write-Host "  Tab 6 (D4 MDLC) reads LIVE data from cost_audit.log via WSL2 UNC path."
Write-Host ""

Write-Section "4.2 - D4 MDLC Tab: What it Shows"
Write-Host "  Reads: \\wsl`$\Ubuntu\home\pheller\.config\fabric\cost_audit.log"
Write-Host ""
Write-Host "  Accordions:"
Write-Host "    KPIs + Filters           - total cost, tokens, run IDs, skills"
Write-Host "    Cost by Artifact Tier    - tier_0 through tier_4 chain"
Write-Host "    Cost by Artifact         - Three-File Standard breakdown"
Write-Host "    Cost by Vendor/Model     - ollama/gemma3:12b breakdown"
Write-Host "    Cost by Skill (FQSN)     - per-skill aggregation"
Write-Host "    Bloat Detection          - Boris Cherney 800-token threshold"
Write-Host "    TOON Efficiency          - yaml vs toon reduction %"
Write-Host ""

Write-Section "4.3 - Launching Monitor"
Write-Host "  URL: http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host "  Navigate to the D4 MDLC tab to see live cost_audit.log data."
Write-Host ""
Write-Host "  Press Enter to launch..." -NoNewline
$null = Read-Host

$env:PYTHONPATH = "Z:\VSCODE Projects\PythonProjects\acms-repo"
$marimo = "Z:\VSCODE Projects\PythonProjects\acms-repo\.venv\Scripts\marimo.exe"
$monitor = "Z:\VSCODE Projects\PythonProjects\acms-repo\ui\acms_monitor.py"

Write-Host ""
Write-Host "  Launching: marimo run ui\acms_monitor.py --port $Port" -ForegroundColor Cyan
Write-Host "  URL: http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host ""
Write-Host "  Navigate to the D4 MDLC tab and expand:" -ForegroundColor Yellow
Write-Host "    - KPIs + Filters"
Write-Host "    - Cost by Artifact Tier"
Write-Host "    - Bloat Detection"
Write-Host "    - TOON Efficiency"
Write-Host ""
Write-Host "  Close the browser and press Ctrl+C here when done." -ForegroundColor Yellow
Write-Host ""

& $marimo run $monitor --port $Port
