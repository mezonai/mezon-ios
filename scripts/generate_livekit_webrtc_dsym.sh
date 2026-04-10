#!/bin/sh
set -e

FRAMEWORK_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/LiveKitWebRTC.framework"
BINARY_PATH="${FRAMEWORK_PATH}/LiveKitWebRTC"
DSYM_OUTPUT="${DWARF_DSYM_FOLDER_PATH}/LiveKitWebRTC.framework.dSYM"

if [ ! -f "${BINARY_PATH}" ]; then
    exit 0
fi

if [ -d "${DSYM_OUTPUT}" ]; then
    exit 0
fi

xcrun dsymutil "${BINARY_PATH}" -o "${DSYM_OUTPUT}" 2>/dev/null || true
