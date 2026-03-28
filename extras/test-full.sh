#!/bin/bash
# ─────────────────────────────────────────────────────────────
# extras/test-full.sh
# Dry run of the complete pipeline — prints every step without
# renaming or moving anything. Use this to validate the whole
# chain before deploying, or to debug unexpected slug output.
#
# Usage: ./extras/test-full.sh path/to/screenshot.png
# ─────────────────────────────────────────────────────────────

source "$HOME/.screenshot-rename.env"
API_KEY="$ANTHROPIC_API_KEY"
API_ENDPOINT="https://api.anthropic.com/v1/chat/completions"
MODEL="claude-haiku-4-5-20251001"
MAX_IMAGE_PX=300

# Uncomment to test with a different provider:
# API_KEY="$OPENAI_API_KEY"
# API_ENDPOINT="https://api.openai.com/v1/chat/completions"
# MODEL="gpt-4o-mini"

inputFile="$1"

if [ -z "$inputFile" ]; then
  echo "Usage: $0 <image-file>"
  exit 1
fi

if [ ! -f "$inputFile" ]; then
  echo "Error: file not found: $inputFile"
  exit 1
fi

ext="${inputFile##*.}"
ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
case "$ext" in
  jpg|jpeg) mediaType="image/jpeg" ;;
  png)      mediaType="image/png" ;;
  webp)     mediaType="image/webp" ;;
  gif)      mediaType="image/gif" ;;
  *)        echo "Unsupported file type: $ext" >&2; exit 1 ;;
esac

datePrefix=$(date +"%Y-%m-%d")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DRY RUN — nothing will be renamed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Input:    $(basename "$inputFile")"
echo "Model:    $MODEL"
echo "Max px:   ${MAX_IMAGE_PX}px"
echo ""

# ── Step 1: OCR ───────────────────────────────────────────────
echo "┌─ Step 1: OCR"
ocrStart=$SECONDS

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

ocrElapsed=$((SECONDS - ocrStart))

if [ -n "$ocrText" ] && [ ${#ocrText} -gt 10 ]; then
  echo "│  Status:  text found (${#ocrText} chars, ${ocrElapsed}s)"
  echo "│  Preview: ${ocrText:0:120}$([ ${#ocrText} -gt 120 ] && echo '…')"
  echo "│  Path:    → OCR (no API call needed)"
  useVision=false
else
  echo "│  Status:  no usable text found (${ocrElapsed}s)"
  echo "│  Path:    → vision fallback"
  useVision=true
fi
echo ""

# ── Step 2: Build request ─────────────────────────────────────
echo "┌─ Step 2: API request"
tmpReq=$(mktemp "$HOME/.cache/test-full-req-XXXXXX.json")

if [ "$useVision" = false ]; then
  prompt="Based on this text from a screenshot, generate a filename slug in 3-6 words. Lowercase, hyphens only, no punctuation, no extension, no explanation. Examples: slack-error-message-login, figma-export-settings, terminal-docker-build. Reply with only the slug.\n\nText:\n${ocrText:0:500}"

  jq -n \
    --arg model "$MODEL" \
    --arg prompt "$prompt" \
    '{ model: $model, max_tokens: 64, messages: [{ role: "user", content: $prompt }] }' \
    > "$tmpReq"

  echo "│  Type:    text-only (OCR path)"
  echo "│  Chars:   ${#ocrText} → truncated to 500 for API"
else
  tmpImg=$(mktemp "$HOME/.cache/test-full-img-XXXXXX.png")
  tmpB64=$(mktemp "$HOME/.cache/test-full-b64-XXXXXX.txt")

  sips -Z "$MAX_IMAGE_PX" "$inputFile" --out "$tmpImg" &>/dev/null
  resizedDims=$(sips -g pixelWidth -g pixelHeight "$tmpImg" 2>/dev/null | grep -E 'pixelWidth|pixelHeight' | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')
  base64 -i "$tmpImg" > "$tmpB64"
  b64size=$(wc -c < "$tmpB64" | tr -d ' ')

  prompt="Describe this screenshot in 3-6 words suitable for a filename slug. Focus on the main subject, colors, and composition. Lowercase, hyphens only, no punctuation, no extension, no explanation. Reply with only the slug."

  jq -n \
    --arg model "$MODEL" \
    --arg mediaType "$mediaType" \
    --rawfile imageData "$tmpB64" \
    --arg prompt "$prompt" \
    '{
      model: $model, max_tokens: 64,
      messages: [{ role: "user", content: [
        { type: "image_url", image_url: { url: ("data:" + $mediaType + ";base64," + ($imageData | rtrimstr("\n"))) } },
        { type: "text", text: $prompt }
      ]}]
    }' > "$tmpReq"

  echo "│  Type:    vision (image path)"
  echo "│  Resized: ${resizedDims}px  →  payload: $((b64size / 1024))KB"

  rm -f "$tmpImg" "$tmpB64"
fi
echo ""

# ── Step 3: API call ──────────────────────────────────────────
echo "┌─ Step 3: API call"
apiStart=$SECONDS

response=$(curl -s "$API_ENDPOINT" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "@$tmpReq")

apiElapsed=$((SECONDS - apiStart))
rm -f "$tmpReq"

echo "│  Endpoint: $API_ENDPOINT"
echo "│  Time:     ${apiElapsed}s"

# ── Step 4: Slug extraction ───────────────────────────────────
echo ""
echo "┌─ Step 4: Slug"
rawSlug=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [ -z "$rawSlug" ]; then
  echo "│  Raw:      [empty — API error or quota issue]"
  echo "│  Error:    $(echo "$response" | jq -r '.error.message // "unknown"' 2>/dev/null)"
  slug="screenshot"
else
  slug=$(echo "$rawSlug" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
  echo "│  Raw:      $rawSlug"
  echo "│  Clean:    $slug"
fi

# ── Step 5: Final filename ────────────────────────────────────
echo ""
echo "┌─ Step 5: Result (DRY RUN)"
dir=$(dirname "$inputFile")
newName="${datePrefix}-${slug}.${ext}"
echo "│  Before:  $(basename "$inputFile")"
echo "│  After:   $newName"
echo "│  Would move to: $dir/$newName"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Nothing was renamed. Run the main script to apply."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
