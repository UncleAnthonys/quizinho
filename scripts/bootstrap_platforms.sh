#!/usr/bin/env bash
# Generates the ios/ and android/ folders with `flutter create` if they are
# missing, then applies Quizinho's settings to them. Safe to run repeatedly:
# flutter create never overwrites existing files, and the patch is idempotent.
#
# Runs in CI (GitHub Actions / Codemagic) so you never need Xcode locally.
set -euo pipefail

ORG="${ORG:-com.littlefortstudios}"

if [ ! -d ios ] || [ ! -d android ] || [ ! -d web ]; then
  echo "Generating platform folders (org: $ORG)…"
  flutter create . --org "$ORG" --project-name quizinho --platforms ios,android,web --no-pub
else
  echo "Platform folders already present."
fi

python3 scripts/patch_platforms.py
