`ifndef CAN_ACK_ERROR_TEST_SV
`define CAN_ACK_ERROR_TEST_SV

class can_ack_error_test extends uvm_test;
  `uvm_component_utils(can_ack_error_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_ack_error_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("ACK_TEST", "Cannot get vif from config_db")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // Use 2 nodes for clean ACK test
    env_cfg.resize(2, 0);
    env_cfg.has_reg_agent       = 0;
    env_cfg.has_can_scoreboard  = 1;

    // ---------------------------
    // Node0 = transmitter
    // Node1 = receiver (but forced to not ACK)
    // ---------------------------
    env_cfg.c_cfg[0].is_active     = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id       = 0;
    env_cfg.c_cfg[0].ack_enable    = 0;      // optional; TX doesn't ACK anyway
    env_cfg.c_cfg[0].expect_no_ack = 0;      // doesn't matter for TX

    env_cfg.c_cfg[1].is_active     = UVM_PASSIVE; // receiver doesn't need a driver
    env_cfg.c_cfg[1].node_id       = 1;
    env_cfg.c_cfg[1].ack_enable    = 1;      // IMPORTANT: receiver is capable of ACK...
    env_cfg.c_cfg[1].expect_no_ack = 1;      // ...but test forces NO-ACK

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_ack_error_seq s0;

    phase.raise_objection(this);

    s0 = can_ack_error_seq::type_id::create("s0");
    s0.id      = 29'h00000123;
    s0.dlc     = 4;
    s0.payload = '{8'hAA, 8'h55, 8'h0F, 8'hF0};

    `uvm_info("ACK_TEST", "Starting ACK-error sequence on node0", UVM_LOW)
    s0.start(m_env.c_agent[0].seqrh);

    #200us;
    phase.drop_objection(this);
  endtask

endclass

`endif
