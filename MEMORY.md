# Memory

Running log of context and decisions for this repo. See [DESIGN.md](DESIGN.md)
for full architecture/rationale; this file is the quick-recap version plus
anything that doesn't belong in a design doc.

## What this is

A single-page tool (`index.html`) that OCRs a photographed/uploaded Nissan
of Huntington repair order and builds a pre-filled link to a Google Form
("Route Sheet Entry Form") so a tech can review and submit it without
retyping. No backend, no paid services — Tesseract.js for OCR (on-device),
GitHub Pages for hosting (free HTTPS, required for camera access).

## Live deployment

- Repo: https://github.com/grillion/route-sheet-ocr
- Page: https://grillion.github.io/route-sheet-ocr/
- Branch: `master` (Pages serves from `master` / root)
- Deploy is automatic on push — no CI config needed.

## Target form

- Google Form: https://forms.gle/fGtAyNxbNoBMQzrs5 ("Route Sheet Entry Form")
- Fields, entry IDs, and how to re-derive them if the form changes: see
  the table in [DESIGN.md](DESIGN.md#target-google-form).
- Advisor # is a closed set (142399, 17824, 159720, 160629, 159462) — this
  makes it the most reliable auto-filled field.
- Customer Status and Express/Main Shop are **always** left for manual
  selection — they don't appear on the paper RO at all.

## Incidents / fixes

- **2026-06-22 — RO# misread as a date.** First real-world test: OCR
  picked `111825` instead of the correct `934986` (visible top-right on
  the RO). Root cause: the RO# heuristic stripped all non-digit chars from
  every OCR token before checking for 6-digit length, so the date
  `11/18/25` collapsed into `111825` and got counted as a candidate.
  Fix: only consider tokens that are *already* pure digits (no slashes),
  and prefer one located in the top-right quadrant of the image (where
  this dealership prints the RO number) before falling back to frequency
  count. Applied the same raw-digit guard to the Advisor # matcher as a
  preventative measure, even though no failure was observed there yet.

- **2026-06-22 — preprocessing/region OCR added.** Kept Tesseract (Scribe
  is built on it — same engine, not worth the rewrite). Added a
  `preprocess()` pass (upscale small images to ~2200px long edge,
  grayscale, Otsu binarize) and a two-pass pipeline: full-page OCR for
  Type of Work / Name / Tag, then targeted region OCR (digit whitelist,
  single-line PSM) for the RO# top-right corner, defined in a `REGIONS`
  config for easy extension. Region OCR overrides the full-page RO# guess
  when it yields a clean value, else degrades to the full-page result.

- **2026-06-22 — name/tag bands broke after upscaling.** Customer Name came
  back empty. Root cause: name/tag heuristics used *fixed pixel* vertical
  bands (40px / 20px) to find words on the line below/beside an anchor.
  Once `preprocess()` started upscaling to ~2200px, those absolute
  thresholds were too small relative to the enlarged text and missed the
  target line. Fix: size all row bands from the anchor word's own text
  height (`lineH`/`labelH`), never hardcoded pixels. **Lesson: any pixel
  threshold in the extraction heuristics must be relative to detected text
  size or image dimensions, because preprocessing rescales the image.**
  Also constrained the name search to the left column (x0 < 40% width) so
  it can't grab the year/make/model text to the right of the VIN.

- **2026-06-22 — moved to explicit, calibratable field bounds.** The
  per-field heuristics (VIN-anchor for name, TAG-label proximity, top-right
  RO# search) were too over-fit to the one sample doc and kept breaking.
  Replaced with region-based OCR as the *authoritative* path for all fixed
  fields. The bounds now live in `regions.js` as a single `FIELD_RECTS`
  object (fractional x/y/w/h per field) — the one thing you edit. Field
  *logic* (whitelist, PSM, parse, target input) stays in `FIELD_LOGIC` in
  the same file. Added `calibrate.html`: load a template photo, drag a box
  per field, copy the generated `FIELD_RECTS` back into regions.js. Only
  Type of Work still comes from a full-page keyword scan (it's spread across
  job lines, not a single box). Files are no longer a single self-contained
  HTML — now index.html + regions.js + calibrate.html (all still static).
  **Key caveat: fractional bounds assume the page fills the frame upright;
  calibrate on an image framed the same way you'll scan.**

- **2026-06-28 — pivoted to a Windows desktop tool (no phone, no OCR).** The
  real workflow is at a desktop running Reynolds & Reynolds **ERA-IGNITE**,
  not a phone. New approach in `windows/`: a global hotkey
  (`Start-EraHotkey.ps1`, default Ctrl+Alt+R) runs `Extract-ERA.ps1`, which
  reads the focused ERA RO Billing screen via **Windows UI Automation**
  (`System.Windows.Automation`) and opens the pre-filled Google Form. No
  installs (built-in .NET), no OCR, no Tesseract. Verified ERA-IGNITE exposes
  its data via UIA — **the values are in each element's `Name` property, not
  Value/Text patterns** (that tripped up the inspector's first readability
  counter). Field rules: RO# from window title (`RO Billing <n>`); customer
  vs. advisor both render as `(<number>) NAME` and are told apart by whether
  the number is a known advisor ID; tag from the value next to `Tag#`. Type
  of Work lives in ERA's grid controls (`PowerGridWnd`) which UIA does NOT
  expose — left manual, along with Customer Status and Express/Main Shop
  (not on the screen). The browser/phone OCR tool (index.html, regions.js,
  calibrate.html) still exists as the photo-based fallback path.

## Open questions / things to revisit if this expands beyond one dealership

- Tag # and Customer Name extraction use layout-specific heuristics (VIN
  position, "TAG" label proximity) tuned to this one RO template — would
  need rework for a different dealership's form.
- No image preprocessing (deskew/contrast) yet; OCR quality is fully
  dependent on photo quality.
- If GitHub Pages free tier ever becomes a constraint (it shouldn't —
  static single-file site, no bandwidth concerns at this scale), Netlify
  or Cloudflare Pages free tiers are equivalent fallbacks.
