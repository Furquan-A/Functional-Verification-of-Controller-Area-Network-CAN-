#!/bin/bash
# =============================================================
#  CAN UVM Agent Regression Script
#  Usage: ./can_regression.sh
#  Tests run in order: Basic ? Arbitration ? Special ? Error
# =============================================================

# -- Colour codes ---------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# -- Test list in order ----------------------------------------
# Format: "TEST_NAME|CATEGORY"
TESTS=(
  "can_ext_frame_test|Basic Frame Tests"
  "can_dlc_boundary_test|Basic Frame Tests"
  "can_id_boundary_test|Basic Frame Tests"
  "can_std_ext_arb_test|Arbitration Tests"
  "can_arb_burst_test|Arbitration Tests"
  "can_remote_response_test|Special Frame Tests"
  "can_ifs_overload_test|Special Frame Tests"
  "can_midframe_error_test|Special Frame Tests"
  "can_crc_error_test|Error Injection Tests"
  "can_stuff_error_test|Error Injection Tests"
  "can_form_error_test|Error Injection Tests"
  "can_ack_error_test|Error Injection Tests"
  "can_dut_init_test|DUT Instantiate Test"
  "can_dut_rx_test|DUT Instantiate Test"
  "can_dut_tx_test|DUT Instantiate Test"
  "can_dut_crc_err_test|DUT Error Test"
  "can_dut_stuff_err_test|DUT Error Test"
  "can_dut_form_err_test|DUT Error Test"
  "can_dut_ack_err_test|DUT Error Test"
  "can_dut_bus_off_test|DUT Functionality Test"
  "can_dut_int_disable_test|DUT Functionality Test"
  "can_dut_overrun_test|DUT Functionality Test"
  "can_dut_abort_tx_test|DUT Functionality Test"
  "can_dut_remote_rx_test|DUT Functionality Test"
  "can_dut_arbitration_lost_test|DUT Functionality Test"
  "can_dut_dual_filter_test|DUT Functionality Test"
  "can_dut_fifo_stress_test|DUT Functionality Test"
  "can_dut_normal_mode_rx_test|DUT Mode Test"
  "can_dut_listen_only_mode_test|DUT Mode Test"
  "can_dut_self_test_mode_test|DUT Mode Test"
  "can_dut_acceptance_filter_test|DUT Mode Test"
  "can_random_test|Constrained Random Tests"
  "reg_init_test|Reg Agent"
  "reg_random_test|Reg Agent"
)

TOTAL=${#TESTS[@]}
PASS=0
FAIL=0
WARN=0
SKIP=0
BASIC_FAILED=0

# -- Results arrays --------------------------------------------
declare -a RESULT_NAME
declare -a RESULT_CAT
declare -a RESULT_STATUS
declare -a RESULT_FATAL
declare -a RESULT_ERROR
declare -a RESULT_WARNING

# -- Log directory ---------------------------------------------
LOGDIR="regression_logs"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SUMMARY_LOG="$LOGDIR/regression_summary_${TIMESTAMP}.txt"

# -- Helper: category banner -----------------------------------
print_banner() {
  local label="$1"
  echo ""
  echo -e "  ${BOLD}${CYAN}-- ${label}${NC}"
}

# -- Helper: result row ----------------------------------------
print_row() {
  local name="$1" status="$2" f="$3" e="$4" w="$5"
  local COLOR
  case "$status" in
    PASS) COLOR=$GREEN  ;;
    WARN) COLOR=$YELLOW ;;
    SKIP) COLOR=$DIM    ;;
    *)    COLOR=$RED    ;;
  esac
  printf "  %-38s ${COLOR}%-8s${NC} %-7s %-7s %-9s\n" \
    "$name" "$status" "$f" "$e" "$w"
}

# -- Header ----------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}============================================================${NC}"
echo -e "${BOLD}${CYAN}  CAN UVM Agent Regression                                  ${NC}"
echo -e "${BOLD}${CYAN}  $(date)${NC}"
echo -e "${BOLD}${CYAN}============================================================${NC}"
echo ""
echo -e "  Running ${BOLD}${TOTAL}${NC} tests across 6 categories"
echo -e "  Logs saved to: ${LOGDIR}/"
echo ""

