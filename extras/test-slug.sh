#!/bin/bash
# ─────────────────────────────────────────────────────────────
# extras/test-slug.sh
# Sends text directly to the API and prints the generated slug.
# Use this to tune the slug prompt without needing a real image.
# Pipe in OCR output or type text directly.
#
# Usage:
#   ./extras/test-slug.sh "some text from a screenshot"
#   echo "Slack error: invalid token" | ./extras/test-slug.sh
# ─────────────────────────────────────────────────────────────

source "$HOME/.screenshot-rename.env"
API_KEY="$ANTHROPIC_API_KEY"
API_ENDPOINT="https://api.anthropic.com/v1/chat/completions"
MODEL="claude-haiku-4-5-20251001"

# Uncomment to test with a different provider:
# API_KEY="$OPENAI_API_KEY"
# API_ENDPOINT="https://api.openai.com/v1/chat/completions"
# MODEL="gpt-4o-mini"

# ── Get input text ────────────────────────────────────────────
if [ -n "$1" ]; then
  inputText="$1"
elif [ ! -t 0 ]; then
  inputText=$(cat)
else
  echo "Usage: $0 \"text from screenshot\""
  echo "       echo \"some text\" | $0"
  exit 1
fi

if [ -z "$inputText" ]; then
  echo "Error: no input text provided"
  exit 1
fi

# ── Current prompt (matches main script) ─────────────────────
PROMPT="Based on this text from a screenshot, generate a filename slug in 3-6 words. Lowercase, hyphens only, no punctuation, no extension, no explanation. Examples: slack-error-message-login, figma-export-settings, terminal-docker-build. Reply with only the slug.\n\nText:\n${inputText:0:500}"

echo "─────────────────────────────────────"
echo "Model:  $MODEL"
echo "Input:  ${inputText:0:120}$([ ${#inputText} -gt 120 ] && echo '…')"
echo "─────────────────────────────────────"
echo ""

tmpReq=$(mktemp "$HOME/.cache/test-slug-XXXXXX.json")

jq -n \
  --arg model "$MODEL" \
  --arg prompt "$PROMPT" \
  '{
    model: $model,
    max_tokens: 64,
    messages: [{ role: "user", content: $prompt }]
  }' > "$tmpReq"

response=$(curl -s "$API_ENDPOINT" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "@$tmpReq")

rm -f "$tmpReq"

slug=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
slug=$(echo "$slug" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

if [ -z "$slug" ]; then
  echo "Result:  [no response]"
  echo ""
  echo "Raw API response:"
  echo "$response" | jq '.' 2>/dev/null || echo "$response"
else
  echo "Slug:    $slug"
  echo ""
  echo "→ Final filename would be: $(date +%Y-%m-%d)-${slug}.png"
fi

echo ""
echo "─────────────────────────────────────"
echo "Tip: edit the PROMPT variable in this script to test"
echo "different wording. Paste the winning prompt into the"
echo "main script when you find something better."
