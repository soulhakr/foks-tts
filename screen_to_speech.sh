#!/bin/zsh
# Usage: screen_to_speech.sh <image> [vlm|vision]   OCR (local VLM or Apple Vision), then Kokoro speech; fully offline.
export HF_HUB_OFFLINE=1
HERE=${0:A:h}; IMG=${1:?image path}; ENGINE=${2:-vlm}
if [[ $ENGINE == vision ]]; then
  TEXT=$(swift "$HERE/vision_ocr.swift" "$IMG")
else
  TEXT=$($HOME/AI/mlx-env/bin/mlx_vlm.generate --model $HOME/AI/gemma3 --image "$IMG" --max-tokens 700 --temperature 0 \
    --prompt "Transcribe the main readable text in this image exactly as written, in reading order. Output only the text." 2>/dev/null \
    | awk '/<start_of_turn>model/{f=1;next} /^==========$/{if(f)exit} f')
fi
echo "OCR ($ENGINE): $(printf '%s' "$TEXT" | tr '\n' ' ' | cut -c1-200)..."
printf '%s' "$TEXT" | $HOME/AI/mlx-env/bin/python "$HERE/speak.py" "${IMG:r}_speech.wav"
[[ -n $PLAY ]] && afplay "${IMG:r}_speech.wav"
