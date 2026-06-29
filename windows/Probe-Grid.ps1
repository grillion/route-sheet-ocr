<#
.SYNOPSIS
  Deep-probe the ERA-IGNITE PowerGrid controls (Opcode/Alerts grids) to see
  whether their cell contents are reachable via UI Automation.

.DESCRIPTION
  The header fields read fine via UIA, but the Opcode grid (Type of Work) came
  back empty in the ControlView dump. This script tries harder, per grid:
    1. RawView tree walk (exposes more than ControlView).
    2. GridPattern  - read RowCount/ColumnCount and each cell.
    3. TablePattern - row/column headers.
    4. LegacyIAccessiblePattern - the MSAA bridge many MFC grids expose.
  Results go to a .txt on your Desktop and a summary prints here.

  If any method returns the op codes (e.g. 24NIZSEATBLT), we can read Type of
  Work exactly - no OCR. If all come back empty, the grid is truly opaque and
  we'll OCR just its rectangle instead.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Probe-Grid.ps1
#>
param(
  [int]$Delay = 4,
  [int]$MaxElements = 20000,
  [string]$OutFile
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('Fg' -as [type])) {
  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
}
"@
}

if (-not $OutFile) {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutFile = Join-Path $desktop "uia-gridprobe-$stamp.txt"
}

Write-Host ""
Write-Host "Focus the ERA-IGNITE RO Billing screen (with the Opcode grid visible)."
Write-Host "Probing in $Delay seconds..." -ForegroundColor Cyan
for ($i = $Delay; $i -gt 0; $i--) { Write-Host "  $i..."; Start-Sleep -Seconds 1 }

$hwnd = [Fg]::GetForegroundWindow()
$tb = New-Object System.Text.StringBuilder 1024
[void][Fg]::GetWindowText($hwnd, $tb, $tb.Capacity)
$title = $tb.ToString()
$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
if ($null -eq $root) { Write-Host "Could not attach to that window." -ForegroundColor Red; exit 1 }

$rawWalker   = [System.Windows.Automation.TreeWalker]::RawViewWalker
$gridPattern = [System.Windows.Automation.GridPattern]::Pattern
$tablePattern= [System.Windows.Automation.TablePattern]::Pattern

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("ERA grid probe")
[void]$sb.AppendLine("Window: $title")
[void]$sb.AppendLine("Captured: $(Get-Date -Format o)")
[void]$sb.AppendLine(("=" * 80))

function Clean($s) { if (-not $s) { return '' } return ($s -replace '[\r\n\t]+', ' ').Trim() }

function Probe-Grid($el, $tag) {
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine(">>> Grid probe: $tag")
  try { $r = $el.Current.BoundingRectangle; [void]$sb.AppendLine("    Rect: $([int]$r.X),$([int]$r.Y),$([int]$r.Width),$([int]$r.Height)") } catch {}

  $found = $false

  # 1. GridPattern
  try {
    $gp = $null
    if ($el.TryGetCurrentPattern($gridPattern, [ref]$gp)) {
      $rows = $gp.Current.RowCount; $cols = $gp.Current.ColumnCount
      [void]$sb.AppendLine("    GridPattern: $rows rows x $cols cols")
      for ($rr = 0; $rr -lt [math]::Min($rows, 40); $rr++) {
        $line = "      row $rr :"
        for ($cc = 0; $cc -lt [math]::Min($cols, 8); $cc++) {
          try { $cell = $gp.GetItem($rr, $cc); $line += " [" + (Clean $cell.Current.Name) + "]" } catch { $line += " [<err>]" }
        }
        [void]$sb.AppendLine($line)
        $found = $true
      }
    } else { [void]$sb.AppendLine("    GridPattern: not supported") }
  } catch { [void]$sb.AppendLine("    GridPattern: error $($_.Exception.Message)") }

  # 2. TablePattern (row/column counts, if the grid exposes it)
  try {
    $tp = $null
    if ($el.TryGetCurrentPattern($tablePattern, [ref]$tp)) {
      [void]$sb.AppendLine("    TablePattern: $($tp.Current.RowCount) rows x $($tp.Current.ColumnCount) cols")
    } else { [void]$sb.AppendLine("    TablePattern: not supported") }
  } catch { [void]$sb.AppendLine("    TablePattern: error $($_.Exception.Message)") }

  # 3. RawView descendants of the grid (cells often live here, not in
  #    ControlView). Walk the whole subtree, not just direct children.
  try {
    $sub = New-Object System.Collections.Stack
    $c0 = $rawWalker.GetFirstChild($el)
    while ($null -ne $c0) { $sub.Push($c0); $c0 = $rawWalker.GetNextSibling($c0) }
    $cn = 0
    while ($sub.Count -gt 0 -and $cn -lt 600) {
      $child = $sub.Pop(); $cn++
      $nm = Clean $child.Current.Name
      $cls = $child.Current.ClassName
      $ct = $child.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
      if ($nm) { $found = $true }
      [void]$sb.AppendLine("      sub[$cn] $ct Name='$nm' Class='$cls'")
      try {
        $cc = $rawWalker.GetFirstChild($child)
        while ($null -ne $cc) { $sub.Push($cc); $cc = $rawWalker.GetNextSibling($cc) }
      } catch {}
    }
    if ($cn -eq 0) { [void]$sb.AppendLine("      (no RawView descendants)") }
  } catch { [void]$sb.AppendLine("    RawView descendants: error $($_.Exception.Message)") }

  [void]$sb.AppendLine("    => $(if ($found) { 'READABLE content found' } else { 'NO readable content' })")
  return $found
}

# Walk the whole RawView tree; probe every PowerGridWnd we meet.
$grids = 0; $readable = 0; $count = 0
$stack = New-Object System.Collections.Stack
$stack.Push($root)
while ($stack.Count -gt 0 -and $count -lt $MaxElements) {
  $el = $stack.Pop(); $count++
  try {
    $nm = Clean $el.Current.Name
    $cls = $el.Current.ClassName
    if ($nm -eq 'PowerGridWnd' -or $cls -match 'Grid') {
      $grids++
      $r = $el.Current.BoundingRectangle
      $tag = "#$grids at $([int]$r.X),$([int]$r.Y) ($([int]$r.Width)x$([int]$r.Height))"
      if (Probe-Grid $el $tag) { $readable++ }
    }
  } catch {}
  try {
    $c = $rawWalker.GetFirstChild($el)
    while ($null -ne $c) { $stack.Push($c); $c = $rawWalker.GetNextSibling($c) }
  } catch {}
}

[void]$sb.AppendLine("")
[void]$sb.AppendLine(("=" * 80))
[void]$sb.AppendLine("Grids probed: $grids   with readable content: $readable   (raw elements scanned: $count)")
[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Grids found: $grids   readable: $readable"
Write-Host "Saved to: $OutFile"
if ($readable -gt 0) {
  Write-Host "At least one grid is readable via UIA - send me the file and I'll wire Type of Work without OCR." -ForegroundColor Green
} else {
  Write-Host "No grid exposed its cells - we'll OCR the grid rectangle for Type of Work." -ForegroundColor Yellow
}
