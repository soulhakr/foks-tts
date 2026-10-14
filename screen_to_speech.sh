#!/bin/zsh
# Usage: screen_to_speech.sh <image> [vlm|vision]   OCR (local VLM or Apple Vision), then Kokoro speech; fully offline.
# Speech uses the FOKS TTS venv (see install.sh). The vlm engine also needs mlx-vlm, which that venv does not
# include: set OCR_MODEL to a local vision model directory, and MLX_VLM_BIN to the bin dir of a venv that has
# mlx-vlm (or have mlx_vlm.generate on PATH).
export HF_HUB_OFFLINE=1
HERE=${0:A:h}; IMG=${1:?image path}; ENGINE=${2:-vlm}
PY="${FOKS_TTS_HOME:-$HOME/Library/Application Support/FOKS-TTS}/venv/bin/python"
if [[ $ENGINE == vision ]]; then
  TEXT=$(swift "$HERE/vision_ocr.swift" "$IMG")
else
  : ${OCR_MODEL:?set OCR_MODEL to a local vision model directory (or use the vision engine)}
  TEXT=$("${MLX_VLM_BIN:+$MLX_VLM_BIN/}mlx_vlm.generate" --model "$OCR_MODEL" --image "$IMG" --max-tokens 700 --temperature 0 \
    --prompt "Transcribe the main readable text in this image exactly as written, in reading order. Output only the text." 2>/dev/null \
    | awk '/<start_of_turn>model/{f=1;next} /^==========$/{if(f)exit} f')
fi
echo "OCR ($ENGINE): $(printf '%s' "$TEXT" | tr '\n' ' ' | cut -c1-200)..."
printf '%s' "$TEXT" | "$PY" "$HERE/speak.py" "${IMG:r}_speech.wav"
[[ -n $PLAY ]] && afplay "${IMG:r}_speech.wav"
