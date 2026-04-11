`ifndef CAN_DUT_INT_DISABLE_TEST_SV
`define CAN_DUT_INT_DISABLE_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_int_disable_test extends uvm_test;
  `uvm_component_utils(can_dut_int_disable_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  uvm_tlm_analysis_fifo #(can_transaction) mon_fifo;

  function new(string name = "can_dut_int_disable_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("INT_DIS_TEST", "Cannot get vif from config_db")

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

    // Node 1: ACTIVE so it can ACK DUT TX and later send a valid RX frame
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
    can_dut_int_disable_seq int_seq;
    can_transaction         obs_tr;
    int unsigned            frames_total;
    int unsigned            errors;
    bit                     saw_dut_tx_201;
    bit                     saw_node1_tx_301;

    phase.raise_objection(this);

    frames_total    = 0;
    errors          = 0;
    saw_dut_tx_201  = 1'b0;
    saw_node1_tx_301= 1'b0;

    int_seq = can_dut_int_disable_seq::type_id::create("int_seq");
    int_seq.vif       = vif;
    int_seq.node1_sqr = m_env.c_agent[1].seqrh; // adapt only if your sequencer name differs

    `uvm_info("INT_DIS_TEST",
      "Starting interrupt-disable closure test for CR_006_TX_INT_DIS / CR_007_RX_INT_DIS",
      UVM_LOW)

    int_seq.start(null);

    #100us;

    while (mon_fifo.try_get(obs_tr)) begin
      frames_total++;

      if ((obs_tr.f_type == `CAN_DATA_FRAME) && (obs_tr.id == 11'h201))
        saw_dut_tx_201 = 1'b1;

      if ((obs_tr.f_type == `CAN_DATA_FRAME) && (obs_tr.id == 11'h301))
        saw_node1_tx_301 = 1'b1;
    end

    `uvm_info("INT_DIS_TEST",
      $sformatf("Monitor observed %0d frame(s), saw_dut_id201=%0b, saw_node1_id301=%0b",
                frames_total, saw_dut_tx_201, saw_node1_tx_301),
      UVM_LOW)

    if (!int_seq.tx_event_seen) begin
      `uvm_error("INT_DIS_TEST",
        "TX interrupt-disable setup failed: sequence never observed TX completion event")
      errors++;
    end

    if (!int_seq.rx_event_seen) begin
      `uvm_error("INT_DIS_TEST",
        "RX interrupt-disable setup failed: sequence never observed RX completion event")
      errors++;
    end

    if (!saw_dut_tx_201) begin
      `uvm_error("INT_DIS_TEST",
        "TX interrupt-disable setup failed: DUT TX frame id=0x201 was not observed")
      errors++;
    end

    if (!saw_node1_tx_301) begin
      `uvm_error("INT_DIS_TEST",
        "RX interrupt-disable setup failed: node1 valid frame id=0x301 was not observed")
      errors++;
    end

    if (!int_seq.tx_int_dis_ok) begin
      `uvm_error("INT_DIS_TEST",
        "CR_006_TX_INT_DIS scenario failed")
      errors++;
    end

    if (!int_seq.rx_int_dis_ok) begin
      `uvm_error("INT_DIS_TEST",
        "CR_007_RX_INT_DIS scenario failed")
      errors++;
    end

    if (errors == 0)
      `uvm_info("INT_DIS_TEST",
        "PASS: interrupt-disable closure test completed",
        UVM_LOW)
    else
      `uvm_error("INT_DIS_TEST",
        $sformatf("FAIL: %0d violation(s)", errors))

    `uvm_info("INT_DIS_TEST",
      "===== INTERRUPT DISABLE TEST COMPLETE =====",
      UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass

`endif