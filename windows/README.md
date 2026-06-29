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

## Phased plan

1. **Inspect (you are here).** Run `Inspect-UIA.ps1`, focus the ERA screen,
   and it dumps that window's UI Automation tree to a `.txt` on your Desktop.
   This tells us whether the data is reachable and the exact element
   identifiers to target.
2. **Extract.** Using the dump, build a script that pulls the specific fields
   (customer name, RO #, advisor, tag, job/op lines) by AutomationId/Name.
3. **Prefill + hotkey.** Map the values to the Google Form pre-filled URL,
   open it in the default browser, and bind the whole thing to a global
   hotkey (no-install, via a registered hotkey or a shortcut key).

## Step 1 — run the inspector

In PowerShell, from this folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Inspect-UIA.ps1
```

You get a 4-second countdown — switch to the ERA Ignite / eraccess window you
want to read during it. When it finishes it prints a summary and saves
`uia-dump-<timestamp>.txt` to your Desktop.

**Then send me that .txt file.** The summary line "with readable text: N"
is the key signal: if N is 0, that screen is opaque to UI Automation and
we'll plan the OCR fallback for it; if N is healthy, we proceed to the
extractor.

Options: `-Delay <seconds>` (default 4), `-OutFile <path>`.
