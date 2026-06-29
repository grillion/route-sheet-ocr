<#
.SYNOPSIS
  Read the current ERA-IGNITE RO Billing screen via UI Automation and open a
  pre-filled Google Form (Route Sheet Entry Form) in the default browser.

.DESCRIPTION
  Attaches to the foreground window (assumed to be ERA-IGNITE when triggered
  by the hotkey), walks its UI Automation tree, and pulls the fields the data
  exposes: customer name, RO #, advisor #, tag #. Builds the Google Form
  pre-filled URL and opens it for review + manual submit. Customer Status,
  Express/Main Shop and Type of Work are not on this screen, so they're left
  for you to pick in the browser.

.PARAMETER Delay
  Seconds to wait before reading (for standalone testing - focus ERA first).
  When run from the hotkey this is 0.

.PARAMETER DryRun
  Print the extracted values and the URL but do not open the browser.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Extract-ERA.ps1 -Delay 4 -DryRun
#>
param(
  [int]$Delay = 0,
  [switch]$DryRun
)

# --- Google Form config (mirrors regions.js / the form's entry IDs) --------
$FORM_BASE = "https://docs.google.com/forms/d/e/1FAIpQLScLJnRO7EemJcZTy9gP_iYE9FvcRBelDArE9dHf0evu6ZKARQ/viewform"
$ENTRY = @{
  name    = "entry.1742178377"
  ro      = "entry.438656768"
  advisor = "entry.1130646650"
  tag     = "entry.22122272"
}
$ADVISORS = @("142399", "17824", "159720", "160629", "159462")

# --- Win32 / UIA setup (guarded so repeated hotkey loads don't re-add) ------
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

function Get-Leaves($root) {
  # Flatten the UIA tree into objects carrying Name + position.
  $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $leaves = New-Object System.Collections.Generic.List[object]
  $stack = New-Object System.Collections.Stack
  $stack.Push($root)
  $n = 0
  while ($stack.Count -gt 0 -and $n -lt 8000) {
    $el = $stack.Pop()
    $n++
    try {
      $name = ($el.Current.Name -replace '[\r\n\t]+', ' ').Trim()
      $r = $el.Current.BoundingRectangle
      $x = if ($r -and -not [double]::IsInfinity($r.X)) { [int]$r.X } else { -1 }
      $y = if ($r -and -not [double]::IsInfinity($r.Y)) { [int]$r.Y } else { -1 }
      $leaves.Add([pscustomobject]@{
        Name  = $name
        Class = $el.Current.ClassName
        X     = $x
        Y     = $y
      })
    } catch {}
    try {
      $c = $walker.GetFirstChild($el)
      while ($null -ne $c) { $stack.Push($c); $c = $walker.GetNextSibling($c) }
    } catch {}
  }
  return $leaves
}

function Value-RightOf($leaves, $labelName) {
  $label = $leaves | Where-Object { $_.Name -eq $labelName -and $_.Y -ge 0 } | Select-Object -First 1
  if (-not $label) { return "" }
  $cand = $leaves |
    Where-Object { $_.X -gt ($label.X + 2) -and [math]::Abs($_.Y - $label.Y) -le 6 -and $_.Name -ne '' -and $_.Name -ne $labelName } |
    Sort-Object X | Select-Object -First 1
  if ($cand) { return $cand.Name } else { return "" }
}

function Invoke-EraExtraction {
  $hwnd = [Fg]::GetForegroundWindow()
  $sb = New-Object System.Text.StringBuilder 1024
  [void][Fg]::GetWindowText($hwnd, $sb, $sb.Capacity)
  $title = $sb.ToString()

  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  if ($null -eq $root) { Write-Host "Could not attach to the foreground window." -ForegroundColor Red; return }

  $leaves = Get-Leaves $root

  # RO #: primary from the window title ("... RO Billing 934986 ..."),
  # fallback to the value right of the "RO#" label in the header strip.
  $ro = ""
  if ($title -match 'RO\s*Billing\s+(\d+)') { $ro = $Matches[1] }
  if (-not $ro) { $ro = (Value-RightOf $leaves 'RO#') -replace '\D', '' }

  # Tag #: value right of "Tag#" (often blank).
  $tag = (Value-RightOf $leaves 'Tag#') -replace '\D', ''

  # Customer name & advisor #: both render as "(<number>) <NAME>". The one
  # whose number is a known advisor ID is the advisor; the other is the
  # customer (we keep just the name, dropping the customer-number prefix).
  $custName = ""
  $advisor = ""
  foreach ($leaf in $leaves) {
    if ($leaf.Name -match '^\((\d+)\)\s+(.+)$') {
      $num = $Matches[1]; $who = $Matches[2].Trim()
      if ($ADVISORS -contains $num) {
        if (-not $advisor) { $advisor = $num }
      } elseif (-not $custName) {
        $custName = $who
      }
    }
  }

  # --- Build the pre-filled URL ---------------------------------------------
  $pairs = @("usp=pp_url")
  if ($custName) { $pairs += ($ENTRY.name + "=" + [uri]::EscapeDataString($custName)) }
  if ($ro)       { $pairs += ($ENTRY.ro + "=" + [uri]::EscapeDataString($ro)) }
  if ($advisor)  { $pairs += ($ENTRY.advisor + "=" + [uri]::EscapeDataString($advisor)) }
  if ($tag)      { $pairs += ($ENTRY.tag + "=" + [uri]::EscapeDataString($tag)) }
  $url = $FORM_BASE + "?" + ($pairs -join "&")

  Write-Host ""
  Write-Host "Extracted from: $title" -ForegroundColor Cyan
  Write-Host ("  Customer : {0}" -f ($(if ($custName) { $custName } else { '(not found)' })))
  Write-Host ("  RO #     : {0}" -f ($(if ($ro) { $ro } else { '(not found)' })))
  Write-Host ("  Advisor #: {0}" -f ($(if ($advisor) { $advisor } else { '(not found)' })))
  Write-Host ("  Tag #    : {0}" -f ($(if ($tag) { $tag } else { '(blank)' })))

  if (-not ($custName -or $ro)) {
    Write-Host "Nothing extracted - is an ERA-IGNITE RO Billing screen focused?" -ForegroundColor Yellow
    return
  }

  if ($DryRun) {
    Write-Host ""
    Write-Host "URL (dry run, not opened):" -ForegroundColor Cyan
    Write-Host $url
  } else {
    Start-Process $url
    Write-Host ""
    Write-Host "Opened pre-filled form. Review, set Status/Shop/Type of Work, then Submit." -ForegroundColor Green
  }
}

if ($Delay -gt 0) {
  Write-Host "Focus the ERA-IGNITE window. Reading in $Delay seconds..." -ForegroundColor Cyan
  for ($i = $Delay; $i -gt 0; $i--) { Write-Host "  $i..."; Start-Sleep -Seconds 1 }
}
Invoke-EraExtraction
