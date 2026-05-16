#!/usr/bin/env bash
# fix-pc-prefix.sh — Make pkg-config .pc files relocatable after cmake --install
#
# cmake --install bakes CMAKE_INSTALL_PREFIX into prefix=, exec_prefix=,
# libdir=, and includedir= as absolute paths. This script replaces all of
# them with ${prefix}-relative and ${pcfiledir}-relative forms so the
# resulting tarball works when extracted anywhere.
#
# Usage:
#   bash fix-pc-prefix.sh /path/to/staging/root
#
# Run AFTER cmake --install, BEFORE tar packaging.

set -euo pipefail

STAGING="${1:?Usage: $0 <staging-dir>}"

if [ ! -d "$STAGING" ]; then
    echo "ERROR: staging directory not found: $STAGING" >&2
    exit 1
fi

count=0
while IFS= read -r -d '' pcfile; do
    # Get relative path for pcfiledir calculation
    relpath="${pcfile#$STAGING}"
    relpath="${relpath#/}"
    rel=$(dirname "$relpath" | sed 's|[^/]\+|..|g')

    # Extract old prefix (may already be pcfiledir-relative from prior fix)
    old_prefix_line=$(grep '^prefix=' "$pcfile" | head -1)
    old_prefix="${old_prefix_line#prefix=}"

    if [ -z "$old_prefix" ]; then
        echo "  SKIP $pcfile (no prefix line)" >&2
        continue
    fi

    # If prefix is already pcfiledir-relative, find the original hardcoded
    # path from exec_prefix or libdir lines (prior fix only touched prefix=).
    if [[ "$old_prefix" == \$\{pcfiledir\}* ]]; then
        # Try to recover the original install prefix from non-relative lines
        old_prefix=$(grep -E '^(exec_prefix|libdir|includedir)=' "$pcfile" \
            | grep -v '\${prefix}' | grep -v '\${pcfiledir}' \
            | sed 's|^[^=]*=||; s|/lib64.*||; s|/lib/.*||; s|/include.*||; s|/share.*||' \
            | head -1)
        if [ -z "$old_prefix" ]; then
            echo "  SKIP $pcfile (already fully relocatable)" >&2
            continue
        fi
    fi

    # Replace ALL occurrences of the hardcoded install prefix with ${prefix}
    # This handles: prefix=, exec_prefix=, libdir=${prefix}/lib64, includedir=${prefix}/include, etc.
    escaped_prefix=$(printf '%s' "$old_prefix" | sed 's/[\/&]/\\&/g')
    sed -i "s|${escaped_prefix}|\${prefix}|g" "$pcfile"

    # Now set prefix=${pcfiledir}/relative/path
    sed -i "s|^prefix=.*|prefix=\${pcfiledir}/${rel}|" "$pcfile"

    echo "  FIXED $pcfile" >&2
    echo "    install prefix: $old_prefix" >&2
    echo "    pcfiledir rel:  ${rel}" >&2
    ((count++)) || true
done < <(find "$STAGING" -name '*.pc' -print0)

echo "Fixed $count .pc file(s) in $STAGING" >&2
