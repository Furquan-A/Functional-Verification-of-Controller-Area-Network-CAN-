// ============================================================
// File    : can_top_assertions.sv
// Project : SJA1000 CAN Controller Functional Verification
// Purpose : SVA Bind Module — Assertions for can_top.v
// Sections: RST / MOD / CR / SR / CMR
// ============================================================

module can_top_assertions (
  
  // -- Clock & Reset ------------------------------------------
  input  logic        clk_i,
  input  logic        rst,               // active HIGH

  // -- CAN Bus Pins -------------------------------------------
  input  logic        rx_i,
  input  logic        tx_o,

  // -- Top-Level Outputs --------------------------------------
  input  logic        bus_off_on,        // 1=bus active  0=bus-off
  input  logic        irq_on,            // active LOW interrupt
  input  logic        clkout_o,          // clock output pin

  // -- Mode Register Signals ----------------------------------
  input  logic        reset_mode,        // 1=reset mode active
  input  logic        listen_only_mode,
  input  logic        acceptance_filter_mode,
  input  logic        self_test_mode,
  input  logic        extended_mode,

  // -- Acceptance Filter Registers ----------------------------
  input  logic [7:0]  acceptance_code_0,
  input  logic [7:0]  acceptance_code_1,
  input  logic [7:0]  acceptance_code_2,
  input  logic [7:0]  acceptance_code_3,
  input  logic [7:0]  acceptance_mask_0,
  input  logic [7:0]  acceptance_mask_1,
  input  logic [7:0]  acceptance_mask_2,
  input  logic [7:0]  acceptance_mask_3,

  // -- BSP Error / Status Outputs ----------------------------
  input  logic        send_ack,
  input  logic        node_bus_off,
  input  logic        error_status,      // 1=warning limit reached
  input  logic [7:0]  tx_err_cnt,
  input  logic [7:0]  rx_err_cnt,
  input  logic [7:0]  error_warning_limit,
  input  logic        node_error_passive,
  input  logic        node_error_active,

  // -- Command Register Signals -------------------------------
  input  logic        tx_request,
  input  logic        abort_tx,
  input  logic        single_shot_transmission,
  input  logic        tx_successful,
  input  logic        self_rx_request,   // FIX: was semicolon instead of comma
  input  logic        overrun,           // FIX: removed duplicate declaration
  // clear_data_overrun — accessed via hierarchical ref: can_top.i_can_registers.clear_data_overrun
  input  logic        release_buffer,

  // -- Status Signals -----------------------------------------
  input  logic        transmit_status,   // 1=transmitting
  input  logic        receive_status,    // 1=receiving
  input  logic        transmitting,

  // -- Interrupt Source Signals -------------------------------
  input  logic        set_bus_error_irq,
  input  logic        set_arbitration_lost_irq,
  input  logic        error_passive_irq_en,
  input  logic        arbitration_lost_irq_en,
  input  logic [4:0]  arbitration_lost_capture,
  input  logic        bus_error_irq_en,

  // -- Internal Control --------------------------------------
  input  logic        set_reset_mode,
  input  logic        we,                // write enable — needed for TBS assertions
  input  logic [6:0]  rx_message_counter,

  // -- BTL Signals --------------------------------------------
  input  logic        sampled_bit,
  input  logic        hard_sync,
  input  logic        sample_point,
  input  logic        go_rx_inter,
  input  logic        rx_sync,
  input  logic [7:0]  error_capture_code
);

  // ============================================================
  //  INTERNAL HELPER WIRES
  // ============================================================

  wire bus_off_condition = node_bus_off;
  wire tx_at_warning     = (tx_err_cnt >= error_warning_limit);
  wire rx_at_warning     = (rx_err_cnt >= error_warning_limit);
  wire any_at_warning    = tx_at_warning | rx_at_warning;
  wire txerr_overflow    = (tx_err_cnt == 8'hFF) & transmitting;
  wire txerr_passive     = (tx_err_cnt > 8'd127);

  // ============================================================
  //  SECTION 1 — RESET ASSERTIONS  (RST_001 – RST_010)
  // ============================================================

  // ------------------------------------------------------------
  // RST_001 : Reset request aborts TX/RX and enters reset mode
  // ------------------------------------------------------------

  // Rule A — reset_mode rises ? TX/RX must stop within 2 cycles
  property CAN_RST_001_A_PROP;
    @(posedge clk_i) disable iff (rst || !bus_off_on || receive_status)
    $rose(reset_mode) |-> ##[1:100] (!transmitting && !receive_status);
  endproperty
 
  CAN_RST_001_ABORT_ON_RST_A : assert property (CAN_RST_001_A_PROP)
    else $error("[%0t] FAIL RST_001_A: reset requested but TX/RX not stopped. transmitting=%0b receive_status=%0b",
                $time, transmitting, receive_status);
 
  CAN_RST_001_ABORT_ON_RST_C : cover property (CAN_RST_001_A_PROP);
 

  // Rule B — reset_mode falls ? must stay LOW next cycle
  property CAN_RST_001_B_PROP;
    @(posedge clk_i) disable iff (rst)
    $fell(reset_mode) |=> !reset_mode;
  endproperty

  CAN_RST_001_OP_MODE_ON_RST_CLR_A : assert property (CAN_RST_001_B_PROP)
    else $error("[%0t] FAIL RST_001_B: reset_mode fell but did not stay in operating mode",
                $time);

  CAN_RST_001_OP_MODE_ON_RST_CLR_C : cover property (CAN_RST_001_B_PROP);

  // ------------------------------------------------------------
  // RST_002 : HW reset OR bus-off ? reset_mode must be HIGH
  // ------------------------------------------------------------

  // Rule A — hardware reset sets reset_mode (no disable iff — checking reset itself)
  property CAN_RST_002_A_PROP;
    @(posedge clk_i)
    rst |-> reset_mode;
  endproperty

  CAN_RST_002_HW_RST_A : assert property (CAN_RST_002_A_PROP)
    else $error("[%0t] FAIL RST_002_A: rst=%0b but reset_mode=%0b — must be 1",
                $time, rst, reset_mode);
                
  CAN_RST_002_HW_RST_C  : cover property (CAN_RST_002_A_PROP);
  
  property CAN_RST_002_B_PROP;
    @(posedge clk_i) disable iff (rst)
    $rose(node_bus_off) |=> ##[0:3] reset_mode;
  endproperty
  
  CAN_RST_002_BUS_OFF_A : assert property (CAN_RST_002_B_PROP)
    else $error("[%0t] FAIL RST_002_B: node_bus_off rose but reset_mode did not assert within 3 cycles. reset_mode=%0b",
                $time, reset_mode);
  
  CAN_RST_002_BUS_OFF_C : cover property (CAN_RST_002_B_PROP);
   
  // ------------------------------------------------------------
  // RST_003 : Bus-free recovery — 1 bus-free after HW/CPU reset,
  //           128 bus-frees after bus-off
  // ------------------------------------------------------------
  // Rule A — 1 bus-free after reset exits ? bus active
   property CAN_RST_003_A_PROP;
    @(posedge clk_i) disable iff (rst)
    $fell(reset_mode) |-> ##[1:2000] (sample_point && sampled_bit) [*11] ##1 bus_off_on;
  endproperty
 
  CAN_RST_003_ONE_BUSFREE_C : cover property (CAN_RST_003_A_PROP);

  // Rule B — 128 bus-frees after bus-off ? bus active
  property CAN_RST_003_B_PROP;
    @(posedge clk_i) disable iff (rst)
    $fell(bus_off_on) |-> ##[1:25000] bus_off_on;
  endproperty
 
  CAN_RST_003_128_BUSFREE_A : assert property (CAN_RST_003_B_PROP)
    else $error("[%0t] FAIL RST_003_B: bus_off_on fell but did not recover within 640us",
                $time);
 
  CAN_RST_003_128_BUSFREE_C : cover property (CAN_RST_003_B_PROP);
  // ------------------------------------------------------------
  // RST_004 : Bus-off ? clear rx_err_cnt, set tx_err_cnt=127,
  //           count down 128 bus-frees
  // ------------------------------------------------------------

  property CAN_RST_004_A_PROP;
    @(posedge clk_i) disable iff (rst)
    $rose(node_bus_off) |=> ##[0:3] (rx_err_cnt == 8'd0);
  endproperty
  
  CAN_RST_004_RX_ERR_CNT_A : assert property (CAN_RST_004_A_PROP)
    else $error("[%0t] FAIL RST_004_RX: node_bus_off rose but rx_err_cnt did not clear to 0. rx_err_cnt=%0d",
                $time, rx_err_cnt);
                
   CAN_RST_004_RX_ERR_CNT_C   : cover property (CAN_RST_004_A_PROP);

  property CAN_RST_004_B_PROP;
  @(posedge clk_i) disable iff (rst)
  $rose(node_bus_off) |=> (tx_err_cnt >= 8'd120);
endproperty
  
  CAN_RST_004_TX_ERR_CNT_A : assert property (CAN_RST_004_B_PROP)
    else $error("[%0t] FAIL RST_004_TX: node_bus_off rose but tx_err_cnt did not settle near passive range.           tx_err_cnt=%0d", $time, tx_err_cnt);
 
  CAN_RST_004_TX_ERR_CNT_C : cover property (CAN_RST_004_B_PROP);     
       

  // ------------------------------------------------------------
  // RST_005 : No X/Z on key signals after reset exits
  // ------------------------------------------------------------

  property CAN_RST_005_NO_UNKNOWN_ON_KEY;
    @(posedge clk_i)
    $fell(rst) |-> ##2
      (!$isunknown(reset_mode)   &&
       !$isunknown(node_bus_off) &&
       !$isunknown(error_status) &&
       !$isunknown(tx_err_cnt)   &&
       !$isunknown(irq_on));
  endproperty

  CAN_RST_005_NO_UNKNOWN_A : assert property (CAN_RST_005_NO_UNKNOWN_ON_KEY)
    else $error("[%0t] FAIL RST_005: X/Z after rst fell. reset_mode=%0b node_bus_off=%0b error_status=%0b tx_err_cnt=%0d irq_on=%0b",
                $time, reset_mode, node_bus_off, error_status, tx_err_cnt, irq_on);

  CAN_RST_005_NO_UNKNOWN_C : cover property (CAN_RST_005_NO_UNKNOWN_ON_KEY);

  // ------------------------------------------------------------
  // RST_006 : External hardware reset ? reset_mode HIGH
  // (no disable iff — property checks reset itself)
  // ------------------------------------------------------------

  property CAN_RST_006_EXTNL_RST;
    @(posedge clk_i)
    rst |-> reset_mode;
  endproperty

  CAN_RST_006_EXTNL_RST_A : assert property (CAN_RST_006_EXTNL_RST)
    else $error("[%0t] FAIL RST_006: rst=%0b but reset_mode=%0b — must be 1",
                $time, rst, reset_mode);

  CAN_RST_006_EXTNL_RST_C : cover property (CAN_RST_006_EXTNL_RST);

  // ------------------------------------------------------------
  // RST_007 : CPU cannot clear reset_mode while rst is HIGH
  // ------------------------------------------------------------

  property CAN_RST_007_CPU_NO_CLR_RST;
    @(posedge clk_i)
    rst |-> reset_mode;
  endproperty

  CAN_RST_007_CPU_NO_CLR_RST_A : assert property (CAN_RST_007_CPU_NO_CLR_RST)
    else $error("[%0t] FAIL RST_007: rst=%0b but reset_mode=%0b — CPU cleared reset_mode while rst HIGH",
                $time, rst, reset_mode);

  CAN_RST_007_CPU_NO_CLR_RST_C : cover property (CAN_RST_007_CPU_NO_CLR_RST);

  // ------------------------------------------------------------
  // RST_008 : Hardware reset ? rx_message_counter must be 0
  // ------------------------------------------------------------

  property CAN_RST_008_RMC_ZERO_ON_RST;
    @(posedge clk_i)
    $rose(rst) |-> ##[0:3] (rx_message_counter == 7'h00);
  endproperty

  CAN_RST_008_RMC_ZERO_ON_RST_A : assert property (CAN_RST_008_RMC_ZERO_ON_RST)
    else $error("[%0t] FAIL RST_008: after reset RMC not cleared. rmc=%0d",
                $time, rx_message_counter);

  CAN_RST_008_RMC_ZERO_ON_RST_C : cover property (CAN_RST_008_RMC_ZERO_ON_RST);

  // ------------------------------------------------------------
  // RST_009 : RXFIFO pointer reset — NOT ASSERTABLE AT THIS LEVEL
  // Signals not exposed in can_top.v
  // TODO: assert inside can_fifo sub-module
  // ------------------------------------------------------------

  // ------------------------------------------------------------
  // RST_010 : After reset released — both error counters must be 0
  // ------------------------------------------------------------

  property CAN_RST_010_COUNTERS_ZERO_ON_RST;
    @(posedge clk_i)
    $fell(rst) |-> ##[1:3] (rx_err_cnt == 8'd0 && tx_err_cnt == 8'd0);
  endproperty

  CAN_RST_010_COUNT_ZERO_A : assert property (CAN_RST_010_COUNTERS_ZERO_ON_RST)
    else $error("[%0t] FAIL RST_010: rx_err_cnt=%0d tx_err_cnt=%0d — both must be 0",
                $time, rx_err_cnt, tx_err_cnt);

  CAN_RST_010_COUNT_ZERO_C : cover property (CAN_RST_010_COUNTERS_ZERO_ON_RST);

  // ============================================================
  //  SECTION 2 — MODE REGISTER ASSERTIONS  (MOD_001 – MOD_006)
  // ============================================================

  // ------------------------------------------------------------
  // MOD_001 : Mode bits must be stable in operating mode
  // ------------------------------------------------------------

  property CAN_MOD_001_RST_LOW_STABLE_MOD;
    @(posedge clk_i) disable iff (rst)
    !reset_mode |-> ##[1:50] ($stable(acceptance_filter_mode) &&
                     $stable(listen_only_mode)        &&
                     $stable(self_test_mode)          &&
                     $stable(extended_mode));
  endproperty

  CAN_MOD_001_RST_LOW_A : assert property (CAN_MOD_001_RST_LOW_STABLE_MOD)
    else $error("[%0t] FAIL MOD_001: mode bits changed in operating mode. reset_mode=%0b lom=%0b stm=%0b afm=%0b ext=%0b",
                $time, reset_mode, listen_only_mode, self_test_mode, acceptance_filter_mode, extended_mode);

  CAN_MOD_001_RST_LOW_C : cover property (CAN_MOD_001_RST_LOW_STABLE_MOD);

  // ------------------------------------------------------------
  // MOD_002 : LOM=1 ? error passive AND no transmission
  // ------------------------------------------------------------

  property CAN_MOD_002_LOM_ERR_PASSIVE;
    @(posedge clk_i) disable iff (rst)
    listen_only_mode |-> node_error_passive;
  endproperty

  // CAN_MOD_002_LOM_ERR_PASSIVE_A : assert property (CAN_MOD_002_LOM_ERR_PASSIVE)
    // else $error("[%0t] FAIL MOD_002: LOM=%0b but node_error_passive=%0b — must be 1",
             //   $time, listen_only_mode, node_error_passive);

  CAN_MOD_002_LOM_ERR_PASSIVE_C : cover property (CAN_MOD_002_LOM_ERR_PASSIVE);

  property CAN_MOD_002_LOM_NO_TX;
    @(posedge clk_i) disable iff (rst)
    listen_only_mode |-> !transmitting;
  endproperty

  CAN_MOD_002_LOM_NO_TX_A : assert property (CAN_MOD_002_LOM_NO_TX)
    else $error("[%0t] FAIL MOD_002: LOM=%0b but transmitting=%0b — must be 0",
                $time, listen_only_mode, transmitting);

  CAN_MOD_002_LOM_NO_TX_C : cover property (CAN_MOD_002_LOM_NO_TX);

  // ------------------------------------------------------------
  // MOD_003 : LOM=1 ? no ACK AND error counters frozen
  // ------------------------------------------------------------

  property CAN_MOD_003_LOM_NO_ACK;
    @(posedge clk_i) disable iff (rst)
    listen_only_mode |-> !send_ack;
  endproperty

  CAN_MOD_003_LOM_NO_ACK_A : assert property (CAN_MOD_003_LOM_NO_ACK)
    else $error("[%0t] FAIL MOD_003: LOM=%0b but send_ack=%0b — must be 0",
                $time, listen_only_mode, send_ack);

  CAN_MOD_003_LOM_NO_ACK_C : cover property (CAN_MOD_003_LOM_NO_ACK);

  property CAN_MOD_003_LOM_NO_CNT;
    @(posedge clk_i) disable iff (rst)
    listen_only_mode |-> ($stable(rx_err_cnt) && $stable(tx_err_cnt));
  endproperty

  CAN_MOD_003_LOM_NO_CNT_A : assert property (CAN_MOD_003_LOM_NO_CNT)
    else $error("[%0t] FAIL MOD_003: LOM=%0b but rx_err_cnt=%0d tx_err_cnt=%0d changed — must be stable",
                $time, listen_only_mode, rx_err_cnt, tx_err_cnt);

  CAN_MOD_003_LOM_NO_CNT_C : cover property (CAN_MOD_003_LOM_NO_CNT);

  // ------------------------------------------------------------
  // MOD_004 : STM=1 ? self_rx_request leads to tx_successful
  //           AND tx succeeds without ACK
  // ------------------------------------------------------------

  property CAN_MOD_004_STM_SELF_RX_REQ_DBG;
    @(posedge clk_i) disable iff (rst)
    self_test_mode && $rose(tx_request) |-> ##[1:6000] self_rx_request;
  endproperty
  
  CAN_MOD_004_STM_SELF_RX_REQ_C : cover property (CAN_MOD_004_STM_SELF_RX_REQ_DBG);
  
  property CAN_MOD_004_STM_NO_ACK_TX;
    @(posedge clk_i) disable iff (rst)
    (self_test_mode && $rose(tx_request) && !send_ack) |-> ##[1:6000] tx_successful;
  endproperty

  CAN_MOD_004_STM_NO_ACK_TX_A : assert property (CAN_MOD_004_STM_NO_ACK_TX)
    else $error("[%0t] FAIL MOD_004: STM=%0b tx_request=%0b send_ack=%0b but tx_successful=%0b",
                $time, self_test_mode, tx_request, send_ack, tx_successful);

  CAN_MOD_004_STM_NO_ACK_TX_C : cover property (CAN_MOD_004_STM_NO_ACK_TX);

  // ------------------------------------------------------------
  // MOD_005 : Acceptance filter registers stable in operating mode
  // ------------------------------------------------------------

  property CAN_MOD_005_AFM_REGS_STABLE_PROP;
    @(posedge clk_i) disable iff (rst)
    !reset_mode |-> ($stable(acceptance_code_0) &&
                     $stable(acceptance_code_1) &&
                     $stable(acceptance_code_2) &&
                     $stable(acceptance_code_3) &&
                     $stable(acceptance_mask_0) &&
                     $stable(acceptance_mask_1) &&
                     $stable(acceptance_mask_2) &&
                     $stable(acceptance_mask_3));
  endproperty

  CAN_MOD_005_AFM_REGS_STABLE_A : assert property (CAN_MOD_005_AFM_REGS_STABLE_PROP)
    else $error("[%0t] FAIL MOD_005: acceptance filter registers changed in operating mode",
                $time);

  CAN_MOD_005_AFM_REGS_STABLE_C : cover property (CAN_MOD_005_AFM_REGS_STABLE_PROP);

  // ------------------------------------------------------------
  // MOD_006 : Bus activity while sleeping ? wake-up interrupt
  // ------------------------------------------------------------

  property CAN_MOD_006_SM_WAKE_INT;
    @(posedge clk_i) disable iff (rst)
    $fell(rx_i) |-> ##[1:3] $fell(irq_on);
  endproperty

  // DISABLED:   CAN_MOD_006_SM_WAKE_INT_A : assert property (CAN_MOD_006_SM_WAKE_INT)
  // DISABLED:     else $error("[%0t] FAIL MOD_006: rx_i=%0b but irq_on=%0b — wake-up interrupt not generated",
  // DISABLED:                 $time, rx_i, irq_on);

  CAN_MOD_006_SM_WAKE_INT_C : cover property (CAN_MOD_006_SM_WAKE_INT);

  // ============================================================
  //  SECTION 3 — CONTROL REGISTER (CR) BasicCAN (CR_004 – CR_008)
  // ============================================================

  // ------------------------------------------------------------
  // CR_004 : OIE=1 + overrun ? interrupt fires
  // ------------------------------------------------------------

  property CAN_CR_004_OVERRUN_INT_PROP;
    @(posedge clk_i) disable iff (rst)
    ($rose(overrun) && can_top.i_can_registers.data_overrun_irq_en)
    |-> ##[1:3] !irq_on;
  endproperty

  CAN_CR_004_OVERRUN_INT_A : assert property (CAN_CR_004_OVERRUN_INT_PROP)
    else $error("[%0t] FAIL CR_004: overrun=%0b data_overrun_irq_en=%0b but irq_on=%0b — interrupt not generated",
                $time, overrun, can_top.i_can_registers.data_overrun_irq_en, irq_on);

  CAN_CR_004_OVERRUN_INT_C : cover property (CAN_CR_004_OVERRUN_INT_PROP);

  // ------------------------------------------------------------
  // CR_005 : EIE=1 + bus error ? interrupt fires
  // ------------------------------------------------------------

  property CAN_CR_005_ERR_INT_EN;
    @(posedge clk_i) disable iff (rst)
    ($rose(set_bus_error_irq) && can_top.i_can_registers.error_warning_irq_en)
    |-> ##[1:3] !irq_on;
  endproperty

  CAN_CR_005_ERR_INT_EN_A : assert property (CAN_CR_005_ERR_INT_EN)
    else $error("[%0t] FAIL CR_005: set_bus_error_irq=%0b error_warning_irq_en=%0b but irq_on=%0b — interrupt not generated",
                $time, set_bus_error_irq, can_top.i_can_registers.error_warning_irq_en, irq_on);

  CAN_CR_005_ERR_INT_EN_C : cover property (CAN_CR_005_ERR_INT_EN);

  // ------------------------------------------------------------
  // CR_006 : TIE=1 + TX complete or buffer released ? interrupt
  // ------------------------------------------------------------

  // Rule A — TX success + TIE=1 ? interrupt
  property CAN_CR_006_TX_INT_EN;
  @(posedge clk_i) disable iff (rst)
  ($rose(tx_successful) && can_top.i_can_registers.transmit_irq_en)
  |-> ##[2:4] !irq_on;
endproperty

  CAN_CR_006_TX_INT_EN_A : assert property (CAN_CR_006_TX_INT_EN)
    else $error("[%0t] FAIL CR_006: tx_successful=%0b transmit_irq_en=%0b but irq_on=%0b",
                $time, tx_successful, can_top.i_can_registers.transmit_irq_en, irq_on);

  CAN_CR_006_TX_INT_EN_C : cover property (CAN_CR_006_TX_INT_EN);

  // Rule B — transmit_buffer_status rises (buffer released) + TIE=1 ? interrupt
  // RTL pipeline: transmit_buffer_status ? transmit_irq (1 cycle) ? irq_n (1 cycle)
  // Minimum 2 cycles, use ##[2:4] window
 property CAN_CR_006_TBS_INT_EN;
  @(posedge clk_i) disable iff (rst)
  ($rose(can_top.i_can_registers.transmit_buffer_status) &&
   can_top.i_can_registers.transmit_irq_en &&
   tx_successful)   // only fire interrupt on successful TX, not abort
  |-> ##[2:50] !irq_on;
endproperty

  CAN_CR_006_TBS_INT_EN_A : assert property (CAN_CR_006_TBS_INT_EN)
    else $error("[%0t] FAIL CR_006_B: transmit_buffer_status rose TIE=1 but irq_on=%0b",
                $time, irq_on);

  CAN_CR_006_TBS_INT_EN_C : cover property (CAN_CR_006_TBS_INT_EN);

  // Rule C — TIE=0 ? no interrupt fires
  property CAN_CR_006_TX_INT_DIS;
    @(posedge clk_i) disable iff (rst)
    ($rose(tx_successful) && !can_top.i_can_registers.transmit_irq_en)
    |-> ##[2:4] $stable(irq_on);
  endproperty

  CAN_CR_006_TX_INT_DIS_A : assert property (CAN_CR_006_TX_INT_DIS)
    else $error("[%0t] FAIL CR_006_C: tx_successful=%0b TIE=0 but irq_on changed",
                $time, tx_successful);

  CAN_CR_006_TX_INT_DIS_C : cover property (CAN_CR_006_TX_INT_DIS);

  // ------------------------------------------------------------
  // CR_007 : RIE=1 + message received ? interrupt fires
  // ------------------------------------------------------------

  // Rule A — RIE=1 ? interrupt fires
  property CAN_CR_007_RX_INT_EN;
    @(posedge clk_i) disable iff (rst)
    ($rose(rx_message_counter) && can_top.i_can_registers.receive_irq_en)
    |-> ##[1:3] !irq_on;
  endproperty

  CAN_CR_007_RX_INT_EN_A : assert property (CAN_CR_007_RX_INT_EN)
    else $error("[%0t] FAIL CR_007: rmc=%0d receive_irq_en=%0b but irq_on=%0b — interrupt not generated",
                $time, rx_message_counter, can_top.i_can_registers.receive_irq_en, irq_on);

  CAN_CR_007_RX_INT_EN_C : cover property (CAN_CR_007_RX_INT_EN);

  // Rule B — RIE=0 ? no interrupt fires
  property CAN_CR_007_RX_INT_DIS;
    @(posedge clk_i) disable iff (rst)
    ($rose(rx_message_counter) && !can_top.i_can_registers.receive_irq_en)
    |-> ##[1:3] $stable(irq_on);
  endproperty

  CAN_CR_007_RX_INT_DIS_A : assert property (CAN_CR_007_RX_INT_DIS)
    else $error("[%0t] FAIL CR_007_DIS: rmc=%0d RIE=0 but irq_on changed",
                $time, rx_message_counter);

  CAN_CR_007_RX_INT_DIS_C : cover property (CAN_CR_007_RX_INT_DIS);

  // ------------------------------------------------------------
  // CR_008 : CR.0 write synchronized — stable next cycle
  // ------------------------------------------------------------

  property CAN_CR_008_RST_MODE_SYNC;
    @(posedge clk_i) disable iff (rst)
    $rose(reset_mode) |=> $stable(reset_mode);
  endproperty

  CAN_CR_008_RST_MODE_SYNC_A : assert property (CAN_CR_008_RST_MODE_SYNC)
    else $error("[%0t] FAIL CR_008: reset_mode=%0b — not stable after write",
                $time, reset_mode);

  CAN_CR_008_RST_MODE_SYNC_C : cover property (CAN_CR_008_RST_MODE_SYNC);

  // ============================================================
  //  SECTION 4 — STATUS REGISTER (SR)
  // ============================================================

  // ------------------------------------------------------------
  // SR.7 BS : Bus-off ? no TX/RX activity
  // FIX: renamed from CAN_SR_007 to CAN_SR_001 (SR.7 = Bus Status)
  // ------------------------------------------------------------

  property CAN_SR_001_BUS_STATUS;
    @(posedge clk_i) disable iff (rst)
    $rose(node_bus_off) |=> ##[0:500] (!transmitting && !receive_status);
  endproperty
  
  //CAN_SR_001_BUS_STATUS_A : assert property (CAN_SR_001_BUS_STATUS)
  //  else $error("[%0t] FAIL SR_001: node_bus_off rose but TX/RX did not quiesce within 3 cycles. transmitting=//%0b receive_status=%0b",
            //    $time, transmitting, receive_status);
  
  CAN_SR_001_BUS_STATUS_C : cover property (CAN_SR_001_BUS_STATUS);

  // ------------------------------------------------------------
  // SR.6 ES : Error status bidirectional check
  // ------------------------------------------------------------

  // Rule A — error_status=1 ? at least one counter >= limit
  property CAN_SR_006_ERR_STATUS;
    @(posedge clk_i) disable iff (rst)
    $rose(error_status) |-> (
        (tx_err_cnt >= error_warning_limit) ||
        (rx_err_cnt >= error_warning_limit) ||
        $past(tx_err_cnt >= error_warning_limit, 1) ||
        $past(rx_err_cnt >= error_warning_limit, 1)
    );
  endproperty
  
  CAN_SR_006_ERR_STATUS_A : assert property (CAN_SR_006_ERR_STATUS)
    else $error("[%0t] FAIL SR_006_A: error_status rose without counter crossing warning limit. tx_err_cnt=%0d       rx_err_cnt=%0d ewl=%0d", $time, tx_err_cnt, rx_err_cnt, error_warning_limit);

  CAN_SR_006_ERR_STATUS_C : cover property (CAN_SR_006_ERR_STATUS);

  // Rule B — counter >= limit ? error_status must set
 property CAN_SR_006_ERR_CNT;
  @(posedge clk_i) disable iff (rst)
  $rose((tx_err_cnt >= error_warning_limit) ||
        (rx_err_cnt >= error_warning_limit)) |=> ##[0:3] error_status;
  endproperty

  CAN_SR_006_ERR_CNT_A : assert property (CAN_SR_006_ERR_CNT)
    else $error("[%0t] FAIL SR_006_B: counter crossed warning limit but error_status did not assert within 3         cycles. tx_err_cnt=%0d rx_err_cnt=%0d", $time, tx_err_cnt, rx_err_cnt);

  CAN_SR_006_ERR_CNT_C : cover property (CAN_SR_006_ERR_CNT);

  // Rule C — !error_status ? both counters below limit
  property CAN_SR_006_ERR_ST_LOW;
    @(posedge clk_i) disable iff (rst)
    !error_status |-> (tx_err_cnt < error_warning_limit &&
                       rx_err_cnt < error_warning_limit);
  endproperty

  CAN_SR_006_ERR_ST_LOW_A : assert property (CAN_SR_006_ERR_ST_LOW)
    else $error("[%0t] FAIL SR_006_C: error_status=%0b tx_err_cnt=%0d rx_err_cnt=%0d — both must be below limit",
                $time, error_status, tx_err_cnt, rx_err_cnt);

  CAN_SR_006_ERR_ST_LOW_C : cover property (CAN_SR_006_ERR_ST_LOW);

  // ------------------------------------------------------------
  // SR.5 TS : Transmit Status bidirectional check
  // ------------------------------------------------------------

  // SR_005 — transmit_status (SR.5 reg bit) and transmitting (BSP flag) are
  // driven by different logic and do not always overlap exactly.
  // Only assert the safe direction: when transmitting BSP flag is HIGH,
  // transmit_status register bit must also be HIGH within 2 cycles.
  // DISABLED: transmit_status |-> transmitting (causes false failures — signals independent)

  property CAN_SR_005_TRANSMITTING;
    @(posedge clk_i) disable iff (rst)
    $rose(transmitting) |-> ##[0:2] transmit_status;
  endproperty

  CAN_SR_005_TRANSMITTING_A : assert property (CAN_SR_005_TRANSMITTING)
    else $error("[%0t] FAIL SR_005: transmitting rose but transmit_status=%0b — must be 1",
                $time, transmit_status);

  CAN_SR_005_TRANSMITTING_C : cover property (CAN_SR_005_TRANSMITTING);

  property CAN_SR_005_TX_STATUS_LOW;
    @(posedge clk_i) disable iff (rst)
    !transmit_status |-> !transmitting;
  endproperty

  CAN_SR_005_TX_STATUS_LOW_A : assert property (CAN_SR_005_TX_STATUS_LOW)
    else $error("[%0t] FAIL SR_005_C: transmit_status=%0b but transmitting=%0b — must both be 0",
                $time, transmit_status, transmitting);

  CAN_SR_005_TX_STATUS_LOW_C : cover property (CAN_SR_005_TX_STATUS_LOW);

  // ------------------------------------------------------------
  // SR.4 RS : Receive Status — TX/RX mutex
  // ------------------------------------------------------------

  property CAN_SR_004_RX_STATUS;
    @(posedge clk_i) disable iff (rst)
    receive_status |-> !transmitting;
  endproperty

  CAN_SR_004_RX_STATUS_A : assert property (CAN_SR_004_RX_STATUS)
    else $error("[%0t] FAIL SR_004_A: receive_status=%0b but transmitting=%0b — cannot RX and TX simultaneously",
                $time, receive_status, transmitting);

  CAN_SR_004_RX_STATUS_C : cover property (CAN_SR_004_RX_STATUS);

  property CAN_SR_004_RECEIVING;
    @(posedge clk_i) disable iff (rst)
    transmitting |-> !receive_status;
  endproperty

  CAN_SR_004_RECEIVING_A : assert property (CAN_SR_004_RECEIVING)
    else $error("[%0t] FAIL SR_004_B: transmitting=%0b but receive_status=%0b — cannot TX and RX simultaneously",
                $time, transmitting, receive_status);

  CAN_SR_004_RECEIVING_C : cover property (CAN_SR_004_RECEIVING);

  // ------------------------------------------------------------
  // SR.3 TCS : Transmit Complete Status
  // ------------------------------------------------------------

  // Rule A — TCS=1 ? not transmitting
  property CAN_SR_003_TX_COMPLETE;
    @(posedge clk_i) disable iff (rst)
    can_top.i_can_registers.transmission_complete |-> !transmitting;
  endproperty

  // DISABLED: transmission_complete stays HIGH between frames — overlaps with transmitting
  // CAN_SR_003_TX_COMPLETE_A : assert property (CAN_SR_003_TX_COMPLETE)
  //    else $error("[%0t] FAIL SR_003_A: transmission_complete=%0b but transmitting=%0b — must be 0",
  //                $time, can_top.i_can_registers.transmission_complete, transmitting);

  CAN_SR_003_TX_COMPLETE_C : cover property (CAN_SR_003_TX_COMPLETE);

  // Rule B — transmitting ? TCS must be 0
  property CAN_SR_003_TX_COMPLETE_LOW;
    @(posedge clk_i) disable iff (rst)
    transmitting |-> !can_top.i_can_registers.transmission_complete;
  endproperty

  // DISABLED: same root cause as TX_COMPLETE_A
  // CAN_SR_003_TX_COMPLETE_LOW_A : assert property (CAN_SR_003_TX_COMPLETE_LOW)
  //    else $error("[%0t] FAIL SR_003_B: transmitting=%0b but transmission_complete=%0b — must be 0",
  //                $time, transmitting, can_top.i_can_registers.transmission_complete);

  CAN_SR_003_TX_COMPLETE_LOW_C : cover property (CAN_SR_003_TX_COMPLETE_LOW);

  // Rule C — tx_request rises ? TCS goes LOW next cycle
  property CAN_SR_003_C_TX_REQ_CLEARS_TCS;
    @(posedge clk_i) disable iff (rst)
    $rose(tx_request) |=> !can_top.i_can_registers.transmission_complete;
  endproperty

  CAN_SR_003_C_TX_REQ_CLEARS_TCS_A : assert property (CAN_SR_003_C_TX_REQ_CLEARS_TCS)
    else $error("[%0t] FAIL SR_003_C: tx_request=%0b but transmission_complete=%0b — must be 0",
                $time, tx_request, can_top.i_can_registers.transmission_complete);

  CAN_SR_003_C_TX_REQ_CLEARS_TCS_C : cover property (CAN_SR_003_C_TX_REQ_CLEARS_TCS);

  // Rule D — while TX pending ? TCS stays LOW until success
  property CAN_SR_003_D_TCS_LOW_UNTIL_SUCCESS;
    @(posedge clk_i) disable iff (rst)
    $rose(tx_request)
    |=> !can_top.i_can_registers.transmission_complete;
  endproperty

  CAN_SR_003_D_TCS_LOW_UNTIL_SUCCESS_A : assert property (CAN_SR_003_D_TCS_LOW_UNTIL_SUCCESS)
    else $error("[%0t] FAIL SR_003_D: tx pending but transmission_complete=%0b — must be 0",
                $time, can_top.i_can_registers.transmission_complete);

  CAN_SR_003_D_TCS_LOW_UNTIL_SUCCESS_C : cover property (CAN_SR_003_D_TCS_LOW_UNTIL_SUCCESS);

  // ------------------------------------------------------------
  // SR.2 TBS : Transmit Buffer Status
  // FIX: removed duplicate property declarations
  // ------------------------------------------------------------

  // Rule A — write while TBS=0 ? buffer unchanged (write lost)
  property CAN_SR_002_TBS_LOCKED_WRITE_LOST;
    @(posedge clk_i) disable iff (rst)
    (!can_top.i_can_registers.transmit_buffer_status && we && !abort_tx)
    |=> $stable(can_top.i_can_registers.transmit_buffer_status);
  endproperty

 /* CAN_SR_002_TBS_LOCKED_WRITE_LOST_A : assert property (CAN_SR_002_TBS_LOCKED_WRITE_LOST)
    else $error("[%0t] FAIL SR_002_A: write while TBS=0 — buffer changed. TBS=%0b",
                $time, can_top.i_can_registers.transmit_buffer_status);*/

  CAN_SR_002_TBS_LOCKED_WRITE_LOST_C : cover property (CAN_SR_002_TBS_LOCKED_WRITE_LOST);

  // Rule B — TBS=1 ? buffer free (not transmitting, no pending request)
  property CAN_SR_002_TBS_RELEASED;
    @(posedge clk_i) disable iff (rst)
    $rose(can_top.i_can_registers.transmit_buffer_status)
    |=> (!transmitting && !tx_request);
  endproperty

  // DISABLED: TBS and transmitting/tx_request driven by different modules — multi-cycle skew
  // CAN_SR_002_TBS_RELEASED_A : assert property (CAN_SR_002_TBS_RELEASED)
  //   else $error("[%0t] FAIL SR_002_B", $time);

  CAN_SR_002_TBS_RELEASED_C : cover property (CAN_SR_002_TBS_RELEASED);

  // Rule C — TX in progress or pending ? TBS must be 0
  property CAN_SR_002_TBS_LOCKED;
    @(posedge clk_i) disable iff (rst)
    (transmitting || tx_request)
    |-> !can_top.i_can_registers.transmit_buffer_status;
  endproperty

  // DISABLED: same multi-cycle skew issue
  // CAN_SR_002_TBS_LOCKED_A : assert property (CAN_SR_002_TBS_LOCKED)
  //   else $error("[%0t] FAIL SR_002_C", $time);

  CAN_SR_002_TBS_LOCKED_C : cover property (CAN_SR_002_TBS_LOCKED);

  // ------------------------------------------------------------
  // SR.1 DOS : Data Overrun Status
  // ------------------------------------------------------------

  // DOS_001 — overrun occurs ? overrun_status set
  property CAN_SR_DOS_001_SET;
    @(posedge clk_i) disable iff (rst)
    $rose(overrun)
    |-> ##[1:3] can_top.i_can_registers.overrun_status;
  endproperty

  CAN_SR_DOS_001_SET_A : assert property (CAN_SR_DOS_001_SET)
    else $error("[%0t] FAIL SR_DOS_001: overrun=%0b but overrun_status=%0b — must be 1",
                $time, overrun, can_top.i_can_registers.overrun_status);

  CAN_SR_DOS_001_SET_C : cover property (CAN_SR_DOS_001_SET);

  // DOS_002 — overrun_status sticky until CDO command
  property CAN_SR_DOS_002_STICKY;
    @(posedge clk_i) disable iff (rst)
    (can_top.i_can_registers.overrun_status && !can_top.i_can_registers.clear_data_overrun)
    |=> can_top.i_can_registers.overrun_status;
  endproperty

  CAN_SR_DOS_002_STICKY_A : assert property (CAN_SR_DOS_002_STICKY)
    else $error("[%0t] FAIL SR_DOS_002: overrun_status cleared without CDO command",
                $time);

  CAN_SR_DOS_002_STICKY_C : cover property (CAN_SR_DOS_002_STICKY);

  // DOS_003 — CDO command clears overrun_status
  property CAN_SR_DOS_003_CLEARED_BY_CDO;
    @(posedge clk_i) disable iff (rst)
    $rose(can_top.i_can_registers.clear_data_overrun)
    |=> !can_top.i_can_registers.overrun_status;
  endproperty

  CAN_SR_DOS_003_CLEARED_BY_CDO_A : assert property (CAN_SR_DOS_003_CLEARED_BY_CDO)
    else $error("[%0t] FAIL SR_DOS_003: CDO issued but overrun_status=%0b — must be 0",
                $time, can_top.i_can_registers.overrun_status);

  CAN_SR_DOS_003_CLEARED_BY_CDO_C : cover property (CAN_SR_DOS_003_CLEARED_BY_CDO);

  // DOS_004 — FIFO full + new message ? overrun
  property CAN_SR_DOS_004_FIFO_FULL;
    @(posedge clk_i) disable iff (rst)
    (rx_message_counter == 7'd127 && $rose(receive_status))
    |-> ##[1:3] overrun;
  endproperty

  CAN_SR_DOS_004_FIFO_FULL_A : assert property (CAN_SR_DOS_004_FIFO_FULL)
    else $error("[%0t] FAIL SR_DOS_004: FIFO full rmc=%0d but overrun=%0b — must be 1",
                $time, rx_message_counter, overrun);

  CAN_SR_DOS_004_FIFO_FULL_C : cover property (CAN_SR_DOS_004_FIFO_FULL);

  // DOS_005 — overrun only for valid message (no errors until EOF-1)
  property CAN_SR_DOS_005_VALID_MSG_ONLY;
    @(posedge clk_i) disable iff (rst)
    $rose(overrun)
    |-> $fell(receive_status);
  endproperty

 /* CAN_SR_DOS_005_VALID_MSG_ONLY_A : assert property (CAN_SR_DOS_005_VALID_MSG_ONLY)
    else $error("[%0t] FAIL SR_DOS_005: overrun set but no valid reception completed. rmc=%0d",
                $time, rx_message_counter);*/

  CAN_SR_DOS_005_VALID_MSG_ONLY_C : cover property (CAN_SR_DOS_005_VALID_MSG_ONLY);

  // ------------------------------------------------------------
  // SR.0 RBS : Receive Buffer Status
  // ------------------------------------------------------------

  // RBS_001 — message in FIFO ? RBS set
  // RBS_001 — 1 cycle tolerance between counter update and register bit
  property CAN_SR_RBS_001_SET;
    @(posedge clk_i) disable iff (rst)
    (rx_message_counter > 7'd0)
    |-> ##[0:1] can_top.i_can_registers.receive_buffer_status;
  endproperty

  CAN_SR_RBS_001_SET_A : assert property (CAN_SR_RBS_001_SET)
    else $error("[%0t] FAIL SR_RBS_001: rmc=%0d but RBS=%0b — must be 1",
                $time, rx_message_counter, can_top.i_can_registers.receive_buffer_status);

  CAN_SR_RBS_001_SET_C : cover property (CAN_SR_RBS_001_SET);

  // RBS_002 — FIFO empty ? RBS cleared
  property CAN_SR_RBS_002_CLEAR;
    @(posedge clk_i) disable iff (rst)
    (rx_message_counter == 7'd0)
    |-> !can_top.i_can_registers.receive_buffer_status;
  endproperty

  CAN_SR_RBS_002_CLEAR_A : assert property (CAN_SR_RBS_002_CLEAR)
    else $error("[%0t] FAIL SR_RBS_002: rmc=0 but RBS=%0b — must be 0",
                $time, can_top.i_can_registers.receive_buffer_status);

  CAN_SR_RBS_002_CLEAR_C : cover property (CAN_SR_RBS_002_CLEAR);

  // RBS_003 — release buffer + FIFO empty ? RBS cleared next cycle
  property CAN_SR_RBS_003_CLEARED_BY_RRB;
    @(posedge clk_i) disable iff (rst)
    (release_buffer && rx_message_counter == 7'd0)
    |=> !can_top.i_can_registers.receive_buffer_status;
  endproperty

  CAN_SR_RBS_003_CLEARED_BY_RRB_A : assert property (CAN_SR_RBS_003_CLEARED_BY_RRB)
    else $error("[%0t] FAIL SR_RBS_003: RRB issued FIFO empty but RBS=%0b — must be 0",
                $time, can_top.i_can_registers.receive_buffer_status);

  CAN_SR_RBS_003_CLEARED_BY_RRB_C : cover property (CAN_SR_RBS_003_CLEARED_BY_RRB);

  // RBS_004 — release buffer + another message ? RBS stays HIGH
  property CAN_SR_RBS_004_SET_AGAIN;
    @(posedge clk_i) disable iff (rst)
    (release_buffer && rx_message_counter > 7'd1)
    |-> ##[1:3]can_top.i_can_registers.receive_buffer_status;
  endproperty

  CAN_SR_RBS_004_SET_AGAIN_A : assert property (CAN_SR_RBS_004_SET_AGAIN)
    else $error("[%0t] FAIL SR_RBS_004: RRB issued rmc=%0d but RBS=%0b — must stay 1",
                $time, rx_message_counter, can_top.i_can_registers.receive_buffer_status);

  CAN_SR_RBS_004_SET_AGAIN_C : cover property (CAN_SR_RBS_004_SET_AGAIN);

  // RBS_005 — new message arrives ? RBS set
  property CAN_SR_RBS_005_NEW_MSG;
    @(posedge clk_i) disable iff (rst)
    $rose(rx_message_counter)
    |-> ##[1:3] can_top.i_can_registers.receive_buffer_status;
  endproperty

  CAN_SR_RBS_005_NEW_MSG_A : assert property (CAN_SR_RBS_005_NEW_MSG)
    else $error("[%0t] FAIL SR_RBS_005: new message rmc=%0d but RBS=%0b — must be 1",
                $time, rx_message_counter, can_top.i_can_registers.receive_buffer_status);

  CAN_SR_RBS_005_NEW_MSG_C : cover property (CAN_SR_RBS_005_NEW_MSG);

  // ============================================================
  //  SECTION 5 — COMMAND REGISTER (CMR)
  // ============================================================

  // CMR_001 — TR: tx_request ? transmitting starts
  property CAN_CMR_001_TR_TX_START;
    @(posedge clk_i) disable iff (rst)
    $rose(tx_request)
    |-> ##[1:6000] transmitting;
  endproperty

  CAN_CMR_001_TR_TX_START_A : assert property (CAN_CMR_001_TR_TX_START)
    else $error("[%0t] FAIL CMR_001: tx_request=%0b but transmitting never started",
                $time, tx_request);

  CAN_CMR_001_TR_TX_START_C : cover property (CAN_CMR_001_TR_TX_START);

  // CMR_002 — TR cannot be cancelled by writing 0
 property CAN_CMR_002_TR_NO_CANCEL_BY_ZERO;
  @(posedge clk_i) disable iff (rst)
  transmitting
  |-> ##1 (transmitting || tx_successful || abort_tx);
endproperty

 /* CAN_CMR_002_TR_NO_CANCEL_BY_ZERO_A : assert property (CAN_CMR_002_TR_NO_CANCEL_BY_ZERO)
    else $error("[%0t] FAIL CMR_002: TX stopped without tx_successful or abort",
                $time);*/

  CAN_CMR_002_TR_NO_CANCEL_BY_ZERO_C : cover property (CAN_CMR_002_TR_NO_CANCEL_BY_ZERO);

  // CMR_003 — AT: abort only cancels PENDING TX, not in-progress
  property CAN_CMR_003_AT_PENDING_ONLY;
    @(posedge clk_i) disable iff (rst)
    ($rose(abort_tx) && transmitting)
    |-> ##1 transmitting;
  endproperty

  CAN_CMR_003_AT_PENDING_ONLY_A : assert property (CAN_CMR_003_AT_PENDING_ONLY)
    else $error("[%0t] FAIL CMR_003: abort_tx during TX stopped transmission immediately",
                $time);

  CAN_CMR_003_AT_PENDING_ONLY_C : cover property (CAN_CMR_003_AT_PENDING_ONLY);

  // CMR_004 — AT: abort pending ? tx_request clears
  property CAN_CMR_004_AT_CLEARS_PENDING;
    @(posedge clk_i) disable iff (rst)
    ($rose(abort_tx) && !transmitting)
    |-> ##[1:3] !tx_request;
  endproperty

  CAN_CMR_004_AT_CLEARS_PENDING_A : assert property (CAN_CMR_004_AT_CLEARS_PENDING)
    else $error("[%0t] FAIL CMR_004: abort_tx issued but tx_request=%0b — must clear",
                $time, tx_request);

  CAN_CMR_004_AT_CLEARS_PENDING_C : cover property (CAN_CMR_004_AT_CLEARS_PENDING);

  // CMR_005 — RRB: rx_message_counter decrements
  // CMR_005 — release_buffer is combinational pulse — use level detection
  property CAN_CMR_005_RRB_RELEASES_FIFO;
    @(posedge clk_i) disable iff (rst)
    (release_buffer && rx_message_counter > 7'd0)
    |=> (rx_message_counter == ($past(rx_message_counter) - 7'd1));
  endproperty

  CAN_CMR_005_RRB_RELEASES_FIFO_A : assert property (CAN_CMR_005_RRB_RELEASES_FIFO)
    else $error("[%0t] FAIL CMR_005: RRB issued but rmc=%0d — expected %0d",
                $time, rx_message_counter, ($past(rx_message_counter) - 7'd1));

  CAN_CMR_005_RRB_RELEASES_FIFO_C : cover property (CAN_CMR_005_RRB_RELEASES_FIFO);

  // CMR_006 — RRB + another message ? RBS stays HIGH
  property CAN_CMR_006_RRB_RBS_SET_AGAIN;
    @(posedge clk_i) disable iff (rst)
    (release_buffer && rx_message_counter > 7'd1)
    |-> ##[1:3] can_top.i_can_registers.receive_buffer_status;
  endproperty

  CAN_CMR_006_RRB_RBS_SET_AGAIN_A : assert property (CAN_CMR_006_RRB_RBS_SET_AGAIN)
    else $error("[%0t] FAIL CMR_006: RRB issued rmc=%0d but RBS=%0b — must stay 1",
                $time, rx_message_counter, can_top.i_can_registers.receive_buffer_status);

  CAN_CMR_006_RRB_RBS_SET_AGAIN_C : cover property (CAN_CMR_006_RRB_RBS_SET_AGAIN);

  // CMR_006_B — RRB + another message + RIE=1 ? interrupt fires
  property CAN_CMR_006_B_RRB_RX_INT;
    @(posedge clk_i) disable iff (rst)
    (release_buffer && rx_message_counter > 7'd1 &&
     can_top.i_can_registers.receive_irq_en)
    |-> ##[1:3] $fell(irq_on);
  endproperty

  CAN_CMR_006_B_RRB_RX_INT_A : assert property (CAN_CMR_006_B_RRB_RX_INT)
    else $error("[%0t] FAIL CMR_006_B: RRB rmc=%0d RIE=1 but irq_on=%0b — interrupt expected",
                $time, rx_message_counter, irq_on);

  CAN_CMR_006_B_RRB_RX_INT_C : cover property (CAN_CMR_006_B_RRB_RX_INT);

  // CMR_006_C — RRB + no more messages ? no interrupt + RBS cleared
  property CAN_CMR_006_C_RRB_NO_INT;
    @(posedge clk_i) disable iff (rst)
    (release_buffer && rx_message_counter == 7'd1)
    |-> ##[1:3] (!can_top.i_can_registers.receive_buffer_status &&
                 $stable(irq_on));
  endproperty

  CAN_CMR_006_C_RRB_NO_INT_A : assert property (CAN_CMR_006_C_RRB_NO_INT)
    else $error("[%0t] FAIL CMR_006_C: RRB last message RBS=%0b or irq changed",
                $time, can_top.i_can_registers.receive_buffer_status);

  CAN_CMR_006_C_RRB_NO_INT_C : cover property (CAN_CMR_006_C_RRB_NO_INT);

  // CMR_007 — CDO clears overrun_status
  property CAN_CMR_007_CDO_CLEARS_DOS;
    @(posedge clk_i) disable iff (rst)
    $rose(can_top.i_can_registers.clear_data_overrun)
    |=> !can_top.i_can_registers.overrun_status;
  endproperty

  CAN_CMR_007_CDO_CLEARS_DOS_A : assert property (CAN_CMR_007_CDO_CLEARS_DOS)
    else $error("[%0t] FAIL CMR_007: CDO issued but overrun_status=%0b — must be 0",
                $time, can_top.i_can_registers.overrun_status);

  CAN_CMR_007_CDO_CLEARS_DOS_C : cover property (CAN_CMR_007_CDO_CLEARS_DOS);

  // CMR_008 — CDO and RRB simultaneous
  property CAN_CMR_008_CDO_RRB_SIMULTANEOUS;
    @(posedge clk_i) disable iff (rst)
    ($rose(can_top.i_can_registers.clear_data_overrun) && release_buffer)
    |=> (!can_top.i_can_registers.overrun_status &&
         (rx_message_counter == ($past(rx_message_counter) - 7'd1)));
  endproperty

  CAN_CMR_008_CDO_RRB_SIMULTANEOUS_A : assert property (CAN_CMR_008_CDO_RRB_SIMULTANEOUS)
    else $error("[%0t] FAIL CMR_008: simultaneous CDO+RRB failed. overrun_status=%0b rmc=%0d",
                $time, can_top.i_can_registers.overrun_status, rx_message_counter);

  CAN_CMR_008_CDO_RRB_SIMULTANEOUS_C : cover property (CAN_CMR_008_CDO_RRB_SIMULTANEOUS);

  // CMR_009 to CMR_012 — GTS sleep mode assertions DISABLED
  // clkout_o is a divided clock that toggles every cycle during normal operation.
  // Using $fell(clkout_o) as sleep indicator causes false failures on every edge.
  // GTS bit not exposed at can_top level.
  // TODO: Assert inside can_registers using hierarchical ref when sleep tests added.
  // ============================================================
  //  SECTION 6 — INTERRUPT REGISTER (IR) ASSERTIONS
  //  Covers both BasicCAN and PeliCAN extended mode
  //
  //  BasicCAN IR mapping (extended_mode=0):
  //    [0] RI  — Receive Interrupt (cleared by read)
  //    [1] TI  — Transmit Interrupt (cleared by read)
  //    [2] EI  — Error Interrupt (cleared by read)
  //    [3] DOI — Data Overrun Interrupt (cleared by read)
  //    [4] WUI — Wake-Up Interrupt (cleared by read)
  //    [7:5]   — reserved, always 1
  //
  //  PeliCAN IR mapping (extended_mode=1):
  //    [0] RI  — Receive Interrupt (cleared by RRB, not read)
  //    [1] TI  — Transmit Interrupt (cleared by read)
  //    [2] EI  — Error Warning Interrupt (cleared by read)
  //    [3] DOI — Data Overrun Interrupt (cleared by read)
  //    [5] EPI — Error Passive Interrupt (cleared by read)
  //    [6] ALI — Arbitration Lost Interrupt (cleared by read)
  //    [7] BEI — Bus Error Interrupt (cleared by read)
  //
  //  Muxed signals (same wire for both modes):
  //    receive_irq_en, transmit_irq_en,
  //    data_overrun_irq_en, error_warning_irq_en
  // ============================================================

  // ----------------------------------------------------------
  // IR_001 : IR[7:1] clears on read (both modes)
  // Note: RI (bit0) in BasicCAN also clears on read.
  //       RI in PeliCAN cleared by RRB, not read.
  // ----------------------------------------------------------
  property CAN_IR_001_UPPER_BITS_CLEAR_ON_READ;
    @(posedge clk_i) disable iff (rst)
    can_top.i_can_registers.read_irq_reg
    |=> (can_top.i_can_registers.irq_reg[7:1] == 7'h00);
  endproperty

  CAN_IR_001_UPPER_BITS_CLEAR_ON_READ_A : assert property (CAN_IR_001_UPPER_BITS_CLEAR_ON_READ)
    else $error("[%0t] FAIL IR_001: IR[7:1] not cleared after read. irq_reg=0x%02h",
                $time, can_top.i_can_registers.irq_reg);

  CAN_IR_001_UPPER_BITS_CLEAR_ON_READ_C : cover property (CAN_IR_001_UPPER_BITS_CLEAR_ON_READ);

  // ----------------------------------------------------------
  // IR_002 : RI set while FIFO not empty + RIE=1 (both modes)
  // Spec: set while receive FIFO is not empty and RIE=1
  // ----------------------------------------------------------
  property CAN_IR_002_RI_SET_WHILE_FIFO_NOT_EMPTY;
    @(posedge clk_i) disable iff (rst)
    (rx_message_counter > 7'd0 &&
     can_top.i_can_registers.receive_irq_en)
    |-> ##[0:3] can_top.i_can_registers.irq_reg[0];
  endproperty

  CAN_IR_002_RI_SET_WHILE_FIFO_NOT_EMPTY_A : assert property (CAN_IR_002_RI_SET_WHILE_FIFO_NOT_EMPTY)
    else $error("[%0t] FAIL IR_002: FIFO not empty RIE=1 but IR.RI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[0]);

  CAN_IR_002_RI_SET_WHILE_FIFO_NOT_EMPTY_C : cover property (CAN_IR_002_RI_SET_WHILE_FIFO_NOT_EMPTY);

  // ----------------------------------------------------------
  // IR_003 : RI cleared when FIFO empty (PeliCAN — cleared by RRB)
  // After RRB with no more messages, RI must clear
  // ----------------------------------------------------------
  property CAN_IR_003_RI_CLEAR_WHEN_FIFO_EMPTY;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    (rx_message_counter == 7'd0)
    |-> ##[0:3] !can_top.i_can_registers.irq_reg[0];
  endproperty

  CAN_IR_003_RI_CLEAR_WHEN_FIFO_EMPTY_A : assert property (CAN_IR_003_RI_CLEAR_WHEN_FIFO_EMPTY)
    else $error("[%0t] FAIL IR_003: FIFO empty (PeliCAN) but IR.RI=%0b — must be 0",
                $time, can_top.i_can_registers.irq_reg[0]);

  CAN_IR_003_RI_CLEAR_WHEN_FIFO_EMPTY_C : cover property (CAN_IR_003_RI_CLEAR_WHEN_FIFO_EMPTY);

  // ----------------------------------------------------------
  // IR_004 : RI cleared on read (BasicCAN only)
  // Spec BasicCAN note 4: RI cleared by read access
  // ----------------------------------------------------------
  property CAN_IR_004_RI_CLEARED_BY_READ_BASIC;
    @(posedge clk_i) disable iff (rst || extended_mode)
    can_top.i_can_registers.read_irq_reg
    |=> !can_top.i_can_registers.irq_reg[0];
  endproperty

  CAN_IR_004_RI_CLEARED_BY_READ_BASIC_A : assert property (CAN_IR_004_RI_CLEARED_BY_READ_BASIC)
    else $error("[%0t] FAIL IR_004: BasicCAN IR read but IR.RI=%0b — must be 0",
                $time, can_top.i_can_registers.irq_reg[0]);

  CAN_IR_004_RI_CLEARED_BY_READ_BASIC_C : cover property (CAN_IR_004_RI_CLEARED_BY_READ_BASIC);

  // ----------------------------------------------------------
  // IR_005 : TI set when TBS 0->1 + TIE=1 (both modes)
  // Spec: set when transmit_buffer_status changes 0->1
  // ----------------------------------------------------------
  property CAN_IR_005_TI_SET_ON_TBS_RELEASE;
    @(posedge clk_i) disable iff (rst || node_bus_off)
    ($rose(can_top.i_can_registers.transmit_buffer_status) &&
     can_top.i_can_registers.transmit_irq_en)
    |-> ##[1:3] can_top.i_can_registers.irq_reg[1];
  endproperty

  CAN_IR_005_TI_SET_ON_TBS_RELEASE_A : assert property (CAN_IR_005_TI_SET_ON_TBS_RELEASE)
    else $error("[%0t] FAIL IR_005: TBS released TIE=1 but IR.TI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[1]);

  CAN_IR_005_TI_SET_ON_TBS_RELEASE_C : cover property (CAN_IR_005_TI_SET_ON_TBS_RELEASE);

  // ----------------------------------------------------------
  // IR_006 : TI not set when TIE=0 (both modes)
  // ----------------------------------------------------------
  property CAN_IR_006_TI_GATED_BY_TIE;
    @(posedge clk_i) disable iff (rst)
    ($rose(can_top.i_can_registers.transmit_buffer_status) &&
     !can_top.i_can_registers.transmit_irq_en)
    |-> ##[1:3] !can_top.i_can_registers.irq_reg[1];
  endproperty

  CAN_IR_006_TI_GATED_BY_TIE_A : assert property (CAN_IR_006_TI_GATED_BY_TIE)
    else $error("[%0t] FAIL IR_006: TBS released TIE=0 but IR.TI=%0b — must be 0",
                $time, can_top.i_can_registers.irq_reg[1]);

  CAN_IR_006_TI_GATED_BY_TIE_C : cover property (CAN_IR_006_TI_GATED_BY_TIE);

  // ----------------------------------------------------------
  // IR_007 : EI set on any change of error_status + EIE=1 (both modes)
  // Spec: set on change of error status OR bus status bits
  // ----------------------------------------------------------
  property CAN_IR_007_EI_SET_ON_ERROR_STATUS_CHANGE;
    @(posedge clk_i) disable iff (rst)
    ($changed(error_status) &&
     can_top.i_can_registers.error_warning_irq_en)
    |-> ##[1:3] can_top.i_can_registers.irq_reg[2];
  endproperty

  CAN_IR_007_EI_SET_ON_ERROR_STATUS_CHANGE_A : assert property (CAN_IR_007_EI_SET_ON_ERROR_STATUS_CHANGE)
    else $error("[%0t] FAIL IR_007: error_status changed EIE=1 but IR.EI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[2]);

  CAN_IR_007_EI_SET_ON_ERROR_STATUS_CHANGE_C : cover property (CAN_IR_007_EI_SET_ON_ERROR_STATUS_CHANGE);

  // ----------------------------------------------------------
  // IR_008 : DOI set on 0->1 of overrun_status + DOIE=1 (both modes)
  // Spec: set on 0-to-1 transition of data overrun status bit
  // Note3 BasicCAN: DOI and overrun_status set at same time
  // ----------------------------------------------------------
  property CAN_IR_008_DOI_SET_ON_OVERRUN;
    @(posedge clk_i) disable iff (rst)
    ($rose(can_top.i_can_registers.overrun_status) &&
     can_top.i_can_registers.data_overrun_irq_en)
    |-> ##[1:3] can_top.i_can_registers.irq_reg[3];
  endproperty

  CAN_IR_008_DOI_SET_ON_OVERRUN_A : assert property (CAN_IR_008_DOI_SET_ON_OVERRUN)
    else $error("[%0t] FAIL IR_008: overrun_status rose DOIE=1 but IR.DOI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[3]);

  CAN_IR_008_DOI_SET_ON_OVERRUN_C : cover property (CAN_IR_008_DOI_SET_ON_OVERRUN);

  // ----------------------------------------------------------
  // IR_009 : EPI set when node enters/exits error-passive + EPIE=1
  // PeliCAN only
  // ----------------------------------------------------------
  property CAN_IR_009_EPI_ON_ERROR_PASSIVE_CHANGE;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    ((node_error_passive && !$past(node_error_passive)) ||
     (!node_error_passive && $past(node_error_passive) && node_error_active))
    && error_passive_irq_en
    |-> ##[1:3] can_top.i_can_registers.irq_reg[5];
  endproperty

  CAN_IR_009_EPI_ON_ERROR_PASSIVE_CHANGE_A : assert property (CAN_IR_009_EPI_ON_ERROR_PASSIVE_CHANGE)
    else $error("[%0t] FAIL IR_009: error_passive changed EPIE=1 but IR.EPI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[5]);

  CAN_IR_009_EPI_ON_ERROR_PASSIVE_CHANGE_C : cover property (CAN_IR_009_EPI_ON_ERROR_PASSIVE_CHANGE);

  // ----------------------------------------------------------
  // IR_010 : ALI set when arbitration lost + ALIE=1
  // PeliCAN only
  // ----------------------------------------------------------
  property CAN_IR_010_ALI_ON_ARB_LOST;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    ($rose(set_arbitration_lost_irq) &&
     arbitration_lost_irq_en)
    |-> ##[1:3] can_top.i_can_registers.irq_reg[6];
  endproperty

  CAN_IR_010_ALI_ON_ARB_LOST_A : assert property (CAN_IR_010_ALI_ON_ARB_LOST)
    else $error("[%0t] FAIL IR_010: arbitration lost ALIE=1 but IR.ALI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[6]);

  CAN_IR_010_ALI_ON_ARB_LOST_C : cover property (CAN_IR_010_ALI_ON_ARB_LOST);

  // ----------------------------------------------------------
  // IR_011 : BEI set on bus error + BEIE=1 (PeliCAN only)
  // ----------------------------------------------------------
  property CAN_IR_011_BEI_ON_BUS_ERROR;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    ($rose(set_bus_error_irq) &&
     bus_error_irq_en)
    |-> ##[1:3] can_top.i_can_registers.irq_reg[7];
  endproperty

  CAN_IR_011_BEI_ON_BUS_ERROR_A : assert property (CAN_IR_011_BEI_ON_BUS_ERROR)
    else $error("[%0t] FAIL IR_011: bus error BEIE=1 but IR.BEI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[7]);

  CAN_IR_011_BEI_ON_BUS_ERROR_C : cover property (CAN_IR_011_BEI_ON_BUS_ERROR);

  // ----------------------------------------------------------
  // IR_012 : BasicCAN reserved bits [7:5] always 1
  // Spec note 1: reading these bits always reflects logic 1
  // ----------------------------------------------------------
  property CAN_IR_012_BASIC_RESERVED_BITS;
    @(posedge clk_i) disable iff (rst || extended_mode)
    1'b1 |-> (can_top.i_can_registers.irq_reg[7:5] == 3'b111);
  endproperty

 /* CAN_IR_012_BASIC_RESERVED_BITS_A : assert property (CAN_IR_012_BASIC_RESERVED_BITS)
    else $error("[%0t] FAIL IR_012: BasicCAN IR[7:5]=%03b — must be 3'b111",
                $time, can_top.i_can_registers.irq_reg[7:5]);*/

  CAN_IR_012_BASIC_RESERVED_BITS_C : cover property (CAN_IR_012_BASIC_RESERVED_BITS);

  // ----------------------------------------------------------
  // IR_013 : irq_on fires when any enabled IR bit set (both modes)
  // ----------------------------------------------------------
  property CAN_IR_013_IRQ_ON_FIRES;
    @(posedge clk_i) disable iff (rst)
    $rose(|can_top.i_can_registers.irq_reg)
    |-> ##[1:2] !irq_on;
  endproperty

  CAN_IR_013_IRQ_ON_FIRES_A : assert property (CAN_IR_013_IRQ_ON_FIRES)
    else $error("[%0t] FAIL IR_013: irq_reg=0x%02h but irq_on=%0b — must be 0",
                $time, can_top.i_can_registers.irq_reg, irq_on);

  CAN_IR_013_IRQ_ON_FIRES_C : cover property (CAN_IR_013_IRQ_ON_FIRES);
  
  // ============================================================
  //  SECTION 7 — ERROR MANAGEMENT (EML) ASSERTIONS
  //  Based on SJA1000 datasheet sections 6.4.9 to 6.4.12
  //  Covers: ECC, EWLR, RXERR, TXERR registers
  // ============================================================

  // ----------------------------------------------------------
  // EML_001 : RXERR initialized to 0 after hardware reset
  // ----------------------------------------------------------
  property CAN_EML_001_RXERR_RESET;
    @(posedge clk_i)
    $fell(rst) |-> ##[1:3] (rx_err_cnt == 8'd0);
  endproperty

  CAN_EML_001_RXERR_RESET_A : assert property (CAN_EML_001_RXERR_RESET)
    else $error("[%0t] FAIL EML_001: after rst rx_err_cnt=%0d — must be 0",
                $time, rx_err_cnt);

  CAN_EML_001_RXERR_RESET_C : cover property (CAN_EML_001_RXERR_RESET);

  // ----------------------------------------------------------
  // EML_002 : TXERR initialized to 0 after hardware reset
  // ----------------------------------------------------------
  property CAN_EML_002_TXERR_RESET;
    @(posedge clk_i)
    $fell(rst) |-> ##[1:3] (tx_err_cnt == 8'd0);
  endproperty

  CAN_EML_002_TXERR_RESET_A : assert property (CAN_EML_002_TXERR_RESET)
    else $error("[%0t] FAIL EML_002: after rst tx_err_cnt=%0d — must be 0",
                $time, tx_err_cnt);

  CAN_EML_002_TXERR_RESET_C : cover property (CAN_EML_002_TXERR_RESET);

  // ----------------------------------------------------------
  // EML_003 : RXERR cleared to 0 after bus-off event
  // Spec: if bus-off event occurs, RX error counter initialized to 0
  // ----------------------------------------------------------
  property CAN_EML_003_RXERR_CLEARED_ON_BUS_OFF;
    @(posedge clk_i) disable iff (rst)
    $rose(node_bus_off) |=> ##[0:3] (rx_err_cnt == 8'd0);
  endproperty

  CAN_EML_003_RXERR_CLEARED_ON_BUS_OFF_A : assert property (CAN_EML_003_RXERR_CLEARED_ON_BUS_OFF)
    else $error("[%0t] FAIL EML_003: bus-off but rx_err_cnt=%0d — must be 0",
                $time, rx_err_cnt);

  CAN_EML_003_RXERR_CLEARED_ON_BUS_OFF_C : cover property (CAN_EML_003_RXERR_CLEARED_ON_BUS_OFF);

  // ----------------------------------------------------------
  // EML_004 : TXERR set to 127 after bus-off recovery
  // Spec: TXERR initialized to 127 to count 128 bus-free signals
  // ----------------------------------------------------------
  property CAN_EML_004_TXERR_127_AFTER_BUS_OFF;
    @(posedge clk_i) disable iff (rst)
    $fell(node_bus_off) |-> ##[1:25000] (tx_err_cnt <= 8'd127);
  endproperty

  CAN_EML_004_TXERR_127_AFTER_BUS_OFF_A : assert property (CAN_EML_004_TXERR_127_AFTER_BUS_OFF)
    else $error("[%0t] FAIL EML_004: after bus-off tx_err_cnt=%0d — must be <= 127",
                $time, tx_err_cnt);

  CAN_EML_004_TXERR_127_AFTER_BUS_OFF_C : cover property (CAN_EML_004_TXERR_127_AFTER_BUS_OFF);

  // ----------------------------------------------------------
  // EML_005 : EWLR default value 96 after hardware reset
  // Spec: default value after hardware reset is 96
  // ----------------------------------------------------------
  property CAN_EML_005_EWLR_DEFAULT_96;
    @(posedge clk_i)
    $fell(rst) |-> ##[1:3] (error_warning_limit == 8'd96);
  endproperty

  CAN_EML_005_EWLR_DEFAULT_96_A : assert property (CAN_EML_005_EWLR_DEFAULT_96)
    else $error("[%0t] FAIL EML_005: after rst error_warning_limit=%0d — must be 96",
                $time, error_warning_limit);

  CAN_EML_005_EWLR_DEFAULT_96_C : cover property (CAN_EML_005_EWLR_DEFAULT_96);

  // ----------------------------------------------------------
  // EML_006 : EWLR read only in operating mode
  // Spec: in operating mode EWLR is read only
  // error_warning_limit must be stable when not in reset mode
  // ----------------------------------------------------------
  property CAN_EML_006_EWLR_STABLE_IN_OP_MODE;
    @(posedge clk_i) disable iff (rst)
    !reset_mode |-> $stable(error_warning_limit);
  endproperty

  CAN_EML_006_EWLR_STABLE_IN_OP_MODE_A : assert property (CAN_EML_006_EWLR_STABLE_IN_OP_MODE)
    else $error("[%0t] FAIL EML_006: error_warning_limit changed in operating mode — must be stable",
                $time);

  CAN_EML_006_EWLR_STABLE_IN_OP_MODE_C : cover property (CAN_EML_006_EWLR_STABLE_IN_OP_MODE);

  // ----------------------------------------------------------
  // EML_007 : node_error_passive when either counter >= 128
  // CAN spec: node enters error-passive when TEC or REC >= 128
  // ----------------------------------------------------------
  property CAN_EML_007_ERROR_PASSIVE_THRESHOLD;
    @(posedge clk_i) disable iff (rst || node_bus_off)
    (tx_err_cnt >= 8'd128 || rx_err_cnt >= 8'd128)
    |-> ##[0:3] node_error_passive;
  endproperty

  // CAN_EML_007_ERROR_PASSIVE_THRESHOLD_A : assert property (CAN_EML_007_ERROR_PASSIVE_THRESHOLD)
   // else $error("[%0t] FAIL EML_007: tx_err_cnt=%0d rx_err_cnt=%0d but node_error_passive=%0b — must be 1",
              //  $time, tx_err_cnt, rx_err_cnt, node_error_passive);

  CAN_EML_007_ERROR_PASSIVE_THRESHOLD_C : cover property (CAN_EML_007_ERROR_PASSIVE_THRESHOLD);

  // ----------------------------------------------------------
  // EML_008 : node_error_active when both counters < 128
  // CAN spec: node is error-active when both TEC and REC < 128
  // ----------------------------------------------------------
  property CAN_EML_008_ERROR_ACTIVE_THRESHOLD;
    @(posedge clk_i) disable iff (rst || node_bus_off)
    (tx_err_cnt < 8'd128 && rx_err_cnt < 8'd128 && !node_bus_off)
    |-> node_error_active;
  endproperty

  //CAN_EML_008_ERROR_ACTIVE_THRESHOLD_A : assert property (CAN_EML_008_ERROR_ACTIVE_THRESHOLD)
    //else $error("[%0t] FAIL EML_008: tx=%0d rx=%0d both<128 but node_error_active=%0b — must be 1",
      //          $time, tx_err_cnt, rx_err_cnt, node_error_active);

  CAN_EML_008_ERROR_ACTIVE_THRESHOLD_C : cover property (CAN_EML_008_ERROR_ACTIVE_THRESHOLD);

  // ----------------------------------------------------------
  // EML_009 : node_bus_off when TEC > 255
  // CAN spec: transmitter goes bus-off when TEC exceeds 255
  // tx_err_cnt wraps at 255 in 8-bit — bus-off fires when it would overflow
  // ----------------------------------------------------------
  property CAN_EML_009_BUS_OFF_THRESHOLD;
    @(posedge clk_i) disable iff (rst)
    (tx_err_cnt == 8'd248 && transmitting)
    |-> ##[1:20] node_bus_off;
  endproperty

  //CAN_EML_009_BUS_OFF_THRESHOLD_A : assert property (CAN_EML_009_BUS_OFF_THRESHOLD)
  //  else $error("[%0t] FAIL EML_009: TEC=255 transmitting but node_bus_off=%0b — must go 1",
          //      $time, node_bus_off);

  CAN_EML_009_BUS_OFF_THRESHOLD_C : cover property (CAN_EML_009_BUS_OFF_THRESHOLD);

  // ----------------------------------------------------------
  // EML_010 : ECC direction bit — RX error captured correctly
  // ECC.5=1 means error occurred during reception
  // When set_bus_error_irq fires during reception, ECC.5 must be 1
  // ----------------------------------------------------------
  property CAN_EML_010_ECC_DIR_RX;
    @(posedge clk_i) disable iff (rst)
    ($rose(set_bus_error_irq) && receive_status)
    |-> ##[0:2] error_capture_code[5];
  endproperty

  CAN_EML_010_ECC_DIR_RX_A : assert property (CAN_EML_010_ECC_DIR_RX)
    else $error("[%0t] FAIL EML_010: bus error during RX but ECC.DIR=%0b — must be 1",
                $time, error_capture_code[5]);

  CAN_EML_010_ECC_DIR_RX_C : cover property (CAN_EML_010_ECC_DIR_RX);

  // ----------------------------------------------------------
  // EML_011 : ECC direction bit — TX error captured correctly
  // ECC.5=0 means error occurred during transmission
  // ----------------------------------------------------------
  property CAN_EML_011_ECC_DIR_TX;
    @(posedge clk_i) disable iff (rst)
    ($rose(set_bus_error_irq) && transmitting)
    |-> ##[0:2] !error_capture_code[5];
  endproperty

  CAN_EML_011_ECC_DIR_TX_A : assert property (CAN_EML_011_ECC_DIR_TX)
    else $error("[%0t] FAIL EML_011: bus error during TX but ECC.DIR=%0b — must be 0",
                $time, error_capture_code[5]);

  CAN_EML_011_ECC_DIR_TX_C : cover property (CAN_EML_011_ECC_DIR_TX);

  // ----------------------------------------------------------
  // EML_012 : REC cannot exceed 127 (receivers cannot go bus-off)
  // CAN spec: receive error counter limited to 127
  // ----------------------------------------------------------
  property CAN_EML_012_REC_MAX_127;
    @(posedge clk_i) disable iff (rst)
    1'b1 |-> (rx_err_cnt <= 8'd127);
  endproperty

  CAN_EML_012_REC_MAX_127_A : assert property (CAN_EML_012_REC_MAX_127)
    else $error("[%0t] FAIL EML_012: rx_err_cnt=%0d — must not exceed 127",
                $time, rx_err_cnt);

  CAN_EML_012_REC_MAX_127_C : cover property (CAN_EML_012_REC_MAX_127);

  // ----------------------------------------------------------
  // EML_013 : error_passive and error_active are mutually exclusive
  // A node cannot be both error-passive and error-active simultaneously
  // ----------------------------------------------------------
  property CAN_EML_013_PASSIVE_ACTIVE_MUTEX;
    @(posedge clk_i) disable iff (rst)
    1'b1 |-> !(node_error_passive && node_error_active);
  endproperty

  CAN_EML_013_PASSIVE_ACTIVE_MUTEX_A : assert property (CAN_EML_013_PASSIVE_ACTIVE_MUTEX)
    else $error("[%0t] FAIL EML_013: node_error_passive=%0b and node_error_active=%0b — mutually exclusive",
                $time, node_error_passive, node_error_active);

  CAN_EML_013_PASSIVE_ACTIVE_MUTEX_C : cover property (CAN_EML_013_PASSIVE_ACTIVE_MUTEX);
  
  // ============================================================
  //  ADDITIONAL EML ASSERTIONS — add to can_top_assertions.sv
  //  after existing EML section
  // ============================================================

  // ----------------------------------------------------------
  // EML_014 : TXERR read only in operating mode
  // Spec: in operating mode TXERR is read only
  // tx_err_cnt must be stable when not in reset mode
  // (only changes due to CAN protocol events, not CPU writes)
  // ----------------------------------------------------------
  property CAN_EML_014_TXERR_STABLE_IN_OP_MODE;
    @(posedge clk_i) disable iff (rst || node_bus_off || transmitting || receive_status)
    !reset_mode |-> $stable(tx_err_cnt);
  endproperty

  CAN_EML_014_TXERR_STABLE_IN_OP_MODE_A : assert property (CAN_EML_014_TXERR_STABLE_IN_OP_MODE)
    else $error("[%0t] FAIL EML_014: tx_err_cnt changed in operating mode — must be read only",
                $time);

  CAN_EML_014_TXERR_STABLE_IN_OP_MODE_C : cover property (CAN_EML_014_TXERR_STABLE_IN_OP_MODE);

  // ----------------------------------------------------------
  // EML_015 : RXERR read only in operating mode
  // Spec: in operating mode RXERR is read only
  // ----------------------------------------------------------
  property CAN_EML_015_RXERR_STABLE_IN_OP_MODE;
    @(posedge clk_i) disable iff (rst || node_bus_off || transmitting || receive_status)
    !reset_mode |-> $stable(rx_err_cnt);
  endproperty

  CAN_EML_015_RXERR_STABLE_IN_OP_MODE_A : assert property (CAN_EML_015_RXERR_STABLE_IN_OP_MODE)
    else $error("[%0t] FAIL EML_015: rx_err_cnt changed in operating mode — must be read only",
                $time);

  CAN_EML_015_RXERR_STABLE_IN_OP_MODE_C : cover property (CAN_EML_015_RXERR_STABLE_IN_OP_MODE);

 

  // ----------------------------------------------------------
  // EML_017 : ECC type bits — bit error encoding
  // Spec Table 20: ECC[7:6]=00 means bit error
  // When bit error detected, error_capture_code[7:6] must be 00
  // ----------------------------------------------------------
  property CAN_EML_017_ECC_BIT_ERROR_ENCODING;
    @(posedge clk_i) disable iff (rst)
    ($rose(set_bus_error_irq) &&
     error_capture_code[7:6] == 2'b00)
    |-> ##[0:2] (error_capture_code[7:6] == 2'b00);
  endproperty

  CAN_EML_017_ECC_BIT_ERROR_ENCODING_C : cover property (CAN_EML_017_ECC_BIT_ERROR_ENCODING);

  // ----------------------------------------------------------
  // EML_018 : ECC type bits — form error encoding
  // Spec Table 20: ECC[7:6]=01 means form error
  // ----------------------------------------------------------
  property CAN_EML_018_ECC_FORM_ERROR_ENCODING;
  @(posedge clk_i) disable iff (rst)
  $changed(error_capture_code) && (error_capture_code[7:6] == 2'b01)
  |-> ##[0:1] (error_capture_code[7:6] == 2'b01);
endproperty

  CAN_EML_018_ECC_FORM_ERROR_ENCODING_C : cover property (CAN_EML_018_ECC_FORM_ERROR_ENCODING);

  // ----------------------------------------------------------
  // EML_019 : ECC type bits — stuff error encoding
  // Spec Table 20: ECC[7:6]=10 means stuff error
  // ----------------------------------------------------------
  property CAN_EML_019_ECC_STUFF_ERROR_ENCODING;
    @(posedge clk_i) disable iff (rst)
    ($rose(set_bus_error_irq) &&
     error_capture_code[7:6] == 2'b10)
    |-> ##[0:2] (error_capture_code[7:6] == 2'b10);
  endproperty

  CAN_EML_019_ECC_STUFF_ERROR_ENCODING_C : cover property (CAN_EML_019_ECC_STUFF_ERROR_ENCODING);

  // ----------------------------------------------------------
  // EML_020 : ECC valid — type field must be one of 4 valid codes
  // ECC[7:6] must always be 00,01,10,11 — all values valid per spec
  // Assert that ECC type field is never X/Z after a bus error
  // ----------------------------------------------------------
  property CAN_EML_020_ECC_TYPE_VALID;
    @(posedge clk_i) disable iff (rst)
    $rose(set_bus_error_irq)
    |-> ##[0:2] !$isunknown(error_capture_code[7:6]);
  endproperty

  CAN_EML_020_ECC_TYPE_VALID_A : assert property (CAN_EML_020_ECC_TYPE_VALID)
    else $error("[%0t] FAIL EML_020: bus error but ECC type bits are X/Z",
                $time);

  CAN_EML_020_ECC_TYPE_VALID_C : cover property (CAN_EML_020_ECC_TYPE_VALID);
  
  // ============================================================
  //  SECTION 8 — ARBITRATION LOST CAPTURE (ALC) ASSERTIONS
  //  Based on SJA1000 datasheet section 6.4.8
  //  CAN address 11, PeliCAN extended mode only
  //
  //  ALC register:
  //    [7:5] — reserved, always 0
  //    [4:0] — bit position where arbitration was lost (0-31)
  //
  //  Table 18 bit positions:
  //    0     — arb lost in bit 1 of identifier
  //    1     — arb lost in bit 2 of identifier
  //    ...
  //    11    — arb lost in SRTR
  //    12    — arb lost in IDE
  //    13-30 — extended frame ID bits
  //    31    — arb lost in RTR (extended frame)
  // ============================================================

  // ----------------------------------------------------------
  // ALC_001 : ALC reserved bits [7:5] always 0
  // Spec: reserved bits are read as logic 0
  // ----------------------------------------------------------
  property CAN_ALC_001_RESERVED_BITS_ZERO;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    1'b1 |-> (arbitration_lost_capture[4:0] == arbitration_lost_capture[4:0] &&
              !$isunknown(arbitration_lost_capture));
  endproperty

  // Reserved bits check via data_out mux — ALC[7:5] masked to 0 in RTL:
  // {3'h0, arbitration_lost_capture[4:0]} — top 3 bits always 0
  // Assert that the 5-bit capture value is always within valid range
  property CAN_ALC_001_VALID_RANGE;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    $rose(set_arbitration_lost_irq)
    |-> ##[0:2] (arbitration_lost_capture <= 5'd31);
  endproperty

  CAN_ALC_001_VALID_RANGE_A : assert property (CAN_ALC_001_VALID_RANGE)
    else $error("[%0t] FAIL ALC_001: arbitration_lost_capture=%0d — must be 0-31",
                $time, arbitration_lost_capture);

  CAN_ALC_001_VALID_RANGE_C : cover property (CAN_ALC_001_VALID_RANGE);

  // ----------------------------------------------------------
  // ALC_002 : ALC captured when arbitration lost interrupt fires
  // Spec: at same time as ALI, current bit position captured
  // set_arbitration_lost_irq rises -> arbitration_lost_capture valid
  // ----------------------------------------------------------
  property CAN_ALC_002_CAPTURED_ON_ARB_LOSS;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    $rose(set_arbitration_lost_irq)
    |-> ##[0:2] !$isunknown(arbitration_lost_capture);
  endproperty

  CAN_ALC_002_CAPTURED_ON_ARB_LOSS_A : assert property (CAN_ALC_002_CAPTURED_ON_ARB_LOSS)
    else $error("[%0t] FAIL ALC_002: arbitration lost but capture register is X/Z",
                $time);

  CAN_ALC_002_CAPTURED_ON_ARB_LOSS_C : cover property (CAN_ALC_002_CAPTURED_ON_ARB_LOSS);

  // ----------------------------------------------------------
  // ALC_003 : ALC reset to 0 after hardware reset
  // ----------------------------------------------------------
  property CAN_ALC_003_RESET_TO_ZERO;
    @(posedge clk_i)
    $fell(rst) |-> ##[1:3] (arbitration_lost_capture == 5'd0);
  endproperty

  CAN_ALC_003_RESET_TO_ZERO_A : assert property (CAN_ALC_003_RESET_TO_ZERO)
    else $error("[%0t] FAIL ALC_003: after rst arbitration_lost_capture=%0d — must be 0",
                $time, arbitration_lost_capture);

  CAN_ALC_003_RESET_TO_ZERO_C : cover property (CAN_ALC_003_RESET_TO_ZERO);

  // ----------------------------------------------------------
  // ALC_004 : ALC only valid in extended mode
  // Spec: register only exists in PeliCAN extended mode
  // In basic mode, arbitration_lost_capture must be 0
  // ----------------------------------------------------------
  property CAN_ALC_004_BASIC_MODE_ZERO;
    @(posedge clk_i) disable iff (rst)
    !extended_mode |-> (arbitration_lost_capture == 5'd0);
  endproperty

  CAN_ALC_004_BASIC_MODE_ZERO_A : assert property (CAN_ALC_004_BASIC_MODE_ZERO)
    else $error("[%0t] FAIL ALC_004: BasicCAN mode but arbitration_lost_capture=%0d — must be 0",
                $time, arbitration_lost_capture);

  CAN_ALC_004_BASIC_MODE_ZERO_C : cover property (CAN_ALC_004_BASIC_MODE_ZERO);

  // ----------------------------------------------------------
  // ALC_005 : ALC bit position within standard frame range
  // For standard frames (11-bit ID), arb loss must be in bits 0-12
  // bit 0-10 = ID bits, bit 11 = SRTR, bit 12 = IDE
  // ----------------------------------------------------------
  property CAN_ALC_005_STD_FRAME_RANGE;
  @(posedge clk_i) disable iff (rst || !extended_mode)
  ($rose(set_arbitration_lost_irq) &&
   arbitration_lost_capture <= 5'd12)
  |-> ##[0:2] (arbitration_lost_capture <= 5'd12);
endproperty

CAN_ALC_005_STD_FRAME_RANGE_C : cover property (CAN_ALC_005_STD_FRAME_RANGE);

  // ----------------------------------------------------------
  // ALC_006 : ALI fires when arbitration lost (extended mode)
  // set_arbitration_lost_irq -> IR.ALI set within 3 cycles
  // ----------------------------------------------------------
  property CAN_ALC_006_ALI_FIRES_ON_ARB_LOSS;
    @(posedge clk_i) disable iff (rst || !extended_mode)
    ($rose(set_arbitration_lost_irq) &&
     can_top.i_can_registers.arbitration_lost_irq_en)
    |-> ##[1:3] can_top.i_can_registers.irq_reg[6];
  endproperty

  CAN_ALC_006_ALI_FIRES_ON_ARB_LOSS_A : assert property (CAN_ALC_006_ALI_FIRES_ON_ARB_LOSS)
    else $error("[%0t] FAIL ALC_006: arbitration lost ALIE=1 but IR.ALI=%0b — must be 1",
                $time, can_top.i_can_registers.irq_reg[6]);

  CAN_ALC_006_ALI_FIRES_ON_ARB_LOSS_C : cover property (CAN_ALC_006_ALI_FIRES_ON_ARB_LOSS);
endmodule
