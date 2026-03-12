`ifndef CAN_DUT_TX_TEST_SV
`define CAN_DUT_TX_TEST_SV

// =============================================================================
// can_dut_tx_test
// =============================================================================
// Writes a frame into the DUT TX buffer, triggers transmission.
// Agent node 0 monitors the bus and ACKs the frame.
// After TX completes, the test grabs the observed transaction from the
// monitor's analysis port and compares against what was written.
// =============================================================================

class can_dut_tx_test extends uvm_test;
  `uvm_component_utils(can_dut_tx_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  // TLM FIFO to capture monitor observations
  uvm_tlm_analysis_fifo #(can_transaction) mon_fifo;

  // Expected values (must match sequence knobs)
  bit [10:0]    exp_id   = 11'h456;
  bit [3:0]     exp_dlc  = 4'd8;
  byte unsigned exp_data[8] = '{8'hAA, 8'hBB, 8'hCC, 8'hDD,
                                 8'hEE, 8'hFF, 8'h11, 8'h22};

  function new(string name="can_dut_tx_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("DUT_TX_TEST", "cannot get vif")

    mon_fifo = new("mon_fifo", this);

    // ── Environment config ───────────────────────────────────
    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 1 active agent — it monitors and ACKs the DUT's frame
    env_cfg.resize(1, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // ── Agent 0 config — match DUT bit timing ────────────────
    //   BTR0=0x00, BTR1=0x14 @ 50 MHz → bit_time = 320 ns, SP = 75 %
    env_cfg.c_cfg[0].is_active            = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id              = 0;
    env_cfg.c_cfg[0].bit_time_ns          = 320;
    env_cfg.c_cfg[0].sample_point_pct     = 75;
    env_cfg.c_cfg[0].ack_enable           = 1'b1;  // CRITICAL — ACK the DUT's frame
    env_cfg.c_cfg[0].expect_no_ack        = 1'b0;
    env_cfg.c_cfg[0].enable_special_decode = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle  = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs   = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  // Connect monitor AP → local FIFO for verification
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m_env.c_agent[0].monh.ap.connect(mon_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_tx_seq tx_seq;
    can_transaction obs_tr;

    phase.raise_objection(this);

    // ── Run the TX sequence ──────────────────────────────────
    tx_seq     = can_dut_tx_seq::type_id::create("tx_seq");
    tx_seq.vif = vif;

    // Set stimulus (must match exp_ values above)
    tx_seq.tx_id   = exp_id;
    tx_seq.tx_dlc  = exp_dlc;
    tx_seq.tx_data = exp_data;

    tx_seq.start(null);  // runs via vif, no sequencer needed

    // ── Grab observed transaction from monitor ───────────────
    // Allow some time for monitor to finish EOF + IFS
    #5us;

    if (mon_fifo.used() == 0) begin
      `uvm_error("DUT_TX_TEST",
        "Monitor did not observe any frame — DUT TX may have failed")
    end
    else begin
      int unsigned errors = 0;

      void'(mon_fifo.try_get(obs_tr));

      `uvm_info("DUT_TX_TEST",
        $sformatf("Monitor observed: %s", obs_tr.convert2string()),
        UVM_LOW)

      // ── Compare ID ──────────────────────────────────────────
      if (obs_tr.id[10:0] !== exp_id) begin
        `uvm_error("DUT_TX_TEST",
          $sformatf("ID mismatch: exp=0x%0h  obs=0x%0h", exp_id, obs_tr.id[10:0]))
        errors++;
      end

      // ── Compare DLC ─────────────────────────────────────────
      if (obs_tr.dlc !== exp_dlc) begin
        `uvm_error("DUT_TX_TEST",
          $sformatf("DLC mismatch: exp=%0d  obs=%0d", exp_dlc, obs_tr.dlc))
        errors++;
      end

      // ── Compare format ──────────────────────────────────────
      if (obs_tr.can_fmt !== `CAN_ID_STD) begin
        `uvm_error("DUT_TX_TEST",
          $sformatf("Format mismatch: exp=STD  obs=%0b", obs_tr.can_fmt))
        errors++;
      end

      if (obs_tr.f_type !== `CAN_DATA_FRAME) begin
        `uvm_error("DUT_TX_TEST",
          $sformatf("Frame type mismatch: exp=DATA  obs=%s", obs_tr.ftype_str()))
        errors++;
      end

      // ── Compare data bytes ──────────────────────────────────
      for (int i = 0; i < exp_dlc && i < 8; i++) begin
        if (i < obs_tr.data.size()) begin
          if (obs_tr.data[i] !== exp_data[i]) begin
            `uvm_error("DUT_TX_TEST",
              $sformatf("DATA[%0d] mismatch: exp=0x%02h  obs=0x%02h",
                        i, exp_data[i], obs_tr.data[i]))
            errors++;
          end
        end else begin
          `uvm_error("DUT_TX_TEST",
            $sformatf("DATA[%0d] missing in observed transaction", i))
          errors++;
        end
      end

      // ── ACK check ───────────────────────────────────────────
      if (!obs_tr.ack_seen)
        `uvm_warning("DUT_TX_TEST", "Monitor did not see ACK on bus")

      // ── CRC check ───────────────────────────────────────────
      if (obs_tr.crc_error_seen)
        `uvm_error("DUT_TX_TEST", "CRC error detected on DUT TX frame")

      // ── Verdict ─────────────────────────────────────────────
      if (errors == 0)
        `uvm_info("DUT_TX_TEST",
          "PASS: Monitor observed frame matches DUT TX buffer contents",
          UVM_LOW)
      else
        `uvm_error("DUT_TX_TEST",
          $sformatf("FAIL: %0d mismatches between DUT TX and monitor observation", errors))
    end

    #10us;
    phase.drop_objection(this);
  endtask

endclass
`endif
