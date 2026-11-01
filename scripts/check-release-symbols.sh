#!/bin/zsh
# Fails if a build carries any ShotlistKit code. Run it in CI on the app's Release build:
#   scripts/check-release-symbols.sh path/to/MyApp.app
# ShotlistKit, ShotlistProtocol (on iOS), ShotlistDependencies and ShotlistTCA are all inside
# #if DEBUG, and ShotlistMacros declares only the `@Shot` macro, so a Release link should contain
# none of their symbols or type names. A Debug build
# should fail this check, which makes it a useful positive control.
set -euo pipefail
app="${1:?usage: check-release-symbols.sh <App.app or executable>}"
if [[ -d "$app" ]]; then
  name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Info.plist")
  binaries=("$app/$name")
  # Xcode's Debug builds keep the app's code in a separate dylib beside a small stub executable.
  [[ -f "$app/$name.debug.dylib" ]] && binaries+=("$app/$name.debug.dylib")
else
  binaries=("$app")
fi
failed=0
for binary in $binaries; do
  [[ -f "$binary" ]] || { echo "no executable at $binary" >&2; exit 2; }
  # Symbol names only: `nm` without -a leaves out debug-map entries, which hold source and object
  # paths and would match any checkout that happens to live in a folder called Shotlist. Module
  # names, case-sensitive: Swift mangling and Objective-C class names both carry them, and a loose
  # match hits other code ("addSnapshotListener" in Firebase).
  pattern="Shotlist(Kit|Protocol|Dependencies|TCA|Macros)"
  symbols=$(nm -j "$binary" 2>/dev/null | grep -cE "$pattern" || true)
  strings_found=$(strings -a "$binary" | grep -ciE "ShotlistKit|ShotlistURLProtocol|shotlist\.port" || true)
  echo "$binary: $symbols Shotlist symbols, $strings_found Shotlist strings"
  if (( symbols > 0 || strings_found > 0 )); then
    nm -j "$binary" | grep -E "$pattern" | head -5 >&2 || true
    failed=1
  fi
done
if (( failed )); then
  echo "FAIL: ShotlistKit code is present in this build" >&2
  exit 1
fi
echo "OK: no ShotlistKit code"
