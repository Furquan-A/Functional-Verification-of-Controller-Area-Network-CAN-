`ifndef CAN_DUT_ACK_ERR_SEQ_SV
`define CAN_DUT_ACK_ERR_SEQ_SV

class can_dut_ack_err_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_ack_err_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // -- PeliCAN register addresses -----------------------------
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;
  localparam byte IR    = 8'h03;
  localparam byte RXERR = 8'h0E; // REC
  localparam byte TXERR = 8'h0F; // TEC

  // TX buffer window (PeliCAN) - Standard Frame Format (11-bit ID)
  localparam byte TX_FI  = 8'h10;
  localparam byte TX_ID1 = 8'h11;
  localparam byte TX_ID2 = 8'h12;
  localparam byte TX_D0  = 8'h13;

  // If 1, we force MOD.STM=0 to ensure ACK is required for TX success.
  localparam bit FORCE_DISABLE_SELF_TEST = 1'b1;

  function new(string name="can_dut_ack_err_seq");
    super.new(name);
  endfunction

  // -- HELPER: sample REC/TEC repeatedly and record peak -------
  task automatic sample_counters_peak(
    input  string tag,
    input  int unsigned nsamples,
    input  time gap,
    output byte unsigned rec_peak,
    output byte unsigned tec_peak
  );
    byte unsigned rec, tec;
    rec_peak = 0;
    tec_peak = 0;

    repeat (nsamples) begin
      vif.reg_read(RXERR, rec);
      vif.reg_read(TXERR, tec);
      if (rec > rec_peak) rec_peak = rec;
      if (tec > tec_peak) tec_peak = tec;
      #(gap);
    end

    `uvm_info("ACK_ERR",
      $sformatf("%s: PEAK REC=%0d PEAK TEC=%0d over %0d samples",
                tag, rec_peak, tec_peak, nsamples),
      UVM_LOW)
  endtask

  // Wait for SR.TBS=1 (TX buffer status: 1 = released/available)
  task automatic wait_tbs_released(int unsigned timeout_iters = 5000);
    byte unsigned sr;
    int unsigned t = 0;
    do begin
      vif.reg_read(SR, sr);
      if (sr[2]) return;      // SR[2] = TBS
      #100ns;
      t++;
    end while (t < timeout_iters);

    `uvm_fatal("ACK_ERR", "Timeout waiting for SR.TBS=1 (TX buffer released)")
  endtask

  // Load a Standard (11-bit) DATA frame into TX buffer
  task automatic load_tx_sff_data(
    input  bit [10:0] id11,
    input  int unsigned dlc,
    input  byte unsigned data_bytes[0:7]
  );
    byte unsigned fi, id1, id2;

    if (dlc > 8) dlc = 8;

    // FI: FF=0 (SFF), RTR=0 (data), DLC in [3:0]
    fi  = byte'(dlc[3:0]);

    // SFF ID packing:
    // ID1 = id[10:3]
    // ID2[7:5] = id[2:0]
    id1 = {id11[10:3]};
    id2 = {id11[2:0], 5'b0};

    vif.reg_write(TX_FI,  fi);
    vif.reg_write(TX_ID1, id1);
    vif.reg_write(TX_ID2, id2);

    for (int i = 0; i < dlc; i++) begin
      vif.reg_write(TX_D0 + byte'(i), data_bytes[i]);
    end
  endtask

  // Quick “did DUT try to transmit?” check: SOF must drive dominant at least once.
  task automatic expect_tx_activity(time timeout = 20us);
    time t_end = $time + timeout;

    while (($time < t_end) && (vif.tx_o !== 1'b0)) begin
      @(posedge vif.clk_i);
    end

    if (vif.tx_o !== 1'b0) begin
      `uvm_warning("ACK_ERR",
        "No dominant observed on tx_o within timeout — DUT may not have attempted TX (or tx_o not connected as expected).")
    end else begin
      `uvm_info("ACK_ERR", "Observed dominant on tx_o — DUT attempted transmission", UVM_LOW)
    end
  endtask

  task body();
    byte unsigned mod, sr, ir, dummy;
    byte unsigned tec_before, tec_after;
    byte unsigned rec_before, rec_after;

    // NEW: peak capture vars (were missing)
    byte unsigned rec_peak, tec_peak;

    byte unsigned data8[0:7];

    // 1) Init DUT (PeliCAN, bitrate, etc.)
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    `uvm_info("ACK_ERR", "DUT initialised — starting ACK error test (DUT as transmitter)", UVM_LOW)

    // 2) Ensure self-test is off (ACK matters only if not in self-test)
    vif.reg_read(MOD, mod);
    if (mod[2]) begin // MOD[2] = STM (Self Test Mode) in PeliCAN
      if (FORCE_DISABLE_SELF_TEST) begin
        byte unsigned new_mod = mod;
        new_mod[2] = 1'b0;
        vif.reg_write(MOD, new_mod);
        `uvm_warning("ACK_ERR",
          $sformatf("MOD.STM was 1; cleared it (MOD 0x%02h -> 0x%02h) to make ACK required.", mod, new_mod))
        mod = new_mod;
      end else begin
        `uvm_warning("ACK_ERR",
          $sformatf("MOD.STM=1 (self-test) is set; ACK may not be required. MOD=0x%02h", mod))
      end
    end

    // 3) Clear any pending interrupts (IR is read-to-clear)
    vif.reg_read(IR, dummy);

    // 4) Snapshot counters before TX attempt
    vif.reg_read(TXERR, tec_before);
    vif.reg_read(RXERR, rec_before);
    `uvm_info("ACK_ERR",
      $sformatf("INFO: before TX attempt: TEC=%0d REC=%0d", tec_before, rec_before),
      UVM_LOW)

    // 5) Wait TX buffer available
    wait_tbs_released();

    // 6) Build a valid frame in TX buffer
    data8[0]=8'hAA; data8[1]=8'hBB; data8[2]=8'hCC; data8[3]=8'hDD;
    for (int i=4;i<8;i++) data8[i]=8'h00;
    load_tx_sff_data(11'h123, 4, data8);

    // 7) Request transmission (single-shot avoids endless retries with no ACK)
    // TR + AT simultaneously => single-shot
    vif.reg_write(CMR, 8'h03);

    // Optional: confirm DUT attempted TX (tx_o should go dominant at SOF)
    expect_tx_activity(20us);

    // 8) Wait TX attempt over (buffer released again)
    wait_tbs_released();

    // NEW: sample counters immediately after TX completes to catch brief TEC changes
    sample_counters_peak("after TX attempt", 20, 200ns, rec_peak, tec_peak);

    // 9) Read SR/IR after attempt (IR read clears)
    vif.reg_read(SR, sr);
    vif.reg_read(IR, ir);

    `uvm_info("ACK_ERR",
      $sformatf("Post-TX: SR=0x%02h (TBS=%0b TCS=%0b) IR=0x%02h (TI=%0b BEI=%0b)",
                sr, sr[2], sr[3], ir, ir[1], ir[7]),
      UVM_LOW)

    // 10) Tighten TCS check: with ACK disabled and not in self-test, TX should not be successful
    if (!mod[2] && sr[3]) begin
      `uvm_error("ACK_ERR", "DUT reports TX success (SR.TCS=1) despite ACK disabled — should not happen")
    end

    // 11) Snapshot counters again (log delta)
    vif.reg_read(TXERR, tec_after);
    vif.reg_read(RXERR, rec_after);
    `uvm_info("ACK_ERR",
      $sformatf("INFO: after TX attempt: TEC=%0d (delta=%0d)  REC=%0d (delta=%0d) | PEAK TEC=%0d PEAK REC=%0d",
                tec_after, tec_after - tec_before,
                rec_after, rec_after - rec_before,
                tec_peak, rec_peak),
      UVM_LOW)

    `uvm_info("ACK_ERR", "===== ACK ERROR TEST COMPLETE =====", UVM_LOW)
  endtask

endclass
`endif