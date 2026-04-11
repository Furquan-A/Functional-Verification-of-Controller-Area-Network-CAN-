`ifndef CAN_DUT_OVERRUN_TEST_SV
`define CAN_DUT_OVERRUN_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_overrun_test extends uvm_test;
  `uvm_component_utils(can_dut_overrun_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  function new(string name="can_dut_overrun_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("DUT_OVR_TEST", "cannot get vif")

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 2 nodes: tx + ack helper
    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // Node0: TX source
    env_cfg.c_cfg[0].is_active        = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id          = 0;
    env_cfg.c_cfg[0].bit_time_ns      = 320;
    env_cfg.c_cfg[0].sample_point_pct = 75;
    env_cfg.c_cfg[0].ack_enable       = 1'b0;   // doesn't matter for transmitter
    env_cfg.c_cfg[0].expect_no_ack    = 1'b0;

    // Node1: ACK helper (keeps bus healthy / avoids retries)
    env_cfg.c_cfg[1].is_active        = UVM_ACTIVE;
    env_cfg.c_cfg[1].node_id          = 1;
    env_cfg.c_cfg[1].bit_time_ns      = 320;
    env_cfg.c_cfg[1].sample_point_pct = 75;
    env_cfg.c_cfg[1].ack_enable       = 1'b1;   // important: drive ACK for valid frames
    env_cfg.c_cfg[1].expect_no_ack    = 1'b0;

    // Keep defaults consistent
    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].enable_special_decode   = 1'b0;
      env_cfg.c_cfg[i].special_decode_idle     = 1'b0;
      env_cfg.c_cfg[i].special_decode_ifs      = 1'b0;
      env_cfg.c_cfg[i].publish_special_frames  = 1'b0;
    end

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_overrun_seq seq;

    phase.raise_objection(this);

    seq     = can_dut_overrun_seq::type_id::create("seq");
    seq.vif = vif;

    // Start on node0 sequencer (sequence sends can_transaction items)
    seq.start(m_env.c_agent[0].seqrh);

    #20us;
    phase.drop_objection(this);
  endtask

endclass

`endif