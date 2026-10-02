#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
[[ "$VERSION" == "4.7.2-stable" && "$(uname -m)" == "x86_64" ]] || {
	echo "Web setup expects the pinned 4.7.2-stable x86_64 engine" >&2
	exit 1
}
for tool in curl unzip sha512sum awk; do command -v "$tool" >/dev/null; done

TOOLS_ROOT="$ROOT/.godot-tools"
DOWNLOADS="${GODOT_DOWNLOAD_CACHE:-/workspace/.tools/godot-4.7.2-downloads}"
if [[ ! -d "$DOWNLOADS" ]]; then DOWNLOADS="$TOOLS_ROOT/downloads/$VERSION"; fi
TEMPLATE_VERSION="${VERSION%-stable}.stable"
DATA_HOME="${XDG_DATA_HOME:-$ROOT/artifacts/user-data}"
mkdir -p "$DOWNLOADS" "$TOOLS_ROOT/$VERSION" "$DATA_HOME/godot/export_templates/$TEMPLATE_VERSION" \
	"$ROOT/artifacts/user-config" "$ROOT/artifacts/user-cache"

ARCHIVE="Godot_v${VERSION}_export_templates.tpz"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}"
if [[ ! -s "$DOWNLOADS/$ARCHIVE" ]]; then
	curl -fsSL --retry 3 "$BASE/$ARCHIVE" -o "$DOWNLOADS/$ARCHIVE"
fi
if [[ ! -s "$DOWNLOADS/SHA512-SUMS.txt" ]]; then
	curl -fsSL --retry 3 "$BASE/SHA512-SUMS.txt" -o "$DOWNLOADS/SHA512-SUMS.txt"
fi
(cd "$DOWNLOADS"
	awk -v name="$ARCHIVE" '$2 == name || $2 == "*" name { print }' SHA512-SUMS.txt > selected.sha512
	test "$(wc -l < selected.sha512)" = 1
	sha512sum -c selected.sha512)

ENGINE="$TOOLS_ROOT/$VERSION/godot"
if [[ ! -x "$ENGINE" ]]; then
	ENGINE_ARCHIVE="Godot_v${VERSION}_linux.x86_64.zip"
	if [[ ! -s "$DOWNLOADS/$ENGINE_ARCHIVE" ]]; then
		curl -fsSL --retry 3 "$BASE/$ENGINE_ARCHIVE" -o "$DOWNLOADS/$ENGINE_ARCHIVE"
	fi
	(cd "$DOWNLOADS"
		awk -v name="$ENGINE_ARCHIVE" '$2 == name || $2 == "*" name { print }' SHA512-SUMS.txt > selected-engine.sha512
		test "$(wc -l < selected-engine.sha512)" = 1
		sha512sum -c selected-engine.sha512)
	ENGINE_TMP="$(mktemp -d "$TOOLS_ROOT/.godot-web-engine.XXXXXX")"
	trap 'rm -rf "$ENGINE_TMP"' EXIT
	unzip -qo "$DOWNLOADS/$ENGINE_ARCHIVE" -d "$ENGINE_TMP"
	ENGINE_FILE="$ENGINE_TMP/Godot_v${VERSION}_linux.x86_64"
	test -f "$ENGINE_FILE"
	chmod +x "$ENGINE_FILE"
	mv "$ENGINE_FILE" "$ENGINE"
	trap - EXIT
	rm -rf "$ENGINE_TMP"
fi
ACTUAL="$($ENGINE --version)"
[[ "$ACTUAL" == "4.7.2.stable."* ]] || { echo "Unexpected engine version: $ACTUAL" >&2; exit 1; }

TEMPLATE_DIR="$DATA_HOME/godot/export_templates/$TEMPLATE_VERSION"
TEMP_DIR="$(mktemp -d "$TEMPLATE_DIR/.extract.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
for name in version.txt web_nothreads_debug.zip web_nothreads_release.zip; do
	unzip -p "$DOWNLOADS/$ARCHIVE" "templates/$name" > "$TEMP_DIR/$name"
done
[[ "$(<"$TEMP_DIR/version.txt")" == "4.7.2.stable" ]]
for name in web_nothreads_debug.zip web_nothreads_release.zip; do
	unzip -tq "$TEMP_DIR/$name" >/dev/null
done
for name in version.txt web_nothreads_debug.zip web_nothreads_release.zip; do
	mv -f "$TEMP_DIR/$name" "$TEMPLATE_DIR/$name"
done
rmdir "$TEMP_DIR"
trap - EXIT
printf 'Godot: %s (%s)\nWeb templates: %s\n' "$ACTUAL" "$ENGINE" "$TEMPLATE_DIR"
