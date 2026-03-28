# screenshot-renamer

**Automatically renames screenshots to descriptive slugs using OCR and AI vision.**

Drop a screenshot on your Desktop — it gets renamed from `Screenshot 2026-03-28 at 11.00.40.png` (useful only for sorting by date) to `2026-03-28-apple-frames-api-shortcut-workflow.png` (actually searchable) and archived. No clicks required.

> **Heads up:** Setup requires a terminal and a text editor. If that's not your thing, this tool probably isn't for you — yet.

![Shell](https://img.shields.io/badge/shell-bash-blue)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)

---

## How it works

A file watcher monitors your Desktop. When a new screenshot appears it runs a bash script that:

1. **OCR first** — uses macOS Vision to extract any text from the screenshot. Fast, free, no API call needed.
2. **AI vision fallback** — if OCR finds no text (diagrams, photos, UI without labels), it sends the image to the AI API for a visual description.
3. **Slug generation** — the extracted text or description is sent to the API to generate a clean kebab-case slug.
4. **Rename + archive** — file is renamed with a date prefix and moved to `~/Screenshots Archive/`.

The result is a searchable, organised archive of every screenshot you take — automatically.

---

## Demo

```
Before: Screenshot 2026-03-24 at 11.00.40.png
After:  2026-03-24-apple-frames-api-shortcut-workflow.png
```

---

## Performance

OCR path (text found): ~200ms — no API call, Vision runs locally  
Vision path (no text): ~800ms — one API call  
Cost: fractions of a cent per image, only when OCR finds nothing

**vs. Automator/Shortcuts:** The previous standard approach — chaining Automator folder actions with Shortcuts and Apple Intelligence — was slow (3-10 seconds per image), flaky (dependent on Apple Intelligence availability and the ChatGPT app being open), and broke silently when either wasn't ready. This script runs in under a second, has no app dependencies, and starts automatically at login via Hazelnut's daemon. It's also significantly simpler to set up: one TOML rule and one `chmod +x`.

---

## AI provider

The script uses **Claude (Anthropic) by default** — it handles both the slug generation and the vision fallback well. But it's two config lines to swap in any OpenAI-compatible API.

Tested alternatives:
- **OpenAI (GPT-4o)** — slightly more consistent on pure visual content with no text. Swap `ANTHROPIC_API_KEY` for `OPENAI_API_KEY` and update the endpoint and model in the script.
- **Local models via Ollama** — free, fully offline, quality varies by model. Point the endpoint at `http://localhost:11434/v1`.
- **Gemini, Mistral, etc.** — anything with an OpenAI-compatible endpoint works.

The `screenshot-rename.env.example` includes commented-out alternatives.

---

## Requirements

- **[Hazelnut](https://github.com/ricardodantas/hazelnut)** (recommended — cross-platform, Rust, fast) or **[Hazel](https://www.noodlesoft.com/)** (macOS only, GUI, $42)
- An API key for your preferred provider — Claude, OpenAI, or compatible
- `jq` — `brew install jq` (macOS/Linux) or via [jq releases](https://jqlang.org/download/) on Windows
- **macOS only**: the OCR path uses the Vision framework. On Linux/Windows only the AI vision path runs.

---

## Platform screenshot filename patterns

The watcher rule needs to match your platform's default screenshot filename. Commented-out patterns are included in the config — uncomment the one that matches your setup.

| Platform | Tool | Default filename pattern |
|----------|------|--------------------------|
| macOS | Screenshot (Cmd+Shift+3/4) | `Screenshot 2026-03-28 at 11.00.40.png` |
| Windows 11 | Win+PrtSc auto-save | `Screenshot (1).png` *(no date — just increment)* |
| Windows 11 | Snipping Tool manual save | `screenshot 2026-03-28 140523.png` |
| Linux GNOME 42+ | Built-in | `Screenshot from 2026-03-28 14-23-00.png` |
| Linux KDE Spectacle | Spectacle | `Screenshot_20260328_142300.png` |

> **Windows auto-save note:** The `Screenshot (N).png` pattern has no date in the filename, so the slug comes entirely from OCR or vision. It still works — there's just nothing useful in the name to fall back on.

> **Windows watch folder:** Unlike macOS (Desktop) and Linux (Desktop or `~/Pictures`), Windows auto-saves screenshots to `Pictures\Screenshots` — not the Desktop. Update the `path` in your Hazelnut config accordingly: `C:\Users\yourname\Pictures\Screenshots`.

---

## Setup

### 1. Set up your API key

Copy the example env file to your home directory:

```bash
cp screenshot-rename.env.example ~/.screenshot-rename.env
```

Open `~/.screenshot-rename.env` and add your key. The file lives in `~` rather than the scripts folder so it's always in a predictable location and won't accidentally get committed to a repo.

```
# Claude (recommended)
ANTHROPIC_API_KEY=sk-ant-...

# Or OpenAI
# OPENAI_API_KEY=sk-...
```

### 2. Install dependencies

```bash
brew install jq
```

### 3. Install the script

```bash
mkdir -p ~/Scripts
cp screenshot-rename.sh ~/Scripts/
chmod +x ~/Scripts/screenshot-rename.sh
```

### 4. Create the archive folder

```bash
mkdir -p ~/Screenshots\ Archive
```

### 5. Configure your file watcher

#### Hazelnut (recommended)

Add to your `~/.config/hazelnut/config.toml`:

```toml
[[watch]]
path = "/Users/yourname/Desktop"
recursive = false
rules = ["Rename screenshots", "Move renamed to archive"]

[[rule]]
name = "Rename screenshots"
enabled = true
stop_processing = true
[rule.condition]
# macOS default:
name_regex = "^Screenshot.*\\.png$"
# Windows Snipping Tool — uncomment if on Windows:
# name_regex = "^screenshot.*\\.png$"
# GNOME Linux — uncomment if on GNOME:
# name_regex = "^Screenshot from.*\\.png$"
# KDE Spectacle — uncomment if on KDE:
# name_regex = "^Screenshot_.*\\.png$"
[rule.action]
type = "script"
command = "/Users/yourname/Scripts/screenshot-rename.sh"

[[rule]]
name = "Move renamed to archive"
enabled = true
[rule.condition]
name_regex = "^\\d{4}-\\d{2}-\\d{2}.*\\.png$"
[rule.action]
type = "move"
destination = "/Users/yourname/Screenshots Archive"
create_destination = false
overwrite = false
```

Restart the daemon: `hazelnutd restart`

#### Hazel

Create two rules on the Desktop folder:
1. **Rename** — condition: name matches `Screenshot*.png`, action: run script `~/Scripts/screenshot-rename.sh`
2. **Archive** — condition: name matches date regex `^\d{4}-\d{2}-\d{2}.*\.png$`, action: move to `~/Screenshots Archive`

---

## How the two-rule pattern works

The date prefix is the handoff signal between the two rules:

```
Screenshot lands on Desktop
  → Rule 1 matches "Screenshot*.png"
  → Script renames it to "2026-03-24-my-slug.png"
  → Rule 2 matches "^\d{4}-\d{2}-\d{2}.*\.png$"
  → File moves to ~/Screenshots Archive
```

No intermediate folders, no labels, no xattr metadata. Clean and reliable.

> **Note:** The archive rule matches `.png` only, which is what the script outputs on macOS. If you need to handle other formats, see the Customisation section.

---

## Calibration notes

These are findings from real usage — worth knowing before you start tweaking:

**300px is the optimal `MAX_IMAGE_PX`** for the vision path. Large enough for Claude to read UI elements and understand context, small enough to keep base64 payloads fast. Going larger doesn't meaningfully improve slug quality.

**OCR is fast enough that it's always worth trying first.** Even on screenshots with sparse text, Vision usually finds something useful. The API call is only triggered when OCR genuinely finds nothing.

**OpenAI performs more consistently than Claude for pure visual content** (diagrams, photos with no text). If you find the vision fallback generating generic slugs, swap `MODEL` on the vision path to an OpenAI model — you'll need an OpenAI API key but the script supports it.

---

## Customisation

**Watch a different folder** — update `path` in your Hazelnut config  
**Change the archive destination** — update `destination` in the Move rule  
**Archive rule matches `.png` only** — if you need to handle other formats (jpg, webp, etc.), update the `name_regex` in the Move rule to `^\\d{4}-\\d{2}-\\d{2}.*\\.(png|jpg|jpeg|webp)$`  
**Disable the vision fallback** — comment out the vision section; files with no OCR text will get a `screenshot` slug  
**Use a different AI provider** — the slug generation and vision calls use standard chat completions format; swap the endpoint and model  
**API key** — stored in `~/.screenshot-rename.env`, never in the script itself

---

## Troubleshooting

**Files getting renamed to `2026-03-24-screenshot.png`**  
OCR found no text and the vision fallback failed. Check `~/screenshot-rename-log.txt` and the Hazelnut daemon log at `~/.local/state/hazelnut/hazelnutd.log`.

**`Argument list too long` error on jq**  
The base64-encoded image is too large for shell argument passing. Lower `MAX_IMAGE_PX` in the script (try 200).

**Script not triggering**  
Make sure the script is executable: `chmod +x ~/Scripts/screenshot-rename.sh`. Check Hazelnut is running: `hazelnutd status`.

**Extension showing in Brave (macOS)**  
`localhost` on modern macOS resolves to `::1` (IPv6) rather than `127.0.0.1`. Make sure both are in your host permissions.

---

## Contributing

PRs welcome. Most useful additions:

- [ ] Linux OCR path (Tesseract fallback)
- [ ] Windows support
- [ ] Support for additional file types (PDF, HEIC)
- [ ] GUI config tool for non-terminal users (the main barrier to wider adoption)

---

## License

MIT
