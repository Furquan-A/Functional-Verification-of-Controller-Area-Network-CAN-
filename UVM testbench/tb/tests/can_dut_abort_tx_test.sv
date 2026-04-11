`ifndef CAN_DUT_ABORT_TX_TEST_SV
`define CAN_DUT_ABORT_TX_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_abort_tx_test extends uvm_test;
  `uvm_component_utils(can_dut_abort_tx_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  uvm_tlm_analysis_fifo #(can_transaction) mon_fifo;

  function new(string name = "can_dut_abort_tx_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("ABORT_TX_TEST", "Cannot get vif from config_db")

    mon_fifo = new("mon_fifo", this);

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // Node 0 passive monitor
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

    // Node 1 active sender for valid busy bus
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
    can_dut_abort_tx_seq ab_seq;
    can_transaction      obs_tr;
    int unsigned         frames_total;
    int unsigned         errors;
    bit                  saw_node1_busy_frame;
    bit                  saw_dut_pending_frame;

    phase.raise_objection(this);

    frames_total         = 0;
    errors               = 0;
    saw_node1_busy_frame = 1'b0;
    saw_dut_pending_frame= 1'b0;

    vif.tb_tx[1] = 1'b1;

    ab_seq = can_dut_abort_tx_seq::type_id::create("ab_seq");
    ab_seq.vif       = vif;
    ab_seq.node1_sqr = m_env.c_agent[1].seqrh;

    `uvm_info("ABORT_TX_TEST",
      "Starting abort / TX-control test for CMR_002 / CMR_003 / CMR_004",
      UVM_LOW)

    ab_seq.start(null);

    #50us;

    while (mon_fifo.try_get(obs_tr)) begin
      frames_total++;

      if ((obs_tr.f_type == `CAN_DATA_FRAME) && (obs_tr.id == 11'h321))
        saw_node1_busy_frame = 1'b1;

      if ((obs_tr.f_type == `CAN_DATA_FRAME) && (obs_tr.id == 11'h102))
        saw_dut_pending_frame = 1'b1;
    end

    `uvm_info("ABORT_TX_TEST",
      $sformatf("Monitor observed %0d frame(s), saw_busy_id321=%0b, saw_dut_id102=%0b",
                frames_total, saw_node1_busy_frame, saw_dut_pending_frame),
      UVM_LOW)

    if (!ab_seq.tr_zero_preserved_ok) begin
      `uvm_error("ABORT_TX_TEST",
        "CMR_002 scenario failed: TR request looked cancelled by zero write")
      errors++;
    end

    if (!ab_seq.at_no_pending_ok) begin
      `uvm_error("ABORT_TX_TEST",
        "CMR_003 scenario failed: AT with no pending request caused unexpected activity")
      errors++;
    end

    if (!ab_seq.at_clears_pending_ok) begin
      `uvm_error("ABORT_TX_TEST",
        "CMR_004 command-level scenario failed: AT did not appear to clear pending request while bus was busy")
      errors++;
    end

    if (!saw_node1_busy_frame) begin
      `uvm_error("ABORT_TX_TEST",
        "S3 setup failed: node1 valid busy frame (id=0x321) was not observed")
      errors++;
    end

    if (saw_dut_pending_frame) begin
      `uvm_error("ABORT_TX_TEST",
        "CMR_004 functional failure: DUT frame id=0x102 was observed after AT")
      errors++;
    end

    if (errors == 0)
      `uvm_info("ABORT_TX_TEST",
        "PASS: abort / TX-control test completed",
        UVM_LOW)
    else
      `uvm_error("ABORT_TX_TEST",
        $sformatf("FAIL: %0d violation(s)", errors))

    `uvm_info("ABORT_TX_TEST",
      "===== ABORT / TX-CONTROL TEST COMPLETE =====",
      UVM_LOW)

    vif.tb_tx[1] = 1'b1;
    phase.drop_objection(this);
  endtask

endclass

`endif