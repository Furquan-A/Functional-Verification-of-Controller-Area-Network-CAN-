`ifndef CAN_REMOTE_RESPONSE_TEST_SV
`define CAN_REMOTE_RESPONSE_TEST_SV

class can_remote_response_test extends uvm_test;
  `uvm_component_utils(can_remote_response_test)

  virtual can_if vif;
  can_env        m_env;
  can_env_config env_cfg;

  function new(string name="can_remote_response_test", uvm_component parent=null);
    super.new(name, parent);  // Bug 1 fixed
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(virtual can_if)::get(this,"","vif",vif))  // Bug 2 fixed
      `uvm_fatal("REM_RSP_TEST","cannot get vif");

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b0;  // Bug 5 fixed

    // Bug 4 fixed — correct assertion logic
    assert(env_cfg.c_cfg[0] != env_cfg.c_cfg[1])
      else `uvm_fatal("REM_RSP_TEST","agents share same config object!")

    foreach(env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active              = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id               = i;
      env_cfg.c_cfg[i].enable_special_decode = 1'b0;  // Bug 8 — not needed
      env_cfg.c_cfg[i].special_decode_idle   = 1'b0;
      env_cfg.c_cfg[i].special_decode_ifs    = 1'b0;
      // Bug 7 fixed — removed special_decode_mid
      env_cfg.c_cfg[i].publish_special_frames= 1'b0;  // Bug 6 fixed
      env_cfg.c_cfg[i].expect_no_ack         = 1'b0;
      env_cfg.c_cfg[i].ack_enable            = 1'b1;
    end

    // Bug 3 fixed — correct type
    uvm_config_db#(can_env_config)::set(this,"m_env","can_env_config",env_cfg);
    m_env = can_env::type_id::create("m_env",this);

    uvm_config_db#(int unsigned)::set(this,"m_env.c_agent0.drvh","max_retries",3);
    uvm_config_db#(int unsigned)::set(this,"m_env.c_agent1.drvh","max_retries",3);
  endfunction

  task run_phase(uvm_phase phase);
    can_remote_response_seq s;

    phase.raise_objection(this);

    s           = can_remote_response_seq::type_id::create("s");
    s.other_sqr = m_env.c_agent[1].seqrh;
    s.req_id    = 11'h321;
    s.req_dlc   = 4;

    s.resp_data    = new[s.req_dlc];
    s.resp_data[0] = 8'hDE;
    s.resp_data[1] = 8'hAD;
    s.resp_data[2] = 8'hBE;
    s.resp_data[3] = 8'hEF;

    s.start(m_env.c_agent[0].seqrh);

    #200us;
    phase.drop_objection(this);
  endtask

endclass
`endif