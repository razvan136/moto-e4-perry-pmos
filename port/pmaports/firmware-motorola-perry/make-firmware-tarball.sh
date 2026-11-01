#!/bin/sh
# Build firmware-motorola-perry.tar.gz from a payload directory, verifying every file
# against firmware-manifest.json before anything is packaged.
#
# Usage: ./make-firmware-tarball.sh <payload-dir>
#
# <payload-dir> must contain the files named by "firmware_request_name" in the manifest.

set -eu

PAYLOAD_DIR="${1:-}"
MANIFEST="$(dirname "$0")/firmware-manifest.json"
OUT="firmware-motorola-perry.tar.gz"

if [ -z "$PAYLOAD_DIR" ] || [ ! -d "$PAYLOAD_DIR" ]; then
	echo "usage: $0 <payload-dir>" >&2
	exit 1
fi
if [ ! -f "$MANIFEST" ]; then
	echo "error: manifest not found at $MANIFEST" >&2
	exit 1
fi

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		shasum -a 256 "$1" | awk '{print $1}'
	fi
}

echo "==> verifying payload against manifest"

command -v python3 >/dev/null 2>&1 || {
	echo "error: python3 is required to read the manifest" >&2
	exit 1
}

# Emit "<request_name> <sha256>" pairs from the manifest.
pairs=$(python3 - "$MANIFEST" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    doc = json.load(fh)
for entry in doc["files"]:
    name = entry["firmware_request_name"]
    want = entry["sha256"]
    if not name or not want:
        sys.exit("error: manifest entry missing name or sha256: %r" % (entry,))
    print(name, want)
PY
) || exit 1

if [ -z "$pairs" ]; then
	echo "error: could not parse $MANIFEST" >&2
	exit 1
fi

expected=$(printf '%s\n' "$pairs" | grep -c . || true)
echo "==> manifest lists $expected files"

printf '%s\n' "$pairs" | while read -r name want; do
	[ -n "$name" ] || continue
	f="$PAYLOAD_DIR/$name"
	if [ ! -f "$f" ]; then
		echo "MISSING  $name" >&2
		exit 2
	fi
	got=$(sha256_of "$f")
	if [ "$got" != "$want" ]; then
		echo "MISMATCH $name" >&2
		echo "  want $want" >&2
		echo "  got  $got" >&2
		exit 3
	fi
done || exit $?

echo "==> payload verified"

echo "==> building $OUT"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/lib/firmware"
# The request name IS the destination path under /usr/lib/firmware, so preserve
# subdirectories exactly (e.g. qcom/a300_pfp.fw, qcom/msm8917/motorola/perry/...).
printf '%s\n' "$pairs" | awk '{print $1}' | while read -r name; do
	[ -n "$name" ] || continue
	dest="$stage/lib/firmware/$name"
	mkdir -p "$(dirname "$dest")"
	cp "$PAYLOAD_DIR/$name" "$dest"
done
tar -czf "$OUT" -C "$stage" lib
count=$(tar -tzf "$OUT" | grep -vc '/$' || true)

echo "==> wrote $OUT ($count files)"
echo
echo "Paste this line into APKBUILD's sha512sums:"
if command -v sha512sum >/dev/null 2>&1; then
	sha512sum "$OUT"
else
	shasum -a 512 "$OUT"
fi
