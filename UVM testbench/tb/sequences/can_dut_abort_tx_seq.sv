`ifndef CAN_DUT_ABORT_TX_SEQ_SV
`define CAN_DUT_ABORT_TX_SEQ_SV

class can_dut_abort_tx_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_abort_tx_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // Provide node1 sequencer from test
  uvm_sequencer #(can_transaction) node1_sqr;

  // Public results for test verdict
  bit tr_zero_preserved_ok;
  bit at_no_pending_ok;
  bit at_clears_pending_ok;

  // Registers
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;
  localparam byte IR    = 8'h03;
  localparam byte ECC   = 8'h0C;

  localparam byte TX_FI  = 8'h10;
  localparam byte TX_ID1 = 8'h11;
  localparam byte TX_ID2 = 8'h12;
  localparam byte TX_D0  = 8'h13;

  // SR bits
  localparam int SR_TBS = 2;
  localparam int SR_TCS = 3;
  localparam int SR_RS  = 4;
  localparam int SR_TS  = 5;

  function new(string name = "can_dut_abort_tx_seq");
    super.new(name);
  endfunction

  task automatic clear_stale_status();
    byte unsigned dummy;
    vif.reg_read(IR,  dummy);
    vif.reg_read(ECC, dummy);
  endtask

  task automatic force_dut_normal_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);
    mod[0] = 1'b1;
    vif.reg_write(MOD, mod);

    vif.reg_read(MOD, mod);
    mod[1] = 1'b0;
    mod[2] = 1'b0;
    vif.reg_write(MOD, mod);

    mod[0] = 1'b0;
    vif.reg_write(MOD, mod);

    vif.reg_read(MOD, mod);
    `uvm_info("ABORT_TX_SEQ",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic soft_reset_cycle();
    byte unsigned mod;

    vif.tb_tx[1] = 1'b1;

    vif.reg_read(MOD, mod);
    mod[0] = 1'b1;
    vif.reg_write(MOD, mod);
    #2us;

    vif.reg_read(MOD, mod);
    mod[0] = 1'b0;
    vif.reg_write(MOD, mod);
    #2us;

    clear_stale_status();
  endtask

  task automatic load_tx_frame_dlc1(bit [10:0] id11, byte unsigned data0);
    vif.reg_write(TX_FI,  8'h01);
    vif.reg_write(TX_ID1, {id11[10:3]});
    vif.reg_write(TX_ID2, {id11[2:0], 5'b0});
    vif.reg_write(TX_D0,  data0);
  endtask

  // DLC=8 frame for longer transmission window (~41.6us at 320ns/bit)
  // Gives enough time to issue commands mid-frame
  task automatic load_tx_frame_dlc8(bit [10:0] id11);
    vif.reg_write(TX_FI,  8'h08);   // FF=0 RTR=0 DLC=8
    vif.reg_write(TX_ID1, {id11[10:3]});
    vif.reg_write(TX_ID2, {id11[2:0], 5'b0});
    for (int i = 0; i < 8; i++)
      vif.reg_write(TX_D0 + byte'(i), 8'hAA);
  endtask

  task automatic read_sr(output byte unsigned sr);
    vif.reg_read(SR, sr);
  endtask

  task automatic wait_tbs_high(int unsigned timeout_iters = 20000);
    byte unsigned sr;
    int unsigned  t = 0;

    do begin
      read_sr(sr);
      if (sr[SR_TBS]) return;
      #100ns;
      t++;
    end while (t < timeout_iters);

    `uvm_fatal("ABORT_TX_SEQ", "Timeout waiting for SR.TBS=1")
  endtask

  task automatic wait_ts_high_window(
    input  time timeout,
    output bit  saw_ts_high
  );
    byte unsigned sr;
    time start_t;

    saw_ts_high = 1'b0;
    start_t = $time;

    while (($time - start_t) < timeout) begin
      read_sr(sr);
      if (sr[SR_TS]) begin
        saw_ts_high = 1'b1;
        return;
      end
      #100ns;
    end
  endtask

  task automatic confirm_no_ts_high_window(
    input  time timeout,
    output bit  clean_no_tx
  );
    byte unsigned sr;
    time start_t;

    clean_no_tx = 1'b1;
    start_t = $time;

    while (($time - start_t) < timeout) begin
      read_sr(sr);
      if (sr[SR_TS]) begin
        clean_no_tx = 1'b0;
        return;
      end
      #100ns;
    end
  endtask

  task automatic wait_pending_not_tx(
    input  time timeout,
    output bit  seen_pending
  );
    byte unsigned sr;
    time start_t;

    seen_pending = 1'b0;
    start_t = $time;

    while (($time - start_t) < timeout) begin
      read_sr(sr);
      if (!sr[SR_TBS] && !sr[SR_TS]) begin
        seen_pending = 1'b1;
        return;
      end
      #100ns;
    end
  endtask

  task automatic wait_tbs_high_while_receiving(
    input  time timeout,
    output bit  saw_abort_commit
  );
    byte unsigned sr;
    time start_t;

    saw_abort_commit = 1'b0;
    start_t = $time;

    while (($time - start_t) < timeout) begin
      read_sr(sr);
      if (sr[SR_TBS] && sr[SR_RS]) begin
        saw_abort_commit = 1'b1;
        return;
      end
      #100ns;
    end
  endtask

  // Wait for SR.TS=1 (DUT is transmitting) with timeout
  task automatic wait_ts_asserted(
    input  time timeout,
    output bit  saw_transmitting
  );
    byte unsigned sr;
    time start_t;

    saw_transmitting = 1'b0;
    start_t = $time;

    while (($time - start_t) < timeout) begin
      read_sr(sr);
      if (sr[SR_TS]) begin
        saw_transmitting = 1'b1;
        return;
      end
      #100ns;
    end
  endtask

  task body();
    byte unsigned     sr;
    bit               saw_tx;
    bit               no_tx_after_release;
    bit               seen_pending;
    bit               saw_abort_commit;
    bit               saw_transmitting;
    can_node_busy_seq busy_seq;

    if (vif == null)
      `uvm_fatal("ABORT_TX_SEQ", "vif is null -- set from test")

    if (node1_sqr == null)
      `uvm_fatal("ABORT_TX_SEQ", "node1_sqr is null -- set from test")

    tr_zero_preserved_ok = 1'b0;
    at_no_pending_ok     = 1'b0;
    at_clears_pending_ok = 1'b0;

    vif.tb_tx[1] = 1'b1;

    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end
    `uvm_info("ABORT_TX_SEQ", "DUT initialised", UVM_LOW)

    force_dut_normal_mode();
    clear_stale_status();
    wait_tbs_high();

    // -------------------------------------------------------------------------
    // S1: TR pending while bus busy, write CMR=0 — TX must still occur (CMR_002
    //     cover: tx_request && transmitting once TX eventually starts)
    // -------------------------------------------------------------------------
    `uvm_info("ABORT_TX_SEQ",
      "Scenario 1: TR pending while bus busy, then write CMR=0; TX must still occur",
      UVM_LOW)

    vif.tb_tx[1] = 1'b0;
    #5us;

    load_tx_frame_dlc1(11'h101, 8'hA1);
    vif.reg_write(CMR, 8'h01);
    #2us;
    vif.reg_write(CMR, 8'h00);
    #2us;

    vif.tb_tx[1] = 1'b1;

    wait_ts_high_window(80us, saw_tx);
    if (saw_tx) begin
      tr_zero_preserved_ok = 1'b1;
      `uvm_info("ABORT_TX_SEQ",
        "PASS S1: TX started after bus release even though CMR=0 was written",
        UVM_LOW)
    end
    else begin
      `uvm_error("ABORT_TX_SEQ",
        "FAIL S1: TX did not start after TR pending + CMR=0")
    end

    soft_reset_cycle();
    wait_tbs_high();

    // -------------------------------------------------------------------------
    // S2: AT with no pending request — must not create TX activity (CMR_004)
    // -------------------------------------------------------------------------
    `uvm_info("ABORT_TX_SEQ",
      "Scenario 2: AT with no pending request; must not create TX activity",
      UVM_LOW)

    clear_stale_status();
    vif.reg_write(CMR, 8'h02);
    #1us;

    confirm_no_ts_high_window(30us, no_tx_after_release);
    read_sr(sr);

    if (no_tx_after_release && sr[SR_TBS]) begin
      at_no_pending_ok = 1'b1;
      `uvm_info("ABORT_TX_SEQ",
        $sformatf("PASS S2: No TX activity after AT-only with no pending request (SR=0x%02h)", sr),
        UVM_LOW)
    end
    else begin
      `uvm_error("ABORT_TX_SEQ",
        $sformatf("FAIL S2: Unexpected TX activity after AT-only (SR=0x%02h)", sr))
    end

    soft_reset_cycle();
    wait_tbs_high();

    // -------------------------------------------------------------------------
    // S3: valid bus busy from node1, DUT TR then AT while pending (CMR_003/004)
    // -------------------------------------------------------------------------
    `uvm_info("ABORT_TX_SEQ",
      "Scenario 3: valid bus busy from node1, DUT TR then AT while pending",
      UVM_LOW)

    seen_pending      = 1'b0;
    saw_abort_commit  = 1'b0;

    clear_stale_status();
    load_tx_frame_dlc1(11'h102, 8'hB2);

    busy_seq = can_node_busy_seq::type_id::create("busy_seq");

    fork
      begin
        busy_seq.start(node1_sqr);
      end
    join_none

    #20us;

    vif.reg_write(CMR, 8'h01);

    wait_pending_not_tx(20us, seen_pending);
    read_sr(sr);

    if (!seen_pending) begin
      `uvm_error("ABORT_TX_SEQ",
        $sformatf("FAIL S3: never observed pending-not-transmitting (SR=0x%02h)", sr))
    end
    else begin
      `uvm_info("ABORT_TX_SEQ",
        $sformatf("S3 intermediate: pending request observed during valid busy bus (SR=0x%02h)", sr),
        UVM_LOW)

      vif.reg_write(CMR, 8'h02);

      wait_tbs_high_while_receiving(40us, saw_abort_commit);
      read_sr(sr);

      if (saw_abort_commit) begin
        at_clears_pending_ok = 1'b1;
        `uvm_info("ABORT_TX_SEQ",
          $sformatf("PASS S3 cmd-level: AT cleared pending request during valid busy bus (SR=0x%02h)", sr),
          UVM_LOW)
      end
      else begin
        `uvm_error("ABORT_TX_SEQ",
          $sformatf("FAIL S3: TBS did not return high while receiving (SR=0x%02h)", sr))
      end
    end

    soft_reset_cycle();
    wait_tbs_high();

    // -------------------------------------------------------------------------
    // S4a: DUT actively transmitting — write CMR=0 mid-frame
    //      Hits CMR_002: (tx_request && transmitting) |-> ##1 (transmitting || tx_successful)
    //      Uses DLC=8 for ~41.6us frame, issues CMR=0 at 10us (well inside frame)
    //      Node1 ACKs so frame completes successfully
    // -------------------------------------------------------------------------
    `uvm_info("ABORT_TX_SEQ",
      "Scenario 4a: DUT transmitting DLC=8 — write CMR=0 mid-frame (must not cancel)",
      UVM_LOW)

    clear_stale_status();
    load_tx_frame_dlc8(11'h103);
    vif.reg_write(CMR, 8'h01);   // TR — DUT starts transmitting

    // Wait until DUT is actually transmitting (SR.TS=1)
    wait_ts_asserted(50us, saw_transmitting);

    if (!saw_transmitting) begin
      `uvm_error("ABORT_TX_SEQ", "FAIL S4a: DUT did not start transmitting")
    end
    else begin
      // Issue CMR=0 while transmitting — must not cancel
      #2us;
      vif.reg_write(CMR, 8'h00);
      `uvm_info("ABORT_TX_SEQ", "S4a: CMR=0 written mid-transmission", UVM_LOW)
    end

    // Wait for TX to complete
    wait_tbs_high(20000);
    read_sr(sr);
    `uvm_info("ABORT_TX_SEQ",
      $sformatf("S4a done: SR=0x%02h TBS=%0b TCS=%0b",
                sr, sr[SR_TBS], sr[SR_TCS]),
      UVM_LOW)

    soft_reset_cycle();
    wait_tbs_high();

    // -------------------------------------------------------------------------
    // S4b: DUT actively transmitting — issue AT mid-frame
    //      Hits CMR_003: ($rose(abort_tx) && transmitting) |-> ##1 transmitting
    //      abort_tx rises while DUT is in the middle of transmitting
    // -------------------------------------------------------------------------
    `uvm_info("ABORT_TX_SEQ",
      "Scenario 4b: DUT transmitting DLC=8 — issue AT mid-frame (abort_tx rises while transmitting)",
      UVM_LOW)

    clear_stale_status();
    load_tx_frame_dlc8(11'h104);
    vif.reg_write(CMR, 8'h01);   // TR

    // Wait until DUT is actively transmitting
    wait_ts_asserted(50us, saw_transmitting);

    if (!saw_transmitting) begin
      `uvm_error("ABORT_TX_SEQ", "FAIL S4b: DUT did not start transmitting")
    end
    else begin
      // Issue AT while transmitting — abort_tx rises while transmitting=1
      #2us;
      vif.reg_write(CMR, 8'h02);   // AT
      `uvm_info("ABORT_TX_SEQ",
        "S4b: AT issued mid-transmission (abort_tx should rise while transmitting=1)",
        UVM_LOW)
    end

    // Wait for buffer to be released (TBS=1)
    wait_tbs_high(20000);
    read_sr(sr);
    `uvm_info("ABORT_TX_SEQ",
      $sformatf("S4b done: SR=0x%02h TBS=%0b TCS=%0b",
                sr, sr[SR_TBS], sr[SR_TCS]),
      UVM_LOW)

    soft_reset_cycle();
    wait_tbs_high();

    `uvm_info("ABORT_TX_SEQ",
      $sformatf("Summary: S1(TR+0)=%0b S2(AT no pending)=%0b S3(AT clears pending)=%0b",
                tr_zero_preserved_ok, at_no_pending_ok, at_clears_pending_ok),
      UVM_LOW)

    `uvm_info("ABORT_TX_SEQ", "===== ABORT / TX CONTROL SEQUENCE COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif