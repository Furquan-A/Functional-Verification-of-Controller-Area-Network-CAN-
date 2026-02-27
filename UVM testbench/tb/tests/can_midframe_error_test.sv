`ifndef CAN_MIDFRAME_ERROR_TEST_SV
`define CAN_MIDFRAME_ERROR_TEST_SV

class can_midframe_error_test extends uvm_test;
  `uvm_component_utils(can_midframe_error_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_midframe_error_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("MID_ERR_TEST", "Cannot get vif")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 0;

    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active              = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id                = i;
      env_cfg.c_cfg[i].enable_special_decode  = 1;
      env_cfg.c_cfg[i].publish_special_frames = 1; // ONLY FOR THIS TEST
      env_cfg.c_cfg[i].expect_no_ack          = 0;
    end

    // Node1 may ACK when it is not transmitting; mid-frame error will likely disrupt ACK anyway
    env_cfg.c_cfg[0].ack_enable = 0;
    env_cfg.c_cfg[1].ack_enable = 1;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);

    // Keep retry noise low
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent0.drvh", "max_retries", 1);
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent1.drvh", "max_retries", 1);
  endfunction

  task run_phase(uvm_phase phase);
    can_midframe_error_seq s;

    phase.raise_objection(this);

    s = can_midframe_error_seq::type_id::create("s");
    s.other_sqr  = m_env.c_agent[1].seqrh;
    s.err_delay  = 10us; // adjust if needed
    s.start(m_env.c_agent[0].seqrh);

    #200us;
    phase.drop_objection(this);
  endtask

endclass

`endif