`ifndef CAN_DUT_NORMAL_MODE_RX_SEQ_SV
`define CAN_DUT_NORMAL_MODE_RX_SEQ_SV

class can_dut_normal_mode_rx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_normal_mode_rx_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN regs
  localparam byte MOD = 8'h00;
  localparam byte CMR = 8'h01;
  localparam byte SR  = 8'h02;

  // RX buffer window (PeliCAN)
  localparam byte RX_FI  = 8'h10;
  localparam byte RX_ID1 = 8'h11;
  localparam byte RX_ID2 = 8'h12;
  localparam byte RX_D0  = 8'h13;

  // Stimulus knobs (keep fixed for debug clarity)
  bit [10:0]    exp_id  = 11'h123;
  bit [3:0]     exp_dlc = 4'd4;
  byte unsigned exp_data[0:7] = '{8'hAA,8'hBB,8'hCC,8'hDD,8'h00,8'h00,8'h00,8'h00};

  function new(string name="can_dut_normal_mode_rx_seq");
    super.new(name);
  endfunction

  // Force DUT into normal mode: RM=0, LOM=0, STM=0
  task automatic force_dut_normal_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);

    // Enter reset mode to safely change mode bits
    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    // Clear Listen-Only and Self-Test
    vif.reg_read(MOD, mod);
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b0; // STM=0
    vif.reg_write(MOD, mod);

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    // Readback and print
    vif.reg_read(MOD, mod);
    `uvm_info("NORM_RX",
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
    can_transaction tr;

    byte unsigned sr, fi, id1, id2;
    byte unsigned d;
    bit rbs_seen;
    bit [10:0] obs_id;
    int errors = 0;
    bit cleared;

    // 1) Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // 2) Force normal mode explicitly (removes any doubt)
    force_dut_normal_mode();

    `uvm_info("NORM_RX", "Starting NORMAL MODE RX test (expect DUT to ACK + store frame)", UVM_LOW)

    // 3) Send a clean DATA frame from agent -> DUT receives
    tr = can_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt         == `CAN_ID_STD;
      id              == exp_id;
      dlc             == exp_dlc;
      f_type          == `CAN_DATA_FRAME;
      data.size()     == exp_dlc;
      data[0]         == exp_data[0];
      data[1]         == exp_data[1];
      data[2]         == exp_data[2];
      data[3]         == exp_data[3];
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("NORM_RX", "TX randomization failed")
    finish_item(tr);

    `uvm_info("NORM_RX",
      $sformatf("Agent TX done: id=0x%0h dlc=%0d ack_seen=%0b",
                tr.id, tr.dlc, tr.ack_seen),
      UVM_LOW)

    // 4) MUST: In normal mode, DUT should ACK a valid frame
    if (!tr.ack_seen) begin
      `uvm_error("NORM_RX", "FAIL: ACK not seen on a valid data frame (DUT did not ACK)")
      errors++;
    end else begin
      `uvm_info("NORM_RX", "PASS: ACK seen (DUT ACKed valid frame)", UVM_LOW)
    end

    // 5) MUST: DUT should store the frame (RBS=1)
    wait_rbs_set(200us, rbs_seen);
    if (!rbs_seen) begin
      `uvm_error("NORM_RX", "FAIL: SR.RBS never set (DUT did not store the received frame)")
      errors++;
    end else begin
      `uvm_info("NORM_RX", "PASS: SR.RBS set (frame stored)", UVM_LOW)
    end

    // 6) Optional: read RX buffer and verify header/data
    vif.reg_read(RX_FI,  fi);
    vif.reg_read(RX_ID1, id1);
    vif.reg_read(RX_ID2, id2);

    // Decode standard ID: id[10:3]=ID1, id[2:0]=ID2[7:5]
    obs_id = {id1, id2[7:5]};

    `uvm_info("NORM_RX",
      $sformatf("RX_FI=0x%02h (FF=%0b RTR=%0b DLC=%0d) RX_ID1=0x%02h RX_ID2=0x%02h -> obs_id=0x%0h",
                fi, fi[7], fi[6], fi[3:0], id1, id2, obs_id),
      UVM_LOW)

    // Check FI fields
    if (fi[7] !== 1'b0) begin
      `uvm_error("NORM_RX", $sformatf("FAIL: FF bit expected 0 (STD), got RX_FI=0x%02h", fi))
      errors++;
    end
    if (fi[6] !== 1'b0) begin
      `uvm_error("NORM_RX", $sformatf("FAIL: RTR bit expected 0 (DATA), got RX_FI=0x%02h", fi))
      errors++;
    end
    if (fi[3:0] !== exp_dlc) begin
      `uvm_error("NORM_RX",
        $sformatf("FAIL: DLC mismatch: exp=%0d obs=%0d", exp_dlc, fi[3:0]))
      errors++;
    end
    if (obs_id !== exp_id) begin
      `uvm_error("NORM_RX",
        $sformatf("FAIL: ID mismatch: exp=0x%0h obs=0x%0h", exp_id, obs_id))
      errors++;
    end

    // Check first exp_dlc data bytes
    for (int i = 0; i < exp_dlc; i++) begin
      vif.reg_read(RX_D0 + byte'(i), d);
      if (d !== exp_data[i]) begin
        `uvm_error("NORM_RX",
          $sformatf("FAIL: RX_DATA[%0d] mismatch: exp=0x%02h obs=0x%02h", i, exp_data[i], d))
        errors++;
      end
    end

    // 7) Release RX buffer (RRB = CMR bit2 => 0x04)
    vif.reg_write(CMR, 8'h04);

    // Give it a few clocks and check RBS clears
    
    wait_rbs_clear(50us, cleared);
    vif.reg_read(SR, sr);
    `uvm_info("NORM_RX", $sformatf("After RRB: SR=0x%02h (RBS=%0b)", sr, sr[0]), UVM_LOW)

    if (!cleared) begin
      `uvm_warning("NORM_RX", "RBS did not clear after RRB (could be another frame arriving or release timing)")
    end

    // 8) Verdict
    if (errors == 0)
      `uvm_info("NORM_RX", "PASS: Normal mode RX path ACKed + stored + matched RX buffer", UVM_LOW)
    else
      `uvm_error("NORM_RX", $sformatf("FAIL: Normal mode RX test had %0d error(s)", errors))

    `uvm_info("NORM_RX", "===== NORMAL MODE RX TEST COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif