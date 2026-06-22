// ===========================================================================
// FIELD BOUNDS — this is the part you edit.
// ===========================================================================
// Each entry is a rectangle as FRACTIONS of the whole page image (0..1):
//   x, y = top-left corner, w, h = width, height.
// They are resolution-independent, so they work whatever size photo/scan you
// feed in — AS LONG AS the page fills the frame upright (like a flat scan).
//
// Don't guess these by hand. Open calibrate.html, load a photo of your form
// framed the way you'll actually scan it, drag a box over each field, and
// paste the generated FIELD_RECTS block over the one below.
const FIELD_RECTS = {
  name:    { x: 0.0500, y: 0.4300, w: 0.3400, h: 0.0300 },
  ro:      { x: 0.7200, y: 0.0000, w: 0.2300, h: 0.0900 },
  advisor: { x: 0.4000, y: 0.2900, w: 0.1000, h: 0.0400 },
  tag:     { x: 0.8600, y: 0.4700, w: 0.1300, h: 0.0300 },
};

// ===========================================================================
// FIELD LOGIC — the code side (usually leave this alone).
// ===========================================================================
// Known advisor IDs (the Google Form dropdown's options).
const ADVISORS = ["142399", "17824", "159720", "160629", "159462"];

// For each field key above: which Google-Form input to fill (`target`), the
// character whitelist + page-seg mode passed to Tesseract for that crop, and
// a `parse(rawText)` that turns the crop's raw OCR text into the final value.
const FIELD_LOGIC = {
  name: {
    label: "Customer Name",
    target: "f_name",
    whitelist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ '.-",
    psm: "7", // single text line
    parse: t => t.replace(/[^A-Z '.-]/gi, "").replace(/\s+/g, " ").trim(),
  },
  ro: {
    label: "RO #",
    target: "f_ro",
    whitelist: "0123456789",
    psm: "7",
    parse: t => (t.match(/\d{4,}/) || [""])[0],
  },
  advisor: {
    label: "Advisor #",
    target: "f_advisor",
    whitelist: "0123456789",
    psm: "7",
    parse: t => {
      const nums = t.match(/\d{4,6}/g) || [];
      for (const n of nums) if (ADVISORS.includes(n)) return n; // prefer a known ID
      return nums[0] || "";
    },
  },
  tag: {
    label: "Tag #",
    target: "f_tag",
    whitelist: "0123456789",
    psm: "7",
    parse: t => (t.match(/\d+/) || [""])[0],
  },
};

// Merge bounds + logic into the REGIONS structure the app consumes. Any key
// present in BOTH FIELD_RECTS and FIELD_LOGIC becomes an active region.
const REGIONS = {};
for (const key of Object.keys(FIELD_LOGIC)) {
  if (FIELD_RECTS[key]) {
    REGIONS[key] = Object.assign({}, FIELD_LOGIC[key], { rect: FIELD_RECTS[key] });
  }
}