# -- Run each test ---------------------------------------------
PREV_CAT=""

for i in "${!TESTS[@]}"; do

  IFS='|' read -r TEST CAT <<< "${TESTS[$i]}"
  LOG="$LOGDIR/${TEST}.log"
  IDX=$((i + 1))

  # Category banner on change
  if [ "$CAT" != "$PREV_CAT" ]; then
    print_banner "$CAT"
    PREV_CAT="$CAT"
  fi

  # Skip if a basic test failed and we are past basic category
  if [ "$BASIC_FAILED" -eq 1 ] && [ "$CAT" != "Basic Frame Tests" ]; then
    echo -e "  [${IDX}/${TOTAL}] ${TEST} ... ${DIM}SKIP (basic test failed)${NC}"
    RESULT_NAME[$i]=$TEST
    RESULT_CAT[$i]=$CAT
    RESULT_STATUS[$i]="SKIP"
    RESULT_FATAL[$i]="-"
    RESULT_ERROR[$i]="-"
    RESULT_WARNING[$i]="-"
    SKIP=$((SKIP + 1))
    continue
  fi

  echo -ne "  [${IDX}/${TOTAL}] ${TEST} ... "

  # Run the test
  ./vcs_run.sh +UVM_TESTNAME="$TEST" > "$LOG" 2>&1

  # Parse UVM report counts from summary line at end of log
  FATAL=$(grep -oP '(?i)uvm_fatal\s*:\s*\K[0-9]+' "$LOG" | tail -1)
  ERROR=$(grep -oP '(?i)uvm_error\s*:\s*\K[0-9]+'  "$LOG" | tail -1)
  WARNING=$(grep -oP '(?i)uvm_warning\s*:\s*\K[0-9]+' "$LOG" | tail -1)
  SB_FAIL=$(grep "Scoreboard summary" "$LOG" | grep -oP 'Fail=\K[0-9]+' | tail -1)

  # Sanitize
  FATAL=${FATAL:-0}
  ERROR=${ERROR:-0}
  WARNING=${WARNING:-0}
  SB_FAIL=${SB_FAIL:-0}

  # Determine status
  if [ "$FATAL" -gt 0 ] || [ "$ERROR" -gt 0 ] || [ "$SB_FAIL" -gt 0 ]; then
    STATUS="FAIL"
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}  (FATAL=${FATAL} ERROR=${ERROR} WARNING=${WARNING} SB_FAIL=${SB_FAIL})"
    if [ "$CAT" = "Basic Frame Tests" ]; then
      BASIC_FAILED=1
      echo -e "  ${BOLD}${RED}  Basic test failed — remaining categories will be skipped${NC}"
    fi
  elif [ "$WARNING" -gt 0 ]; then
    STATUS="PASS"
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}  (FATAL=${FATAL} ERROR=${ERROR} WARNING=${WARNING} SB_FAIL=${SB_FAIL})"
  else
    STATUS="PASS"
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}  (FATAL=${FATAL} ERROR=${ERROR} WARNING=${WARNING} SB_FAIL=${SB_FAIL})"
  fi

  RESULT_NAME[$i]=$TEST
  RESULT_CAT[$i]=$CAT
  RESULT_STATUS[$i]=$STATUS
  RESULT_FATAL[$i]=$FATAL
  RESULT_ERROR[$i]=$ERROR
  RESULT_WARNING[$i]=$WARNING

done

# -- Summary table ---------------------------------------------
echo ""
echo ""
echo -e "${BOLD}${CYAN}============================================================${NC}"
echo -e "${BOLD}  REGRESSION SUMMARY${NC}"
echo -e "${BOLD}${CYAN}============================================================${NC}"
printf "  %-38s %-8s %-7s %-7s %-9s\n" "TEST" "STATUS" "FATAL" "ERROR" "WARNING"
echo "  -----------------------------------------------------------------------"

