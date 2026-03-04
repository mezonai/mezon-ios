#!/bin/bash
# =============================================================================
# gen-proto.sh
# Re-generate Swift protobuf files from mezon-protocol source.
#
# Usage:
#   bash scripts/gen-proto.sh
#
# Requirements:
#   brew install protobuf       # provides `protoc`
#   brew install swift-protobuf # provides `protoc-gen-swift`
# =============================================================================

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROTO_REPO="/Users/thomas/Documents/Swift/mezon-protocol"

OUT_API="$PROJECT_DIR/MezonChat/Generated/api"
OUT_RTAPI="$PROJECT_DIR/MezonChat/Generated/rtapi"

# ── Check required tools ─────────────────────────────────────────────────────

echo "🔍 Checking tools..."

if ! command -v protoc &>/dev/null; then
    echo "❌ protoc not found. Run: brew install protobuf"
    exit 1
fi

if ! command -v protoc-gen-swift &>/dev/null; then
    echo "❌ protoc-gen-swift not found. Run: brew install swift-protobuf"
    exit 1
fi

echo "   protoc:           $(protoc --version)"
echo "   protoc-gen-swift: $(protoc-gen-swift --version 2>&1 || echo 'ok')"

# ── Check source files ───────────────────────────────────────────────────────

API_PROTO="$PROTO_REPO/api/api.proto"
RT_PROTO="$PROTO_REPO/rtapi/realtime.proto"

if [ ! -f "$API_PROTO" ]; then
    echo "❌ Not found: $API_PROTO"
    exit 1
fi

if [ ! -f "$RT_PROTO" ]; then
    echo "❌ Not found: $RT_PROTO"
    exit 1
fi

# ── Generate ─────────────────────────────────────────────────────────────────

echo ""
echo "📦 Generating from mezon-protocol..."
echo "   Source : $PROTO_REPO"
echo "   api    → $OUT_API"
echo "   rtapi  → $OUT_RTAPI"
echo ""

# Clean old generated files before regenerating to avoid stale artifacts
rm -f "$OUT_API"/*.swift "$OUT_RTAPI"/*.swift
mkdir -p "$OUT_API" "$OUT_RTAPI"

# Use the repo root as --proto_path so protoc can resolve:
#   import "api/api.proto"        (referenced by realtime.proto)
#   import "google/protobuf/..."  (built-in well-known types)
PROTOC_INCLUDE="$(brew --prefix protobuf)/include"

# protoc preserves the relative path of the input file in the output directory.
# e.g. input = api/api.proto → output = <OUT>/api/api.pb.swift (extra subfolder)
# Use a temp directory and then flatten the file to the correct destination.
TEMP_OUT=$(mktemp -d)

# api.proto → TEMP/api/api.pb.swift → move → Generated/api/api.pb.swift
protoc \
    --proto_path="$PROTO_REPO" \
    --proto_path="$PROTOC_INCLUDE" \
    --swift_out="$TEMP_OUT" \
    "$API_PROTO"

mv "$TEMP_OUT/api/api.pb.swift" "$OUT_API/api.pb.swift"
echo "✅ Generated: api.pb.swift"

# realtime.proto → TEMP/rtapi/realtime.pb.swift → move → Generated/rtapi/realtime.pb.swift
protoc \
    --proto_path="$PROTO_REPO" \
    --proto_path="$PROTOC_INCLUDE" \
    --swift_out="$TEMP_OUT" \
    "$RT_PROTO"

mv "$TEMP_OUT/rtapi/realtime.pb.swift" "$OUT_RTAPI/realtime.pb.swift"
echo "✅ Generated: realtime.pb.swift"

rm -rf "$TEMP_OUT"

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "🎉 Done! Build Xcode (⌘B) to check for any breaking changes."
echo "   If there are compiler errors, update field/type names to match the newly generated files."
