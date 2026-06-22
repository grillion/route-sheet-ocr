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

## Open questions / things to revisit if this expands beyond one dealership

- Tag # and Customer Name extraction use layout-specific heuristics (VIN
  position, "TAG" label proximity) tuned to this one RO template — would
  need rework for a different dealership's form.
- No image preprocessing (deskew/contrast) yet; OCR quality is fully
  dependent on photo quality.
- If GitHub Pages free tier ever becomes a constraint (it shouldn't —
  static single-file site, no bandwidth concerns at this scale), Netlify
  or Cloudflare Pages free tiers are equivalent fallbacks.
