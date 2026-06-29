# Desktop (Windows) version

Reads field values directly off the **ERA Ignite / eraccess** screen and
opens a pre-filled Google Form — no phone, no photos. Triggered by a global
hotkey. No-install: uses Windows' built-in PowerShell + .NET UI Automation
(`System.Windows.Automation`). OCR is only a fallback if a given screen can't
be read via the API.

## Why UI Automation instead of OCR

Reading the actual control values via the Windows API gives exact text with
no recognition errors and no calibration. The catch: it only works if the app
exposes its content to UI Automation. Modern WPF/WinForms/WebView screens
usually do; an old terminal-emulator screen may not. So we check first.

## Status: working on ERA-IGNITE

Confirmed that ERA-IGNITE's **RO Billing** screen is fully readable via UI
Automation (the data lives in each element's `Name` property). The tool reads
these fields directly, with no OCR:

- **Customer name** — from the `(custno) NAME` element
- **RO #** — from the window title (`... RO Billing <ro> ...`)
- **Advisor #** — from the `(advisorno) NAME` element whose number is a known
  advisor ID
- **Tag #** — from the value next to the `Tag#` label (often blank)

Not auto-filled (you pick these in the browser before submitting):
**Customer Status**, **Express/Main Shop** (not on this screen), and
**Type of Work** (it's inside ERA's grid controls, which UI Automation
doesn't expose).

## Files

- `Inspect-UIA.ps1` — diagnostic tree dumper (used to discover the layout;
  rerun it if a *different* ERA screen needs reading).
- `Probe-Grid.ps1` — deep probe of ERA's `PowerGridWnd` controls (the Opcode
  grid that holds Type of Work) to see if their cells are reachable via UIA.
- `Extract-ERA.ps1` — reads the focused ERA screen and opens the pre-filled
  form. Run with `-Delay 4` to test by hand, `-DryRun` to print without
  opening the browser.
- `Start-EraHotkey.ps1` — registers the global hotkey that runs the extractor.

## Type of Work — grid probe

The Opcode grid (e.g. `24NIZSEATBLT`, `16NIZSTEERSTIFF`) is the source for
Type of Work, but it's a custom-drawn ERA `PowerGridWnd` that came back empty
in the plain UIA dump. Before falling back to OCR, `Probe-Grid.ps1` tries
harder to read it three ways per grid: **GridPattern**, **TablePattern**, and
a full **RawView** subtree walk (RawView exposes elements the ControlView dump
can't see).

Run it with the RO Billing screen focused (Opcode grid visible):

```powershell
powershell -ExecutionPolicy Bypass -File .\Probe-Grid.ps1
```

Focus ERA during the 4-second countdown. It saves
`uia-gridprobe-<timestamp>.txt` to your Desktop and prints a verdict:

- **`readable: N` with N > 0** — a grid exposes its cells; Type of Work can be
  read exactly with **no OCR**. Send the `.txt` to wire it up.
- **`No grid exposed its cells`** — the grid is opaque; fall back to OCRing
  just the grid's rectangle (UIA can still locate the rectangle) using
  Windows' built-in OCR engine.

Options: `-Delay <seconds>` (default 4), `-OutFile <path>`,
`-MaxElements <n>` (default 20000).

## Daily use

1. Start the hotkey listener once (leave it minimized):
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Start-EraHotkey.ps1
   ```
   Default hotkey is **Ctrl+Alt+R** (change with `-Modifiers`/`-Key`).
2. In ERA-IGNITE, open the RO Billing screen for the customer.
3. Press the hotkey. The default browser opens the Google Form pre-filled
   with customer/RO/advisor/tag. Set Status, Shop, and Type of Work, then
   Submit.

## Testing without the hotkey

```powershell
# Focus ERA during the countdown; prints values + URL, doesn't open browser
powershell -ExecutionPolicy Bypass -File .\Extract-ERA.ps1 -Delay 4 -DryRun
```

## Auto-start the hotkey at login (optional)

Put a shortcut to this in your Startup folder (`shell:startup`):

```
powershell.exe -WindowStyle Minimized -ExecutionPolicy Bypass -File "C:\Users\frabklon\route-sheet-ocr\windows\Start-EraHotkey.ps1"
```

## Re-inspecting a new screen

If you later want to read fields that live on a different ERA screen, run
`Inspect-UIA.ps1`, focus that screen during the countdown, and send the
resulting Desktop `.txt`. The "with readable Name/Value: N" line tells you if
that screen is reachable (N healthy) or opaque/OCR-only (N ~ 0).

Options: `Inspect-UIA.ps1 -Delay <seconds>` (default 4), `-OutFile <path>`.
