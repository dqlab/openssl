#!/usr/bin/env bash
# fix-pc-prefix.sh — Make pkg-config .pc files relocatable after cmake --install
#
# Problem: cmake --install bakes the absolute CMAKE_INSTALL_PREFIX into every
# .pc file's "prefix=" line. When the tarball is extracted to a different path
# on another machine, pkg-config returns wrong -I and -L flags.
#
# Fix: Replace hardcoded prefix with ${pcfiledir}/../.. which pkg-config resolves
# at runtime relative to the .pc file's actual location on disk.
#
# Usage:
#   bash fix-pc-prefix.sh /path/to/staging/root
#
# Run this AFTER cmake --install and BEFORE tar packaging.

set -euo pipefail

STAGING="${1:?Usage: $0 <staging-dir>}"

if [ ! -d "$STAGING" ]; then
    echo "ERROR: staging directory not found: $STAGING" >&2
    exit 1
fi

count=0
while IFS= read -r -d '' pcfile; do
    # Strip the staging prefix to get the relative path
    relpath="${pcfile#$STAGING}"
    relpath="${relpath#/}"

    # Compute relative levels from .pc to install root
    # e.g. lib64/pkgconfig/foo.pc → ../../..
    #      lib/pkgconfig/foo.pc   → ../../..
    #      share/pkgconfig/foo.pc → ../../..
    rel=$(dirname "$relpath" | sed 's|[^/]\+|..|g')

    old_prefix=$(grep '^prefix=' "$pcfile" | head -1)

    if [ -z "$old_prefix" ]; then
        echo "  SKIP $pcfile (no prefix line)" >&2
        continue
    fi

    sed -i "s|^prefix=.*|prefix=\${pcfiledir}/${rel}|" "$pcfile"
    echo "  FIXED $pcfile" >&2
    echo "    was: $old_prefix" >&2
    echo "    now: prefix=\${pcfiledir}/${rel}" >&2
    ((count++)) || true
done < <(find "$STAGING" -name '*.pc' -print0)

echo "Fixed $count .pc file(s) in $STAGING" >&2
