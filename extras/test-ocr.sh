#!/bin/bash
# ─────────────────────────────────────────────────────────────
# extras/test-ocr.sh
# Runs macOS Vision OCR on an image and prints the raw result.
# Useful for checking what text the script actually sees before
# deciding whether to use OCR or fall back to vision.
#
# Usage: ./extras/test-ocr.sh path/to/screenshot.png
# ─────────────────────────────────────────────────────────────

inputFile="$1"

if [ -z "$inputFile" ]; then
  echo "Usage: $0 <image-file>"
  exit 1
fi

if [ ! -f "$inputFile" ]; then
  echo "Error: file not found: $inputFile"
  exit 1
fi

echo "─────────────────────────────────────"
echo "File:   $(basename "$inputFile")"
echo "Size:   $(du -h "$inputFile" | cut -f1)"
echo "─────────────────────────────────────"
echo ""
echo "Running Vision OCR..."
echo ""

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
" 2>/dev/null)

if [ -z "$ocrText" ]; then
  echo "Result:  (no text found)"
  echo ""
  echo "→ Script will use the vision fallback for this image."
else
  charCount=${#ocrText}
  echo "Result ($charCount chars):"
  echo ""
  echo "$ocrText"
  echo ""
  if [ "$charCount" -gt 10 ]; then
    echo "→ Script will use OCR path (>10 chars found). No API call needed."
  else
    echo "→ Script will use vision fallback (<10 chars). Too little text to generate a useful slug."
  fi
fi

echo ""
echo "─────────────────────────────────────"
echo "Tip: the 10-char threshold is set in the main script."
echo "Lower it to use OCR on images with very sparse text."
