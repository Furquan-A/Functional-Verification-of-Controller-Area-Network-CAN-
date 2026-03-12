`ifndef CAN_DUT_TX_SEQ_SV
`define CAN_DUT_TX_SEQ_SV

// =============================================================================
// can_dut_tx_seq
// =============================================================================
// 1. Runs DUT init sequence (via vif)
// 2. Writes a STD DATA frame into the DUT TX buffer registers
// 3. Issues TX command (CMD[0])
// 4. Polls SR until transmission is complete (TCS=1)
// 5. Reports result — monitor captures the frame separately
// =============================================================================

class can_dut_tx_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_tx_seq)

  // -- Set from test ------------------------------------------
  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // -- Test stimulus knobs ------------------------------------
  bit [10:0]     tx_id   = 11'h456;
  bit [3:0]      tx_dlc  = 4'd8;
  byte unsigned  tx_data[8] = '{8'hAA, 8'hBB, 8'hCC, 8'hDD,
                                 8'hEE, 8'hFF, 8'h11, 8'h22};

  // -- Register addresses (PeliCAN extended mode) -------------
  localparam byte SR   = 8'h02;
  localparam byte CMD  = 8'h01;
  // TX buffer (PeliCAN extended mode — same addresses as RX, write path)
  localparam byte TX_FRAME_INFO = 8'h10;
  localparam byte TX_ID1        = 8'h11;
  localparam byte TX_ID2        = 8'h12;
  // STD frame: data starts at addr 19 (0x13)
  localparam byte TX_DATA_BASE  = 8'h13;

  function new(string name = "can_dut_tx_seq");
    super.new(name);
  endfunction

  task body();
    byte unsigned rdata;
    byte unsigned fi_val, id1_val, id2_val;
    int unsigned poll_cnt;

    if (vif == null)
      `uvm_fatal("DUT_TX", "vif is null — set from test")

    // -- Phase A: Init DUT --------------------------------------
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    `uvm_info("DUT_TX", "DUT initialised — starting TX test", UVM_LOW)

    // -- Phase B: Verify TX buffer is free ----------------------
    vif.wb_read(SR, rdata);
    if (rdata[2] !== 1'b1) begin
      `uvm_fatal("DUT_TX",
        $sformatf("TX buffer not free before write (SR=0x%0h)", rdata))
    end

    // -- Phase C: Write frame into DUT TX buffer ----------------
    //
    //  PeliCAN STD frame TX buffer layout:
    //    Addr 0x10: Frame Info  [7]=FF=0(STD) [6]=RTR=0(DATA) [3:0]=DLC
    //    Addr 0x11: ID byte 1   = ID[10:3]
    //    Addr 0x12: ID byte 2   = {ID[2:0], 5'b00000}
    //    Addr 0x13..0x1A: Data bytes 0..7
    //
    fi_val  = {1'b0, 1'b0, 2'b00, tx_dlc};          // FF=0 RTR=0 DLC
    id1_val = tx_id[10:3];                            // ID[10:3]
    id2_val = {tx_id[2:0], 5'b00000};                // ID[2:0] + padding

    vif.wb_write(TX_FRAME_INFO, fi_val);
    vif.wb_write(TX_ID1,        id1_val);
    vif.wb_write(TX_ID2,        id2_val);

    for (int i = 0; i < tx_dlc && i < 8; i++) begin
      vif.wb_write(TX_DATA_BASE + i, tx_data[i]);
    end

    `uvm_info("DUT_TX",
      $sformatf("TX buffer loaded: id=0x%0h dlc=%0d FI=0x%02h ID1=0x%02h ID2=0x%02h",
                tx_id, tx_dlc, fi_val, id1_val, id2_val),
      UVM_LOW)
    begin
      string d_s;
      d_s = "";
      for (int i = 0; i < tx_dlc; i++)
        d_s = {d_s, $sformatf("%02h ", tx_data[i])};
      `uvm_info("DUT_TX", $sformatf("TX data: %s", d_s), UVM_LOW)
    end

    // -- Phase D: Issue TX Request ------------------------------
    //   CMD[0] = 1 ? Transmit Request (self-clearing)
    vif.wb_write(CMD, 8'h01);
    `uvm_info("DUT_TX", "TX request issued (CMD=0x01)", UVM_LOW)

    // -- Phase E: Poll SR until transmission completes ----------
    //   SR[3] = TCS (Transmission Complete Status) = 1 when done
    //   SR[2] = TBS (TX Buffer Status) = 1 when buffer released
    poll_cnt = 0;
    forever begin
      vif.wb_read(SR, rdata);
      if (rdata[3] == 1'b1 && rdata[2] == 1'b1) break;  // TCS=1 + TBS=1
      poll_cnt++;
      if (poll_cnt > 5000) begin
        `uvm_fatal("DUT_TX",
          $sformatf("Timeout waiting for TX complete (SR=0x%0h after %0d polls)", rdata, poll_cnt))
      end
      #100ns;
    end

    `uvm_info("DUT_TX",
      $sformatf("TX complete (SR=0x%0h after %0d polls)", rdata, poll_cnt),
      UVM_LOW)

    `uvm_info("DUT_TX", "===== DUT TX TEST COMPLETE =====", UVM_LOW)
  endtask

endclass
`endif
