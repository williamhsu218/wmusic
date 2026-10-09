#!/usr/bin/env bash
# embed-deps.sh — post-build/export step: bundle Homebrew dylib dependencies of
# the app's main binary into Contents/Frameworks/, rewrite load commands to
# @rpath, and re-sign the app so it runs on machines without Homebrew.
#
# Run AFTER "xcodebuild -exportArchive" and BEFORE "notarytool submit".
#
# What it does:
#   1. Scans the executable named in Info.plist for any dylib under
#      the Homebrew prefix (/opt/homebrew or /usr/local).
#   2. Copies each such dylib into Contents/Frameworks/, rewrites its own
#      install name to @rpath/<name>, and recursively bundles its own
#      Homebrew dependencies.
#   3. Rewrites every Homebrew-path reference in the main binary to
#      @rpath/<name> so dyld resolves them from Contents/Frameworks/.
#   4. Ensures @executable_path/../Frameworks is in the binary's LC_RPATH.
#   5. Signs everything (Frameworks first, then binary, then app bundle).
#
# Usage:
#   bash Scripts/embed-deps.sh [app-path] [signing-identity]
#   SIGNING_IDENTITY="Developer ID Application: ..." \
#     bash Scripts/embed-deps.sh build/export/Bocan.app

set -euo pipefail

APP="${1:-build/export/Bocan.app}"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || true)"
BINARY="$APP/Contents/MacOS/$EXECUTABLE_NAME"
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${2:-"-"}}"

[[ -d "$APP" ]]    || { echo "ERROR: app not found at $APP";           exit 1; }
[[ -n "$EXECUTABLE_NAME" ]] || { echo "ERROR: CFBundleExecutable is missing"; exit 1; }
[[ -f "$BINARY" ]] || { echo "ERROR: binary not found at $BINARY";     exit 1; }

echo "=== embed-deps: bundling Homebrew dylibs into $(basename "$APP") ==="
echo "    binary    : $BINARY"
echo "    frameworks: $FRAMEWORKS_DIR"
echo "    identity  : $SIGNING_IDENTITY"
echo ""

mkdir -p "$FRAMEWORKS_DIR"

# Preserve the app's original entitlements by default. A local package can
# provide the source plist to omit Xcode's development-only injected keys.
ENTITLEMENTS_FILE="$(mktemp)"
if [[ -n "${SIGNING_ENTITLEMENTS:-}" ]]; then
    cp "$SIGNING_ENTITLEMENTS" "$ENTITLEMENTS_FILE"
else
    codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS_FILE" 2>/dev/null
fi
plutil -lint "$ENTITLEMENTS_FILE" >/dev/null

# Temp file tracking which source owns each bundled dylib basename.
SEEN_FILE="$(mktemp)"
trap 'rm -f "$SEEN_FILE" "$ENTITLEMENTS_FILE"' EXIT

# ── helpers ───────────────────────────────────────────────────────────────────

