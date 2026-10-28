#!/bin/bash
# Usage: tools/render.sh [--seq]  -> headless check, final still (+wrap still), optional sequence
cd "$(dirname "$0")/.."
GODOT="/c/Users/Loadcomplete/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
timeout 60 "$GODOT" --headless --path . --quit-after 3 2>&1 | grep -iE "error" | head
timeout 90 "$GODOT" --path . --resolution 1536x1024 -- --shot=screenshots/final.png --frames=40 --phase=0.0 2>&1 | grep -iE "error|saved"
if [ "$1" == "--seq" ]; then
  timeout 90 "$GODOT" --path . --resolution 1536x1024 -- --shot=screenshots/final_wrap.png --frames=40 --phase=0.9999 2>&1 | grep -iE "error|saved"
  rm -rf screenshots/seq
  timeout 200 "$GODOT" --path . --resolution 1536x1024 -- --seq=screenshots/seq:45:12 2>&1 | grep -iE "error|saved"
fi
