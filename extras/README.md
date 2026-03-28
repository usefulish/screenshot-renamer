# extras/

Test scripts for calibrating and debugging the screenshot renamer.
None of these modify or rename any files — they're all read-only diagnostic tools.

## Setup

Make them executable:

```bash
chmod +x extras/*.sh
```

---

## Scripts

### `test-ocr.sh` — inspect raw OCR output

```bash
./extras/test-ocr.sh ~/Desktop/Screenshot\ 2026-03-28\ at\ 11.00.40.png
```

Runs macOS Vision OCR and prints exactly what text the script sees. Useful for understanding why a particular screenshot got an unexpected slug — sometimes OCR picks up UI chrome, tooltips, or background text you didn't notice.

Also shows whether the 10-char threshold would trigger the vision fallback. Lower the threshold in the main script if you want OCR to run on images with very sparse text.

**Not available on Linux/Windows** — uses macOS Vision framework.

---

### `test-vision.sh` — compare slug quality at different resolutions

```bash
./extras/test-vision.sh ~/Desktop/Screenshot\ 2026-03-28\ at\ 11.00.40.png
```

Sends the image to the vision API at 5 different sizes (100px → 600px) and prints the slug generated at each, along with payload size and response time. Output looks like:

```
  Size      |  Payload         |  Time  |  Slug
  ──────────┼──────────────────┼────────┼───────────────────────────
  100    px  |     12 KB        |   1s   |  blurry-ui-screenshot
  200    px  |     48 KB        |   1s   |  figma-export-settings-panel
  300    px  |    108 KB        |   1s   |  figma-component-export-settings
  400    px  |    192 KB        |   2s   |  figma-component-export-settings
  600    px  |    432 KB        |   2s   |  figma-component-export-settings
```

**Finding from real use:** 300px is the sweet spot for most screenshots. Slug quality plateaus there — going to 400px or 600px rarely changes the output but doubles or quadruples the payload. 100-200px can produce generic or inaccurate slugs for dense UIs.

Makes 5 API calls per run — factor in cost if you're on a metered plan.

---

### `test-slug.sh` — test slug generation from text

```bash
./extras/test-slug.sh "Slack error: workspace not found, please sign in again"
```

Or pipe OCR output directly:

```bash
./extras/test-ocr.sh screenshot.png | grep "Result" | ./extras/test-slug.sh
```

Sends text to the API and prints the slug. Use this to tune the prompt wording in the main script without needing a real image — much faster feedback loop. Edit the `PROMPT` variable in this script and run it a few times on different inputs to find wording that produces consistently good slugs.

---

### `test-full.sh` — dry run of the complete pipeline

```bash
./extras/test-full.sh ~/Desktop/Screenshot\ 2026-03-28\ at\ 11.00.40.png
```

Runs the entire pipeline — OCR, vision fallback if needed, API call, slug sanitisation — and prints every step in detail. Nothing is renamed. Output looks like:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DRY RUN — nothing will be renamed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Input:    Screenshot 2026-03-28 at 11.00.40.png
Model:    claude-haiku-4-5-20251001
Max px:   300px

┌─ Step 1: OCR
│  Status:  text found (342 chars, 0s)
│  Preview: File Edit View Window Help  New Tab…
│  Path:    → OCR (no API call needed)

┌─ Step 2: API request
│  Type:    text-only (OCR path)
│  Chars:   342 → truncated to 500 for API

┌─ Step 3: API call
│  Endpoint: https://api.anthropic.com/v1/chat/completions
│  Time:     1s

┌─ Step 4: Slug
│  Raw:      terminal-new-tab-menu
│  Clean:    terminal-new-tab-menu

┌─ Step 5: Result (DRY RUN)
│  Before:  Screenshot 2026-03-28 at 11.00.40.png
│  After:   2026-03-28-terminal-new-tab-menu.png
```

Good for validating a new provider or model before switching, or debugging why a specific image produces a bad slug.

---

## Notes on provider differences

From real-world testing with the same set of screenshots:

**Claude Haiku** — fast, cheap, reliable on text-heavy screenshots. Slug wording tends to be descriptive and accurate.

**GPT-4o-mini** — slightly better on pure visual content (diagrams, photos with no text). Comparable speed and cost to Haiku.

**Gemini Flash** — competitive quality, useful if you already have a Gemini API key.

**Llava (Ollama)** — free and fully offline. Quality varies significantly by image type — good on photos, inconsistent on UI screenshots. Worth trying if privacy or cost is a priority.

Run `test-vision.sh` with the provider uncommented to compare directly on your own screenshots.
