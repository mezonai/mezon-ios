#!/bin/sh
APP_BUNDLE="${CODESIGNING_FOLDER_PATH:-${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}}"
FW="${APP_BUNDLE}/Frameworks/LiveKitWebRTC.framework/LiveKitWebRTC"
if [ ! -f "$FW" ]; then
  exit 0
fi
OUT="${BUILT_PRODUCTS_DIR}/LiveKitWebRTC.framework.dSYM"
rm -rf "$OUT"
dsymutil "$FW" -o "$OUT" || exit 0
