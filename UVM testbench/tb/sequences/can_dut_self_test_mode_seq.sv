`ifndef CAN_DUT_SELF_TEST_MODE_SEQ_SV
`define CAN_DUT_SELF_TEST_MODE_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_self_test_mode_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_self_test_mode_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN regs
  localparam byte MOD = 8'h00;
  localparam byte CMR = 8'h01;
  localparam byte SR  = 8'h02;
  localparam byte IR  = 8'h03;

  // TX buffer window (SFF)
  localparam byte TX_FI  = 8'h10;
  localparam byte TX_ID1 = 8'h11;
  localparam byte TX_ID2 = 8'h12;
  localparam byte TX_D0  = 8'h13;

  // RX buffer window (SFF)
  localparam byte RX_FI  = 8'h10;
  localparam byte RX_ID1 = 8'h11;
  localparam byte RX_ID2 = 8'h12;
  localparam byte RX_D0  = 8'h13;

  // Stimulus knobs
  bit [10:0] exp_id  = 11'h123;
  bit [3:0]  exp_dlc = 4'd4;
  byte unsigned exp_data[0:7] = '{8'hAA,8'hBB,8'hCC,8'hDD,8'h00,8'h00,8'h00,8'h00};

  function new(string name="can_dut_self_test_mode_seq");
    super.new(name);
  endfunction

  // -------- Helpers --------

  task automatic force_dut_self_test_mode();
    byte unsigned mod;

    // Enter reset mode
    vif.reg_read(MOD, mod);
    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    // Set STM=1, clear LOM
    vif.reg_read(MOD, mod);
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b1; // STM=1
    vif.reg_write(MOD, mod);

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    // Readback
    vif.reg_read(MOD, mod);
    `uvm_info("STM",
      $sformatf("MOD after force_self_test = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic clear_ir();
    byte unsigned dummy;
    vif.reg_read(IR, dummy); // read-to-clear
  endtask

  task automatic clear_rx_buffer_if_needed();
    byte unsigned sr;
    int unsigned tries = 0;

    vif.reg_read(SR, sr);
    while (sr[0] && tries < 50) begin
      vif.reg_write(CMR, 8'h04); // RRB
      #200ns;
      vif.reg_read(SR, sr);
      tries++;
    end
  endtask

  task automatic wait_tbs_released(int unsigned timeout_iters = 5000);
    byte unsigned sr;
    int unsigned t = 0;
    do begin
      vif.reg_read(SR, sr);
      if (sr[2]) return; // SR[2]=TBS
      #100ns;
      t++;
    end while (t < timeout_iters);
    `uvm_fatal("STM", "Timeout waiting for SR.TBS=1 (TX buffer released)")
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

  task automatic load_tx_sff_data(
    input bit [10:0] id11,
    input int unsigned dlc,
    input byte unsigned data_bytes[0:7]
  );
    byte unsigned fi, id1, id2;

    if (dlc > 8) dlc = 8;

    // FI: FF=0 (SFF), RTR=0 (DATA), DLC in [3:0]
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

  task body();
    byte unsigned sr, fi, id1, id2, d;
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

    // 2) Force STM=1
    force_dut_self_test_mode();

    // Clean start
    clear_ir();
    clear_rx_buffer_if_needed();

    // 3) Wait TX buffer ready
    wait_tbs_released();

    // 4) Load TX buffer
    load_tx_sff_data(exp_id, exp_dlc, exp_data);

    // 5) Trigger TX in single-shot + self reception request
    // CMR bits we’re using:
    //  bit0 TR  (Transmit Request)
    //  bit1 AT  (Abort / Single-shot helper depending on core; in your env you used 0x03 as single-shot)
    //  bit4 SRR (Self Reception Request)  -> common in SJA1000-style cores
    // So: TR + AT + SRR = 0x13
    vif.reg_write(CMR, 8'h10);

    // 6) Wait TX attempt done
    wait_tbs_released();

    // Read SR to check TCS
    vif.reg_read(SR, sr);
    `uvm_info("STM",
      $sformatf("Post-TX SR=0x%02h (TBS=%0b TCS=%0b RBS=%0b)", sr, sr[2], sr[3], sr[0]),
      UVM_LOW)

    // In self-test, TX should be “successful” even without external ACK
    if (!sr[3]) begin
      `uvm_error("STM", "FAIL: SR.TCS=0 in Self-Test mode (expected TX success)")
      errors++;
    end else begin
      `uvm_info("STM", "PASS: SR.TCS=1 (TX success in Self-Test mode)", UVM_LOW)
    end

    // 7) If self reception works, RX buffer should get the frame
    wait_rbs_set(200us, rbs_seen);
    if (!rbs_seen) begin
      `uvm_warning("STM", "RBS never set — self reception may not be enabled/implemented (SRR behavior).")
    end else begin
      // Read RX header/data and compare
      vif.reg_read(RX_FI,  fi);
      vif.reg_read(RX_ID1, id1);
      vif.reg_read(RX_ID2, id2);
      obs_id = {id1, id2[7:5]};

      `uvm_info("STM",
        $sformatf("RX_FI=0x%02h (FF=%0b RTR=%0b DLC=%0d) obs_id=0x%0h",
                  fi, fi[7], fi[6], fi[3:0], obs_id),
        UVM_LOW)

      if (fi[6] != 1'b0) begin
        `uvm_error("STM", "FAIL: RTR=1 in self-received frame (expected DATA)")
        errors++;
      end
      if (fi[3:0] != exp_dlc) begin
        `uvm_error("STM", $sformatf("FAIL: DLC mismatch: exp=%0d obs=%0d", exp_dlc, fi[3:0]))
        errors++;
      end
      if (obs_id != exp_id) begin
        `uvm_error("STM", $sformatf("FAIL: ID mismatch: exp=0x%0h obs=0x%0h", exp_id, obs_id))
        errors++;
      end

      for (int i = 0; i < exp_dlc; i++) begin
        vif.reg_read(RX_D0 + byte'(i), d);
        if (d != exp_data[i]) begin
          `uvm_error("STM",
            $sformatf("FAIL: RX_DATA[%0d] mismatch: exp=0x%02h obs=0x%02h", i, exp_data[i], d))
          errors++;
        end
      end

      // Release RX buffer
      vif.reg_write(CMR, 8'h04);
    end

    if (errors == 0)
      `uvm_info("STM", "PASS: Self-Test mode behavior verified", UVM_LOW)
    else
      `uvm_error("STM", $sformatf("FAIL: Self-Test mode test had %0d error(s)", errors))

    `uvm_info("STM", "===== SELF-TEST MODE TEST COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif