`ifndef CAN_DUT_TX_FULL_PAYLOAD_SEQ_SV
`define CAN_DUT_TX_FULL_PAYLOAD_SEQ_SV

// =============================================================================
// can_dut_tx_full_payload_seq
// =============================================================================
// Sends multiple frames through the DUT TX path with varied payloads to
// exercise ALL 13 TX buffer IBO instances (i_ibo_tx_data_0 .. _12).
//
// Coverage targets:
//   - i_ibo_tx_data_0  (Frame Info byte)
//   - i_ibo_tx_data_1  (ID byte 1)
//   - i_ibo_tx_data_2  (ID byte 2 / EXT ID byte 2)
//   - i_ibo_tx_data_3  (EXT ID byte 3 / STD data[0])
//   - i_ibo_tx_data_4  (EXT ID byte 4 / STD data[1])
//   - i_ibo_tx_data_5..12 (data bytes)
//
// Strategy:
//   Round 1: STD DATA  DLC=8  data=0xFF toggle pattern
//   Round 2: STD DATA  DLC=8  data=0xAA/0x55 alternating
//   Round 3: STD DATA  DLC=8  data=0x00 (all zeros)
//   Round 4: EXT DATA  DLC=8  data=0xFF (exercises EXT ID IBO slots)
//   Round 5: EXT DATA  DLC=8  data=0xAA/0x55 alternating
//   Round 6: STD REMOTE DLC=8 (no data, but DLC field toggles IBO)
//   Round 7: EXT REMOTE DLC=4 (varied DLC)
//   Round 8: STD DATA  DLC=1  data=0x5A (short frame, boundary)
// =============================================================================