PREV_CAT=""
for i in "${!TESTS[@]}"; do
  CAT="${RESULT_CAT[$i]}"
  if [ "$CAT" != "$PREV_CAT" ]; then
    echo ""
    echo -e "  ${BOLD}${CAT}${NC}"
    PREV_CAT="$CAT"
  fi
  print_row \
    "${RESULT_NAME[$i]}"    \
    "${RESULT_STATUS[$i]}"  \
    "${RESULT_FATAL[$i]}"   \
    "${RESULT_ERROR[$i]}"   \
    "${RESULT_WARNING[$i]}"
done

echo ""
echo "  -----------------------------------------------------------------------"
echo ""

# -- Counts ----------------------------------------------------
printf "  %-10s ${BOLD}%d${NC}\n"              "Total  :"  "$TOTAL"
printf "  %-10s ${BOLD}${GREEN}%d${NC}\n"      "Pass   :"  "$PASS"
printf "  %-10s ${BOLD}${YELLOW}%d${NC}\n"     "Warn   :"  "$WARN"
printf "  %-10s ${BOLD}${RED}%d${NC}\n"        "Fail   :"  "$FAIL"
printf "  %-10s ${BOLD}${DIM}%d${NC}\n"        "Skip   :"  "$SKIP"
echo ""

# -- Verdict ---------------------------------------------------
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ] && [ "$SKIP" -eq 0 ]; then
  echo -e "${BOLD}${GREEN}  ALL ${TOTAL} TESTS PASSED — CAN verification complete${NC}"
  echo -e "${BOLD}${GREEN}  Ready to move ahead in your project${NC}"
elif [ "$FAIL" -eq 0 ] && [ "$SKIP" -eq 0 ]; then
  echo -e "${BOLD}${YELLOW}  ALL TESTS PASSED WITH WARNINGS${NC}"
else
  echo -e "${BOLD}${RED}  ${FAIL} TEST(S) FAILED — check logs in ${LOGDIR}/${NC}"
  echo ""
  echo -e "  ${BOLD}Failed tests:${NC}"
  for i in "${!RESULT_STATUS[@]}"; do
    if [ "${RESULT_STATUS[$i]}" = "FAIL" ]; then
      echo -e "    ${RED}x ${RESULT_NAME[$i]}${NC}"
      echo -e "      log: ${LOGDIR}/${RESULT_NAME[$i]}.log"
    fi
  done
fi

echo ""
echo -e "${BOLD}${CYAN}============================================================${NC}"
echo -e "  Full logs : ${LOGDIR}/"
echo -e "  Summary   : ${SUMMARY_LOG}"
echo -e "${BOLD}${CYAN}============================================================${NC}"
echo ""

# -- Save plain text summary to file --------------------------
{
  echo "CAN UVM Regression"
  echo "Run: $(date)"
  echo "============================================================"
  printf "%-38s %-8s %-7s %-7s %-9s\n" "TEST" "STATUS" "FATAL" "ERROR" "WARNING"
  echo "-----------------------------------------------------------------------"

  PREV_CAT=""
  for i in "${!TESTS[@]}"; do
    CAT="${RESULT_CAT[$i]}"
    if [ "$CAT" != "$PREV_CAT" ]; then
      echo ""
      echo "  ${CAT}"
      PREV_CAT="$CAT"
    fi
    printf "  %-36s %-8s %-7s %-7s %-9s\n" \
      "${RESULT_NAME[$i]}"   \
      "${RESULT_STATUS[$i]}" \
      "${RESULT_FATAL[$i]}"  \
      "${RESULT_ERROR[$i]}"  \
      "${RESULT_WARNING[$i]}"
  done

  echo ""
  echo "-----------------------------------------------------------------------"
  echo "Total=${TOTAL}  Pass=${PASS}  Warn=${WARN}  Fail=${FAIL}  Skip=${SKIP}"

} > "$SUMMARY_LOG"

# -- Exit code -------------------------------------------------
[ "$FAIL" -eq 0 ] && exit 0 || exit 1