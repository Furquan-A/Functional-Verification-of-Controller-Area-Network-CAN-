`ifndef CAN_IFS_OVERLOAD_TEST_SV
`define CAN_IFS_OVERLOAD_TEST_SV

class can_ifs_overload_test extends uvm_test;
  `uvm_component_utils(can_ifs_overload_test)
  
  virtual can_if vif;
  can_env_config env_cfg;
  can_env m_env;
  
  function new(string name = "can_ifs_overload_test", uvm_component parent = null);
    super.new(name,parent);
  endfunction 
  
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    if(!uvm_config_db #(virtual can_if)::get(this,"","vif",vif))
      `uvm_fatal("IFS_OVL_TEST","cannot get vif");
      
    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;
    
    env_cfg.resize(2,0);
    env_cfg.has_can_scoreboard = 1'b0;
    
    assert(env_cfg.c_cfg[0] != env_cfg.c_cfg[1])
      else `uvm_fatal("TEST","agents share same config object!")
  
    foreach(env_cfg.c_cfg[i]) begin 
      env_cfg.c_cfg[i].is_active = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id = i;
      env_cfg.c_cfg[i].enable_special_decode = 1;
      env_cfg.c_cfg[i].special_decode_idle     = 0; // disable IDLE special decode
      env_cfg.c_cfg[i].special_decode_ifs      = 1; // enable IFS overload decode
    //  env_cfg.c_cfg[i].special_decode_mid      = 0; // disable midframe detection
      env_cfg.c_cfg[i].publish_special_frames = 1; // only for this test
      env_cfg.c_cfg[i].expect_no_ack = 1'b0;
    end 
    
    // make primer data succees ( ACK from Node1)
    env_cfg.c_cfg[0].ack_enable = 1'b0;
    env_cfg.c_cfg[1].ack_enable = 1'b1;
    
    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env",this);
    
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent0.drvh", "max_retries", 5);
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent1.drvh", "max_retries", 5);
  endfunction
  
  task run_phase(uvm_phase phase);
    can_ifs_overload_seq s;
    
    phase.raise_objection(this);
    
    s = can_ifs_overload_seq::type_id::create("s");
    s.other_sqr = m_env.c_agent[1].seqrh;
    s.start(m_env.c_agent[0].seqrh);
    
    #200us;
    
    if(!m_env.c_agent[0].monh.overload_seen)
      `uvm_error("IFS_CHECK","Node0 moniotr did NOT see the OVERLOAD FRAME")
      
    if (!m_env.c_agent[1].monh.overload_seen)
      `uvm_error("IFS_CHECK", "node1 monitor did NOT see overload frame") 
      
    phase.drop_objection(this);
    
  endtask
  
endclass
`endif