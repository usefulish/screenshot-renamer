#!/bin/bash
# ─────────────────────────────────────────────────────────────
# screenshot-rename.sh
# Renames screenshots using AI (OCR + vision fallback)
# OpenAI-compatible API format — swap provider by changing
# the three config lines below
# ─────────────────────────────────────────────────────────────

# ── Provider config (change these to switch providers) ────────
# Load API key from env file
source "$HOME/.screenshot-rename.env"
API_KEY="$ANTHROPIC_API_KEY"
API_ENDPOINT="https://api.anthropic.com/v1/chat/completions"
MODEL="claude-haiku-4-5-20251001"

# Other providers — uncomment to use:
# OpenAI
# API_ENDPOINT="https://api.openai.com/v1/chat/completions"
# MODEL="gpt-4o-mini"

# Google Gemini (OpenAI-compatible endpoint)
# API_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
# MODEL="gemini-2.0-flash"

# Groq
# API_ENDPOINT="https://api.groq.com/openai/v1/chat/completions"
# MODEL="llama-3.2-11b-vision-preview"

# ── Settings ──────────────────────────────────────────────────
LOG_FILE="$HOME/screenshot-rename-log.txt"
MAX_IMAGE_PX=300   # Max dimension for vision path (px)

# ── Validate input ────────────────────────────────────────────
inputFile="$1"

if [ ! -f "$inputFile" ]; then
  echo "File not found: $inputFile" >&2
  exit 1
fi

# ── Detect media type ─────────────────────────────────────────
ext="${inputFile##*.}"
ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  jpg|jpeg) mediaType="image/jpeg" ;;
  png)      mediaType="image/png" ;;
  webp)     mediaType="image/webp" ;;
  gif)      mediaType="image/gif" ;;
  *)        echo "Unsupported file type: $ext" >&2; exit 1 ;;
esac

# ── Date prefix ───────────────────────────────────────────────
datePrefix=$(date +"%Y-%m-%d")

# ── Step 1: OCR via macOS Vision framework ────────────────────
ocrText=$(osascript -e "
  use framework \"Vision\"
  use scripting additions
  set theImage to current application's NSImage's alloc()'s initWithContentsOfFile_(\"$inputFile\")
  set requestHandler to current application's VNImageRequestHandler's alloc()'s initWithData_(theImage's TIFFRepresentation()) options:(current application's NSDictionary's alloc()'s init())
  set request to current application's VNRecognizeTextRequest's alloc()'s init()
  requestHandler's performRequests_({request}) |error|:(missing value)
  set results to request's results()
  set ocrResult to \"\"
  repeat with observation in results
    set ocrResult to ocrResult & (item 1 of observation's topCandidates_(1))'s |string|() & \" \"
  end repeat
  return ocrResult
" 2>/dev/null || echo "")

# ── Step 2: Build request ─────────────────────────────────────
tmpRequest=$(mktemp "$HOME/.cache/screenshot-request-XXXXXX.json")

if [ -n "$ocrText" ] && [ ${#ocrText} -gt 10 ]; then
  # Text found — send OCR text only (cheaper, faster, no image needed)
  prompt="Based on this text from a screenshot, generate a filename slug in 3-6 words. Lowercase, hyphens only, no punctuation, no extension, no explanation. Examples: slack-error-message-login, figma-export-settings, terminal-docker-build. Reply with only the slug.\n\nText:\n${ocrText:0:500}"

  jq -n \
    --arg model "$MODEL" \
    --arg prompt "$prompt" \
    '{
      model: $model,
      max_tokens: 64,
      messages: [{
        role: "user",
        content: $prompt
      }]
    }' > "$tmpRequest"

else
  # No text — resize image then send for visual description
  tmpImg=$(mktemp "$HOME/.cache/screenshot-resize-XXXXXX.png")
  tmpB64=$(mktemp "$HOME/.cache/screenshot-b64-XXXXXX.txt")

  sips -Z "$MAX_IMAGE_PX" "$inputFile" --out "$tmpImg" &>/dev/null
  base64 -i "$tmpImg" > "$tmpB64"
  rm -f "$tmpImg"

  prompt="Describe this screenshot in 3-6 words suitable for a filename slug. Focus on the main subject, colors, and composition. Lowercase, hyphens only, no punctuation, no extension, no explanation. Examples: brown-horse-white-background, aerial-city-night-view, red-sports-car-road. Reply with only the slug."

  jq -n \
    --arg model "$MODEL" \
    --arg mediaType "$mediaType" \
    --rawfile imageData "$tmpB64" \
    --arg prompt "$prompt" \
    '{
      model: $model,
      max_tokens: 64,
      messages: [{
        role: "user",
        content: [
          {
            type: "image_url",
            image_url: {
              url: ("data:" + $mediaType + ";base64," + ($imageData | rtrimstr("\n")))
            }
          },
          {
            type: "text",
            text: $prompt
          }
        ]
      }]
    }' > "$tmpRequest"

  rm -f "$tmpB64"
fi

# ── Step 3: Call API ──────────────────────────────────────────
response=$(curl -s "$API_ENDPOINT" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "@$tmpRequest")

rm -f "$tmpRequest"

# ── Step 4: Extract slug ──────────────────────────────────────
slug=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

# Sanitize
if [ -n "$slug" ]; then
  slug=$(echo "$slug" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
fi

# Fallback
if [ -z "$slug" ]; then
  slug="screenshot"
fi

# ── Step 5: Build new filename ────────────────────────────────
dir=$(dirname "$inputFile")
newFile="$dir/${datePrefix}-${slug}.${ext}"

counter=1
while [ -f "$newFile" ]; do
  newFile="$dir/${datePrefix}-${slug}-${counter}.${ext}"
  ((counter++))
done

# ── Step 6: Rename ────────────────────────────────────────────
mv "$inputFile" "$newFile"

# ── Step 7: Log ───────────────────────────────────────────────
echo "$datePrefix" >> "$LOG_FILE"

echo "Renamed: $(basename "$newFile")"