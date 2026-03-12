`ifndef CAN_DUT_REMOTE_RX_TEST_SV
`define CAN_DUT_REMOTE_RX_TEST_SV

class can_dut_remote_rx_test extends uvm_test;
  `uvm_component_utils(can_dut_remote_rx_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  function new(string name="can_dut_remote_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("DUT_REMOTE_RX_TEST", "cannot get vif")

    // -- Environment config -----------------------------------
    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 1 active agent — sends the remote frame
    env_cfg.resize(1, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // Match your DUT bit timing (same as your other tests)
    env_cfg.c_cfg[0].is_active          = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id            = 0;
    env_cfg.c_cfg[0].bit_time_ns        = 320;
    env_cfg.c_cfg[0].sample_point_pct   = 75;

    // ACK behavior here is irrelevant (agent is transmitter), but keep it enabled
    env_cfg.c_cfg[0].ack_enable         = 1'b0;
    env_cfg.c_cfg[0].expect_no_ack      = 1'b0;

    env_cfg.c_cfg[0].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent*.drvh", "max_retries", 1);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_remote_rx_seq seq;

    phase.raise_objection(this);

    seq     = can_dut_remote_rx_seq::type_id::create("seq");
    seq.vif = vif;
    seq.start(m_env.c_agent[0].seqrh);

    #10us;
    phase.drop_objection(this);
  endtask

endclass

`endif