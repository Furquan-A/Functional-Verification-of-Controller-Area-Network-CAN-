#!/usr/bin/env bash
set -euo pipefail

# --- project paths ---
PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="${SIM_DIR:-$PROJ_ROOT/sim}"
FILELIST="$PROJ_ROOT/scripts/filelist.f"

mkdir -p "$SIM_DIR"

echo "[INFO] PROJ_ROOT = $PROJ_ROOT"
echo "[INFO] SIM_DIR    = $SIM_DIR"
echo "[INFO] FILELIST   = $FILELIST"

# Clean old build outputs inside SIM_DIR only
rm -rf "$SIM_DIR"/csrc "$SIM_DIR"/simv "$SIM_DIR"/simv.daidir "$SIM_DIR"/ucli.key \
       "$SIM_DIR"/*.log "$SIM_DIR"/*.vpd "$SIM_DIR"/*.vcd 2>/dev/null || true

# Build compile command as an array (prevents quoting/line-continuation bugs)
VCS_CMD=(
  vcs
  -full64
  -sverilog
  -timescale=1ns/1ps
  -ntb_opts uvm-1.2
  -debug_access+all
  +define+CAN_WISHBONE_IF
  +incdir+"$PROJ_ROOT/rtl"
  +incdir+"$PROJ_ROOT/tb"
  +incdir+"$PROJ_ROOT/tb/pkg"
  +incdir+"$PROJ_ROOT/tb/can_interface"

  "$PROJ_ROOT/rtl/can_bsp.v"
  "$PROJ_ROOT/rtl/can_btl.v"
  "$PROJ_ROOT/rtl/can_crc.v"
  "$PROJ_ROOT/rtl/can_fifo.v"
  "$PROJ_ROOT/rtl/can_ibo.v"
  "$PROJ_ROOT/rtl/can_acf.v"
  "$PROJ_ROOT/rtl/can_register.v"
  "$PROJ_ROOT/rtl/can_register_asyn.v"
  "$PROJ_ROOT/rtl/can_register_asyn_syn.v"
  "$PROJ_ROOT/rtl/can_register_syn.v"
  "$PROJ_ROOT/rtl/can_registers.v"
  "$PROJ_ROOT/rtl/can_top.v"
  

  "$PROJ_ROOT/tb/interfaces/can_if.sv"
  "$PROJ_ROOT/tb/pkg/can_pkg.sv"
  
  # ---- sequences (compiled after package so types are visible)
  # "$PROJ_ROOT/tb/sequences/can_tx_seq.sv"
  
  # ---- tests (compiled after package + sequences)
 #  "$PROJ_ROOT/tb/tests/can_smoke_test.sv"
  "$PROJ_ROOT/tb/top/can_top_tb.sv"

  -o "$SIM_DIR/simv"
  -l "$SIM_DIR/compile.log"
)

echo "[INFO] Running VCS compile..."
echo "[CMD ] ${VCS_CMD[*]}"
"${VCS_CMD[@]}"

echo "[OK] Compile done."
echo "[OK] Binary: $SIM_DIR/simv"
echo "[OK] Log   : $SIM_DIR/compile.log"
