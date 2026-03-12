`ifndef CAN_DUT_RX_TEST_SV
`define CAN_DUT_RX_TEST_SV

// =============================================================================
// can_dut_rx_test
// =============================================================================
// Agent node 0 drives a STD DATA frame onto the CAN bus.
// The DUT (connected via Wishbone) receives it.
// The test reads the DUT RX buffer via WB and compares against what was sent.
//
// CRITICAL:  Agent bit_time_ns and sample_point_pct MUST match the DUT's
//            BTR0/BTR1 configuration set in can_dut_init_seq.
// =============================================================================

class can_dut_rx_test extends uvm_test;
  `uvm_component_utils(can_dut_rx_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  function new(string name="can_dut_rx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("DUT_RX_TEST", "cannot get vif")

    // -- Environment config -----------------------------------
    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 1 active agent (bus side), no scoreboard for now
    env_cfg.resize(1, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // -- Agent 0 config — must match DUT bit timing -----------
    //   DUT BTR0=0x00, BTR1=0x14 @ 50 MHz:
    //     tq = 2*(0+1)/50MHz = 40 ns
    //     TSEG1 = 5 tq,  TSEG2 = 2 tq
    //     bit_time = 8 * 40 = 320 ns
    //     sample_point = (1+5)/8 = 75 %
    env_cfg.c_cfg[0].is_active            = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id              = 0;
    env_cfg.c_cfg[0].bit_time_ns          = 320;
    env_cfg.c_cfg[0].sample_point_pct     = 75;
    env_cfg.c_cfg[0].ack_enable           = 1'b0;  // DUT will ACK, agent observes
    env_cfg.c_cfg[0].expect_no_ack        = 1'b0;
    env_cfg.c_cfg[0].enable_special_decode = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle  = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs   = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_rx_seq rx_seq;

    phase.raise_objection(this);

    rx_seq     = can_dut_rx_seq::type_id::create("rx_seq");
    rx_seq.vif = vif;

    // Stimulus knobs (change here for different test vectors)
    rx_seq.tx_id   = 11'h123;
    rx_seq.tx_dlc  = 4'd8;
    rx_seq.tx_data = '{8'hDE, 8'hAD, 8'hBE, 8'hEF,
                       8'hCA, 8'hFE, 8'h01, 8'h02};

    rx_seq.start(m_env.c_agent[0].seqrh);

    #10us;
    phase.drop_objection(this);
  endtask

endclass
`endif
