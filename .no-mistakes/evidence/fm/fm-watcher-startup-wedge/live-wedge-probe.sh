#!/usr/bin/env bash
# Live probe for fm/fm-watcher-startup-wedge (base a774c44 -> target 1b14f4b).
# Drives the real bin/fm-watch-arm.sh and bin/fm-watch.sh against scratch
# FM_HOME/state fixtures built the same way tests/fm-watcher-lock.test.sh builds
# them (fake tmux on PATH; real watcher scripts). Nothing live is touched.
set -u
cd /Users/mengyi/.no-mistakes/worktrees/93f9eed8ee70/01M3QMFS4PJ50YQQS9S4B95E3S
# shellcheck disable=SC1091
. tests/wake-helpers.sh
WATCH="$ROOT/bin/fm-watch.sh"
WATCH_ARM="$ROOT/bin/fm-watch-arm.sh"
TMP_ROOT=$(fm_test_tmproot fm-live-wedge-probe)
EV=/Users/mengyi/.no-mistakes/evidence/01M3QMFS4PJ50YQQS9S4B95E3S
transcript="$EV/live-wedge-probe.transcript"
: > "$transcript"

say() { printf '\n=== %s ===\n' "$1" | tee -a "$transcript"; }
note() { printf '%s\n' "$*" | tee -a "$transcript"; }

# ---------------------------------------------------------------------------
say "PROBE A: arm startup from the 2026-09-29 wedged state shape"
dir=$(make_case probe-arm-wedged)
state="$dir/state"
dead=$(dead_pid)
mkdir "$state/.watch.lock.owner.WEDG01"
printf '%s\n' "$dead" > "$state/.watch.lock.owner.WEDG01/pid"
ln -s "$state/.watch.lock.owner.WEDG01" "$state/.watch.lock"
ln -s "$state/.watch.lock.steal.owner.GONE01" "$state/.watch.lock.steal"
mkdir "$state/.watcher-down.lock.owner.WEDG02" "$state/.wake-queue.lock.owner.WEDG03"
printf '%s\n' "$dead" > "$state/.watcher-down.lock.owner.WEDG02/pid"
printf '%s\n' "$dead" > "$state/.wake-queue.lock.owner.WEDG03/pid"
ln -s "$state/.watcher-down.lock.owner.WEDG02" "$state/.watcher-down.lock"
ln -s "$state/.wake-queue.lock.owner.WEDG03" "$state/.wake-queue.lock"
printf 'acked:handling:1.1700000000.abcDEF\n' > "$state/.watcher-down"
note "seeded wedge: dead pid $dead holds .watch.lock/.watcher-down.lock/.wake-queue.lock; dangling .watch.lock.steal; acked:handling marker"
armout="$dir/arm.out"
PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_POLL=5 FM_SIGNAL_GRACE=1 \
  FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$WATCH_ARM" > "$armout" 2>&1 &
armpid=$!
started=
i=0
while [ "$i" -lt 120 ]; do
  grep -qF 'watcher: started pid=' "$armout" 2>/dev/null && { started=1; break; }
  is_live_non_zombie "$armpid" || break
  sleep 0.1
  i=$((i + 1))
done
if [ "$started" = 1 ]; then
  note "PASS: arm confirmed a started watcher from the wedged state"
else
  note "FAIL: arm never confirmed a started watcher; arm output follows"
  cat "$armout" | tee -a "$transcript"
fi
grep -E 'watcher: started pid=|check: rearm-resurface' "$armout" | tee -a "$transcript" || true
lock_pid=$(sed -n 's/^watcher: started pid=\([0-9][0-9]*\).*/\1/p' "$armout" | head -n 1)
[ -z "$lock_pid" ] || note "watcher pid from started line: $lock_pid (alive: $(is_live_non_zombie "$lock_pid" && echo yes || echo no))"
[ ! -e "$state/.watch.lock.steal" ] && [ ! -L "$state/.watch.lock.steal" ] \
  && note "PASS: dangling steal mutex reclaimed" \
  || note "FAIL: dangling steal mutex survived"
for rec in .watch.lock.owner.WEDG01 .watcher-down.lock.owner.WEDG02 .wake-queue.lock.owner.WEDG03; do
  [ ! -d "$state/$rec" ] && note "PASS: $rec collected" || note "FAIL: $rec survived"
