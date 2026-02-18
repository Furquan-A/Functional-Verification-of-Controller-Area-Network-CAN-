`ifndef CAN_CRC_ERROR_TEST_SV
`define CAN_CRC_ERROR_TEST_SV

class can_crc_error_test extends uvm_test;
  `uvm_component_utils(can_crc_error_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_crc_error_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_CRC_TEST", "Cannot get vif from config_db (key='vif')")

    // ---------------- ENV CFG ----------------
    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 3 nodes: node0 TX, node1/2 RX
    env_cfg.resize(3, 0);
    env_cfg.has_reg_agent        = 0;
    env_cfg.has_can_scoreboard   = 1;

    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active  = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id    = i;

      // Timing defaults ok (or set explicitly)
      // env_cfg.c_cfg[i].bit_time_ns        = 100;
      // env_cfg.c_cfg[i].sample_point_pct   = 75;

      // ACK behavior:
      // node0 is transmitter => should NOT ACK
      // node1/node2 are receivers => should ACK (unless CRC error detected)
      env_cfg.c_cfg[i].ack_enable = (i != 0);

      // arbitration doesn't matter here (only node0 transmits), but keep enabled
      env_cfg.c_cfg[i].arbitration_enable = 1'b1;

      // error injection knobs here are per-transaction, not per-node
    end

    // Scoreboard needs num_nodes
    uvm_config_db#(int unsigned)::set(this, "m_env.c_sb", "num_nodes", 3);

    // Driver retry depth for this test
    uvm_config_db#(int unsigned)::set(this, "m_env.c_agent0.drv", "max_retries", 3);

    // push env cfg
    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);

    // create env
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_crc_error_seq seq;

    phase.raise_objection(this);

    // sanity
    if (m_env.c_agent.size() < 3)
      `uvm_fatal("CAN_CRC_TEST", "Need 3 CAN agents")

    foreach (m_env.c_agent[i]) begin
      if (m_env.c_agent[i] == null || m_env.c_agent[i].seqrh == null)
        `uvm_fatal("CAN_CRC_TEST", $sformatf("Agent %0d missing or sequencer null", i))
    end

    // ------------------------------------------------------------
    // Start CRC error sequence on node0 only
    // The seq sends:
    //   1) CRC-bad frame (inj_crc_error=1)
    //   2) CRC-good frame (inj_crc_error=0)
    // Driver should see NO ACK on first and retry (if your receivers gate ACK on CRC mismatch)
    // ------------------------------------------------------------
    seq = can_crc_error_seq::type_id::create("seq");

    // optional GO barrier (only if your sequence supports it)
    // seq.use_go_event = 1;
    // uvm_event_pool::get_global("CRC_GO").trigger();

    seq.id  = 29'h00000123;
    seq.dlc = 4;
    seq.payload = '{8'hC0, 8'hC1, 8'hC2, 8'hC3};

    seq.start(m_env.c_agent[0].seqrh);

    // allow decode + scoreboard
    #500us;

    phase.drop_objection(this);
  endtask

endclass : can_crc_error_test

`endif // CAN_CRC_ERROR_TEST_SV
