`ifndef CAN_ID_BOUNDARY_TEST_SV
`define CAN_ID_BOUNDARY_TEST_SV

class can_id_boundary_test extends uvm_test;
  `uvm_component_utils(can_id_boundary_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  function new(string name="can_id_boundary_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(virtual can_if)::get(this,"","vif",vif))
      `uvm_fatal("ID_BOUND_TEST","cannot get vif")

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b1;

    assert(env_cfg.c_cfg[0] != env_cfg.c_cfg[1])
      else `uvm_fatal("ID_BOUND_TEST","agents share same config object!")

    foreach(env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active              = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id               = i;
      env_cfg.c_cfg[i].enable_special_decode = 0;
      env_cfg.c_cfg[i].special_decode_idle   = 0;
      env_cfg.c_cfg[i].special_decode_ifs    = 0;
      env_cfg.c_cfg[i].publish_special_frames= 0;
      env_cfg.c_cfg[i].expect_no_ack         = 0;
      env_cfg.c_cfg[i].ack_enable            = 1'b1;
    end

    uvm_config_db#(can_env_config)::set(this,"m_env","can_env_config",env_cfg);
    m_env = can_env::type_id::create("m_env", this);

    uvm_config_db#(int unsigned)::set(this,"m_env.c_agent0.drvh","max_retries",3);
    uvm_config_db#(int unsigned)::set(this,"m_env.c_agent1.drvh","max_retries",3);
  endfunction

  task run_phase(uvm_phase phase);
    can_id_boundary_seq s;

    phase.raise_objection(this);

    s = can_id_boundary_seq::type_id::create("s");
    s.start(m_env.c_agent[0].seqrh);

    #200us;
    phase.drop_objection(this);
  endtask

endclass
`endif