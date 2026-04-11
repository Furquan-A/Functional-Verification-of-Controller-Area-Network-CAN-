`ifndef CAN_DUT_OVERRUN_SEQ_SV
`define CAN_DUT_OVERRUN_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

class can_dut_overrun_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_overrun_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN regs
  localparam byte MOD = 8'h00;
  localparam byte CMR = 8'h01;
  localparam byte SR  = 8'h02;
  localparam byte IR  = 8'h03; // read-to-clear

  // SR bits
  localparam int SR_RBS = 0; // Receive Buffer Status
  localparam int SR_DOS = 1; // Data Overrun Status

  // IR bits
  localparam int IR_DOI = 3; // Data Overrun Interrupt

  int unsigned n_frames = 12;
  int unsigned ovr_dlc  = 8;
  bit [10:0]   base_id  = 11'h200;

  function new(string name="can_dut_overrun_seq");
    super.new(name);
  endfunction

  task automatic force_dut_normal_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);

    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    vif.reg_read(MOD, mod);
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b0; // STM=0
    vif.reg_write(MOD, mod);

    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    vif.reg_read(MOD, mod);
    `uvm_info("OVR",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic clear_ir();
    byte unsigned dummy;
    vif.reg_read(IR, dummy);
  endtask

  task automatic drain_rx_fifo(time timeout);
    time t_end = $time + timeout;
    byte unsigned sr;
    int unsigned pops = 0;

    forever begin
      vif.reg_read(SR, sr);
      if (!sr[SR_RBS]) break;
      vif.reg_write(CMR, 8'h04); // RRB
      pops++;
      #200ns;
      if ($time > t_end) begin
        `uvm_warning("OVR",
          $sformatf("Timeout draining RX FIFO (popped %0d). SR=0x%02h", pops, sr))
        break;
      end
    end

    // FIX: issue one final RRB after FIFO is confirmed empty
    // Hits CAN_SR_RBS_003_CLEARED_BY_RRB_C:
    //   (release_buffer && rx_message_counter == 0) |=> !receive_buffer_status
    vif.reg_write(CMR, 8'h04); // RRB on empty FIFO
    #200ns;

    `uvm_info("OVR", $sformatf("Drain RX done (popped %0d, +1 empty RRB)", pops), UVM_LOW)
  endtask

  task automatic clear_overrun();
    byte unsigned sr;
    vif.reg_read(SR, sr);
    if (sr[SR_DOS]) begin
      vif.reg_write(CMR, 8'h08); // CDO
      #200ns;
    end
  endtask

  task body();
    can_transaction tr;
    byte unsigned sr, ir;

    void'($value$plusargs("OVR_N=%d",   n_frames));
    void'($value$plusargs("OVR_DLC=%d", ovr_dlc));

    if (ovr_dlc > 8) ovr_dlc = 8;
    if (ovr_dlc < 1) ovr_dlc = 1;
    if (n_frames < 2) n_frames = 2;

    // 1) Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // 2) Force Normal mode
    force_dut_normal_mode();

    // 3) Clean start
    clear_ir();
    clear_overrun();
    drain_rx_fifo(200us);

    `uvm_info("OVR",
      $sformatf("Starting OVERRUN test: sending %0d frames, DLC=%0d, without releasing RX buffer",
                n_frames, ovr_dlc),
      UVM_LOW)

    // 4) Flood frames — do NOT release RX buffer during burst
    for (int unsigned i = 0; i < n_frames; i++) begin
      tr = can_transaction::type_id::create($sformatf("tr_%0d", i));
      start_item(tr);
      assert(tr.randomize() with {
        can_fmt == `CAN_ID_STD;
        id      == (base_id + i);
        dlc     == ovr_dlc[3:0];
        f_type  == `CAN_DATA_FRAME;
        data.size() == ovr_dlc;
        foreach (data[j]) data[j] == byte'(i + j);
        inj_crc_error   == 0;
        inj_stuff_error == 0;
        inj_form_error  == 0;
        inj_ack_error   == 0;
      }) else `uvm_fatal("OVR", "TX randomization failed")
      finish_item(tr);
    end

    // 5) Drain then check for DOS
    drain_rx_fifo(500us);

    vif.reg_read(SR, sr);
    vif.reg_read(IR, ir);

    `uvm_info("OVR",
      $sformatf("Post-drain: SR=0x%02h (RBS=%0b DOS=%0b) IR=0x%02h (DOI=%0b)",
                sr, sr[SR_RBS], sr[SR_DOS], ir, ir[IR_DOI]),
      UVM_LOW)

    if (sr[SR_DOS] || ir[IR_DOI]) begin
      `uvm_info("OVR", "PASS: Data Overrun detected (DOS and/or DOI asserted)", UVM_LOW)
    end else begin
      `uvm_error("OVR",
        $sformatf("FAIL: Overrun not detected after drain (sent %0d frames DLC=%0d)",
                  n_frames, ovr_dlc))
    end

    // 6) Cleanup
    clear_overrun();
    drain_rx_fifo(200us);

    vif.reg_read(SR, sr);
    `uvm_info("OVR",
      $sformatf("After cleanup: SR=0x%02h (RBS=%0b DOS=%0b)", sr, sr[SR_RBS], sr[SR_DOS]),
      UVM_LOW)

    `uvm_info("OVR", "===== OVERRUN TEST COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif