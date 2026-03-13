module can_top_assertions (
  
  // -- Clock & Reset ------------------------------------------
  input  logic        clk_i,
  input  logic        rst,           // active HIGH

  // -- CAN Bus Pins -------------------------------------------
  input  logic        rx_i,
  input  logic        tx_o,

  // -- Top-Level Outputs --------------------------------------
  input  logic        bus_off_on,    // 1=bus active  0=bus-off
  input  logic        irq_on,        // active LOW interrupt

  // -- Mode Register Signals ----------------------------------
  input  logic        reset_mode,    // 1=reset mode active

  // -- BSP Error / Status Outputs ----------------------------
  input  logic        node_bus_off,
  input  logic        error_status,          // 1=warning limit reached
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

  // -- Status Signals -----------------------------------------
  input  logic        transmit_status,       // 1=transmitting
  input  logic        receive_status,        // 1=receiving
  input  logic        transmitting,
  input  logic        overrun,               // data overrun flag

  // -- Interrupt Source Signals -------------------------------
  input  logic        set_bus_error_irq,
  input  logic        set_arbitration_lost_irq,

  // -- Internal Control --------------------------------------
  input  logic        set_reset_mode,        // BSP requesting reset mode
  input  logic [6:0]  rx_message_counter,

  // -- BTL Signals --------------------------------------------
  input  logic        sampled_bit,           // current RX bit value
  input  logic        hard_sync,             // hard synchronisation pulse
  input  logic        sample_point,          // sample point pulse
  input  logic        go_rx_inter,           // entering interframe space
  input  logic        rx_sync                // synchronized RX line

);

  wire bus_off_condition = node_bus_off;

  // Warning limit reached: either counter >= error_warning_limit
  wire tx_at_warning = (tx_err_cnt >= error_warning_limit);
  wire rx_at_warning = (rx_err_cnt >= error_warning_limit);
  wire any_at_warning = tx_at_warning | rx_at_warning;
  
  // TX error counter overflow (>255 — bus-off threshold)
  // tx_err_cnt is 8 bits so >255 wraps; bus-off fires when it would exceed 255
  // In this implementation the BSP asserts node_bus_off when this occurs
  wire txerr_overflow = (tx_err_cnt == 8'hFF) & transmitting;
  
  // TX error passive threshold (>127)
  wire txerr_passive = (tx_err_cnt > 8'd127);
  
  // ============================================================
  //  SECTION 1 — RESET ASSERTIONS  (RST_001 – RST_010)
  // ============================================================
  
  // ------------------------------------------------------------
  // RST_001 Reset request Results in abort current transmission
  // And enter Reset Mode
  // ------------------------------------------------------------
  
  // Rule A
  property CAN_RST_001_A_PROP;
    @(posedge clk_i) disable iff (rst)
    $rose(reset_mode) |-> ##[1:2] (!transmitting && !receive_status);
  endproperty
  
  CAN_RST_001_ABORT_ON_RST_A : assert property (CAN_RST_001_A_PROP)
    else $error("[%0t] FAIL RST_001_A: reset requested but TX/RX not stopped. transmitting=%0b receive_status=%0b",
                $time, transmitting, receive_status);
  
  CAN_RST_001_ABORT_ON_RST_C : cover property (CAN_RST_001_A_PROP);
  
  
  // Rule B
  property CAN_RST_001_B_PROP;
    @(posedge clk_i) disable iff (rst)
    $fell(reset_mode) |=> !reset_mode;
  endproperty
  
  CAN_RST_001_OP_MODE_ON_RST_CLR_A : assert property (CAN_RST_001_B_PROP)
    else $error("[%0t] FAIL RST_001_B: reset_mode fell but DUT did not stay in operating mode",
                $time);
  
  CAN_RST_001_OP_MODE_ON_RST_CLR_C : cover property (CAN_RST_001_B_PROP);
  
  
  // ------------------------------------------------------------
  // RST_002 When the bus Status bit is HIGH ( bus_off)
  // the RESET_MODE bit is also set High 
  // ------------------------------------------------------------
  
  // Rule A — hardware reset sets reset_mode
  property CAN_RST_002_A_PROP;
    @(posedge clk_i)
    rst |-> reset_mode;
  endproperty
  
  // Rule B — bus-off sets reset_mode
  property CAN_RST_002_B_PROP;
    @(posedge clk_i) disable iff (rst)
    node_bus_off |-> reset_mode;
  endproperty
  
  // Assertions
  CAN_RST_002_HW_RST_A : assert property (CAN_RST_002_A_PROP)
    else $error("[%0t] FAIL RST_002_A: rst=%0b but reset_mode=%0b — must be 1",
                $time, rst, reset_mode);
  
  CAN_RST_002_BUS_OFF_A : assert property (CAN_RST_002_B_PROP)
    else $error("[%0t] FAIL RST_002_B: node_bus_off=%0b but reset_mode=%0b — must be 1",
                $time, node_bus_off, reset_mode);
  
  // Covers
  CAN_RST_002_HW_RST_C  : cover property (CAN_RST_002_A_PROP);
  CAN_RST_002_BUS_OFF_C : cover property (CAN_RST_002_B_PROP);
  
  // ------------------------------------------------------------
  // RST_003 : On Occurance of bus_free after HW Reset
  // 128 occurances of bus_free after CAN node_bus_off reset
  // ------------------------------------------------------------
  
  sequence SEQ_BUS_FREE;
  (sample_point && sampled_bit) [*11];
  endsequence
  
  // Rule A
  property CAN_RST_003_A_PROP;
    @(posedge clk_i) disable iff (rst)
    $fell(reset_mode) |-> ##1 SEQ_BUS_FREE ##1 bus_off_on;
  endproperty
  
  CAN_RST_003_ONE_BUSFREE_A : assert property (CAN_RST_003_A_PROP)
    else $error("[%0t] FAIL :  reset_mode=%0b but bus_off_on=%0b - must be 1",$time,reset_mode,bus_off_on );
  CAN_RST_003_ONE_BUSFREE_C : cover property (CAN_RST_003_A_PROP);
  
  
  // Rule B
  property CAN_RST_003_B_PROP;
    @(posedge clk_i) disable iff (rst)
    $rose(node_bus_off) |-> ##1 SEQ_BUS_FREE [->128] ##1 bus_off_on;
  endproperty
  
  CAN_RST_003_128_BUSFREE_A : assert property (CAN_RST_003_B_PROP)
    else $error("[%0t] FAIL RST_003 : node_bus_off=%0b bus_off_on=%0b - must be 1",$time,node_bus_off,bus_off_on);
  CAN_RST_003_128_BUSFREE_C : cover property (CAN_RST_003_B_PROP);
  
  // ------------------------------------------------------------
  // RST_004 : If reset occured due to node_bus_off 1. clear receive error counter
  // Then set tx_err_cnt to 127 and then count down the bus recovery time 
  // ------------------------------------------------------------
  property CAN_RST_004_A_PROP;
    @(posedge clk_i) disable iff(rst)
    $rose(node_bus_off) |=> rx_err_cnt == 0;
  endproperty 
  
  property CAN_RST_004_B_PROP;
    @(posedge clk_i) disable iff(rst)
    $rose(node_bus_off) |=> tx_err_cnt == 8'd127;
  endproperty
  
  property CAN_RST_004_C_PROP;
    @(posedge clk_i) disable iff(rst)
    $rose(node_bus_off) |-> ##1 SEQ_BUS_FREE [->128] ##1 bus_off_on;
  endproperty
  
  // Assertions 
  CAN_RST_004_RX_ERR_CNT_A: assert property (CAN_RST_004_A_PROP)
    else $error("[%0t] FAIL_RST_004_RX : node_bus_off=%0b rx_err_cnt=%0d - MUST be 0",$time,node_bus_off,rx_err_cnt);
  
  CAN_RST_004_TX_ERR_CNT_A:  assert property (CAN_RST_004_B_PROP)
    else $error("[%0t] FAIL_RST_004_TX : node_bus_off=%0b tx_err_cnt=%0d - MUST be 127",$time,node_bus_off,tx_err_cnt);
    
  CAN_RST_004_BUS_OFF_COUNT_A:  assert property (CAN_RST_004_C_PROP)
    else $error("[%0t] FAIL_RST_004 : node_bus_off=%0b.",$time,node_bus_off );
  
  // Covers
  CAN_RST_004_RX_ERR_CNT_C : cover property(CAN_RST_004_A_PROP);
  CAN_RST_004_TX_ERR_CNT_C :  cover property(CAN_RST_004_B_PROP);
  CAN_RST_004_BUS_OFF_COUNT_C : cover property(CAN_RST_004_C_PROP);
    
  // ------------------------------------------------------------
  // RST_005 : After Reset exits no , X on the key signal 
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
      else $error("[%0t] FAIL RST_005: X/Z detected after rst fell. reset_mode=%0b node_bus_off=%0b error_status=%0b tx_err_cnt=%0d irq_on=%0b",
                  $time, reset_mode, node_bus_off, error_status, tx_err_cnt, irq_on);
    
    CAN_RST_005_NO_UNKNOWN_C : cover property (CAN_RST_005_NO_UNKNOWN_ON_KEY);
    
  // ------------------------------------------------------------
  // RST_006 : External reset
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
  // RST_007 : CPU cannot clear the HW reset 
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
  // RST_008 : Upon Reset rx_message_counter be 0
  // ------------------------------------------------------------
  property PROP_RST_008_RMC_ZERO_ON_RST;
    @(posedge clk_i)
    $rose(rst) |-> ##[0:3] (rx_message_counter == 7'h00);
  endproperty
  
  CAN_RST_008_RMC_ZERO_ON_RST_A : assert property (PROP_RST_008_RMC_ZERO_ON_RST)
    else $error("[%0t] FAIL RST_004: After reset, RMC not cleared. rmc=%0d",
                $time, rx_message_counter);
  
  CAN_RST_008_RMC_ZERO_ON_RST_C : cover property (PROP_RST_008_RMC_ZERO_ON_RST);
  
  // ------------------------------------------------------------
  // RST_009 : No assertion can be written for RXFIFO 
  // ------------------------------------------------------------
  
  // ------------------------------------------------------------
  // RST_010 : When Reset the counters become 0
  // ------------------------------------------------------------
  property CAN_RST_010_COUNTERS_ZERO_ON_RST;
    @(posedge clk_i) 
    $fell(rst) |-> ##[1:3](rx_err_cnt == 8'd0 && tx_err_cnt == 8'd0);
  endproperty
  
  CAN_RST_010_COUNT_ZERO_A: assert property (CAN_RST_010_COUNTERS_ZERO_ON_RST)
    else $error("[%0t] FAIL RST_010: After reset,rx_err_cnt = %0d & tx_err_cnt = %0d - BOTH must be zero.",$time,rx_err_cnt,tx_err_cnt);
    
  CAN_RST_010_COUNT_ZERO_C: cover property (CAN_RST_010_COUNTERS_ZERO_ON_RST); 
  
  // ============================================================
  //  SECTION 1 — MODES ASSERTIOND  (MOD_001 to MOD_004)
  // ============================================================
  
  // ------------------------------------------------------------
  // MOD_001 : Reset Mode is Low - All the modes Stable
  // ------------------------------------------------------------
  property CAN_MOD_001_RST_LOW_STABLE_MOD;
    @(posedge clk_i) disable iff (rst)
    !reset_mode |-> ($stable(acceptance_filter_mode) &&
                     $stable(listen_only_mode)        &&
                     $stable(self_test_mode)          &&
                     $stable(extended_mode));
  endproperty
  
  CAN_MOD_001_RST_LOW_A : assert property (CAN_MOD_001_RST_LOW_STABLE_MOD)
    else $error("[%0t] FAIL MOD_001: mode bits changed in operating mode. reset_mode=%0b lom=%0b stm=%0b afm=%0b ext=%0b",
                $time, reset_mode, listen_only_mode, self_test_mode, acceptance_filter_mode, extended_mode);
  
  CAN_MOD_001_RST_LOW_C : cover property (CAN_MOD_001_RST_LOW_STABLE_MOD);