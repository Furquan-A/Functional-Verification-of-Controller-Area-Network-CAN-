`ifndef CAN_FORM_ERROR_TEST_SV
`define CAN_FORM_ERROR_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_form_error_test extends uvm_test;
  `uvm_component_utils(can_form_error_test)

  can_env m_env;
  can_env_config env_cfg;
  virtual can_if vif;
  

  function new(string name="can_form_error_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
  
    // ------------------------------------------------------------
    // 1) Get vif
    // ------------------------------------------------------------
    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "Cannot get vif from config_db (key='vif')")
  
    // ------------------------------------------------------------
    // 2) Create + fill env config BEFORE env is created
    // ------------------------------------------------------------
    env_cfg = can_env_config::type_id::create("env_cfg");
    if (env_cfg == null)
      `uvm_fatal(get_type_name(), "Failed to create env_cfg")
  
    env_cfg.vif = vif;
  
    // ---- Our spec: 3 nodes (node0 TX, node1+node2 RX/ACK)
    env_cfg.resize(3, 0);
  
    env_cfg.has_reg_agent        = 0;
    env_cfg.has_can_scoreboard   = 1;
      

    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active  = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id    = i;
  
      // default safe values
      env_cfg.c_cfg[i].ack_enable       = 1'b1;
      env_cfg.c_cfg[i].expect_no_ack    = 1'b0;
      env_cfg.c_cfg[i].is_tx_in_progress = 1'b0; // driver will toggle it
      env_cfg.c_cfg[i].enable_special_decode  = 0;
    env_cfg.c_cfg[i].publish_special_frames = 0;
    end
  
    // ------------------------------------------------------------
    // 3) Apply per-node behavior (our spec)
    // ------------------------------------------------------------
    // Node0: transmitter, MUST NOT ACK itself
    env_cfg.c_cfg[0].ack_enable = 1'b0;
  
    // Node1/2: receivers, they ACK only if frame is valid (monitor logic)
    env_cfg.c_cfg[1].ack_enable = 1'b1;
    env_cfg.c_cfg[2].ack_enable = 1'b1;
  
    // ------------------------------------------------------------
    // 4) Set config into DB BEFORE creating the env
    // ------------------------------------------------------------
    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
  
    // ------------------------------------------------------------
    // 5) Now create env (it will pick config in its build_phase)
    // ------------------------------------------------------------
    m_env = can_env::type_id::create("m_env", this);
    if (m_env == null)
      `uvm_fatal(get_type_name(), "Failed to create m_env")
  
  endfunction


  task run_phase(uvm_phase phase);
    can_form_error_seq seq;

    phase.raise_objection(this);

    `uvm_info("FORM_TEST", "Starting FORM-error sequence on node0", UVM_LOW)

    seq = can_form_error_seq::type_id::create("seq");
    seq.id  = 29'h00000123;
    seq.dlc = 4;

    // start on node0 only
    seq.start(m_env.c_agent[0].seqrh);

    // allow retries + scoreboard compare
    #300us;

    phase.drop_objection(this);
  endtask

endclass : can_form_error_test

`endif