class can_dut_tx_full_payload_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_tx_full_payload_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN register addresses
  localparam byte MOD  = 8'h00;
  localparam byte CMD  = 8'h01;
  localparam byte SR   = 8'h02;
  localparam byte TX_FI = 8'h10;
  // STD: ID1=0x11, ID2=0x12, DATA_BASE=0x13
  // EXT: ID1=0x11, ID2=0x12, ID3=0x13, ID4=0x14, DATA_BASE=0x15

  function new(string name = "can_dut_tx_full_payload_seq");
    super.new(name);
  endfunction

  // -- Helper: wait for TX complete (TCS=1 + TBS=1) ----------
  task automatic wait_tx_complete(output bit success);
    byte unsigned sr;
    int unsigned poll_cnt = 0;
    success = 1'b0;
    forever begin
      vif.reg_read(SR, sr);
      if (sr[3] && sr[2]) begin success = 1'b1; return; end
      poll_cnt++;
      if (poll_cnt > 10000) begin
        `uvm_error("TX_FULL", $sformatf("TX timeout SR=0x%02h after %0d polls", sr, poll_cnt))
        return;
      end
      #100ns;
    end
  endtask

  // -- Helper: verify TBS=1 before writing --------------------
  task automatic wait_tbs_free();
    byte unsigned sr;
    int unsigned poll_cnt = 0;
    forever begin
      vif.reg_read(SR, sr);
      if (sr[2]) return;
      poll_cnt++;
      if (poll_cnt > 5000)
        `uvm_fatal("TX_FULL", "TX buffer never became free")
      #100ns;
    end
  endtask

  // -- Send STD DATA frame via DUT TX buffer ------------------
  task automatic send_std_data(
    input bit [10:0]    id,
    input bit [3:0]     dlc,
    input byte unsigned data[8],
    input string        tag
  );
    byte unsigned fi, id1, id2;
    bit success;

    wait_tbs_free();

    // Frame Info: FF=0(STD) RTR=0(DATA) r1r0=00 DLC
    fi  = {1'b0, 1'b0, 2'b00, dlc};
    id1 = id[10:3];
    id2 = {id[2:0], 5'b00000};

    vif.reg_write(TX_FI,        fi);
    vif.reg_write(TX_FI + 8'd1, id1);
    vif.reg_write(TX_FI + 8'd2, id2);

    for (int i = 0; i < dlc && i < 8; i++)
      vif.reg_write(TX_FI + 8'd3 + i[7:0], data[i]);

    `uvm_info("TX_FULL", $sformatf("[%s] STD DATA id=0x%03h dlc=%0d FI=0x%02h", tag, id, dlc, fi), UVM_LOW)

    // Issue TX request
    vif.reg_write(CMD, 8'h01);
    wait_tx_complete(success);

    if (success)
      `uvm_info("TX_FULL", $sformatf("[%s] TX complete", tag), UVM_LOW)
    else
      `uvm_error("TX_FULL", $sformatf("[%s] TX failed", tag))
  endtask

  // -- Send EXT DATA frame via DUT TX buffer ------------------
  task automatic send_ext_data(
    input bit [28:0]    id,
    input bit [3:0]     dlc,
    input byte unsigned data[8],
    input string        tag
  );
    byte unsigned fi, id1, id2, id3, id4;
    bit success;

    wait_tbs_free();

    // Frame Info: FF=1(EXT) RTR=0(DATA) r1r0=00 DLC
    fi  = {1'b1, 1'b0, 2'b00, dlc};
    id1 = id[28:21];
    id2 = id[20:13];
    id3 = id[12:5];
    id4 = {id[4:0], 3'b000};

    vif.reg_write(TX_FI,        fi);
    vif.reg_write(TX_FI + 8'd1, id1);
    vif.reg_write(TX_FI + 8'd2, id2);
    vif.reg_write(TX_FI + 8'd3, id3);
    vif.reg_write(TX_FI + 8'd4, id4);

    for (int i = 0; i < dlc && i < 8; i++)
      vif.reg_write(TX_FI + 8'd5 + i[7:0], data[i]);

    `uvm_info("TX_FULL", $sformatf("[%s] EXT DATA id=0x%07h dlc=%0d FI=0x%02h", tag, id, dlc, fi), UVM_LOW)

    vif.reg_write(CMD, 8'h01);
    wait_tx_complete(success);

    if (success)
      `uvm_info("TX_FULL", $sformatf("[%s] TX complete", tag), UVM_LOW)
    else
      `uvm_error("TX_FULL", $sformatf("[%s] TX failed", tag))
  endtask

  // -- Send STD REMOTE frame via DUT TX buffer ----------------
  task automatic send_std_remote(
    input bit [10:0] id,
    input bit [3:0]  dlc,
    input string     tag
  );
    byte unsigned fi, id1, id2;
    bit success;

    wait_tbs_free();

    // Frame Info: FF=0(STD) RTR=1(REMOTE) r1r0=00 DLC
    fi  = {1'b0, 1'b1, 2'b00, dlc};
    id1 = id[10:3];
    id2 = {id[2:0], 5'b00000};

    vif.reg_write(TX_FI,        fi);
    vif.reg_write(TX_FI + 8'd1, id1);
    vif.reg_write(TX_FI + 8'd2, id2);
    // No data bytes for remote frame

    `uvm_info("TX_FULL", $sformatf("[%s] STD REMOTE id=0x%03h dlc=%0d FI=0x%02h", tag, id, dlc, fi), UVM_LOW)

    vif.reg_write(CMD, 8'h01);
    wait_tx_complete(success);

    if (success)
      `uvm_info("TX_FULL", $sformatf("[%s] TX complete", tag), UVM_LOW)
    else
      `uvm_error("TX_FULL", $sformatf("[%s] TX failed", tag))
  endtask

  // -- Send EXT REMOTE frame via DUT TX buffer ----------------
  task automatic send_ext_remote(
    input bit [28:0] id,
    input bit [3:0]  dlc,
    input string     tag
  );
    byte unsigned fi, id1, id2, id3, id4;
    bit success;

    wait_tbs_free();

    fi  = {1'b1, 1'b1, 2'b00, dlc};
    id1 = id[28:21];
    id2 = id[20:13];
    id3 = id[12:5];
    id4 = {id[4:0], 3'b000};

    vif.reg_write(TX_FI,        fi);
    vif.reg_write(TX_FI + 8'd1, id1);
    vif.reg_write(TX_FI + 8'd2, id2);
    vif.reg_write(TX_FI + 8'd3, id3);
    vif.reg_write(TX_FI + 8'd4, id4);

    `uvm_info("TX_FULL", $sformatf("[%s] EXT REMOTE id=0x%07h dlc=%0d FI=0x%02h", tag, id, dlc, fi), UVM_LOW)

    vif.reg_write(CMD, 8'h01);
    wait_tx_complete(success);

    if (success)
      `uvm_info("TX_FULL", $sformatf("[%s] TX complete", tag), UVM_LOW)
    else
      `uvm_error("TX_FULL", $sformatf("[%s] TX failed", tag))
  endtask

  // --------------------------------------------------------------
  task body();
    byte unsigned d_ff[8]   = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
    byte unsigned d_aa55[8] = '{8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55, 8'hAA, 8'h55};
    byte unsigned d_00[8]   = '{8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
    byte unsigned d_walk[8] = '{8'h01, 8'h02, 8'h04, 8'h08, 8'h10, 8'h20, 8'h40, 8'h80};
    byte unsigned d_5a[8]   = '{8'h5A, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};

    if (vif == null)
      `uvm_fatal("TX_FULL", "vif is null — set from test")

    // -- Init DUT ----------------------------------------------
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    `uvm_info("TX_FULL", "===== Starting TX Full Payload Coverage Test =====", UVM_LOW)

    // -- Round 1: STD DATA DLC=8 all-0xFF ----------------------
    send_std_data(11'h7FF, 4'd8, d_ff, "R1_STD_FF");

    // -- Round 2: STD DATA DLC=8 alternating 0xAA/0x55 --------
    send_std_data(11'h000, 4'd8, d_aa55, "R2_STD_AA55");

    // -- Round 3: STD DATA DLC=8 all-0x00 ----------------------
    send_std_data(11'h2AB, 4'd8, d_00, "R3_STD_00");

    // -- Round 4: EXT DATA DLC=8 all-0xFF ----------------------
    // This exercises IBO slots 0-4 (FI + 4 EXT ID bytes) + 5-12 (data)
    send_ext_data(29'h1FFFFFFF, 4'd8, d_ff, "R4_EXT_FF");

    // -- Round 5: EXT DATA DLC=8 alternating -------------------
    send_ext_data(29'h00000000, 4'd8, d_aa55, "R5_EXT_AA55");

    // -- Round 6: EXT DATA DLC=8 walking bit pattern -----------
    send_ext_data(29'h0AAAAAAA, 4'd8, d_walk, "R6_EXT_WALK");

    // -- Round 7: STD REMOTE DLC=8 (no data, exercises FI+ID) --
    send_std_remote(11'h555, 4'd8, "R7_STD_REM");

    // -- Round 8: EXT REMOTE DLC=4 -----------------------------
    send_ext_remote(29'h15555555, 4'd4, "R8_EXT_REM");

    // -- Round 9: STD DATA DLC=1 (boundary) --------------------
    send_std_data(11'h001, 4'd1, d_5a, "R9_STD_DLC1");

    // -- Round 10: EXT DATA DLC=0 (no data, boundary) ---------
    send_ext_data(29'h1F0F0F0F, 4'd0, d_00, "R10_EXT_DLC0");

    `uvm_info("TX_FULL", "===== TX Full Payload Coverage Test COMPLETE =====", UVM_LOW)
  endtask

endclass
`endif