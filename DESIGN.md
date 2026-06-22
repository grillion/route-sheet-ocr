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
index.html     — markup, styles, scanner UI, OCR pipeline
regions.js     — field bounds (FIELD_RECTS) + field logic (FIELD_LOGIC)
calibrate.html — tool to draw field boxes and generate FIELD_RECTS
```

Flow:

1. User taps **Start Camera** (live capture, `getUserMedia`) or
   **Upload Photo** (file picker, for an existing image).
2. The frame is drawn to an off-screen `<canvas>` and `preprocess()`d
   (upscale, grayscale, Otsu binarize).
3. **Pass 1 — full page:** `Tesseract.recognize()` over the whole image,
   used for the Type of Work keyword scan and the debug overlay/word list.
4. **Pass 2 — region OCR:** for each field in `regions.js`, the known box
   is cropped and OCR'd with a field-specific character whitelist + PSM,
   then `parse()`d into the final value. This is the authoritative path for
   the fixed fields (name, RO #, advisor, tag).
5. Results pre-fill an on-page review form; a visual overlay shows the word
   boxes + region crops. User reviews/corrects every field (nothing sent
   yet).
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

## Field extraction (region-based)

Because the RO is a fixed template, fixed fields are read by **cropping a
known box and OCRing just that crop** — far more reliable than searching the
full-page text. Each field is defined in `regions.js`:

- `FIELD_RECTS[key]` — the box, as fractions of the page (`x, y, w, h`). This
  is the part you calibrate. Generate it by drawing on a template photo in
  `calibrate.html`, then paste the output over this object.
- `FIELD_LOGIC[key]` — `target` (which form input to fill), `whitelist` +
  `psm` (Tesseract params for the crop), and `parse(rawText)` → final value.

At runtime the two are merged into `REGIONS` and each crop is OCR'd with its
own whitelist/PSM. Current fields: **name** (letters whitelist), **RO #**,
**advisor #** (digits, parse prefers a known advisor ID), **tag #** (digits).
OCR is still imperfect, so the user always reviews/edits before generating
the link — nothing is trusted silently.

Two fields are *not* region-based:

- **Type of Work** — a keyword regex scan over the full-page OCR text of the
  job-description lines (`BRAKE` → BRAKES, `TIRE` → TIRES, `STEER|SUSPENSION`
  → SUSPENSION, `MULTI ?POINT|INSPECT` → MAINTENANCE, …). It's spread across
  several job lines, not a single box, so a keyword scan fits better. Fuzzy;
  most likely to need manual correction.
- **Customer Status** and **Express or Main Shop** — *never* auto-filled;
  this info isn't on the paper RO at all, so the user always picks them.

**Why region-based replaced the old heuristics.** The first version inferred
each field from full-page structure (VIN-anchor for the name, "TAG"-label
proximity, a top-right 6-digit search for RO#). Those were over-fit to one
sample document and brittle:

- The RO# search stripped non-digits before checking for 6 digits, so a date
  like `11/18/25` collapsed to `111825` and could win — values must never be
  built from digit-stripped tokens.
- Name/Tag used *fixed pixel* row bands that silently broke once `preprocess`
  started upscaling images — **any pixel threshold in extraction must be
  relative to detected text size or image dimensions, never hardcoded.**

Region OCR sidesteps all of this: a digits-only whitelist on an isolated crop
can't even see a date, and fractional bounds scale with any image size.

**Limitation of fractional bounds:** they assume the page fills the frame
upright (as in a flat scan). A badly cropped/rotated photo will misalign the
crops; calibrate on an image framed the same way you'll scan. Rectifying the
page (perspective transform) before cropping would lift this constraint but
isn't implemented.

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
