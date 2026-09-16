#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command -v bash >/dev/null 2>&1 || fail 'Bash is required. On macOS, use /bin/bash tools/bootstrap.sh.'
command -v curl >/dev/null 2>&1 || fail 'curl is required. Restore the macOS-provided /usr/bin/curl and ensure /usr/bin is on PATH.'
command -v git >/dev/null 2>&1 || fail 'Git is required. Install full Xcode and open it to finish developer tools setup.'
git --version || fail 'Git is unavailable. Open Xcode to finish developer tools setup.'
command -v xcode-select >/dev/null 2>&1 || fail 'Install full Xcode from the App Store, then open it to finish setup.'
developer_dir=$(xcode-select -p) || fail 'Select full Xcode with: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer'
xcode_version=$(xcodebuild -version) || fail 'Select full Xcode, then open it to accept the license and install required components.'
case "$xcode_version" in
  Xcode*) ;;
  *) fail 'Full Xcode is required; standalone Command Line Tools are insufficient.' ;;
esac
for tool in swift xcodebuild simctl xed; do
  xcrun --find "$tool" >/dev/null 2>&1 || fail "Xcode tool $tool is unavailable. Open Xcode to finish setup and check xcode-select -p."
done

runtimes=$(xcrun simctl list runtimes) || fail 'Cannot query Simulator services. Open Xcode/Device Hub and retry outside any restrictive sandbox.'
ios_runtimes=$(printf '%s\n' "$runtimes" | awk '/^iOS / && /com\.apple\.CoreSimulator\.SimRuntime\.iOS-/ && !/[Uu]navailable/ { print }')
[ -n "$ios_runtimes" ] || fail 'No available iOS Simulator runtime. Install one in Xcode Settings > Components, then rerun bootstrap.'

printf 'Selected developer directory: %s\n%s\nAvailable iOS runtimes:\n%s\n' "${DEVELOPER_DIR:-$developer_dir}" "$xcode_version" "$ios_runtimes"

if command -v mise >/dev/null 2>&1; then
  mise_bin=$(command -v mise)
elif [ -x "$HOME/.local/bin/mise" ]; then
  mise_bin="$HOME/.local/bin/mise"
else
  mise_bin="$HOME/.local/bin/mise"
  installer=$(mktemp "${TMPDIR:-/tmp}/dreamproject-mise.XXXXXX")
  trap 'rm -f "$installer"' EXIT
  printf 'Installing mise from https://mise.run into %s\n' "$mise_bin"
  curl --fail --silent --show-error --location https://mise.run --output "$installer" || fail 'Could not download the official mise installer. Check your internet connection and retry.'
  MISE_INSTALL_PATH="$mise_bin" sh "$installer" || fail 'mise installation failed. Check the installer output and permissions for ~/.local/bin, then retry.'
fi

export PATH="$(dirname "$mise_bin"):$PATH"
"$mise_bin" --version || fail 'mise could not run. Repair or reinstall the executable and retry.'
# Trust only this reviewed repository configuration, not every parent directory.
"$mise_bin" trust "$repo_root/mise.toml"
"$mise_bin" install
printf '\nBootstrap complete. mise executable: %s\n' "$mise_bin"
printf 'If mise is not on your shell PATH, run: export PATH="%s:$PATH"\n' "$(dirname "$mise_bin")"
