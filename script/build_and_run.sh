#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
case "$mode" in
  run|--verify|--debug|--logs|--telemetry|--build-only) ;;
  *)
    echo "usage: $0 [run|--verify|--debug|--logs|--telemetry|--build-only]" >&2
    exit 2
    ;;
esac

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
player_dir="$root_dir/player"
derived_data="$player_dir/DerivedData"
app_bundle="$derived_data/Build/Products/Debug/WMusic.app"
app_executable="$app_bundle/Contents/MacOS/WMusic"
build_log_dir="$root_dir/.build-logs"
build_log="$build_log_dir/wmusic-xcodebuild.log"

if ! command -v xcodebuild >/dev/null; then
  echo "Xcode is required to build WMusic." >&2
  exit 1
fi

if command -v xcodegen >/dev/null; then
  xcodegen_bin="$(command -v xcodegen)"
elif [[ -x /opt/homebrew/opt/xcodegen/bin/xcodegen ]]; then
  xcodegen_bin=/opt/homebrew/opt/xcodegen/bin/xcodegen
else
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

if [[ ! -f "$player_dir/Secrets.xcconfig" ]]; then
  cp "$player_dir/Secrets.xcconfig.template" "$player_dir/Secrets.xcconfig"
fi

if [[ ! -x "$player_dir/Resources/fpcalc" ]] || ! compgen -G "$player_dir/Resources/libav*.dylib" >/dev/null; then
  echo "Preparing the local audio analysis libraries..."
  (cd "$player_dir" && PATH="$(dirname "$xcodegen_bin"):$PATH" make bundle-fpcalc)
fi

(cd "$player_dir" && "$xcodegen_bin" generate)
mkdir -p "$build_log_dir"

echo "Building WMusic from player/Bocan.xcodeproj..."
if ! (cd "$player_dir" && xcodebuild \
  -project Bocan.xcodeproj \
  -scheme Bocan \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build >"$build_log" 2>&1); then
  echo "WMusic build failed. First compiler diagnostics:" >&2
  rg -n 'error:|BUILD FAILED|CodeSign' "$build_log" | head -30 >&2 || true
  echo "Complete log: $build_log" >&2
  exit 1
fi

if [[ ! -x "$app_executable" ]]; then
  echo "Build finished, but the expected app was not found: $app_bundle" >&2
  exit 1
fi

echo "Built: $app_bundle"
if [[ "$mode" == --build-only ]]; then
  exit 0
fi

project_pid() {
  local pid process_command
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    process_command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$process_command" == "$app_executable"* ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
  done < <(pgrep -x WMusic || true)
  return 1
}

if running_pid="$(project_pid)"; then
  /usr/bin/swift "$root_dir/script/quit_local_app.swift" "$running_pid" "$app_executable"
  for _ in {1..40}; do
    kill -0 "$running_pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$running_pid" 2>/dev/null; then
    echo "WMusic is still running. Finish or cancel its quit prompt, then rerun this command." >&2
    exit 1
  fi
fi

/usr/bin/open -n "$app_bundle"

for _ in {1..40}; do
  if running_pid="$(project_pid)"; then
    echo "Running WMusic PID $running_pid from $app_bundle"
    case "$mode" in
      --debug) exec lldb -p "$running_pid" ;;
      --logs|--telemetry)
        exec /usr/bin/log stream --info --style compact --predicate 'process == "WMusic"'
        ;;
    esac
    exit 0
  fi
  sleep 0.5
done

echo "WMusic did not remain running after launch. Inspect macOS crash and app logs." >&2
exit 1
