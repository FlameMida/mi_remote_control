#!/bin/bash
# Spike orchestrator: Secure Input receive/deliver matrix. Throwaway; runs only on spike/secure-input-macro.
set -u
D=/tmp/spike; B=/tmp/spikebin/secureprobe
rm -rf "$D"; mkdir -p "$D/shots" /tmp/spikebin
OUT="${1:-spike-out}"; mkdir -p "$OUT"

swiftc -swift-version 5 -O spike/SecureProbe.swift -o "$B" 2>&1 | grep -v "warning:" ; codesign -s - -f "$B" || true
[ -x "$B" ] || { echo "BUILD FAILED"; exit 1; }

echo "== TCC grants (attempt; throwaway CI VM)"
NOW=$(date +%s)
for db in "/Library/Application Support/com.apple.TCC/TCC.db" "$HOME/Library/Application Support/com.apple.TCC/TCC.db"; do
  for svc in kTCCServiceAccessibility kTCCServiceListenEvent kTCCServicePostEvent; do
    sudo sqlite3 "$db" "INSERT OR REPLACE INTO access VALUES('$svc','$B',1,2,4,1,NULL,NULL,0,'UNUSED',NULL,0,$NOW,NULL,NULL,'UNUSED',$NOW);" 2>&1 | sed "s|^|tcc $svc: |"
  done
done
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "select service,client,auth_value from access where client like '%secureprobe%' or client like '%provisioner%' or client like '%bash%';" 2>&1 | head -20
csrutil status || true

"$B" status
sudo "$B" status

phase() { echo "$1" > "$D/phase"; echo; echo "===== PHASE $1 ====="; }
cmd() { echo "$1 #$RANDOM" > "$D/cmd"; sleep 1.2; echo "target-state: $(cat $D/target-state)"; }
xy() { sed -n "s/.*$1XY=\([0-9-]*\),\([0-9-]*\).*/\1 \2/p" "$D/target-state"; }
inject_all() {
  "$B" inject cghid "aa"; sleep 0.6
  "$B" inject cgsession "ss"; sleep 0.6
  "$B" inject unicode "UU"; sleep 0.6
  echo "0e 0e" > "$D/vhid-keys"; sleep 1.5
  echo "after inject: $(cat $D/target-state)"
  "$B" status
  ioreg -l -w 0 | grep -o '"kCGSSessionSecureInputPID"=[0-9]*' | head -2 || true
}

phase SETUP
"$B" target > "$D/target.log" 2>&1 & TPID=$!
sleep 3
"$B" listener user > "$D/listener-user.log" 2>&1 &
sudo "$B" listener root --no-ns > "$D/listener-root.log" 2>&1 &
sudo "$B" vhid 400 > "$D/vhid.log" 2>&1 &
sleep 4

phase P0-plain-nosecure
cmd focusPlain
if ! grep -q "active=true key=true" "$D/target-state"; then
  echo "target not active; clicking plain field"; "$B" inject click $(xy plain); sleep 1; cmd focusPlain
fi
cmd clear
inject_all
screencapture -x "$D/shots/P0.png" 2>&1 || true
cmd "shot P0"

phase P1-securefield-focused
cmd focusSecure
grep -q "responder=.*Secure\|responder=NSTextView" "$D/target-state" || { "$B" inject click $(xy secure); sleep 1; }
cmd clear
sleep 1; "$B" status
inject_all
screencapture -x "$D/shots/P1.png" 2>&1 || true
cmd "shot P1"

phase P2-helper-EnableSecureEventInput-plainfocused
cmd focusPlain
cmd clear
"$B" secure-helper 12 > "$D/helper.log" 2>&1 & sleep 2
"$B" status
inject_all
wait %4 2>/dev/null; sleep 11; cat "$D/helper.log"

phase P3-after-helper-plain
cmd focusPlain
cmd clear
inject_all

phase P4-securefield-again-macro-delivery
cmd focusSecure
cmd clear
sleep 1
"$B" inject unicode "Pw0rd!"; sleep 1
echo "delivery readback: $(cat $D/target-state)"
cmd "shot P4"

phase DONE
sleep 1
kill $TPID 2>/dev/null; sudo pkill -f "$B" 2>/dev/null; pkill -f "$B" 2>/dev/null
sleep 1
for f in "$D"/*.log; do echo; echo "---- $f"; cat "$f"; done

echo; echo "===== RECEIVE MATRIX (RECV lines per phase x channel) ====="
cat "$D"/listener-*.log | grep " RECV " | sed -E 's/^[^ ]+ \[([^]]+)\] \[([^]]+)\] RECV ([A-Za-z]+) .*/\2 \1:\3/' | sort | uniq -c
echo; echo "===== RECEIVE DETAIL (which injected source reached which channel) ====="
cat "$D"/listener-*.log | grep " RECV " | grep -v "type=up\|value=0" | sed -E 's/^[^ ]+ (\[[^]]+\]) (\[[^]]+\]) RECV ([A-Za-z]+) (.*)/\2 \1 \3 \4/' | cut -c1-200
cp -R "$D"/. "$OUT"/
