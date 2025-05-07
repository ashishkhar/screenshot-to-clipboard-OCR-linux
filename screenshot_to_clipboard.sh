#!/bin/bash

# Terminal Text Optimized OCR Script
# Specialized for capturing terminal output, error messages, and code on dark backgrounds

# --- Configuration ---
# OCR Language (install tesseract-ocr-<lang>)
OCR_LANG="eng"

# Base DPI for Tesseract
TESS_DPI="300"

# Tesseract OCR Engine Mode (OEM):
# 0 = Original Tesseract only.
# 1 = Neural nets LSTM only.
# 2 = Original + LSTM.
# 3 = Default, based on what is available.
TESS_OEM="1"

# Tesseract Page Segmentation Mode (PSM):
# 6 = Assume a single uniform block of text. (Good for terminal output)
# 4 = Assume a single column of text of variable sizes. (Sometimes better for complex layouts or code blocks)
TESS_PSM_STANDARD="6"
TESS_PSM_BINARY="4" # Using 4 for binary might help with disjoint characters

# --- Setup ---
# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Create a temporary directory and ensure it's cleaned up on exit or error
TMPDIR=$(mktemp -d)
SCREENSHOT="$TMPDIR/screenshot.png"
OUTPUT_FILE="$TMPDIR/output.txt"

# Function to clean up the temporary directory
cleanup() {
  echo "Cleaning up temporary directory: $TMPDIR"
  rm -rf "$TMPDIR"
}

# Register the cleanup function to be called on EXIT, HUP, INT, TERM
trap cleanup EXIT HUP INT TERM

echo "Using temporary directory: $TMPDIR"

