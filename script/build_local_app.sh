#!/usr/bin/env bash
# Build a self-contained, ad-hoc signed WMusic.app for this Mac or private use.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
player_dir="$root_dir/player"
dist_dir="$root_dir/dist"
derived_data="$player_dir/DerivedData"
built_app="$derived_data/Build/Products/Release/WMusic.app"
final_app="$dist_dir/WMusic.app"
build_log_dir="$root_dir/.build-logs"

for command_name in xcodebuild xcodegen brew otool install_name_tool codesign; do
  command -v "$command_name" >/dev/null || {
    echo "Missing build tool: $command_name" >&2
    exit 1
  }
done

mkdir -p "$build_log_dir" "$dist_dir"
stage_dir="$(mktemp -d "$dist_dir/.wmusic-package.XXXXXX")"
previous_candidate="$stage_dir/previous-candidate.app"
candidate_ready=0
cleanup() {
  if [[ "$candidate_ready" == 0 && -d "$previous_candidate" ]]; then
    [[ ! -e "$final_app" ]] || mv "$final_app" "$stage_dir/failed-candidate.app"
    if ! mv "$previous_candidate" "$final_app"; then
      echo "Could not restore the previous candidate; preserved $stage_dir" >&2
      return
    fi
  fi
  rm -rf "$stage_dir"
}
trap cleanup EXIT
stage_app="$stage_dir/WMusic.app"

if [[ ! -f "$player_dir/Secrets.xcconfig" ]]; then
  cp "$player_dir/Secrets.xcconfig.template" "$player_dir/Secrets.xcconfig"
fi

echo "Preparing bundled audio tools..."
(cd "$player_dir" && bash Scripts/build-fpcalc.sh > "$build_log_dir/wmusic-fpcalc.log" 2>&1)
(cd "$player_dir" && bash Scripts/gen-notices.sh > "$build_log_dir/wmusic-notices.log" 2>&1)
(cd "$player_dir" && xcodegen generate > "$build_log_dir/wmusic-xcodegen.log" 2>&1)

echo "Building Release WMusic.app with ad-hoc signing..."
if ! (cd "$player_dir" && xcodebuild \
  -project Bocan.xcodeproj \
  -scheme Bocan \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  build > "$build_log_dir/wmusic-release-xcodebuild.log" 2>&1); then
  rg -n 'error:|BUILD FAILED|CodeSign' "$build_log_dir/wmusic-release-xcodebuild.log" | tail -30 >&2 || true
  echo "Full build log: $build_log_dir/wmusic-release-xcodebuild.log" >&2
  exit 1
fi

[[ -x "$built_app/Contents/MacOS/WMusic" ]] || {
  echo "Release build did not produce $built_app" >&2
  exit 1
}
if otool -L "$built_app/Contents/MacOS/WMusic" | rg -q 'WMusic\.debug\.dylib'; then
  echo "Release app unexpectedly links the Debug dylib" >&2
  exit 1
fi

ditto "$built_app" "$stage_app"
cp "$player_dir/LICENSE" "$stage_app/Contents/Resources/LICENSE"

# Preserve the licence files from the precise Homebrew installations whose
# dylibs this build embeds. These files travel inside the app, so a Mac running
# WMusic does not need Homebrew to read them.
native_licence_dir="$stage_app/Contents/Resources/ThirdPartyLicenses"
mkdir -p "$native_licence_dir"
native_licence_specs=(
  'ffmpeg:LICENSE.md'
  'ffmpeg:COPYING.LGPLv2.1'
  'ffmpeg:COPYING.LGPLv3'
  'ffmpeg:COPYING.GPLv2'
  'ffmpeg:COPYING.GPLv3'
  'taglib:COPYING.LGPL'
  'taglib:COPYING.MPL'
  'chromaprint:LICENSE.md'
  'svt-av1:LICENSE.md'
  'svt-av1:LICENSE-BSD2.md'
  'dav1d:COPYING'
  'xz:COPYING'
  'xz:COPYING.0BSD'
  'lame:LICENSE'
  'lame:COPYING'
  'mpg123:COPYING'
  'opus:COPYING'
  'libvpx:LICENSE'
  'x264:COPYING'
  'x265:COPYING'
  'openssl@3:LICENSE.txt'
)
for licence_spec in "${native_licence_specs[@]}"; do
  formula_name="${licence_spec%%:*}"
  licence_name="${licence_spec#*:}"
  source_licence="$(brew --prefix "$formula_name")/$licence_name"
  [[ -f "$source_licence" ]] || {
    echo "Missing bundled library licence: $source_licence" >&2
    exit 1
  }
  cp "$source_licence" "$native_licence_dir/$formula_name-$licence_name"
done

echo "Embedding audio libraries and signing the independent app..."
SIGNING_ENTITLEMENTS="$player_dir/Resources/Bocan.entitlements" \
  bash "$player_dir/Scripts/embed-deps.sh" "$stage_app" - > "$build_log_dir/wmusic-embed-deps.log" 2>&1 || {
  tail -50 "$build_log_dir/wmusic-embed-deps.log" >&2
  exit 1
}

echo "Checking every bundled Mach-O dependency and signature..."
codesign --verify --deep --strict --verbose=2 "$stage_app"
codesign_info="$(codesign -dvv "$stage_app" 2>&1)"
[[ "$codesign_info" == *"Signature=adhoc"* ]] || {
  echo "The app does not have an ad-hoc signature" >&2
  exit 1
}
entitlements_file="$stage_dir/entitlements.plist"
codesign -d --entitlements :- "$stage_app" > "$entitlements_file" 2>/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements_file")" == true ]] || {
  echo "The signed app lost its sandbox entitlement" >&2
  exit 1
}

while IFS= read -r -d '' binary; do
  [[ "$(file -b "$binary")" == *Mach-O* ]] || continue
  codesign --verify --strict "$binary"
  while IFS= read -r dependency; do
    case "$dependency" in
      /usr/lib/*|/System/*|@*) ;;
      /*)
        echo "Machine-specific dependency in $binary: $dependency" >&2
        exit 1
        ;;
    esac
  done < <(otool -L "$binary" | awk 'NR>1 {print $1}')
  while IFS= read -r runpath; do
    case "$runpath" in
      /usr/lib/*|/System/*|@*) ;;
      /*)
        echo "Machine-specific runpath in $binary: $runpath" >&2
        exit 1
        ;;
    esac
  done < <(otool -l "$binary" | awk '/cmd LC_RPATH/{found=1} found && /path /{print $2; found=0}')
done < <(find "$stage_app/Contents" -type f -print0)

if [[ -e "$final_app" ]]; then
  [[ -d "$final_app" && ! -L "$final_app" ]] || {
    echo "Candidate destination is not a regular app directory: $final_app" >&2
    exit 1
  }
  mv "$final_app" "$previous_candidate"
fi
mv "$stage_app" "$final_app"
codesign --verify --deep --strict "$final_app"
candidate_ready=1
echo "Candidate ready: $final_app"
echo "Install after normally quitting WMusic: $root_dir/script/install_local_app.sh"
du -sh "$final_app"
