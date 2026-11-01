#!/usr/bin/env bash
# Downloads the same Whisper model the Linux setup uses (small.en, Q5_1, 181 MiB)
# into ~/Library/Application Support/Softly/Models and verifies it.
# Alternatively copy ~/.local/share/voxtype/models/ggml-small.en-q5_1.bin from
# the Linux laptop into that folder.
set -euo pipefail
DIR="$HOME/Library/Application Support/Softly/Models"
FILE="$DIR/ggml-small.en-q5_1.bin"
SHA1="20f54878d608f94e4a8ee3ae56016571d47cba34"
mkdir -p "$DIR"
if [[ ! -f $FILE ]]; then
  curl -fL --progress-bar -o "$FILE.part" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin"
  mv "$FILE.part" "$FILE"
fi
echo "$SHA1  $FILE" | shasum -a 1 -c -
