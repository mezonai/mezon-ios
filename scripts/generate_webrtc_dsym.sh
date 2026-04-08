#!/bin/sh
# stasel/WebRTC SPM ships a binary XCFramework without dSYM; App Store / Xcode 16+ expect a matching dSYM.
BINARY="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
if [ ! -f "$BINARY" ]; then
  echo "note: WebRTC not at $BINARY — skip dSYM (simulator-only build or package layout changed)"
  exit 0
fi
mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
OUT="${DWARF_DSYM_FOLDER_PATH}/WebRTC.framework.dSYM"
rm -rf "$OUT"
if dsymutil "$BINARY" -o "$OUT" 2>&1; then
  echo "note: wrote $OUT"
else
  echo "warning: dsymutil failed for WebRTC (binary may be fully stripped). See https://github.com/stasel/WebRTC/issues/105"
  exit 0
fi
