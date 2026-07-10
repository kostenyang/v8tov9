#!/bin/sh
for b in /bootbank /altbootbank; do
  f=$b/boot.cfg
  [ -f "$f" ] || continue
  echo "=== $f BEFORE ==="
  grep -E "^(kernelopt|bootstate|updated)" "$f"
  if ! grep -q allowLegacyCPU "$f"; then
    sed -i "s|^kernelopt=.*|& allowLegacyCPU=TRUE|" "$f"
  fi
  echo "=== $f AFTER ==="
  grep -E "^(kernelopt|bootstate|updated)" "$f"
done
