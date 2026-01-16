`ifndef CAN_SMOKE_TEST_SV
`define CAN_SMOKE_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_smoke_test extends uvm_test;
  `uvm_component_utils(can_smoke_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name = "can_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get vif that top sets: uvm_config_db#(virtual can_if)::set(null,"*","vif",vif);
    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_SMOKE_TEST", "Cannot get vif from config_db (key='vif')")

    // Build env config
    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // For smoke: 1 CAN agent (TX) + 1 REG agent (to configure DUT if needed)
    env_cfg.resize(1, 1);

    // Make CAN agent active (so it has driver + sequencer)
    env_cfg.c_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id   = 0;

    // Make sure reg agent config has vif too (resize() already did if you fixed it)
    // env_cfg.r_cfg[0].is_active = UVM_ACTIVE; // if your reg_agent_config supports it

    // Validate
    begin
      string why;
      if (!env_cfg.validate(why))
        `uvm_fatal("CAN_SMOKE_TEST", {"env_cfg validate failed: ", why})
    end

    // Set env config into env
    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);

    // Create env
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // Pick which smoke sequence to run:
     can_std_smoke_tx_seq seq;
   // can_ext_smoke_tx_seq seq;

    seq = can_std_smoke_tx_seq::type_id::create("seq");

    // Sanity: ensure agent exists and has sequencer
    if (m_env.c_agent.size() == 0 || m_env.c_agent[0] == null)
      `uvm_fatal("CAN_SMOKE_TEST", "No CAN agent[0] found in env")

    if (m_env.c_agent[0].seqrh == null)
      `uvm_fatal("CAN_SMOKE_TEST", "CAN agent[0] sequencer is null (is_active must be UVM_ACTIVE)")

    seq.start(m_env.c_agent[0].seqrh);

    // Give monitor time to decode EOF and publish
    #200us;

    phase.drop_objection(this);
  endtask

endclass : can_smoke_test

`endif // CAN_SMOKE_TEST_SV
