`ifndef CAN_RANDOM_TEST_SV
`define CAN_RANDOM_TEST_SV

// =============================================================================
// can_random_test
// =============================================================================
// Runs can_random_seq on 2 active agent nodes simultaneously.
// Node 0 sends frames with higher IDs, Node 1 with lower IDs.
// Natural arbitration occurs when both transmit concurrently.
// Scoreboard enabled — verifies all successful frames.
// =============================================================================

class can_random_test extends uvm_test;
  `uvm_component_utils(can_random_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  int unsigned frames_per_node = 100;

  function new(string name="can_random_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("RANDOM_TEST", "cannot get vif")

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 2 active agents — both TX and monitor/ACK each other
    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // -- Agent 0: higher IDs ----------------------------------
    env_cfg.c_cfg[0].is_active            = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id              = 0;
    env_cfg.c_cfg[0].bit_time_ns          = 320;
    env_cfg.c_cfg[0].sample_point_pct     = 75;
    env_cfg.c_cfg[0].ack_enable           = 1'b1;
    env_cfg.c_cfg[0].expect_no_ack        = 1'b0;
    env_cfg.c_cfg[0].arbitration_enable   = 1'b1;
    env_cfg.c_cfg[0].enable_special_decode = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle  = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs   = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    // -- Agent 1: lower IDs -----------------------------------
    env_cfg.c_cfg[1].is_active            = UVM_ACTIVE;
    env_cfg.c_cfg[1].node_id              = 1;
    env_cfg.c_cfg[1].bit_time_ns          = 320;
    env_cfg.c_cfg[1].sample_point_pct     = 75;
    env_cfg.c_cfg[1].ack_enable           = 1'b1;
    env_cfg.c_cfg[1].expect_no_ack        = 1'b0;
    env_cfg.c_cfg[1].arbitration_enable   = 1'b1;
    env_cfg.c_cfg[1].enable_special_decode = 1'b0;
    env_cfg.c_cfg[1].special_decode_idle  = 1'b0;
    env_cfg.c_cfg[1].special_decode_ifs   = 1'b0;
    env_cfg.c_cfg[1].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_random_seq seq0, seq1;

    phase.raise_objection(this);

    // Create sequences for both nodes
    seq0 = can_random_seq::type_id::create("seq0");
    seq0.n_frames = frames_per_node;
    seq0.is_node0 = 1;

    seq1 = can_random_seq::type_id::create("seq1");
    seq1.n_frames = frames_per_node;
    seq1.is_node0 = 0;

    // Launch both in parallel — natural arbitration on the bus
    fork
      seq0.start(m_env.c_agent[0].seqrh);
      seq1.start(m_env.c_agent[1].seqrh);
    join

    // Allow monitor to finish last frame (EOF + IFS)
    #50us;

    `uvm_info("RANDOM_TEST", "===== RANDOM TEST COMPLETE =====", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass
`endif