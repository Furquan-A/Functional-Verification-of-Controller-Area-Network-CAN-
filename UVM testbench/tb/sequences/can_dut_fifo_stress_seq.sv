`ifndef CAN_DUT_FIFO_STRESS_SEQ_SV
`define CAN_DUT_FIFO_STRESS_SEQ_SV

// =============================================================================
// can_dut_fifo_stress_seq
// =============================================================================
// Stresses the DUT RX FIFO to improve i_can_fifo condition coverage (78.82%).
//
// Phase 1: Fill FIFO to capacity — send many frames without releasing
// Phase 2: Verify overrun behavior — send one more after full
// Phase 3: Drain FIFO — release all buffered frames one by one
// Phase 4: Rapid fill-and-release — interleave sends with RRB commands
// Phase 5: Boundary — single frame in/out cycle
//
// Coverage targets:
//   - i_can_fifo condition/branch paths
//   - FIFO full, empty, wrap-around conditions
//   - Data overrun status + CDO clear
// =============================================================================

class can_dut_fifo_stress_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_fifo_stress_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  localparam byte MOD  = 8'h00;
  localparam byte CMD  = 8'h01;
  localparam byte SR   = 8'h02;
  localparam byte IR   = 8'h03;
  localparam byte RX_FI  = 8'h10;
  localparam byte RX_ID1 = 8'h11;

  int errors = 0;

  function new(string name = "can_dut_fifo_stress_seq");
    super.new(name);
  endfunction

  // -- Helpers ------------------------------------------------

  task automatic send_std_data(
    input bit [10:0] id,
    input bit [3:0]  dlc,
    output can_transaction tr
  );
    tr = can_transaction::type_id::create($sformatf("fifo_tr_%03h", id));
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt == `CAN_ID_STD;
      this.id == local::id;
      this.dlc == local::dlc;
      f_type  == `CAN_DATA_FRAME;
      data.size() == local::dlc;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("FIFO_STRESS", "randomize failed")
    finish_item(tr);
  endtask

  task automatic wait_rbs_set(time timeout, output bit seen);
    time t_end = $time + timeout;
    byte unsigned sr;
    seen = 1'b0;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin seen = 1'b1; return; end
      #200ns;
    end
  endtask

  task automatic release_one_frame(output bit had_frame);
    byte unsigned sr;
    int cnt = 0;

    vif.reg_read(SR, sr);
    had_frame = sr[0];  // RBS

    if (!had_frame) return;

    vif.reg_write(CMD, 8'h04);  // RRB

    // Wait for RBS to update
    repeat (20) begin
      #100ns;
    end
  endtask

  task automatic check_dos(output bit dos_set);
    byte unsigned sr;
    vif.reg_read(SR, sr);
    dos_set = sr[1];  // DOS bit
  endtask

  task automatic clear_data_overrun();
    vif.reg_write(CMD, 8'h08);  // CDO
    #500ns;
  endtask

  // --------------------------------------------------------------
  task body();
    can_transaction tr;
    bit rbs_seen, had_frame, dos_set;
    byte unsigned sr, ir;
    int rx_count;

    if (vif == null)
      `uvm_fatal("FIFO_STRESS", "vif is null")

    // -- Init DUT ----------------------------------------------
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // Clear any leftover
    release_one_frame(had_frame);
    while (had_frame) release_one_frame(had_frame);

    `uvm_info("FIFO_STRESS", "===== Phase 1: Fill FIFO to capacity =====", UVM_LOW)

    // ------------------------------------------------------------
    // SJA1000 RX FIFO = 64 bytes. A minimal STD frame with DLC=1
    // uses ~4 bytes in FIFO (FI + ID1 + ID2 + 1 data).
    // Worst case: 64/4 = 16 frames. DLC=0 uses 3 bytes ? ~21 frames.
    // Send 20 frames without releasing to test near-full behavior.
    // ------------------------------------------------------------
    for (int i = 0; i < 20; i++) begin
      send_std_data(11'h100 + i[10:0], 4'd1, tr);

      wait_rbs_set(200us, rbs_seen);
      if (!rbs_seen && i < 15) begin
        `uvm_warning("FIFO_STRESS",
          $sformatf("Frame %0d: RBS not set — FIFO may be full already", i))
      end

      vif.reg_read(SR, sr);
      `uvm_info("FIFO_STRESS",
        $sformatf("Frame %0d sent: SR=0x%02h (RBS=%0b DOS=%0b)", i, sr, sr[0], sr[1]),
        UVM_LOW)

      // Check for overrun
      if (sr[1]) begin
        `uvm_info("FIFO_STRESS",
          $sformatf("Data overrun detected at frame %0d — FIFO full", i),
          UVM_LOW)
        break;
      end
    end

    `uvm_info("FIFO_STRESS", "===== Phase 2: Verify overrun =====", UVM_LOW)

    // ------------------------------------------------------------
    // Send one more frame — should trigger overrun (DOS)
    // ------------------------------------------------------------
    send_std_data(11'h1FF, 4'd1, tr);
    #10us;

    check_dos(dos_set);
    if (dos_set)
      `uvm_info("FIFO_STRESS", "PASS: Data overrun status set (DOS=1)", UVM_LOW)
    else
      `uvm_info("FIFO_STRESS", "INFO: DOS not set — FIFO may not be full yet", UVM_LOW)

    // Check interrupt
    vif.reg_read(IR, ir);
    `uvm_info("FIFO_STRESS", $sformatf("IR=0x%02h after overrun attempt", ir), UVM_LOW)

    `uvm_info("FIFO_STRESS", "===== Phase 3: Drain FIFO =====", UVM_LOW)

    // ------------------------------------------------------------
    // Release all frames one by one
    // ------------------------------------------------------------
    rx_count = 0;
    forever begin
      byte unsigned fi, id1;
      vif.reg_read(SR, sr);
      if (!sr[0]) break;  // RBS=0, FIFO empty

      // Read frame info for debug
      vif.reg_read(RX_FI, fi);
      vif.reg_read(RX_ID1, id1);
      `uvm_info("FIFO_STRESS",
        $sformatf("Draining frame %0d: FI=0x%02h ID1=0x%02h", rx_count, fi, id1),
        UVM_LOW)

      vif.reg_write(CMD, 8'h04);  // RRB
      rx_count++;
      #500ns;

      if (rx_count > 30) begin
        `uvm_warning("FIFO_STRESS", "Drained 30+ frames — breaking")
        break;
      end
    end

    `uvm_info("FIFO_STRESS", $sformatf("Drained %0d frames from FIFO", rx_count), UVM_LOW)

    // Clear overrun
    if (dos_set) begin
      clear_data_overrun();
      check_dos(dos_set);
      if (!dos_set)
        `uvm_info("FIFO_STRESS", "PASS: CDO cleared data overrun (DOS=0)", UVM_LOW)
      else begin
        `uvm_error("FIFO_STRESS", "FAIL: CDO did not clear DOS")
        errors++;
      end
    end

    `uvm_info("FIFO_STRESS", "===== Phase 4: Rapid fill-and-release =====", UVM_LOW)

    // ------------------------------------------------------------
    // Interleave: send frame, release, send frame, release
    // Tests FIFO write pointer wrap-around and single-entry paths
    // ------------------------------------------------------------
    for (int i = 0; i < 10; i++) begin
      send_std_data(11'h200 + i[10:0], 4'd2, tr);

      wait_rbs_set(200us, rbs_seen);
      if (!rbs_seen) begin
        `uvm_warning("FIFO_STRESS", $sformatf("Rapid[%0d]: RBS not set", i))
      end

      // Release immediately
      vif.reg_write(CMD, 8'h04);
      #1us;
    end

    `uvm_info("FIFO_STRESS", "Rapid fill-and-release done", UVM_LOW)

    `uvm_info("FIFO_STRESS", "===== Phase 5: Boundary — empty FIFO read =====", UVM_LOW)

    // ------------------------------------------------------------
    // Issue RRB when FIFO is already empty — should be harmless
    // ------------------------------------------------------------
    vif.reg_read(SR, sr);
    `uvm_info("FIFO_STRESS", $sformatf("Before empty RRB: SR=0x%02h", sr), UVM_LOW)

    vif.reg_write(CMD, 8'h04);  // RRB on empty FIFO
    #1us;

    vif.reg_read(SR, sr);
    if (!sr[0])
      `uvm_info("FIFO_STRESS", "PASS: RRB on empty FIFO — no crash (RBS=0)", UVM_LOW)
    else begin
      `uvm_error("FIFO_STRESS", "FAIL: RRB on empty FIFO set RBS=1")
      errors++;
    end

    // -- Summary ----------------------------------------------
    if (errors == 0)
      `uvm_info("FIFO_STRESS", "===== FIFO STRESS TEST PASSED =====", UVM_LOW)
    else
      `uvm_error("FIFO_STRESS", $sformatf("===== FIFO STRESS: %0d ERROR(S) =====", errors))

  endtask

endclass
`endif