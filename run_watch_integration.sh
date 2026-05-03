#!/usr/bin/env bash
# run_watch_integration.sh
# Runs iPhone + Watch integration tests sequentially.
# State persists between runs via in_progress.json on disk.
#
# Usage:
#   bash run_watch_integration.sh
#   bash run_watch_integration.sh --iphone-id <uuid> --watch-id <uuid>

set -euo pipefail

SCHEME="GoBirdie"
PROJECT="GoBirdie.xcodeproj"
IPHONE_ID="C3AE9AEB-8948-4B8B-813E-4F0CA15CAB27"  # iPhone 16e + Watch (paired)
WATCH_ID="DCE458ED-3E94-4988-AE17-BA660BEC99A7"   # Apple Watch Series 6 (40mm)
RESULTS_DIR="$(pwd)/TestResults"

while [[ $# -gt 0 ]]; do
    case $1 in
        --iphone-id) IPHONE_ID="$2"; shift 2 ;;
        --watch-id)  WATCH_ID="$2";  shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ── Boot simulators if needed ─────────────────────────────────────────────────
boot_if_needed() {
    local udid="$1"
    local state
    state=$(xcrun simctl list devices "$udid" 2>/dev/null | grep "$udid" | grep -o '(Booted)' || echo "Shutdown")
    if [[ "$state" != "(Booted)" ]]; then
        echo "Booting $udid..."
        xcrun simctl boot "$udid"
    else
        echo "$udid already booted"
    fi
}

echo "iPhone: $IPHONE_ID"
echo "Watch:  $WATCH_ID"

boot_if_needed "$IPHONE_ID"
boot_if_needed "$WATCH_ID"
open -a Simulator
echo "Waiting 5s for simulators to finish booting..."
sleep 5

mkdir -p "$RESULTS_DIR"
cd "$(dirname "$0")"

DEST="platform=iOS Simulator,id=$IPHONE_ID"

# ── Helper ────────────────────────────────────────────────────────────────────
run_test() {
    local label="$1"
    local target="$2"
    local test_class="$3"
    local destination="$4"
    local current_scheme="${5:-$SCHEME}"

    echo ""
    echo "══════════════════════════════════════════════"
    echo "  $label"
    echo "══════════════════════════════════════════════"

    # ADD THIS LINE: Remove existing bundle to prevent xcodebuild error
    rm -rf "$RESULTS_DIR/${label}.xcresult"

    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$current_scheme" \
        -only-testing "$target/$test_class" \
        -destination "$destination" \
        -resultBundlePath "$RESULTS_DIR/${label}.xcresult" \
        -test-timeouts-enabled NO \
        2>&1 || { echo "FAILED: $label"; exit 1; }
}

# ── Run sequentially ──────────────────────────────────────────────────────────

# Act 1 (iPhone)
run_test "Act1_PhoneStartRound" \
         "GoBirdieUITests" \
         "Plan1_PhoneStartRound/test01_StartAndPlayRound" \
         "platform=iOS Simulator,id=$IPHONE_ID"

echo "Waiting 5s for WatchConnectivity..."
sleep 5

# Act 2 (Watch)
rm -rf "$RESULTS_DIR/Act2_WatchPlayRound.xcresult"
# xcodebuild test \
#     -project "$PROJECT" \
#     -scheme "GoBirdie Watch App" \
#     -only-testing "GoBirdie Watch AppUITests/GoBirdie_Watch_AppUITests/test02_WatchPlayAndEndRound" \
#     -destination "platform=watchOS Simulator,id=$WATCH_ID" \
#     -resultBundlePath "$RESULTS_DIR/Act2_WatchPlayRound.xcresult" \
#     -test-timeouts-enabled NO \
#     2>&1 || { echo "FAILED: Act2_WatchPlayRound"; exit 1; }

xcodebuild -project GoBirdie.xcodeproj -scheme "GoBirdie Watch App" \
           -destination "platform=watchOS Simulator,id=$WATCH_ID" \
           test

echo "Waiting 3s for sync..."
sleep 3

# Act 3 (iPhone)
run_test "Act3_PhoneVerify" \
         "GoBirdieUITests" \
         "Plan3_PhoneVerify/test03_VerifyRoundSaved" \
         "platform=iOS Simulator,id=$IPHONE_ID"

echo ""
echo "══════════════════════════════════════════════"
echo "  All 3 acts passed ✓"
echo "  Results: $RESULTS_DIR"
echo "══════════════════════════════════════════════"
