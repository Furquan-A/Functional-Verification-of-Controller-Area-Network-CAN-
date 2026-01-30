`ifndef CAN_SMOKE_TEST_SV
`define CAN_SMOKE_TEST_SV

class can_smoke_test extends uvm_test;
  `uvm_component_utils(can_smoke_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_smoke_test", uvm_component parent=null);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_SMOKE_TEST", "Cannot get vif (key='vif')")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;
    env_cfg.resize(2, 0);              // 2 CAN agent, 0 reg agents (Phase A)
    env_cfg.has_reg_agent = 0;
    
    // Node 0: Active TX node 
    env_cfg.c_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id   = 0;
    env_cfg.c_cfg[0].vif       = vif;
    env_cfg.c_cfg[0].ack_enable = 0;
    
    //Nde 1: Passive observer for now ( we will add ack later)
    env_cfg.c_cfg[1].is_active  = UVM_ACTIVE; 
    env_cfg.c_cfg[1].node_id   = 1;
    env_cfg.c_cfg[0].vif       = vif;
    env_cfg.c_cfg[1].ack_enable = 1;
    
    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);

    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_ext_smoke_tx_seq seq;

    phase.raise_objection(this);

    seq = can_ext_smoke_tx_seq::type_id::create("seq");
    seq.start(m_env.c_agent[0].seqrh);

    #200us;
    phase.drop_objection(this);
  endtask
  
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass

`endif
