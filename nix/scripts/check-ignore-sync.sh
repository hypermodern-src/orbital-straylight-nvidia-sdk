#!/usr/bin/env bash
# check-ignore-sync.sh — verify autoPatchelfIgnoreMissingDeps and verify-closure
# ignore lists are in sync for every .nix file that uses both.
#
# When a library is ignored by autoPatchelf but not by verify-closure, the build
# will fail at postFixup with a MODE2 dangling error. This script catches the
# mismatch early, at `nix flake check` time.
#
# Usage: check-ignore-sync.sh <root-dir>

set -euo pipefail

root="${1:-.}"
fail=0

# Extract quoted strings from a nix list, handling both single-line and
# multi-line lists. Returns one string per line.
extract_nix_strings() {
  # Match "..." strings, stripping the quotes
  sed -n 's/.*"\([^"]*\)".*/\1/p'
}

for f in "$root"/nix/pkgs/*.nix; do
  [ -f "$f" ] || continue

  # Skip files that don't use both autoPatchelfIgnoreMissingDeps and verify-closure
  grep -q 'autoPatchelfIgnoreMissingDeps' "$f" || continue
  grep -q 'verify-closure' "$f" || continue

  # Extract autoPatchelfIgnoreMissingDeps entries
  ap_ignore=$(
    sed -n '/autoPatchelfIgnoreMissingDeps/,/];/p' "$f" | extract_nix_strings | sort
  )

  # Extract verify-closure ignore entries
  vc_ignore=$(
    sed -n '/verify-closure/,/}}/p' "$f" | sed -n '/ignore/,/];/p' | extract_nix_strings | sort
  )

  # Check that every autoPatchelf entry (minus wildcards) appears in verify-closure
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    # Skip wildcard patterns — they match multiple sonames and are harder to
    # compare literally.
    case "$entry" in *'*'*) continue ;; esac
    if ! echo "$vc_ignore" | grep -qxF "$entry"; then
      echo "MISMATCH: $f — '$entry' in autoPatchelfIgnoreMissingDeps but not in verify-closure ignore" >&2
      fail=1
    fi
  done <<<"$ap_ignore"
done

if [ "$fail" -ne 0 ]; then
  echo "FAIL: autoPatchelfIgnoreMissingDeps and verify-closure ignore lists are out of sync." >&2
  echo "Fix: add the missing entries to the verify-closure ignore list." >&2
  exit 1
fi

echo "OK: autoPatchelfIgnoreMissingDeps and verify-closure ignore lists are in sync."