# --- Check dependencies ---
check_dependencies() {
  local missing_cmds=()
  local install_cmds=()
  for cmd in gnome-screenshot convert tesseract identify xclip bc; do
    if ! command -v "$cmd" &> /dev/null; then
      missing_cmds+=("$cmd")
      case "$cmd" in
        gnome-screenshot) install_cmds+=("gnome-screenshot") ;;
        convert|identify) install_cmds+=("imagemagick") ;;
        tesseract) install_cmds+=("tesseract-ocr") ;;
        xclip) install_cmds+=("xclip") ;;
        bc) install_cmds+=("bc") ;;
      esac
    fi
  done

  if [ ${#missing_cmds[@]} -ne 0 ]; then
    echo "ERROR: Required commands not found:" >&2
    printf " - %s\n" "${missing_cmds[@]}" >&2
    # Suggest a common install command if running on Debian/Ubuntu
    if command -v apt-get &> /dev/null; then
       echo "You might be able to install them using: sudo apt-get update && sudo apt-get install ${install_cmds[*]} tesseract-ocr-${OCR_LANG:-eng}" >&2
    # Add more package managers if needed (e.g., yum, dnf, pacman, brew)
    fi
    exit 1
  fi
}

check_dependencies

# --- Take screenshot ---
echo "Select area containing terminal/code text to capture..."
# Use -w for wait mode, robust error check on exit status
if ! gnome-screenshot -a -f "$SCREENSHOT" ; then
  echo "ERROR: Screenshot failed or cancelled." >&2
  exit 1
fi

if [ ! -s "$SCREENSHOT" ]; then
  echo "ERROR: Screenshot file is empty or creation failed after wait." >&2
  exit 1
fi

# --- Analyze image to detect background type ---
echo "Analyzing terminal background..."

# Check if dark or light background by getting average brightness
# Add error handling for convert and bc
BRIGHTNESS=$(convert "$SCREENSHOT" -colorspace Gray -format "%[fx:mean*100]" info: 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$BRIGHTNESS" ]; then
  echo "WARNING: Could not determine image brightness. Assuming dark background for processing." >&2
  IS_DARK=true
else
  # Use printf for potential float issues with bc, or ensure bc output is integer
  # Adding a simple check against 50 is usually sufficient for mean*100
  IS_DARK=false
  if (( $(echo "$BRIGHTNESS < 50" | bc -l) )); then
    IS_DARK=true
  fi
fi

if [ "$IS_DARK" = "true" ]; then
  echo "Dark background detected"
else
  echo "Light background detected"
fi

# --- Create optimized versions for terminal text ---
echo "Creating optimized image versions..."

# Base ImageMagick command: convert input -> common preprocessing
# COMMON_PREP will be built conditionally
COMMON_PREP_OPS=("-colorspace" "Gray")

# Conditional negation for dark backgrounds
if [ "$IS_DARK" = "true" ]; then
  COMMON_PREP_OPS=("-negate" "${COMMON_PREP_OPS[@]}")
fi

# Function to apply common prep and save
prepare_image() {
  local input_file="$1"
  local output_file="$2"
  # All subsequent arguments are considered extra_ops
  shift 2
  local extra_ops=("$@") # Capture remaining args as an array

  echo "Processing: $output_file"
  # Combine operations into a single convert command for efficiency
  if ! convert "$input_file" "${COMMON_PREP_OPS[@]}" "${extra_ops[@]}" "$output_file"; then
      echo "WARNING: ImageMagick 'convert' failed for $output_file" >&2
      # Optionally, decide if this is a fatal error or if you can continue
  fi
}

# Version 1: Standard processing
prepare_image "$SCREENSHOT" "$TMPDIR/terminal_standard.png" -normalize -sharpen 0x1

# Version 2: Enhanced monospace processing (often needs higher resolution)
# Level adjustment to increase contrast, morphology for thinning, resize, sharpen
prepare_image "$SCREENSHOT" "$TMPDIR/terminal_enhanced.png" -level 10%,90% -define morphology:compose=darken -morphology Thinning Rectangle:1x1 -resize 200% -sharpen 0x1

# Version 3: High-contrast terminal mode (different leveling/sharpening)
prepare_image "$SCREENSHOT" "$TMPDIR/terminal_contrast.png" -level 15%,85% -sharpen 0x1.5 -resize 150%

# Version 4: Binary mode (thresholding)
# Threshold value is crucial and can depend on brightness - 75% for dark (after negate), 50% for light
THRESHOLD_VAL="50%"
if [ "$IS_DARK" = "true" ]; then
  THRESHOLD_VAL="75%" # Applied after -negate
fi
prepare_image "$SCREENSHOT" "$TMPDIR/terminal_binary.png" -threshold "$THRESHOLD_VAL" -morphology Open Rectangle:1x1


# --- Run OCR with terminal-optimized settings ---
echo "Running OCR on optimized images..."

# Function to run OCR with specific settings and input
# Returns 0 on success, 1 on failure
run_ocr() {
  local input_file=$1
  local output_base=$2
  local custom_settings=$3

  echo " Running Tesseract on $input_file -> ${output_base}.txt"

  # Explicitly name output file and check exit status
  if ! tesseract "$input_file" "$output_base" \
     --oem "$TESS_OEM" --psm "$TESS_PSM_STANDARD" -l "$OCR_LANG" \
     -c preserve_interword_spaces=1 \
     $custom_settings &> /dev/null; then # Suppress Tesseract's own output
    echo " WARNING: Tesseract failed for $input_file" >&2
    return 1
  fi

  # Check if output file was actually created and is not empty
  if [ ! -s "${output_base}.txt" ]; then
    echo " WARNING: Tesseract output file ${output_base}.txt is empty or missing." >&2
    return 1
  fi

  return 0
}

# Run multiple OCR passes with different settings
# Store results in separate files
OCR_RESULTS=() # Array to store successfully created output files

# Pass 1: Standard with character whitelist
# Whitelist common terminal characters, including spaces and special symbols
if run_ocr "$TMPDIR/terminal_standard.png" "$TMPDIR/result1" "-c tessedit_char_whitelist='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.:=/\\\"\'(){}[]<>+*&^%$#@!~\`|, ;!@#$%^&*()_+{}[]|\\:;\"'<>,.?/'"; then
  OCR_RESULTS+=("$TMPDIR/result1.txt")
fi

# Pass 2: Enhanced with higher DPI and line size adjustment
if run_ocr "$TMPDIR/terminal_enhanced.png" "$TMPDIR/result2" "--dpi $TESS_DPI -c textord_min_linesize=1"; then
   OCR_RESULTS+=("$TMPDIR/result2.txt")
fi

# Pass 3: High-contrast with higher DPI
if run_ocr "$TMPDIR/terminal_contrast.png" "$TMPDIR/result3" "--dpi $TESS_DPI"; then
   OCR_RESULTS+=("$TMPDIR/result3.txt")
fi

# Pass 4: Binary with higher DPI and potentially different PSM
if run_ocr "$TMPDIR/terminal_binary.png" "$TMPDIR/result4" "--dpi $TESS_DPI --psm $TESS_PSM_BINARY"; then
   OCR_RESULTS+=("$TMPDIR/result4.txt")
fi

# Check if any OCR result was successful
if [ ${#OCR_RESULTS[@]} -eq 0 ]; then
  echo "ERROR: All OCR passes failed or produced empty results." >&2
  exit 1
fi

# --- Select best result based on terminal-specific scoring ---
echo "Evaluating results for terminal text..."

score_result() {
  local result_file="$1"
  local current_score=0 # Renamed to avoid conflict with outer scope 'score' if it existed

  if [ ! -s "$result_file" ]; then
      echo 0 # Return 0 for empty or missing files
      return
  fi

  local content
  content=$(cat "$result_file")

  # Detect terminal-specific patterns (paths, commands, errors)
  if echo "$content" | grep -q -E '/|error|fail|Traceback|File:|line \d|import'; then
    current_score=$((current_score + 20)) # Increased weight for strong indicators
  fi

  # Check for common terminal symbols
  if echo "$content" | grep -q -E ':|>|#|\$|%|=|&|~|`'; then
    current_score=$((current_score + 10)) # Increased weight
  fi

  # Word count with bias toward complete content
  # Using echo + wc -w is safer for files with odd characters
  local wc=$(echo "$content" | wc -w)
  current_score=$((current_score + (wc / 10))) # Adjusting weight

  # Penalize common garbage text
  if echo "$content" | grep -q -E "����|■|□|�"; then
    current_score=$((current_score - 20)) # Increased penalty
  fi

  # Bonus for containing common shell prompts (simple regex)
  if echo "$content" | grep -q -E '\[.*?@.*? .*?\][\$#%]'; then
      current_score=$((current_score + 15))
  fi

  echo $current_score
}

# Calculate scores for successful results
declare -A SCORES # Associative array to store scores by filename
BEST_SCORE=-1     # Initialize with a very low score
BEST_RESULT=""

echo "--- Scores ---"
for result_file in "${OCR_RESULTS[@]}"; do
    # 'score' here is a regular variable, not local to a function
    score=$(score_result "$result_file")
    SCORES["$result_file"]=$score
    echo "$(basename "$result_file"): $score"

    if [ "$score" -gt "$BEST_SCORE" ]; then
        BEST_SCORE="$score"
        BEST_RESULT="$result_file"
    fi
done
echo "--------------"

# Fallback if somehow no best result was found (shouldn't happen with the initial check)
if [ -z "$BEST_RESULT" ]; then
    echo "ERROR: Could not determine the best OCR result." >&2
    exit 1
fi

echo "Selected best result: $(basename "$BEST_RESULT") with score $BEST_SCORE"
cp "$BEST_RESULT" "$OUTPUT_FILE"

# --- Terminal-specific post-processing ---
echo "Applying terminal-specific post-processing..."

# Use a single sed command with multiple expressions for efficiency
# Add more common terminal/code fixes
sed -i -E \
  -e 's/[l1]lama/llama/gi' \
  -e 's/Il/ll/g' \
  -e 's/([0-9])l/\11/g' \
  -e 's/0O/00/g' -e 's/O0/00/g' \
  -e 's/\bD:/d:/g' \
  -e 's/--/-/g' \
  -e 's/\s+/ /g' \
  -e 's/^([a-zA-Z0-9_]+)\s*:\s*/\1:/g' \
  -e 's/»>/>>/g' -e 's/«</<</g' \
  -e 's/\bimporc\b/import/g' \
  -e 's/\bciass\b/class/g' \
  -e 's/\bdeF\b/def/g' \
  -e 's/\bprin\b/print/g' \
  -e 's/\bfunc\b/func/g' \
  -e 's/\blet\b/let/g' \
  -e 's/\bvar\b/var/g' \
  -e 's/\bcats\b/cats/g' \
  -e 's/\bpip\b/pip/g' \
  -e 's|usr/1ib|usr/lib|g' \
  -e 's|/etc/1ib|/etc/lib|g' \
  -e 's|site-packaqes|site-packages|g' \
  -e 's|site-packages|site-packages|g' \
  -e 's|bin/basn|bin/bash|g' \
  -e 's|/home/[a-zA-Z0-9_]+/|~/|g' \
  -e 's|sudo[o0]|sudo|g' \
  -e 's/=[ =]+/=/g' \
  -e 's/\[ \]/[]/g' \
  -e 's/\{ \}/{}/g' \
  -e 's/ < >/<>/g' \
  -e 's/ :/:/g' \
  -e 's/ ;/;/g' \
  -e 's/ ,/,/g' \
  "$OUTPUT_FILE"

# --- Copy to clipboard ---
echo "Copying text to clipboard..."
if ! cat "$OUTPUT_FILE" | xclip -selection clipboard; then
  echo "WARNING: Failed to copy text to clipboard using xclip." >&2
fi

# Display preview
echo ""
echo "===== TERMINAL OCR RESULT ====="
cat "$OUTPUT_FILE"
echo "==============================="
echo "" # Add newline for cleaner output

# --- Show visual notification on screen ---
# Check availability in preferred order
NOTIFICATION_SENT=false
if command -v notify-send &> /dev/null; then
  notify-send "Terminal OCR Complete" "Text copied to clipboard" --icon=edit-copy
  NOTIFICATION_SENT=true
elif command -v zenity &> /dev/null; then
  zenity --info --title="OCR Complete" --text="Text copied to clipboard" --timeout=2 &
  NOTIFICATION_SENT=true
elif command -v xmessage &> /dev/null; then
  xmessage -center "Text copied to clipboard" -timeout 2 &
  NOTIFICATION_SENT=true
fi

if [ "$NOTIFICATION_SENT" = false ]; then
    echo "Note: Notification tools (notify-send, zenity, xmessage) not found. Cannot show visual notification."
fi

# Cleanup is handled by the trap function automatically on script exit

echo "Done! Terminal text has been copied to clipboard."
exit 0