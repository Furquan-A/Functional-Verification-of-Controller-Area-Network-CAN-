#!/usr/bin/env bash
set -euo pipefail
# Project root = one level above scripts/
PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="${SIM_DIR:-$PROJ_ROOT/sim}"
SIMV="$SIM_DIR/simv"
RUN_LOG="$SIM_DIR/run.log"
PRETTY_LOG="$SIM_DIR/pretty.log"
TXN_LOG="$SIM_DIR/txn.log"
if [[ ! -x "$SIMV" ]]; then
  echo "[ERROR] simv not found/executable at: $SIMV"
  echo "Run: ./scripts/vcs_compile.sh"
  exit 1
fi
mkdir -p "$SIM_DIR"
echo "[INFO] Running simulation..."
echo "[CMD ] $SIMV $* -l $RUN_LOG"
"$SIMV" "$@" -l "$RUN_LOG"
"$SIMV" "$@" -cm line+cond+fsm+branch+tgl+assert \
             -cm_dir "$SIM_DIR/coverage_db" \
             -cm_name "$(date +%s)" \
             -l "$RUN_LOG"
echo "[OK] Run done."
echo "[OK] Log: $RUN_LOG"
# ---------------- Pretty, readable log ----------------
egrep "CAN_SB_TXN|CAN_SB.*summary|CAN_DRV.*Sent frame|CAN_MON.*Observed frame|Running test" "$RUN_LOG" \
| awk '
{
  time="NA";
  if (match($0, /\( @ [0-9]+:/)) time=substr($0, RSTART+4, RLENGTH-5);
  tag="NA";
  if (match($0, /\[[A-Za-z0-9_]+\]/)) tag=substr($0, RSTART+1, RLENGTH-2);
  msg=$0;
  sub(/^.*\] /, "", msg);
  printf "%-10s %-12s %s\n", time, tag, msg
}' > "$PRETTY_LOG"
# Only the scoreboard compare rows (transactions in order)
grep "CAN_SB_TXN" "$RUN_LOG" > "$TXN_LOG" || true
echo "[OK] Pretty log: $PRETTY_LOG"
echo "[OK] Txn log   : $TXN_LOG"
/home/users4/fl892838/can_uvm_project $

give me html for coverage