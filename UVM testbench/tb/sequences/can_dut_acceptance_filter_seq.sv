`ifndef CAN_DUT_ACCEPTANCE_FILTER_SEQ_SV
`define CAN_DUT_ACCEPTANCE_FILTER_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_acceptance_filter_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_acceptance_filter_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN regs
  localparam byte MOD = 8'h00;
  localparam byte CMR = 8'h01;
  localparam byte SR  = 8'h02;

  // Acceptance code/mask in reset_mode
  localparam byte ACR0 = 8'h10;
  localparam byte ACR1 = 8'h11;
  localparam byte ACR2 = 8'h12;
  localparam byte ACR3 = 8'h13;
  localparam byte AMR0 = 8'h14;
  localparam byte AMR1 = 8'h15;
  localparam byte AMR2 = 8'h16;
  localparam byte AMR3 = 8'h17;

  // RX buffer window (normal mode)
  localparam byte RX_FI  = 8'h10;
  localparam byte RX_ID1 = 8'h11;
  localparam byte RX_ID2 = 8'h12;

  // IDs
  bit [10:0] id_allow = 11'h123;
  bit [10:0] id_block = 11'h124;

  // payload
  bit [3:0] exp_dlc = 4'd4;
  byte unsigned data4[0:3] = '{8'hAA,8'hBB,8'hCC,8'hDD};

  function new(string name="can_dut_acceptance_filter_seq");
    super.new(name);
  endfunction

  // --- Helpers ---
  function automatic byte unsigned sff_id1(input bit [10:0] id11);
    return byte'({id11[10:3]});
  endfunction

  function automatic byte unsigned sff_id2(input bit [10:0] id11);
    return byte'({id11[2:0], 5'b0});
  endfunction

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

  task automatic wait_rbs_clear(time timeout, output bit cleared);
    time t_end = $time + timeout;
    byte unsigned sr;
    cleared = 1'b0;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (!sr[0]) begin cleared = 1'b1; return; end
      #200ns;
    end
  endtask

  // Robust RX buffer clear: issue RRB then *wait* for RBS to clear
  task automatic clear_rx_buffer_robust();
    byte unsigned sr;
    bit cleared;

    vif.reg_read(SR, sr);
    if (!sr[0]) return; // already clear

    // Issue Release Receive Buffer (RRB)
    vif.reg_write(CMR, 8'h04);

    // Wait up to 50us for RBS to clear
    wait_rbs_clear(50us, cleared);

    vif.reg_read(SR, sr);
    if (!cleared) begin
      `uvm_warning("AFM",
        $sformatf("RBS did not clear after RRB within timeout. SR=0x%02h (RBS=%0b)", sr, sr[0]))
    end
  endtask

  task automatic program_accept_only_id123();
    byte unsigned mod;
    byte unsigned id1, id2;

    id1 = sff_id1(id_allow); // 0x24 for 0x123
    id2 = sff_id2(id_allow); // 0x60 for 0x123

    // Enter reset mode, set AFM=1 (single filter)
    vif.reg_read(MOD, mod);
    mod[0] = 1'b1; // RM=1
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b0; // STM=0
    mod[3] = 1'b1; // AFM=1 (single filter)
    vif.reg_write(MOD, mod);

    // Program ACR/AMR for STD ID match
    vif.reg_write(ACR0, id1);
    vif.reg_write(ACR1, id2);
    vif.reg_write(ACR2, 8'h00);
    vif.reg_write(ACR3, 8'h00);

    vif.reg_write(AMR0, 8'h00); // compare all bits of ACR0
    vif.reg_write(AMR1, 8'h1F); // compare [7:5], ignore [4:0]
    vif.reg_write(AMR2, 8'hFF); // ignore
    vif.reg_write(AMR3, 8'hFF); // ignore

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    // Readback MOD for debug
    vif.reg_read(MOD, mod);
    `uvm_info("AFM",
      $sformatf("Programmed AFM filter for only ID=0x%0h. MOD=0x%02h (RM=%0b LOM=%0b STM=%0b AFM=%0b)",
                id_allow, mod, mod[0], mod[1], mod[2], mod[3]),
      UVM_LOW)
  endtask

  task automatic send_frame_and_log(input bit [10:0] fid, output can_transaction tr);
    tr = can_transaction::type_id::create($sformatf("tr_%0h", fid));
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt == `CAN_ID_STD;
      id      == fid;
      dlc     == exp_dlc;
      f_type  == `CAN_DATA_FRAME;
      data.size() == exp_dlc;
      data[0] == data4[0];
      data[1] == data4[1];
      data[2] == data4[2];
      data[3] == data4[3];
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("AFM", "TX randomization failed")
    finish_item(tr);

    `uvm_info("AFM",
      $sformatf("Agent TX done: id=0x%0h dlc=%0d ack_seen=%0b",
                tr.id, tr.dlc, tr.ack_seen),
      UVM_LOW)
  endtask

  task automatic wait_rbs_stays_clear(time window, output bit stayed_clear);
    time t_end = $time + window;
    byte unsigned sr;
    stayed_clear = 1'b1;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin stayed_clear = 1'b0; return; end
      #200ns;
    end
  endtask

  task body();
    can_transaction tr_allow, tr_block;
    bit rbs_seen, stayed_clear, cleared;
    byte unsigned fi, id1, id2;
    bit [10:0] obs_id;
    int errors = 0;

    // 1) Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // Ensure RX buffer is clear before we begin
    clear_rx_buffer_robust();

    // 2) Program acceptance filter to allow only 0x123
    program_accept_only_id123();

    // ------------------ Allowed frame ------------------
    send_frame_and_log(id_allow, tr_allow);

    if (!tr_allow.ack_seen) begin
      `uvm_error("AFM", "FAIL: Allowed ID was not ACKed (expected ACK)")
      errors++;
    end else begin
      `uvm_info("AFM", "PASS: Allowed ID was ACKed", UVM_LOW)
    end

    wait_rbs_set(200us, rbs_seen);
    if (!rbs_seen) begin
      `uvm_error("AFM", "FAIL: Allowed ID was not stored (RBS never set)")
      errors++;
    end else begin
      `uvm_info("AFM", "PASS: Allowed ID stored (RBS=1)", UVM_LOW)

      // Optional print of what was stored
      vif.reg_read(RX_FI,  fi);
      vif.reg_read(RX_ID1, id1);
      vif.reg_read(RX_ID2, id2);
      obs_id = {id1, id2[7:5]};
      `uvm_info("AFM",
        $sformatf("Stored RX: RX_FI=0x%02h DLC=%0d obs_id=0x%0h", fi, fi[3:0], obs_id),
        UVM_LOW)

      // Release buffer + WAIT for clear (important!)
      vif.reg_write(CMR, 8'h04);
      wait_rbs_clear(50us, cleared);
      if (!cleared)
        `uvm_warning("AFM", "RBS did not clear after releasing allowed frame (may affect blocked-phase)")
    end

    // ------------------ Blocked frame ------------------
    // Ensure buffer really clear before blocked test
    clear_rx_buffer_robust();

    send_frame_and_log(id_block, tr_block);

    // ACK is not a reliable indicator of acceptance filtering.
    if (!tr_block.ack_seen)
      `uvm_warning("AFM", "Blocked ID was not ACKed (some designs still ACK filtered frames; not a failure).")
    else
      `uvm_info("AFM", "INFO: Blocked ID was ACKed (allowed; filter affects storage, not necessarily ACK).", UVM_LOW);

    // Must-have: blocked frame must NOT be stored
    wait_rbs_stays_clear(50us, stayed_clear);
    if (!stayed_clear) begin
      `uvm_error("AFM", "FAIL: Blocked ID got stored (RBS became 1)")
      errors++;
    end else begin
      `uvm_info("AFM", "PASS: Blocked ID not stored (RBS stayed 0)", UVM_LOW)
    end

    if (errors == 0)
      `uvm_info("AFM", "PASS: Acceptance filter behavior verified", UVM_LOW)
    else
      `uvm_error("AFM", $sformatf("FAIL: Acceptance filter test had %0d error(s)", errors))

  endtask

endclass

`endif