done
kill "$armpid" "$lock_pid" 2>/dev/null || true
wait "$armpid" 2>/dev/null || true

# ---------------------------------------------------------------------------
say "PROBE B: dead-pid lock whose reclaim is refused -> honest typed refusal"
dir=$(make_case probe-refusal)
state="$dir/state"
dead=$(dead_pid)
sleep 300 >/dev/null 2>&1 &
holder=$!
mkdir "$state/.watch.lock.owner.REF01"
printf '%s\n' "$dead" > "$state/.watch.lock.owner.REF01/pid"
ln -s "$state/.watch.lock.owner.REF01" "$state/.watch.lock"
# A live wake-drain-style holder of the downtime marker lock: the steal's
# downtime publication must wait on it, refuse, and name the reason.
mkdir "$state/.watcher-down.lock.owner.REF02"
printf '%s\n' "$holder" > "$state/.watcher-down.lock.owner.REF02/pid"
ln -s "$state/.watcher-down.lock.owner.REF02" "$state/.watcher-down.lock"
note "seeded: .watch.lock names dead pid $dead; .watcher-down.lock held live by pid $holder; no .last-watcher-beat"
watchout="$dir/watch.out"
start=$(date +%s)
PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_POLL=5 FM_SIGNAL_GRACE=1 \
  FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
  "$WATCH" > "$watchout" 2>&1 &
wpid=$!
wait_for_exit "$wpid" 300
rc=$?
elapsed=$(( $(date +%s) - start ))
kill "$holder" 2>/dev/null || true
note "watcher exit=$rc after ${elapsed}s (no beat file: the old code printed 'live pid ... but no heartbeat exists' or 'already running pid <dead>')"
cat "$watchout" | tee -a "$transcript"
if grep -qF "stale lock names pid $dead which is not running and could not be reclaimed (downtime publication refused within 10s" "$watchout" \
  && [ "$rc" -eq 1 ]; then
  note "PASS: refusal names the dead pid and the reclaim reason, exits 1"
else
  note "FAIL: expected honest dead-pid refusal, got the above"
fi
if grep -qE "already running pid $dead|live pid $dead" "$watchout"; then
  note "FAIL: watcher described the provably-dead pid as live/running"
else
  note "PASS: dead pid never described as live/running"
fi

# ---------------------------------------------------------------------------
say "PROBE C: FM_RECOVERY_LOCK_BOUND=08 is parsed base-10 (octal corner)"
dir=$(make_case probe-octal)
state="$dir/state"
dead=$(dead_pid)
sleep 300 >/dev/null 2>&1 &
holder=$!
mkdir "$state/.watch.lock.owner.OCT01"
printf '%s\n' "$dead" > "$state/.watch.lock.owner.OCT01/pid"
ln -s "$state/.watch.lock.owner.OCT01" "$state/.watch.lock"
mkdir "$state/.watcher-down.lock.owner.OCT02"
printf '%s\n' "$holder" > "$state/.watcher-down.lock.owner.OCT02/pid"
ln -s "$state/.watcher-down.lock.owner.OCT02" "$state/.watcher-down.lock"
watchout="$dir/watch.out"
start=$(date +%s)
PATH="$dir/fakebin:$PATH" FM_HOME="$dir" FM_POLL=5 FM_SIGNAL_GRACE=1 \
  FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 FM_RECOVERY_LOCK_BOUND=08 \
  "$WATCH" > "$watchout" 2>&1 &
wpid=$!
wait_for_exit "$wpid" 300
rc=$?
elapsed=$(( $(date +%s) - start ))
kill "$holder" 2>/dev/null || true
note "watcher exit=$rc after ${elapsed}s with FM_RECOVERY_LOCK_BOUND=08"
cat "$watchout" | tee -a "$transcript"
if grep -qF "downtime publication refused within 8s" "$watchout" \
  && [ "$rc" -eq 1 ] && ! grep -q "value too great for base" "$watchout"; then
  note "PASS: bound honored as decimal 8s, no arithmetic abort"
else
  note "FAIL: leading-zero bound misparsed or aborted arithmetic"
fi

say "probe complete"
