`ifndef CAN_DUT_ARBITRATION_LOST_TEST_SV
`define CAN_DUT_ARBITRATION_LOST_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_arbitration_lost_test extends uvm_test;
  `uvm_component_utils(can_dut_arbitration_lost_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  uvm_tlm_analysis_fifo #(can_transaction) mon_fifo;

  function new(string name = "can_dut_arbitration_lost_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("ARB_LOST_TEST", "Cannot get vif from config_db")

    mon_fifo = new("mon_fifo", this);

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // Node 0: passive monitor
    env_cfg.c_cfg[0].is_active              = UVM_PASSIVE;
    env_cfg.c_cfg[0].node_id                = 0;
    env_cfg.c_cfg[0].bit_time_ns            = 320;
    env_cfg.c_cfg[0].sample_point_pct       = 75;
    env_cfg.c_cfg[0].ack_enable             = 1'b0;
    env_cfg.c_cfg[0].expect_no_ack          = 1'b0;
    env_cfg.c_cfg[0].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    // Node 1: ACTIVE contender / winner
    env_cfg.c_cfg[1].is_active              = UVM_ACTIVE;
    env_cfg.c_cfg[1].node_id                = 1;
    env_cfg.c_cfg[1].bit_time_ns            = 320;
    env_cfg.c_cfg[1].sample_point_pct       = 75;
    env_cfg.c_cfg[1].ack_enable             = 1'b1;
    env_cfg.c_cfg[1].expect_no_ack          = 1'b0;
    env_cfg.c_cfg[1].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[1].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[1].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[1].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m_env.c_agent[0].monh.ap.connect(mon_fifo.analysis_export);
  endfunction

 task run_phase(uvm_phase phase);
  can_dut_arbitration_lost_seq arb_seq;
  can_transaction              obs_tr;
  int unsigned                 frames_total;
  int unsigned                 errors;
  bit                          saw_dut_retry_180;

  phase.raise_objection(this);

  frames_total      = 0;
  errors            = 0;
  saw_dut_retry_180 = 1'b0;

  arb_seq = can_dut_arbitration_lost_seq::type_id::create("arb_seq");
  arb_seq.vif       = vif;
  arb_seq.node1_sqr = m_env.c_agent[1].seqrh; // change only if your sequencer name differs

  `uvm_info("ARB_LOST_TEST",
    "Starting DUT arbitration-lost test",
    UVM_LOW)

  arb_seq.start(null);

  #100us;

  while (mon_fifo.try_get(obs_tr)) begin
    if (obs_tr.f_type == `CAN_DATA_FRAME) begin
      frames_total++;

      if (obs_tr.id[10:0] == 11'h180)
        saw_dut_retry_180 = 1'b1;
    end
  end

  `uvm_info("ARB_LOST_TEST",
    $sformatf("Monitor observed %0d data frame(s), saw_dut_retry_id180=%0b",
              frames_total, saw_dut_retry_180),
    UVM_LOW)

  if (!arb_seq.arb_irq_seen) begin
    `uvm_error("ARB_LOST_TEST",
      "Arbitration-lost IRQ was not observed")
    errors++;
  end

  if (!arb_seq.arb_ir_ali_seen) begin
    `uvm_error("ARB_LOST_TEST",
      "IR.ALI was not observed after arbitration loss")
    errors++;
  end

  if (!arb_seq.arb_alc_captured) begin
    `uvm_error("ARB_LOST_TEST",
      "ALC did not appear to capture the arbitration lost location")
    errors++;
  end

  if (!saw_dut_retry_180) begin
    `uvm_error("ARB_LOST_TEST",
      "DUT retry frame id=0x180 was not observed after arbitration loss")
    errors++;
  end

  if (!arb_seq.arb_lost_ok) begin
    `uvm_error("ARB_LOST_TEST",
      "Overall arbitration-lost sequence result failed")
    errors++;
  end

  if (errors == 0)
    `uvm_info("ARB_LOST_TEST",
      "PASS: DUT arbitration-lost test completed",
      UVM_LOW)
  else
    `uvm_error("ARB_LOST_TEST",
      $sformatf("FAIL: %0d violation(s)", errors))

  `uvm_info("ARB_LOST_TEST",
    "===== ARBITRATION LOST TEST COMPLETE =====",
    UVM_LOW)

  phase.drop_objection(this);
endtask

endclass

`endif