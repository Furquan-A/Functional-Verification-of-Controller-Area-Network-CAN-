`ifndef CAN_DUT_ACCEPTANCE_FILTER_TEST_SV
`define CAN_DUT_ACCEPTANCE_FILTER_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_acceptance_filter_test extends uvm_test;
  `uvm_component_utils(can_dut_acceptance_filter_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  function new(string name="can_dut_acceptance_filter_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("DUT_AFM_TEST", "cannot get vif")

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(1, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    env_cfg.c_cfg[0].is_active          = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id            = 0;
    env_cfg.c_cfg[0].bit_time_ns        = 320;
    env_cfg.c_cfg[0].sample_point_pct   = 75;

    // Agent is transmitter here; these are harmless defaults
    env_cfg.c_cfg[0].ack_enable         = 1'b1;
    env_cfg.c_cfg[0].expect_no_ack      = 1'b0;

    env_cfg.c_cfg[0].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_acceptance_filter_seq seq;

    phase.raise_objection(this);

    seq     = can_dut_acceptance_filter_seq::type_id::create("seq");
    seq.vif = vif;

    // Start on agent sequencer (sequence sends can_transaction items)
    seq.start(m_env.c_agent[0].seqrh);

    #10us;
    phase.drop_objection(this);
  endtask

endclass

`endif