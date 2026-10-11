#!/usr/bin/env bash
# Headless LAN tests on one machine (loopback):
#   A) phone <-> phone  : two Godot instances, host + ENet client
#   B) PS4  <-> phones  : host + ENet client + the PS4 client's PC build (plain-UDP bridge)
# Needs a Godot 4.3 binary in $GODOT and g++/make.
set -u
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
make -C ps4 >/dev/null || { echo "FAIL: could not build ps4 client"; exit 1; }
OUT=$(mktemp -d)
fail=0
check() { # name file regex
  if grep -Eq "$3" "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; grep -E '^\[|SCRIPT ERROR' "$2" | head -5; fail=1; fi
}

echo "== A: phone <-> phone =="
$GODOT --headless --path . -s tests/lan_test.gd -- host 9 1 >"$OUT/a_host.log" 2>&1 &
sleep 2
$GODOT --headless --path . -s tests/lan_test.gd -- client 7 >"$OUT/a_client.log" 2>&1 &
wait
check "host sees the phone's car"   "$OUT/a_host.log"   'RESULT: my_id=1 remote_cars=\[[0-9]+\]'
check "phone sees the host's car"   "$OUT/a_client.log" 'RESULT: .*remote_cars=\[1\]'

echo "== B: PS4 <-> phone <-> phone =="
$GODOT --headless --path . -s tests/lan_test.gd -- host 9 1 >"$OUT/b_host.log" 2>&1 &
sleep 2
$GODOT --headless --path . -s tests/lan_test.gd -- client 7 >"$OUT/b_client.log" 2>&1 &
sleep 0.5
./ps4/pc_client --host 127.0.0.1 --frames 500 --steer 0 >"$OUT/b_ps4.log" 2>&1 &
wait
check "host sees phone + PS4"       "$OUT/b_host.log"   'RESULT: my_id=1 remote_cars=\[1000, [0-9]+\]'
check "phone sees host + PS4"       "$OUT/b_client.log" 'RESULT: .*remote_cars=\[1, 1000\]'
check "PS4 sees host + phone"       "$OUT/b_ps4.log"    'remote=\[ 1 [0-9]+ \]'

[ $fail -eq 0 ] && echo "ALL LAN TESTS PASSED" || { echo "SOME LAN TESTS FAILED (logs in $OUT)"; exit 1; }
