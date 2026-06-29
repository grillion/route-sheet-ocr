<#
.SYNOPSIS
  Diagnostic: dump the UI Automation tree of the foreground window.

.DESCRIPTION
  Step 1 of the desktop tool. Run this, switch to the ERA Ignite / eraccess
  screen you want to read, and it captures that window's full UI Automation
  tree to a text file on your Desktop. The dump shows, for every element:
  its ControlType, Name, AutomationId, ClassName, any readable Value/Text,
  and its on-screen rectangle.

  We use this to find out (a) whether the field data is reachable via UI
  Automation at all, and (b) the exact identifiers to target when building
  the real extractor. Send me the resulting .txt file.

.PARAMETER Delay
  Seconds to wait before capturing, so you can focus the target window.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Inspect-UIA.ps1
#>
param(
  [int]$Delay = 4,
  [int]$MaxDepth = 50,
  [int]$MaxElements = 8000,
  [string]$OutFile
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Fg {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
}
"@

if (-not $OutFile) {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutFile = Join-Path $desktop "uia-dump-$stamp.txt"
}

Write-Host ""
Write-Host "Switch to the ERA Ignite / eraccess window you want to read."
Write-Host "Capturing the FOREGROUND window in $Delay seconds..." -ForegroundColor Cyan
for ($i = $Delay; $i -gt 0; $i--) { Write-Host "  $i..."; Start-Sleep -Seconds 1 }

$hwnd = [Fg]::GetForegroundWindow()
$titleSb = New-Object System.Text.StringBuilder 1024
[void][Fg]::GetWindowText($hwnd, $titleSb, $titleSb.Capacity)
$title = $titleSb.ToString()

try {
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
} catch {
  Write-Host "ERROR: could not attach UI Automation to that window: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
if ($null -eq $root) { Write-Host "ERROR: no UI Automation element for that window." -ForegroundColor Red; exit 1 }

$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$valuePattern = [System.Windows.Automation.ValuePattern]::Pattern
$textPattern  = [System.Windows.Automation.TextPattern]::Pattern

function Get-ElementText($el) {
  # Prefer ValuePattern (edit boxes, combos), then a short TextPattern grab.
  try {
    $p = $null
    if ($el.TryGetCurrentPattern($valuePattern, [ref]$p)) {
      $v = $p.Current.Value
      if ($v) { return $v }
    }
  } catch {}
  try {
    $tp = $null
    if ($el.TryGetCurrentPattern($textPattern, [ref]$tp)) {
      $t = $tp.DocumentRange.GetText(300)
      if ($t) { return $t }
    }
  } catch {}
  return ''
}

function Clean($s) {
  if (-not $s) { return '' }
  return ($s -replace '[\r\n\t]+', ' ').Trim()
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("UI Automation dump")
[void]$sb.AppendLine("Window title : $title")
[void]$sb.AppendLine("HWND         : $hwnd")
[void]$sb.AppendLine("Captured     : $(Get-Date -Format o)")
[void]$sb.AppendLine("Columns      : [depth] ControlType | Name | AutoId | Class | Value | Rect(x,y,w,h)")
[void]$sb.AppendLine(("-" * 80))

$count = 0
$withText = 0
$stack = New-Object System.Collections.Stack
$stack.Push([pscustomobject]@{ El = $root; Depth = 0 })

while ($stack.Count -gt 0 -and $count -lt $MaxElements) {
  $node = $stack.Pop()
  $el = $node.El
  $depth = $node.Depth
  $count++

  try {
    $ct = $el.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
    $name = Clean $el.Current.Name
    $autoId = Clean $el.Current.AutomationId
    $class = Clean $el.Current.ClassName
    $value = Clean (Get-ElementText $el)
    if ($value) { $withText++ }
    $r = $el.Current.BoundingRectangle
    $rect = "-"
    if ($r -and -not [double]::IsInfinity($r.X) -and $r.Width -ge 0) {
      $rect = "{0},{1},{2},{3}" -f [int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height
    }
    $indent = "  " * $depth
    $line = "{0}[{1}] {2} | Name='{3}' | AutoId='{4}' | Class='{5}' | Value='{6}' | Rect={7}" -f `
      $indent, $depth, $ct, $name, $autoId, $class, $value, $rect
    [void]$sb.AppendLine($line)
  } catch {
    [void]$sb.AppendLine(("  " * $depth) + "[$depth] <element read error: $($_.Exception.Message)>")
  }

  if ($depth -lt $MaxDepth) {
    try {
      $children = @()
      $child = $walker.GetFirstChild($el)
      while ($null -ne $child) { $children += $child; $child = $walker.GetNextSibling($child) }
      [array]::Reverse($children)  # push reversed so they pop in document order
      foreach ($c in $children) { $stack.Push([pscustomobject]@{ El = $c; Depth = $depth + 1 }) }
    } catch {}
  }
}

[void]$sb.AppendLine(("-" * 80))
[void]$sb.AppendLine("Elements dumped: $count   (with readable Value/Text: $withText)")
if ($count -ge $MaxElements) { [void]$sb.AppendLine("NOTE: hit MaxElements cap ($MaxElements) - tree may be truncated.") }

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Window  : $title"
Write-Host "Elements: $count  (with readable text: $withText)"
Write-Host "Saved to: $OutFile"
if ($withText -eq 0) {
  Write-Host ""
  Write-Host "No elements exposed readable text. This app's screen is likely a custom-drawn" -ForegroundColor Yellow
  Write-Host "surface (e.g. a terminal emulator) that UI Automation can't read - we'll" -ForegroundColor Yellow
  Write-Host "probably need the OCR fallback for this screen." -ForegroundColor Yellow
}
