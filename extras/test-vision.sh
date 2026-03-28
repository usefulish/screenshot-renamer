#!/bin/bash
# ─────────────────────────────────────────────────────────────
# extras/test-vision.sh
# Sends an image to the AI vision API at multiple resolutions
# and prints the slug generated at each size.
# Use this to find the right MAX_IMAGE_PX for your use case.
#
# Usage: ./extras/test-vision.sh path/to/screenshot.png
#
# Finding: 300px is the sweet spot for most screenshots —
# large enough to read UI elements, small enough to be fast.
# Going higher rarely improves slug quality.
# ─────────────────────────────────────────────────────────────

source "$HOME/.screenshot-rename.env"
API_KEY="$ANTHROPIC_API_KEY"
API_ENDPOINT="https://api.anthropic.com/v1/chat/completions"
MODEL="claude-haiku-4-5-20251001"

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
  *)        mediaType="image/png" ;;
esac

PROMPT="Describe this screenshot in 3-6 words suitable for a filename slug. Focus on the main subject, colors, and composition. Lowercase, hyphens only, no punctuation, no extension, no explanation. Examples: brown-horse-white-background, aerial-city-night-view, red-sports-car-road. Reply with only the slug."

echo "─────────────────────────────────────"
echo "File:     $(basename "$inputFile")"
echo "Original: $(sips -g pixelWidth -g pixelHeight "$inputFile" 2>/dev/null | grep -E 'pixelWidth|pixelHeight' | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')px"
echo "Model:    $MODEL"
echo "─────────────────────────────────────"
echo ""

call_api() {
  local size="$1"
  local tmpImg tmpB64 tmpReq response slug elapsed

  tmpImg=$(mktemp "$HOME/.cache/test-resize-XXXXXX.png")
  tmpB64=$(mktemp "$HOME/.cache/test-b64-XXXXXX.txt")
  tmpReq=$(mktemp "$HOME/.cache/test-req-XXXXXX.json")

  sips -Z "$size" "$inputFile" --out "$tmpImg" &>/dev/null
  base64 -i "$tmpImg" > "$tmpB64"

  jq -n \
    --arg model "$MODEL" \
    --arg mediaType "$mediaType" \
    --rawfile imageData "$tmpB64" \
    --arg prompt "$PROMPT" \
    '{
      model: $model,
      max_tokens: 64,
      messages: [{
        role: "user",
        content: [
          { type: "image_url", image_url: { url: ("data:" + $mediaType + ";base64," + ($imageData | rtrimstr("\n"))) } },
          { type: "text", text: $prompt }
        ]
      }]
    }' > "$tmpReq"

  local start=$SECONDS
  response=$(curl -s "$API_ENDPOINT" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d "@$tmpReq")
  elapsed=$((SECONDS - start))

  slug=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  slug=$(echo "$slug" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

  local b64size
  b64size=$(wc -c < "$tmpB64" | tr -d ' ')

  rm -f "$tmpImg" "$tmpB64" "$tmpReq"

  printf "  %-6s px  |  payload: %5s KB  |  %2ss  |  %s\n" \
    "$size" \
    "$((b64size / 1024))" \
    "$elapsed" \
    "${slug:-[no response]}"
}

echo "  Size      |  Payload         |  Time  |  Slug"
echo "  ──────────┼──────────────────┼────────┼───────────────────────────"

for size in 100 200 300 400 600; do
  call_api "$size"
done

echo ""
echo "─────────────────────────────────────"
echo "Tip: 300px is the recommended default. Higher resolutions"
echo "rarely improve slug quality but increase payload size and cost."
