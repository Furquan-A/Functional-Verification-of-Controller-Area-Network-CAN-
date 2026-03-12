`ifndef CAN_DUT_ACK_ERR_TEST_SV
`define CAN_DUT_ACK_ERR_TEST_SV

// =============================================================================
// can_dut_ack_err_test
// =============================================================================
// DUT transmits a VALID frame via register writes (sequence does it).
// Agent node 0 monitors the bus but does NOT ACK the frame (ack_enable=0).
// The test captures the observed transaction from the monitor FIFO and checks:
//   - Observed ID/DLC/DATA match expected
//   - ack_seen == 0 (no ACK)
//   - no CRC error reported by monitor
// =============================================================================

class can_dut_ack_err_test extends uvm_test;
  `uvm_component_utils(can_dut_ack_err_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  // TLM FIFO to capture monitor observations
  uvm_tlm_analysis_fifo #(can_transaction) mon_fifo;

  // Expected values (MUST match what can_dut_ack_err_seq loads)
  bit [10:0]    exp_id   = 11'h123;
  bit [3:0]     exp_dlc  = 4'd4;
  byte unsigned exp_data[8] = '{8'hAA, 8'hBB, 8'hCC, 8'hDD,
                                 8'h00, 8'h00, 8'h00, 8'h00};

  function new(string name="can_dut_ack_err_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("ACK_ERR_TEST", "cannot get vif")

    mon_fifo = new("mon_fifo", this);

    // -- Environment config -----------------------------------
    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 1 active agent — monitors but does NOT ACK
    env_cfg.resize(1, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // -- Agent 0 config — match DUT bit timing ----------------
    //   BTR0=0x00, BTR1=0x14 @ 50 MHz ? bit_time = 320 ns, SP = 75 %
    env_cfg.c_cfg[0].is_active              = UVM_ACTIVE;
    env_cfg.c_cfg[0].node_id                = 0;
    env_cfg.c_cfg[0].bit_time_ns            = 320;
    env_cfg.c_cfg[0].sample_point_pct       = 75;

    // CRITICAL: disable ACK to force ACK error at DUT transmitter
    env_cfg.c_cfg[0].ack_enable             = 1'b0;
    env_cfg.c_cfg[0].expect_no_ack          = 1'b1;

    // keep consistent with your existing TX test
    env_cfg.c_cfg[0].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  // Connect monitor AP ? local FIFO for verification
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m_env.c_agent[0].monh.ap.connect(mon_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_ack_err_seq seq;
    can_transaction     obs_tr;

    phase.raise_objection(this);

    // -- Run the ACK error sequence (DUT TX via registers) -----
    seq     = can_dut_ack_err_seq::type_id::create("seq");
    seq.vif = vif;

    // If you later add knobs to the sequence (tx_id/tx_dlc/tx_data),
    // set them here and keep exp_* aligned.
    seq.start(null);

    // Allow monitor to finish capturing frame + error handling + IFS
    #20us;

    if (mon_fifo.used() == 0) begin
      `uvm_error("ACK_ERR_TEST",
        "Monitor did not observe any frame — either DUT did not TX, or monitor does not publish frames that end with error handling")
      // Still drop objection; sequence already printed SR/IR/TEC info.
    end
    else begin
      int unsigned errors = 0;

      // If retransmissions ever occur (should not with single-shot),
      // take the first observed frame and warn if there are more.
      if (mon_fifo.used() > 1)
        `uvm_warning("ACK_ERR_TEST", $sformatf("Monitor captured %0d frames; taking the first", mon_fifo.used()))

      void'(mon_fifo.try_get(obs_tr));

      `uvm_info("ACK_ERR_TEST",
        $sformatf("Monitor observed: %s", obs_tr.convert2string()),
        UVM_LOW)

      // -- Compare ID ------------------------------------------
      if (obs_tr.id[10:0] !== exp_id) begin
        `uvm_error("ACK_ERR_TEST",
          $sformatf("ID mismatch: exp=0x%0h  obs=0x%0h", exp_id, obs_tr.id[10:0]))
        errors++;
      end

      // -- Compare DLC -----------------------------------------
      if (obs_tr.dlc !== exp_dlc) begin
        `uvm_error("ACK_ERR_TEST",
          $sformatf("DLC mismatch: exp=%0d  obs=%0d", exp_dlc, obs_tr.dlc))
        errors++;
      end

      // -- Compare format/type ---------------------------------
      if (obs_tr.can_fmt !== `CAN_ID_STD) begin
        `uvm_error("ACK_ERR_TEST",
          $sformatf("Format mismatch: exp=STD  obs=%0b", obs_tr.can_fmt))
        errors++;
      end

      if (obs_tr.f_type !== `CAN_DATA_FRAME) begin
        `uvm_error("ACK_ERR_TEST",
          $sformatf("Frame type mismatch: exp=DATA  obs=%s", obs_tr.ftype_str()))
        errors++;
      end

      // -- Compare data bytes ----------------------------------
      for (int i = 0; i < exp_dlc && i < 8; i++) begin
        if (i < obs_tr.data.size()) begin
          if (obs_tr.data[i] !== exp_data[i]) begin
            `uvm_error("ACK_ERR_TEST",
              $sformatf("DATA[%0d] mismatch: exp=0x%02h  obs=0x%02h",
                        i, exp_data[i], obs_tr.data[i]))
            errors++;
          end
        end else begin
          `uvm_error("ACK_ERR_TEST",
            $sformatf("DATA[%0d] missing in observed transaction", i))
          errors++;
        end
      end

      // -- ACK must NOT be seen --------------------------------
      if (obs_tr.ack_seen) begin
        `uvm_error("ACK_ERR_TEST",
          "ACK was observed on the bus but ack_enable=0. Another node may be ACKing or config didn’t apply.")
        errors++;
      end else begin
        `uvm_info("ACK_ERR_TEST", "PASS: No ACK observed (expected for ACK error)", UVM_LOW)
      end

      // -- CRC should be OK (this is ACK-only scenario) ---------
      if (obs_tr.crc_error_seen) begin
        `uvm_error("ACK_ERR_TEST", "CRC error detected — expected valid frame with only missing ACK")
        errors++;
      end

      // -- Verdict ---------------------------------------------
      if (errors == 0)
        `uvm_info("ACK_ERR_TEST",
          "PASS: Observed frame matches DUT TX buffer contents and no ACK was seen (ACK error scenario)",
          UVM_LOW)
      else
        `uvm_error("ACK_ERR_TEST",
          $sformatf("FAIL: %0d mismatches/violations in ACK error test", errors))
    end

    #10us;
    phase.drop_objection(this);
  endtask

endclass
`endif