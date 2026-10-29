#!/bin/bash
# Run the project's Godot binary (shared in ../마녀산장/.tools) from this checkout.
cd "$(dirname "$0")/.."
GODOT="D:/2020_이전승찬파일/작업,내파일/2026/프로토타입 게임/마녀산장/.tools/Godot-4.7.2.exe"
exec "$GODOT" --path . "$@"
