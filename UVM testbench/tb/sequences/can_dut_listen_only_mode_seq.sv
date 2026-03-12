`ifndef CAN_DUT_LISTEN_ONLY_MODE_SEQ_SV
`define CAN_DUT_LISTEN_ONLY_MODE_SEQ_SV

class can_dut_listen_only_mode_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_listen_only_mode_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN regs
  localparam byte MOD = 8'h00;
  localparam byte CMR = 8'h01;
  localparam byte SR  = 8'h02;

  // RX buffer window
  localparam byte RX_FI  = 8'h10;
  localparam byte RX_ID1 = 8'h11;
  localparam byte RX_ID2 = 8'h12;
  localparam byte RX_D0  = 8'h13;

  // Stimulus knobs
  bit [10:0] exp_id  = 11'h123;
  bit [3:0]  exp_dlc = 4'd4;
  byte unsigned exp_data[0:7] = '{8'hAA,8'hBB,8'hCC,8'hDD,8'h00,8'h00,8'h00,8'h00};

  function new(string name="can_dut_listen_only_mode_seq");
    super.new(name);
  endfunction

  // Force DUT into listen-only mode: RM=0, LOM=1, STM=0
  task automatic force_dut_listen_only_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);

    // Enter reset mode to safely change bits
    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    // Set LOM=1, STM=0
    vif.reg_read(MOD, mod);
    mod[1] = 1'b1; // LOM=1 (listen-only)
    mod[2] = 1'b0; // STM=0
    vif.reg_write(MOD, mod);

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    // Readback
    vif.reg_read(MOD, mod);
    `uvm_info("LOM_RX",
      $sformatf("MOD after force_listen_only = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic wait_rbs_set(time timeout, output bit seen);
    time t_end = $time + timeout;
    byte unsigned sr;
    seen = 1'b0;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin
        seen = 1'b1;
        return;
      end
      #200ns;
    end
  endtask

  task body();
    can_transaction tr;
    byte unsigned fi, id1, id2, d;
    bit rbs_seen;
    bit [10:0] obs_id;
    int errors = 0;

    // 1) Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // 2) Force Listen-Only mode
    force_dut_listen_only_mode();

    `uvm_info("LOM_RX", "Starting LISTEN-ONLY RX test (expect NO ACK)", UVM_LOW)

    // 3) Agent sends a clean DATA frame
    tr = can_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt     == `CAN_ID_STD;
      id          == exp_id;
      dlc         == exp_dlc;
      f_type      == `CAN_DATA_FRAME;
      data.size() == exp_dlc;
      data[0]     == exp_data[0];
      data[1]     == exp_data[1];
      data[2]     == exp_data[2];
      data[3]     == exp_data[3];
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("LOM_RX", "TX randomization failed")
    finish_item(tr);

    `uvm_info("LOM_RX",
      $sformatf("Agent TX done: id=0x%0h dlc=%0d ack_seen=%0b",
                tr.id, tr.dlc, tr.ack_seen),
      UVM_LOW)

    // MUST: Listen-only must NOT ACK
    if (tr.ack_seen) begin
      `uvm_error("LOM_RX", "FAIL: DUT ACKed frame in Listen-Only mode (should not ACK)")
      errors++;
    end else begin
      `uvm_info("LOM_RX", "PASS: No ACK seen (expected in Listen-Only mode)", UVM_LOW)
    end

    // Optional: does it store?
    wait_rbs_set(200us, rbs_seen);
    if (!rbs_seen) begin
      `uvm_info("LOM_RX", "INFO: RBS never set — DUT did not store frame (implementation-dependent)", UVM_LOW)
    end else begin
      `uvm_info("LOM_RX", "INFO: RBS set — DUT stored frame even in Listen-Only (allowed in many designs)", UVM_LOW)

      // Read RX header (optional)
      vif.reg_read(RX_FI,  fi);
      vif.reg_read(RX_ID1, id1);
      vif.reg_read(RX_ID2, id2);
      obs_id = {id1, id2[7:5]};

      `uvm_info("LOM_RX",
        $sformatf("RX_FI=0x%02h (FF=%0b RTR=%0b DLC=%0d) obs_id=0x%0h",
                  fi, fi[7], fi[6], fi[3:0], obs_id),
        UVM_LOW)

      // Release RX buffer
      vif.reg_write(CMR, 8'h04);
    end

    if (errors == 0)
      `uvm_info("LOM_RX", "PASS: Listen-Only mode behavior verified", UVM_LOW)
    else
      `uvm_error("LOM_RX", $sformatf("FAIL: Listen-Only mode test had %0d error(s)", errors))

    `uvm_info("LOM_RX", "===== LISTEN-ONLY MODE RX TEST COMPLETE =====", UVM_LOW)
  endtask

endclass
`endif