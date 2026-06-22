# Route Sheet Scanner — Design

## Goal

Photograph (or upload a photo of) a paper Nissan of Huntington repair order
(RO), extract the relevant fields via on-device OCR, and produce a
pre-filled link to the shop's "Route Sheet Entry Form" (Google Forms) so a
tech only has to review and submit — no typing.

Hard constraint: **zero ongoing service fees**. Every piece of this runs
either on-device or on free-tier infrastructure:

- OCR: [Tesseract.js](https://github.com/naptha/tesseract.js) — runs
  entirely in the browser via WebAssembly, no API key, no server call.
- Hosting: GitHub Pages (free, automatic HTTPS — required for camera
  access, since browsers only grant `getUserMedia` on secure origins).
- Form fill: Google Forms' native ["pre-filled link"](https://support.google.com/docs/answer/9348611)
  feature (`?entry.<id>=value` query params) instead of browser automation —
  more robust than driving the form's DOM, and Google doesn't allow a URL
  to silently submit on its own, which conveniently forces a human review
  step before the response is recorded.

## Architecture

Single static file, no build step, no backend:

```
index.html   — markup, styles, and all JS inline
```

Flow:

1. User taps **Start Camera** (live capture, `getUserMedia`) or
   **Upload Photo** (file picker, for an existing image).
2. The frame is drawn to an off-screen `<canvas>`.
3. `Tesseract.recognize()` runs OCR on the canvas, returning full text plus
   word-level bounding boxes (`data.words[i].bbox`).
4. `populateForm()` applies heuristics (see below) to guess each Google
   Form field from the OCR output and pre-fills an on-page review form.
5. User reviews/corrects every field in the browser (nothing is sent
   anywhere yet).
6. **Build Pre-filled Link** assembles a
   `docs.google.com/forms/.../viewform?entry.X=...` URL from the current
   field values and shows it as a link to tap.
7. Tapping the link opens the real Google Form, pre-filled, for the user
   to do a final check and hit Submit themselves.

Nothing is ever auto-submitted — this was an explicit choice (see Decisions
below), not just a limitation of the pre-filled-link approach.

## Target Google Form

"Route Sheet Entry Form" — internal shop form for logging a technician
route assignment from an RO.

Form (short link): https://forms.gle/fGtAyNxbNoBMQzrs5
Canonical viewform: `https://docs.google.com/forms/d/e/1FAIpQLScLJnRO7EemJcZTy9gP_iYE9FvcRBelDArE9dHf0evu6ZKARQ/viewform`

Field → `entry.` ID mapping (extracted from the form's
`FB_PUBLIC_LOAD_DATA_` blob embedded in the viewform HTML — see "How to
re-derive entry IDs" below if the form is ever rebuilt):

| Field | entry ID | Type | Notes |
|---|---|---|---|
| CUSTOMERS NAME | `entry.1742178377` | short text | |
| RO # | `entry.438656768` | short text | |
| ADVISOR # | `entry.1130646650` | dropdown | options: 142399, 17824, 159720, 160629, 159462 |
| TAG # | `entry.22122272` | short text | often blank on the paper RO |
| CUSTOMER STATUS | `entry.1856597312` | radio | WAIT / DROP / DROP WITH LOANER |
| EXPRESS OR MAIN SHOP | `entry.707168016` | radio | EXPRESS / MAIN SHOP / BOTH |
| TYPE OF WORK | `entry.454520462` | checkbox (multi) | repeat the param once per checked value |
| NOTES | `entry.760985235` | paragraph | |

### How to re-derive entry IDs

If the form is ever edited (fields added/removed) the IDs above may
become stale. To re-derive:

```sh
curl -s -L "<viewform URL>" -o form.html
grep -o 'var FB_PUBLIC_LOAD_DATA_ = .*;' form.html
```

The blob is a nested array; each question is `[fieldId, "LABEL", ..., type,
[[entryId, options..., ...]], ...]`. The `entryId` (second-level array,
first element) is what goes in the URL as `entry.<entryId>`. `type` codes
seen here: `0` = short text, `1` = paragraph, `2` = radio, `3` = dropdown,
`4` = checkboxes.

## Source document

The paper RO is a Reynolds & Reynolds-style multi-page dealership repair
order (Nissan of Huntington). It is dense and not purpose-built for this
form — most Route Sheet fields are inferred rather than directly labeled.

Reference photo used during development: a Nissan Armada RO, RO# 934986,
Advisor# 142399, customer Cassandra N Rebecchi, jobs covering seatbelt,
steering, multi-point inspection, brakes, tire inspection.

## Field extraction heuristics (and why)

OCR on this layout is noisy (small print, overlapping pink boxes, mixed
print/handwriting), so every heuristic below is a *best guess* — the user
always reviews/edits before generating the link. None of this silently
trusts OCR for a value that matters.

- **Advisor #** — exact match of a raw, all-digit OCR token against the
  five known advisor IDs from the form's dropdown. This is the most
  reliable field because it's matched against a closed, finite set.
- **RO #** — a pure 6-digit token (`^\d{6}$`, no separators) located in the
  top-right quadrant of the page, where Nissan of Huntington prints the RO
  number (it's also repeated in the barcode caption and footer). Falls
  back to whichever pure 6-digit token appears most often on the page if
  nothing is found top-right.
  - **Bug fixed 2026-06-22**: the original version stripped *all*
    non-digit characters from every OCR token before checking length 6.
    That collapsed dates like `11/18/25` into `111825` — a fake 6-digit
    "candidate" that could outrank the real RO number in the frequency
    count. Dates must never enter the RO#/Advisor# candidate pools; always
    require the raw token to already be pure digits.
- **Tag #** — nearest OCR word to the right of a token containing "TAG",
  within a small vertical band (same row). Often comes back empty since
  the Tag # box is frequently blank on this dealership's RO.
- **Customer Name** — looks for a 17-character VIN-like token, then takes
  the run of all-caps words immediately below it (the customer name prints
  directly under the VIN on this layout).
- **Type of Work** — keyword regex scan over the full OCR text of the job
  description lines (e.g. `BRAKE` → BRAKES, `TIRE` → TIRES, `STEER|
  SUSPENSION` → SUSPENSION, `MULTI ?POINT|INSPECT` → MAINTENANCE). Multiple
  categories can get checked; this is the fuzziest heuristic and most
  likely to need manual correction.
- **Customer Status** and **Express or Main Shop** are *never* auto-filled
  — this information doesn't appear anywhere on the paper RO, so guessing
  would be worse than leaving it blank. The user always picks these two
  manually.

## Key decisions

- **Pre-filled link + manual submit, not full browser automation.**
  Considered driving the Google Form's DOM directly (e.g. Playwright) to
  also auto-submit. Rejected: more fragile (breaks if Google changes the
  form's HTML/IDs), and removes the human review step that catches OCR
  mistakes — which matters since this data is uncorrectable once
  submitted to the spreadsheet backing the form.
- **Single static HTML file, no framework/build step.** The whole tool is
  one page; adding a bundler or framework would add no value for something
  this size and would complicate free hosting.
- **GitHub Pages over a local dev server.** Camera access requires HTTPS;
  GitHub Pages gives a permanent, free HTTPS URL without the user needing
  to run anything.
- **Editable review form between OCR and link generation.** Every
  heuristic above is fallible, so nothing is sent anywhere until the user
  has seen and can correct every field — this was the explicit design
  response to "what if OCR gets a field wrong" rather than trying to make
  each heuristic perfect.

## Known limitations

- Tag # and Customer Name heuristics are tuned to this one RO's layout;
  other dealerships' ROs (or even a redesigned Nissan of Huntington RO)
  may need different heuristics.
- Type of Work keyword mapping is a best-effort guess from job
  descriptions, not a real field on the RO — always verify before
  submitting.
- OCR accuracy depends heavily on photo lighting/angle/focus; no
  preprocessing (deskew, contrast normalization) is done yet.
