`ifndef CAN_EXT_FRAME_TEST_SV
`define CAN_EXT_FRAME_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_ext_frame_test extends uvm_test;
  `uvm_component_utils(can_ext_frame_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_ext_frame_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("EXT_TEST", "Cannot get vif (key='vif')")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1;
    env_cfg.has_reg_agent      = 0;

    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active              = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id                = i;

      // Disable special decode for this test
      env_cfg.c_cfg[i].enable_special_decode  = 0;
      env_cfg.c_cfg[i].publish_special_frames = 0;

      env_cfg.c_cfg[i].expect_no_ack          = 0;
    end

    // ACK on node1 so node0 succeeds
    env_cfg.c_cfg[0].ack_enable = 0;
    env_cfg.c_cfg[1].ack_enable = 1;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);

    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent0.drvh", "max_retries", 2);
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent1.drvh", "max_retries", 2);
  endfunction

  task run_phase(uvm_phase phase);
    can_ext_data_seq s;

    phase.raise_objection(this);

    s = can_ext_data_seq::type_id::create("s");

    // Pick a clearly-extended 29-bit ID
    s.ext_id = 29'h1ABCDE1;
    s.dlc    = 8;

    s.payload = new[s.dlc];
    foreach (s.payload[i]) s.payload[i] = (8'h10 + i);

    s.start(m_env.c_agent[0].seqrh);

    #200us;
    phase.drop_objection(this);
  endtask

endclass

`endif