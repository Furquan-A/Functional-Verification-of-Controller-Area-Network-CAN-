`ifndef CAN_DUT_REMOTE_RX_SEQ_SV
`define CAN_DUT_REMOTE_RX_SEQ_SV

class can_dut_remote_rx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_remote_rx_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN regs
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;

  // RX buffer window (PeliCAN)
  localparam byte RX_FI  = 8'h10; // Frame Info (FF/RTR/DLC)
  localparam byte RX_ID1 = 8'h11;
  localparam byte RX_ID2 = 8'h12;

  // knobs
  bit [10:0] exp_id  = 11'h321;

  // Start with DLC=0 for the cleanest remote frame.
  // Later try 4'd4 and see if DUT still ACKs.
  bit [3:0]  exp_dlc = 4'd0;

  function new(string name="can_dut_remote_rx_seq");
    super.new(name);
  endfunction

  // -- HELPER: wait for RBS set --
  task automatic wait_rbs_set(time timeout, output bit seen);
    time t_end = $time + timeout;
    byte unsigned sr;
    seen = 1'b0;

    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin // SR[0]=RBS
        seen = 1'b1;
        return;
      end
      #200ns;
    end
  endtask

  // -- HELPER: wait for RBS clear --
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

  // Put DUT into normal mode (RM=0, LOM=0, STM=0)
  task automatic force_dut_normal_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);

    // Enter reset mode
    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    // Clear listen-only + self-test
    vif.reg_read(MOD, mod);
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b0; // STM=0
    vif.reg_write(MOD, mod);

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    // Readback
    vif.reg_read(MOD, mod);
    `uvm_info("REMOTE_RX",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task body();
    can_transaction tr;
    byte unsigned sr, fi, id1, id2;
    bit rbs_seen, rbs_cleared;
    bit [10:0] obs_id;
    int errors = 0;

    // Init DUT (accept all, PeliCAN, etc.)
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // Force normal mode so ACK should be possible
    force_dut_normal_mode();

    `uvm_info("REMOTE_RX",
      $sformatf("Starting REMOTE frame RX test in NORMAL mode (expect ACK + store). ID=0x%0h DLC=%0d",
                exp_id, exp_dlc),
      UVM_LOW)

    // Send REMOTE frame from agent (DUT is receiver)
    tr = can_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt         == `CAN_ID_STD;
      id              == exp_id;
      dlc             == exp_dlc;
      f_type          == `CAN_REMOTE_FRAME;
      data.size()     == 0;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("REMOTE_RX", "Remote-frame randomization failed")
    finish_item(tr);

    `uvm_info("REMOTE_RX",
      $sformatf("Agent TX done: REMOTE id=0x%0h dlc=%0d ack_seen=%0b",
                tr.id, tr.dlc, tr.ack_seen),
      UVM_LOW)

    // In NORMAL mode, a valid remote frame should be ACKed by receivers
    if (!tr.ack_seen) begin
      `uvm_warning("REMOTE_RX",
        "ACK not seen for remote frame. DUT may not ACK remote frames, or remote-frame generation/CRC is not matching DUT.")
    end else begin
      `uvm_info("REMOTE_RX", "PASS: ACK seen for remote frame", UVM_LOW)
    end

    // DUT should store the remote frame
    wait_rbs_set(200us, rbs_seen);
    if (!rbs_seen) begin
      `uvm_error("REMOTE_RX", "FAIL: SR.RBS never set — DUT did not store the remote frame")
      return;
    end

    // Read RX buffer registers
    vif.reg_read(RX_FI,  fi);
    vif.reg_read(RX_ID1, id1);
    vif.reg_read(RX_ID2, id2);

    obs_id = {id1, id2[7:5]};

    `uvm_info("REMOTE_RX",
      $sformatf("RX_FI=0x%02h (RTR=%0b DLC=%0d) RX_ID1=0x%02h RX_ID2=0x%02h -> obs_id=0x%0h",
                fi, fi[6], fi[3:0], id1, id2, obs_id),
      UVM_LOW)

    // Check RTR bit
    if (fi[6] != 1'b1) begin
      `uvm_error("REMOTE_RX", $sformatf("FAIL: RTR bit not set in RX_FI (RX_FI=0x%02h)", fi))
      errors++;
    end

    // Check DLC
    if (fi[3:0] !== exp_dlc) begin
      `uvm_error("REMOTE_RX",
        $sformatf("FAIL: DLC mismatch in RX_FI: exp=%0d obs=%0d", exp_dlc, fi[3:0]))
      errors++;
    end

    // Check ID
    if (obs_id !== exp_id) begin
      `uvm_error("REMOTE_RX",
        $sformatf("FAIL: ID mismatch: exp=0x%0h obs=0x%0h", exp_id, obs_id))
      errors++;
    end

    if (errors == 0)
      `uvm_info("REMOTE_RX", "PASS: DUT stored remote frame and RX buffer shows RTR=1", UVM_LOW)

    // Release RX buffer (CMR.RRB = bit2)
    vif.reg_write(CMR, 8'h04);

    // Poll for RBS clear (prevents the “still 1” confusion)
    wait_rbs_clear(50us, rbs_cleared);
    vif.reg_read(SR, sr);
    `uvm_info("REMOTE_RX", $sformatf("After RRB: SR=0x%02h (RBS=%0b)", sr, sr[0]), UVM_LOW)

    if (!rbs_cleared)
      `uvm_warning("REMOTE_RX", "RBS did not clear after RRB (possible new frame arrival or release timing)")

    `uvm_info("REMOTE_RX", "===== REMOTE RX TEST COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif