`ifndef CAN_DUT_RX_SEQ_SV
`define CAN_DUT_RX_SEQ_SV

// =============================================================================
// can_dut_rx_seq (UPDATED for "Normal Mode" baseline)
// =============================================================================
// 1) Runs DUT init seq (reg-driven)
// 2) Forces DUT into Normal Mode: RM=0, LOM=0, STM=0
// 3) Agent sends a clean STD DATA frame (sequence must be started on agent sequencer)
// 4) Confirms ACK seen
// 5) Polls SR.RBS until message available
// 6) Reads RX buffer (FI/ID/DATA) and compares
// 7) Releases RX buffer (CMR.RRB) and optionally confirms RBS clears
// =============================================================================

class can_dut_rx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_rx_seq)

  // -- Set from test ------------------------------------------
  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // -- Test stimulus knobs ------------------------------------
  bit [10:0]     tx_id   = 11'h123;
  bit [3:0]      tx_dlc  = 4'd8;
  byte unsigned  tx_data[8] = '{8'hDE, 8'hAD, 8'hBE, 8'hEF,
                                8'hCA, 8'hFE, 8'h01, 8'h02};

  // -- PeliCAN register addresses ------------------------------
  localparam byte MOD  = 8'h00;
  localparam byte CMR  = 8'h01;
  localparam byte SR   = 8'h02;

  // RX buffer window (PeliCAN) starts at 0x10
  localparam byte RX_FRAME_INFO = 8'h10;
  localparam byte RX_ID1        = 8'h11;
  localparam byte RX_ID2        = 8'h12;
  localparam byte RX_DATA_BASE  = 8'h13; // data starts here for SFF

  function new(string name = "can_dut_rx_seq");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // Force DUT into normal mode: RM=0, LOM=0, STM=0
  // (Same pattern you used in your working normal-mode tests)
  // --------------------------------------------------------------------------
  task automatic force_dut_normal_mode();
    byte unsigned mod;

    // Read current MOD
    vif.reg_read(MOD, mod);

    // Enter reset mode to safely change mode bits
    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    // Clear LOM + STM
    vif.reg_read(MOD, mod);
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b0; // STM=0
    vif.reg_write(MOD, mod);

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    // Readback for debug
    vif.reg_read(MOD, mod);
    `uvm_info("DUT_RX",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic wait_rbs_set(time timeout, output bit seen);
    time t_end = $time + timeout;
    byte unsigned sr;
    seen = 1'b0;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin // RBS
        seen = 1'b1;
        return;
      end
      #200ns;
    end
  endtask

  task automatic wait_rbs_clear(time timeout, output bit seen);
    time t_end = $time + timeout;
    byte unsigned sr;
    seen = 1'b0;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (!sr[0]) begin
        seen = 1'b1;
        return;
      end
      #200ns;
    end
  endtask

  task body();
    can_transaction tx_tr;
    byte unsigned rdata;
    bit rbs_seen, rbs_cleared;

    // -- Phase A: Init DUT --------------------------------------
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);  // reg-driven init
    end

    // Force normal mode explicitly (removes doubt about LOM/RM/STM)
    force_dut_normal_mode();

    `uvm_info("DUT_RX", "DUT initialised — starting RX test (NORMAL mode)", UVM_LOW)

    // -- Phase B: Agent sends a STD DATA frame ------------------
    // NOTE: This sequence must be started on the AGENT sequencer because it uses start_item/finish_item.
    tx_tr = can_transaction::type_id::create("tx_tr");
    start_item(tx_tr);
    assert(tx_tr.randomize() with {
      can_fmt == `CAN_ID_STD;
      id      == tx_id;
      dlc     == tx_dlc;
      f_type  == `CAN_DATA_FRAME;
      data.size() == tx_dlc;

      // constrain the payload bytes (only 0..dlc-1 exist because size==dlc)
      foreach (data[i]) data[i] == tx_data[i];

      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("DUT_RX", "TX randomization failed")
    finish_item(tx_tr);

    `uvm_info("DUT_RX",
      $sformatf("Agent TX done: id=0x%0h dlc=%0d ack_seen=%0b",
                tx_tr.id, tx_tr.dlc, tx_tr.ack_seen),
      UVM_LOW)

    // -- Phase C: Verify ACK was seen (DUT acknowledged) --------
    if (!tx_tr.ack_seen)
      `uvm_error("DUT_RX", "FAIL: DUT did not ACK a valid frame in NORMAL mode (check acceptance/mode/bit-timing)")

    // -- Phase D: Wait for SR.RBS=1 -----------------------------
    wait_rbs_set(200us, rbs_seen);
    if (!rbs_seen) begin
      vif.reg_read(SR, rdata);
      `uvm_fatal("DUT_RX",
        $sformatf("Timeout waiting for RBS=1 (SR=0x%02h)", rdata))
    end

    vif.reg_read(SR, rdata);
    `uvm_info("DUT_RX",
      $sformatf("DUT RX buffer has data (SR=0x%02h, RBS=%0b)", rdata, rdata[0]),
      UVM_LOW)

    // -- Phase E: Read RX buffer and compare --------------------
    begin
      byte unsigned fi, id1, id2;
      bit [10:0]    rx_id;
      bit [3:0]     rx_dlc;
      bit           rx_ff, rx_rtr;
      byte unsigned rx_data_buf[8];
      int unsigned  errors = 0;

      // Frame Information register
      vif.reg_read(RX_FRAME_INFO, fi);
      rx_ff  = fi[7];
      rx_rtr = fi[6];
      rx_dlc = fi[3:0];

      // ID bytes (STD frame)
      vif.reg_read(RX_ID1, id1);
      vif.reg_read(RX_ID2, id2);
      rx_id = {id1, id2[7:5]};

      `uvm_info("DUT_RX",
        $sformatf("RX buffer: FF=%0b RTR=%0b DLC=%0d ID=0x%0h (RX_FI=0x%02h)",
                  rx_ff, rx_rtr, rx_dlc, rx_id, fi),
        UVM_LOW)

      // Check frame format
      if (rx_ff !== 1'b0) begin
        `uvm_error("DUT_RX", $sformatf("FF mismatch: exp=0 (STD) got=%0b", rx_ff))
        errors++;
      end

      if (rx_rtr !== 1'b0) begin
        `uvm_error("DUT_RX", $sformatf("RTR mismatch: exp=0 (DATA) got=%0b", rx_rtr))
        errors++;
      end

      // Check ID
      if (rx_id !== tx_id) begin
        `uvm_error("DUT_RX",
          $sformatf("ID mismatch: exp=0x%0h got=0x%0h", tx_id, rx_id))
        errors++;
      end

      // Check DLC
      if (rx_dlc !== tx_dlc) begin
        `uvm_error("DUT_RX",
          $sformatf("DLC mismatch: exp=%0d got=%0d", tx_dlc, rx_dlc))
        errors++;
      end

      // Read data bytes (up to rx_dlc)
      for (int i = 0; i < int'(rx_dlc) && i < 8; i++) begin
        vif.reg_read(RX_DATA_BASE + byte'(i), rx_data_buf[i]);
      end
      
      // --- Pretty print TX vs RX data (first rx_dlc bytes) ----------
      begin
        string tx_s, rx_s;
        tx_s = "";
        rx_s = "";
      
        for (int i = 0; i < int'(rx_dlc) && i < 8; i++) begin
          tx_s = {tx_s, $sformatf("%02h ", tx_data[i])};
          rx_s = {rx_s, $sformatf("%02h ", rx_data_buf[i])};
        end
      
        `uvm_info("DUT_RX", $sformatf("TX data (%0d): %s", rx_dlc, tx_s), UVM_LOW)
        `uvm_info("DUT_RX", $sformatf("RX data (%0d): %s", rx_dlc, rx_s), UVM_LOW)
      
        if (tx_s == rx_s)
          `uvm_info("DUT_RX", "DATA MATCH: TX payload equals RX buffer payload", UVM_LOW)
        else
          `uvm_warning("DUT_RX", "DATA MISMATCH: TX payload != RX buffer payload (see lines above)")
      end

      // Compare data
      for (int i = 0; i < int'(rx_dlc) && i < 8; i++) begin
        if (rx_data_buf[i] !== tx_data[i]) begin
          `uvm_error("DUT_RX",
            $sformatf("DATA[%0d] mismatch: exp=0x%02h got=0x%02h",
                      i, tx_data[i], rx_data_buf[i]))
          errors++;
        end
      end

      if (errors == 0)
        `uvm_info("DUT_RX", "PASS: DUT RX buffer matches agent TX", UVM_LOW)
      else
        `uvm_error("DUT_RX",
          $sformatf("FAIL: %0d mismatches between agent TX and DUT RX buffer", errors))
    end

    // -- Phase F: Release RX buffer -----------------------------
    // CMR[2] = Release Buffer (RRB) => 0x04
    vif.reg_write(CMR, 8'h04);
    `uvm_info("DUT_RX", "RX buffer release requested (CMR=0x04)", UVM_LOW)

    // Optional: confirm RBS clears
    wait_rbs_clear(50us, rbs_cleared);
    vif.reg_read(SR, rdata);
    `uvm_info("DUT_RX",
      $sformatf("After RRB: SR=0x%02h (RBS=%0b)", rdata, rdata[0]),
      UVM_LOW)

    if (!rbs_cleared)
      `uvm_warning("DUT_RX", "RBS did not clear after RRB (possible new frame arrival or timing)")

    `uvm_info("DUT_RX", "===== DUT RX TEST COMPLETE =====", UVM_LOW)
  endtask

endclass
`endif