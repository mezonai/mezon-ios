#!/bin/sh
# LiveKitWebRTC is a prebuilt XCFramework; embed dSYM into the archive so symbol upload succeeds.
BINARY="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/LiveKitWebRTC.framework/LiveKitWebRTC"
if [ ! -f "$BINARY" ]; then
  echo "note: LiveKitWebRTC not at $BINARY — skip dSYM (Simulator-only or dependency changed)"
  exit 0
fi
mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
OUT="${DWARF_DSYM_FOLDER_PATH}/LiveKitWebRTC.framework.dSYM"
rm -rf "$OUT"
if dsymutil "$BINARY" -o "$OUT" 2>&1; then
  echo "note: wrote $OUT"
else
  echo "warning: dsymutil failed for LiveKitWebRTC (binary may be stripped). Update livekit/client-sdk-swift or webrtc-xcframework; App Store may still warn."
  exit 0
fi
