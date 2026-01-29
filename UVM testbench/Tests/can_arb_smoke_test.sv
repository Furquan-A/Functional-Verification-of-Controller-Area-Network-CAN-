`ifndef CAN_ARB_SMOKE_TEST_SV
`define CAN_ARB_SMOKE_TEST_SV

class can_arb_smoke_test extends uvm_test;
  `uvm_component_utils(can_arb_smoke_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_arb_smoke_test", uvm_component parent=null);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_ARB_TEST", "Cannot get vif from config_db (key='vif')")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 2 CAN nodes, no reg agent for now
    env_cfg.resize(3, 0);
    env_cfg.has_reg_agent = 0;

    /* // Both ACTIVE (both transmit)
    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active  = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id    = i;
      env_cfg.c_cfg[i].vif        = vif;
      env_cfg.c_cfg[i].ack_enable = 0; // add a 3rd node later for ACK
    end
    */
    env_cng.c_cfg[0].is_active = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id = 0;
    env_cfg.c_cfg[0].ack_enable = 0; // Winner of Arbitration (TX) should not ack 
    
    env_cng.c_cfg[1].is_active = UVM_ACTIVE;
    env_cfg.c_cfg[1].node_id = 1;
    env_cfg.c_cfg[1].ack_enable = 1; // receiver will ack 
    
    env_cng.c_cfg[2].is_active = UVM_ACTIVE;
    env_cfg.c_cfg[2].node_id = 2;
    env_cfg.c_cfg[2].ack_enable = 1; // receiver will ack // Winner of Arbitration (TX) should not ack 
    
    // Validate
    begin
      string why;
      if (!env_cfg.validate(why))
        `uvm_fatal("CAN_ARB_TEST", {"env_cfg validate failed: ", why})
    end

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_arb_tx_seq seq0;
    can_arb_tx_seq seq1;

    phase.raise_objection(this);

    // Two IDs: lower wins
    seq0 = can_arb_tx_seq::type_id::create("seq0");
    seq0.cfg_fmt    = `CAN_ID_STD;
    seq0.cfg_id     = 29'(11'h120);
    seq0.cfg_remote = 0;
    seq0.cfg_data   = new[4];
    seq0.cfg_data[0]= 8'hAA;
    seq0.cfg_data[1]= 8'h55;
    seq0.cfg_data[2]= 8'h0F;
    seq0.cfg_data[3]= 8'hF0;
    seq0.cfg_dlc    = 4;

    seq1 = can_arb_tx_seq::type_id::create("seq1");
    seq1.cfg_fmt    = `CAN_ID_STD;
    seq1.cfg_id     = 29'(11'h123);
    seq1.cfg_remote = 0;
    seq1.cfg_data   = new[4];
    seq1.cfg_data[0]= 8'h11;
    seq1.cfg_data[1]= 8'h22;
    seq1.cfg_data[2]= 8'h33;
    seq1.cfg_data[3]= 8'h44;
    seq1.cfg_dlc    = 4;

    // Start both concurrently
    fork
      seq0.start(m_env.c_agent[0].seqrh);
      seq1.start(m_env.c_agent[1].seqrh);
    join

    // Let monitors finish decoding + scoreboard compare
    #300us;

    phase.drop_objection(this);
  endtask

endclass : can_arb_smoke_test

`endif
