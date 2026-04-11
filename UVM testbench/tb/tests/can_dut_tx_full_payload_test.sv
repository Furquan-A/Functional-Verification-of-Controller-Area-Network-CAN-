`ifndef CAN_DUT_TX_FULL_PAYLOAD_TEST_SV
`define CAN_DUT_TX_FULL_PAYLOAD_TEST_SV

// =============================================================================
// can_dut_tx_full_payload_test
// =============================================================================
// Exercises ALL 13 TX buffer IBO modules by sending STD/EXT DATA/REMOTE
// frames with varied payloads (0xFF, 0xAA/0x55, 0x00, walking-bit).
// Agent node 0 monitors and ACKs each frame.
// =============================================================================

class can_dut_tx_full_payload_test extends uvm_test;
  `uvm_component_utils(can_dut_tx_full_payload_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  function new(string name="can_dut_tx_full_payload_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("TX_FULL_TEST", "cannot get vif")

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 1 active agent — monitors bus and ACKs DUT frames
    env_cfg.resize(1, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    env_cfg.c_cfg[0].is_active            = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id              = 0;
    env_cfg.c_cfg[0].bit_time_ns          = 320;
    env_cfg.c_cfg[0].sample_point_pct     = 75;
    env_cfg.c_cfg[0].ack_enable           = 1'b1;
    env_cfg.c_cfg[0].expect_no_ack        = 1'b0;
    env_cfg.c_cfg[0].enable_special_decode = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle  = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs   = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_tx_full_payload_seq seq;

    phase.raise_objection(this);

    seq     = can_dut_tx_full_payload_seq::type_id::create("seq");
    seq.vif = vif;
    seq.start(null);

    #20us;
    phase.drop_objection(this);
  endtask

endclass
`endif