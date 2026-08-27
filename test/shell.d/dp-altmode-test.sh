#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A device tree fixture. phandle values are 4 big-endian bytes, the same encoding
# the kernel exposes under /proc/device-tree.
make_tree() { # make_tree <dir> <dcpext-status> <wire-displayport:yes|no>
  local dir=$1 status=$2 wired=$3
  local dcp="$dir/soc/dcp@271c00000"
  local conn="$dir/soc/i2c@235010000/usb-pd@3f/connector"
  local other="$dir/soc/i2c@235010000/usb-pd@38/connector"

  mkdir -p "$dcp" "$conn" "$other"
  printf 'apple,j293\0apple,t8103\0' >"$dir/compatible"
  printf 'Apple MacBook Pro (13-inch, M1, 2020)\0' >"$dir/model"
  printf '\x00\x00\x00\x45' >"$dcp/phandle"
  printf '%s\0' "$status" >"$dcp/status"
  printf 'USB-C Left-front\0' >"$conn/label"
  printf 'USB-C Left-back\0' >"$other/label"
  [[ $wired == "yes" ]] && printf '\x00\x00\x00\x45' >"$conn/displayport"
  return 0
}

# The whole point of the check: both halves have to hold. Either one alone is the
# state a machine sits in halfway through enabling this, and reporting success
# there would send someone hunting for a cable fault that does not exist.
make_tree "$TMP/ok" okay yes
OMARCHY_DEVICE_TREE="$TMP/ok" "$ROOT/bin/omarchy-hw-dp-altmode" ||
  fail "dp-altmode is detected when dcpext is enabled and the connector is wired"
pass "dp-altmode is detected when dcpext is enabled and the connector is wired"

make_tree "$TMP/disabled" disabled yes
OMARCHY_DEVICE_TREE="$TMP/disabled" "$ROOT/bin/omarchy-hw-dp-altmode" &&
  fail "dp-altmode is not detected while dcpext is disabled"
pass "dp-altmode is not detected while dcpext is disabled"

make_tree "$TMP/unwired" okay no
OMARCHY_DEVICE_TREE="$TMP/unwired" "$ROOT/bin/omarchy-hw-dp-altmode" &&
  fail "dp-altmode is not detected without the displayport phandle"
pass "dp-altmode is not detected without the displayport phandle"

# A phandle that names no enabled node must not count. This is what a connector
# left pointing at a removed node looks like.
make_tree "$TMP/dangling" okay yes
printf '\x00\x00\x00\x99' >"$TMP/dangling/soc/i2c@235010000/usb-pd@3f/connector/displayport"
OMARCHY_DEVICE_TREE="$TMP/dangling" "$ROOT/bin/omarchy-hw-dp-altmode" &&
  fail "dp-altmode is not detected when the phandle names no enabled node"
pass "dp-altmode is not detected when the phandle names no enabled node"

# Non-Apple hardware must fall out of the diagnostic without claiming anything.
mkdir -p "$TMP/pc"
printf 'some,laptop\0' >"$TMP/pc/compatible"
OUT=$(OMARCHY_DEVICE_TREE="$TMP/pc" "$ROOT/bin/omarchy-debug-dp-altmode")
[[ $OUT == *"not an Apple Silicon machine"* ]] ||
  fail "the diagnostic exits cleanly on non-Apple hardware" "$OUT"
pass "the diagnostic exits cleanly on non-Apple hardware"

# The stock Asahi state is the common one, and it has to say plainly that this is
# expected rather than reading as a fault.
OUT=$(PATH="$ROOT/bin:$PATH" OMARCHY_DEVICE_TREE="$TMP/disabled" \
  OMARCHY_TYPEC_PATH="$TMP/none" OMARCHY_DRM_PATH="$TMP/none" \
  "$ROOT/bin/omarchy-debug-dp-altmode")
[[ $OUT == *"work in progress"* && $OUT == *"Nothing is broken"* ]] ||
  fail "the diagnostic explains the stock Asahi state instead of reporting a fault" "$OUT"
pass "the diagnostic explains the stock Asahi state instead of reporting a fault"

# portN is assigned in i2c probe order and has been observed to swap between two
# boots on the same machine, so nothing may resolve the port by its number.
grep -q 'portN' "$ROOT/bin/omarchy-debug-dp-altmode" ||
  fail "the diagnostic records why the port is resolved by i2c address"
grep -qE '0-00\[0-9a-f\]\+' "$ROOT/bin/omarchy-debug-dp-altmode" ||
  fail "the diagnostic resolves the cable's port by i2c address"
pass "the diagnostic resolves the cable's port by i2c address, not by port number"
