<#
.SYNOPSIS
  Register a global hotkey (default Ctrl+Alt+R) that reads the focused
  ERA-IGNITE RO Billing screen and opens the pre-filled Google Form.

.DESCRIPTION
  Leave this running in a PowerShell window (minimize it). Whenever an
  ERA-IGNITE RO screen is focused, press the hotkey to extract the fields and
  open the pre-filled form for review + submit. No installs - uses the
  built-in .NET hotkey APIs.

.PARAMETER Modifiers
  Comma list of: Ctrl, Alt, Shift, Win. Default "Ctrl,Alt".

.PARAMETER Key
  Single key, e.g. R. Default "R".

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\Start-EraHotkey.ps1
  powershell -ExecutionPolicy Bypass -File .\Start-EraHotkey.ps1 -Modifiers "Ctrl,Shift" -Key G
#>
param(
  [string]$Modifiers = "Ctrl,Alt",
  [string]$Key = "R"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('HotKeyForm' -as [type])) {
  Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing @"
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public class HotKeyForm : Form {
  [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
  [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
  const int WM_HOTKEY = 0x0312;
  const int HOTKEY_ID = 0xB001;
  public event Action HotKeyPressed;
  public HotKeyForm(uint mod, uint vk) {
    var h = this.Handle;            // force handle creation
    RegisterHotKey(h, HOTKEY_ID, mod, vk);
  }
  protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); } // stay hidden
  protected override void WndProc(ref Message m) {
    if (m.Msg == WM_HOTKEY && (int)m.WParam == HOTKEY_ID && HotKeyPressed != null) HotKeyPressed();
    base.WndProc(ref m);
  }
  protected override void OnHandleDestroyed(EventArgs e) { UnregisterHotKey(this.Handle, HOTKEY_ID); base.OnHandleDestroyed(e); }
}
"@
}

# Modifier flags for RegisterHotKey.
$MOD = 0
foreach ($m in ($Modifiers -split ',')) {
  switch ($m.Trim().ToLower()) {
    'alt'   { $MOD = $MOD -bor 0x1 }
    'ctrl'  { $MOD = $MOD -bor 0x2 }
    'shift' { $MOD = $MOD -bor 0x4 }
    'win'   { $MOD = $MOD -bor 0x8 }
  }
}
# Virtual key code from the letter/key name.
$vk = [int][System.Windows.Forms.Keys]::$Key
if (-not $vk) { Write-Host "Unknown key: $Key" -ForegroundColor Red; exit 1 }

$extractScript = Join-Path $PSScriptRoot "Extract-ERA.ps1"
if (-not (Test-Path $extractScript)) { Write-Host "Extract-ERA.ps1 not found next to this script." -ForegroundColor Red; exit 1 }

$form = New-Object HotKeyForm ([uint32]$MOD), ([uint32]$vk)
$form.add_HotKeyPressed({
  try { & $extractScript } catch { Write-Host "Extraction error: $($_.Exception.Message)" -ForegroundColor Red }
})

Write-Host ""
Write-Host "ERA route-sheet hotkey is active: $Modifiers + $Key" -ForegroundColor Green
Write-Host "Focus an ERA-IGNITE RO Billing screen and press the hotkey to fill the form."
Write-Host "Keep this window open (you can minimize it). Press Ctrl+C here to stop."
Write-Host ""

try {
  [System.Windows.Forms.Application]::Run()
} finally {
  $form.Dispose()
}