is_system_path() {
    local p="$1"
    [[ "$p" == /usr/lib/*             ]] && return 0
    [[ "$p" == /System/*              ]] && return 0
    [[ "$p" == @rpath/*               ]] && return 0
    [[ "$p" == @loader_path/*         ]] && return 0
    [[ "$p" == @executable_path/*     ]] && return 0
    return 1
}

is_homebrew_path() {
    local p="$1"
    [[ "$p" == /opt/homebrew/* ]] && return 0
    [[ "$p" == /usr/local/*    ]] && return 0
    return 1
}

already_seen() {
    local name="$1" source="$2" previous
    previous="$(awk -F '\t' -v name="$name" '$1 == name {print $2; exit}' "$SEEN_FILE")"
    [[ -n "$previous" ]] || return 1
    if [[ "$previous" != "$source" ]]; then
        echo "ERROR: two different dylibs share the filename $name" >&2
        echo "  first: $previous" >&2
        echo "  next:  $source" >&2
        exit 1
    fi
    return 0
}
mark_seen() { printf '%s\t%s\n' "$1" "$2" >> "$SEEN_FILE"; }

# bundle_dep <src-path>
#   Copies a Homebrew dylib into Frameworks/, rewrites its own install name to
#   @rpath/<name>, rewrites all its Homebrew dep references, then recurses.
bundle_dep() {
    local src="$1"
    local name
    name="$(basename "$src")"
    local canonical_source
    canonical_source="$(realpath "$src")"

    already_seen "$name" "$canonical_source" && return 0
    mark_seen "$name" "$canonical_source"

    local dst="$FRAMEWORKS_DIR/$name"
    echo "  bundle  $name"
    # -L dereferences symlinks so we copy the real file, not a symlink.
    cp -L "$src" "$dst"
    chmod 755 "$dst"

    # Rewrite this dylib's own install name.
    local own_id
    own_id="$(otool -D "$dst" 2>/dev/null | tail -1)"
    if [[ -n "$own_id" && "$own_id" != "@rpath/$name" ]]; then
        install_name_tool -id "@rpath/$name" "$dst"
    fi

    # Rewrite all Homebrew-path references inside this dylib to @rpath/<name>.
    while IFS= read -r dep; do
        is_system_path "$dep"   && continue
        is_homebrew_path "$dep" || continue
        local dep_name
        dep_name="$(basename "$dep")"
        install_name_tool -change "$dep" "@rpath/$dep_name" "$dst"
    done < <(otool -L "$dst" 2>/dev/null | awk 'NR>1{print $1}')

    # Recurse: bundle any Homebrew libs this lib itself depends on.
    # Re-read from $src so we follow the original paths (not the rewritten ones).
    while IFS= read -r dep; do
        is_system_path "$dep"   && continue
        is_homebrew_path "$dep" || continue
        bundle_dep "$dep"
    done < <(otool -L "$src" 2>/dev/null | awk 'NR>1{print $1}')
}

# ── scan and bundle main binary's Homebrew deps ───────────────────────────────

echo "--- scanning main binary for Homebrew deps ---"
while IFS= read -r dep; do
    is_system_path "$dep"   && continue
    is_homebrew_path "$dep" || continue
    dep_name="$(basename "$dep")"
    echo "  found: $dep"

    # Rewrite the reference in the main binary to @rpath/<name>.
    install_name_tool -change "$dep" "@rpath/$dep_name" "$BINARY"

    # Bundle the dylib and its transitive Homebrew deps.
    bundle_dep "$dep"
done < <(otool -L "$BINARY" 2>/dev/null | awk 'NR>1{print $1}')

# ── fix @rpath references inside bundled dylibs ───────────────────────────────
# Some dylibs reference their own deps via @rpath (not absolute paths), which
# the loop above doesn't catch.  Sweep all bundled dylibs and fix any @rpath
# entries that resolve to a file we placed in Frameworks/.

echo ""
echo "--- fixing @rpath references inside bundled dylibs ---"
for f in "$FRAMEWORKS_DIR"/*.dylib; do
    [[ -f "$f" ]] || continue
    while IFS= read -r dep; do
        [[ "$dep" == @rpath/* ]] || continue
        dep_name="${dep#@rpath/}"
        # Only rewrite if the dylib actually exists in Frameworks/ to avoid
        # clobbering intentional @rpath entries that need the system linker.
        [[ -f "$FRAMEWORKS_DIR/$dep_name" ]] || continue
        install_name_tool -change "$dep" "@rpath/$dep_name" "$f" 2>/dev/null || true
    done < <(otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}')

    # Strip machine-specific absolute LC_RPATH entries.
    while IFS= read -r rp; do
        [[ "$rp" == /* ]] || continue
        [[ "$rp" == /usr/lib/* || "$rp" == /System/* ]] && continue
        install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null || true
    done < <(otool -l "$f" 2>/dev/null \
        | awk '/cmd LC_RPATH/{found=1} found && /path /{print $2; found=0}')
done

# Build-product paths are also machine-specific, even when they are not used
# by the current set of linked libraries.
while IFS= read -r rp; do
    [[ "$rp" == /* ]] || continue
    [[ "$rp" == /usr/lib/* || "$rp" == /System/* ]] && continue
    install_name_tool -delete_rpath "$rp" "$BINARY"
done < <(otool -l "$BINARY" 2>/dev/null \
    | awk '/cmd LC_RPATH/{found=1} found && /path /{print $2; found=0}')

# ── ensure @executable_path/../Frameworks is in the binary's rpath ────────────

if ! otool -l "$BINARY" 2>/dev/null \
        | awk '/cmd LC_RPATH/{found=1} found && /path /{print $2; found=0}' \
        | grep -qxF "@executable_path/../Frameworks"; then
    echo ""
    echo "--- adding @executable_path/../Frameworks to binary rpath ---"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY"
fi

# ── sign everything (inside-out) ──────────────────────────────────────────────

echo ""
echo "--- signing (identity: $SIGNING_IDENTITY) ---"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    CS_ARGS=(--force --sign "$SIGNING_IDENTITY")
else
    CS_ARGS=(--force --sign "$SIGNING_IDENTITY" --options runtime --timestamp)
fi

# 1. Sign each bundled dylib.
for f in "$FRAMEWORKS_DIR"/*.dylib; do
    [[ -f "$f" ]] || continue
    echo "  sign  $(basename "$f")"
    codesign "${CS_ARGS[@]}" "$f"
done

# 2. Sign the bundled fpcalc helper and its libraries as separate code objects.
for f in "$APP/Contents/Resources/fpcalc" "$APP/Contents/Resources"/*.dylib; do
    [[ -f "$f" ]] || continue
    echo "  sign  $(basename "$f")"
    codesign "${CS_ARGS[@]}" "$f"
done

# 3. Re-sign the main binary (install_name_tool changes invalidated the sig).
echo "  sign  $(basename "$BINARY")"
codesign "${CS_ARGS[@]}" "$BINARY"

# 4. Re-sign the app bundle (regenerates CodeResources to include new Frameworks/).
echo "  sign  $(basename "$APP")"
codesign "${CS_ARGS[@]}" --entitlements "$ENTITLEMENTS_FILE" "$APP"

echo ""
echo "=== embed-deps: done ==="
