`ifndef CAN_DUT_CRC_ERR_SEQ_SV
`define CAN_DUT_CRC_ERR_SEQ_SV

class can_dut_crc_err_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_crc_err_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN register addresses
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;
  localparam byte IR    = 8'h03; // read-to-clear
  localparam byte IER   = 8'h04; // interrupt enable (info)
  localparam byte ECC   = 8'h0C; // read-to-clear in your RTL
  localparam byte RXERR = 8'h0E; // REC
  localparam byte TXERR = 8'h0F; // TEC

  function new(string name = "can_dut_crc_err_seq");
    super.new(name);
  endfunction

  // Force DUT into normal mode: RM=0, LOM=0, STM=0
  task automatic force_dut_normal_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);

    // Enter reset mode to safely change mode bits
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
    `uvm_info("CRC_ERR",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  // Wait for irq_on to toggle (edge) within timeout (polarity-agnostic).
  task automatic wait_irq_any(input time timeout, output bit irq_seen);
    irq_seen = 1'b0;
    fork
      begin : wait_irq
        @(posedge vif.irq_on or negedge vif.irq_on);
        irq_seen = 1'b1;
      end
      begin : wait_to
        #(timeout);
      end
    join_any
    disable fork;
  endtask

  task body();
    can_transaction tx_tr;

    byte unsigned sr_val;
    byte unsigned ecc_val, ir_val, ier_val, dummy;
    byte unsigned rec_before, tec_before;
    byte unsigned rec_after,  tec_after;
    bit irq_seen;

    // -- Init DUT ---------------------------------------------
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    // Force NORMAL mode explicitly (important change)
    force_dut_normal_mode();

    `uvm_info("CRC_ERR", "Starting CRC error injection test (DUT in NORMAL mode)", UVM_LOW)

    // Clear any pending interrupts (IR is read-to-clear)
    vif.reg_read(IR, dummy);

    // Info: show IER so we know interrupts are enabled as expected
    vif.reg_read(IER, ier_val);
    `uvm_info("CRC_ERR", $sformatf("INFO: IER=0x%02h (interrupt enables)", ier_val), UVM_LOW)

    // Snapshot counters before (info)
    vif.reg_read(RXERR, rec_before);
    vif.reg_read(TXERR, tec_before);
    `uvm_info("CRC_ERR",
      $sformatf("INFO: before injection: REC=%0d TEC=%0d", rec_before, tec_before),
      UVM_LOW)

    // -- Agent sends DATA frame with CRC error ----------------
    tx_tr = can_transaction::type_id::create("tx_tr");
    start_item(tx_tr);
    assert(tx_tr.randomize() with {
      can_fmt         == `CAN_ID_STD;
      id              == 11'h123;
      dlc             == 4'd4;
      f_type          == `CAN_DATA_FRAME;
      data.size()     == 4;
      data[0]         == 8'hAA;
      data[1]         == 8'hBB;
      data[2]         == 8'hCC;
      data[3]         == 8'hDD;
      inj_crc_error   == 1;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("CRC_ERR", "TX randomization failed")
    finish_item(tx_tr);

    `uvm_info("CRC_ERR",
      $sformatf("Agent TX done: id=0x%0h dlc=%0d ack_seen=%0b",
                tx_tr.id, tx_tr.dlc, tx_tr.ack_seen),
      UVM_LOW)

    // -- Must-have: DUT must NOT ACK --------------------------
    if (tx_tr.ack_seen)
      `uvm_error("CRC_ERR", "FAIL: DUT ACKed a CRC-corrupted frame — should not happen")
    else
      `uvm_info("CRC_ERR", "PASS: DUT did not ACK the CRC-corrupted frame", UVM_LOW)

    // --- Wait for interrupt indication (irq_on) --------------
    wait_irq_any(200us, irq_seen);

    if (!irq_seen) begin
      `uvm_warning("CRC_ERR",
        "irq_on did not toggle within timeout after CRC error; ECC/REC may not update in this implementation.")
    end

    // Read snapshots ONCE (ECC/IR are read-to-clear in your RTL)
    vif.reg_read(ECC,   ecc_val);
    vif.reg_read(IR,    ir_val);
    vif.reg_read(RXERR, rec_after);
    vif.reg_read(TXERR, tec_after);

    `uvm_info("CRC_ERR",
      $sformatf("Post-check: ECC=0x%02h (ERRC=%02b DIR=%0b SEG=%05b) IR=0x%02h(BEI=%0b EI=%0b) REC=%0d TEC=%0d",
                ecc_val, ecc_val[7:6], ecc_val[5], ecc_val[4:0],
                ir_val, ir_val[7], ir_val[2], rec_after, tec_after),
      UVM_LOW)

    // -- Must-have: frame must NOT be stored -------------------
    vif.reg_read(SR, sr_val);
    if (sr_val[0])
      `uvm_error("CRC_ERR",
        $sformatf("FAIL: DUT stored a corrupt frame in RX buffer (SR=0x%02h)", sr_val))
    else
      `uvm_info("CRC_ERR", "PASS: DUT RX buffer empty — corrupt frame rejected", UVM_LOW)

    `uvm_info("CRC_ERR", "===== CRC ERROR INJECTION TEST COMPLETE =====", UVM_LOW)
  endtask

endclass
`endif