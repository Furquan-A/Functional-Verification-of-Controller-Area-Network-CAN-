`ifndef CAN_STUFF_ERROR_TEST_SV
`define CAN_STUFF_ERROR_TEST_SV

class can_stuff_error_test extends uvm_test;
  `uvm_component_utils(can_stuff_error_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_stuff_error_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_STUFF_TEST", "Cannot get vif from config_db (key='vif')")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(3, 0);
    env_cfg.has_reg_agent = 0;
    env_cfg.has_can_scoreboard = 1;
    
    

    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active  = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id    = i;

      // Only receivers ACK. Let node1 & node2 ACK, node0 does not.
      env_cfg.c_cfg[i].ack_enable = (i != 0);
      env_cfg.c_cfg[i].enable_special_decode  = 0;
    env_cfg.c_cfg[i].publish_special_frames = 0;  
    end

    begin
      string why;
      if (!env_cfg.validate(why))
        `uvm_fatal("CAN_STUFF_TEST", {"env_cfg validate failed: ", why})
    end

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);

    // Optional: allow more retries if you want
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent0.drvh", "max_retries", 5);
  endfunction

  task run_phase(uvm_phase phase);
    can_stuff_error_seq seq;

    phase.raise_objection(this);

    seq = can_stuff_error_seq::type_id::create("seq");
    seq.id  = 29'h00000123;
    seq.dlc = 4;
    // seq.payload optional; default makes lots of zeros

    seq.start(m_env.c_agent[0].seqrh);

    // give time for retries + monitors + scoreboard
    #300us;

    phase.drop_objection(this);
  endtask

endclass : can_stuff_error_test

`endif // CAN_STUFF_ERROR_TEST_SV
