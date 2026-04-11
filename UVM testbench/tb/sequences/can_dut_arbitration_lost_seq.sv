`ifndef CAN_DUT_ARBITRATION_LOST_SEQ_SV
`define CAN_DUT_ARBITRATION_LOST_SEQ_SV

class can_dut_arbitration_lost_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_arbitration_lost_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // node1 active sequencer
  uvm_sequencer #(can_transaction) node1_sqr;

  // Public results
  bit arb_irq_seen;
  bit arb_ir_ali_seen;
  bit arb_alc_captured;
  bit arb_lost_ok;

  // Register map
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;
  localparam byte IR    = 8'h03; // read-to-clear
  localparam byte IER   = 8'h04;
  localparam byte ALC   = 8'h0B;
  localparam byte ECC   = 8'h0C; // read-to-clear

  localparam byte TX_FI  = 8'h10;
  localparam byte TX_ID1 = 8'h11;
  localparam byte TX_ID2 = 8'h12;
  localparam byte TX_D0  = 8'h13;

  // Bits
  localparam int SR_TBS       = 2;
  localparam int IR_ALI_BIT   = 6;
  localparam int IER_ALIE_BIT = 6;

  // IDs used for contention
  // DUT must lose: higher ID / lower priority
  localparam bit [10:0] DUT_ARB_LOSE_ID = 11'h180;
  localparam bit [10:0] NODE1_WIN_ID    = 11'h100;

  // Launch DUT TR at same fork point as node1 traffic
  time dut_tr_issue_delay = 0ns;

  function new(string name = "can_dut_arbitration_lost_seq");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

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
    `uvm_info("ARB_LOST_SEQ",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic clear_status_regs();
    byte unsigned dummy;
    vif.reg_read(IR,  dummy);
    vif.reg_read(ECC, dummy);
  endtask

  task automatic set_alie_enable(bit en);
    byte unsigned ier_val;

    vif.reg_read(IER, ier_val);
    ier_val[IER_ALIE_BIT] = en;
    vif.reg_write(IER, ier_val);

    vif.reg_read(IER, ier_val);
    `uvm_info("ARB_LOST_SEQ",
      $sformatf("IER programmed to 0x%02h (ALIE=%0b)",
                ier_val, ier_val[IER_ALIE_BIT]),
      UVM_LOW)
  endtask

  task automatic wait_tbs_high(int unsigned timeout_iters = 20000);
    byte unsigned sr;
    int unsigned  t = 0;

    do begin
      vif.reg_read(SR, sr);
      if (sr[SR_TBS]) return;
      #100ns;
      t++;
    end while (t < timeout_iters);

    `uvm_fatal("ARB_LOST_SEQ", "Timeout waiting for SR.TBS=1")
  endtask

  task automatic load_dut_tx_frame(bit [10:0] id11, byte unsigned data0);
    vif.reg_write(TX_FI,  8'h01);             // STD DATA, DLC=1
    vif.reg_write(TX_ID1, {id11[10:3]});
    vif.reg_write(TX_ID2, {id11[2:0], 5'b0});
    vif.reg_write(TX_D0,  data0);
  endtask

  task automatic send_node1_arb_frame(bit [10:0] id11);
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    start_item(tr, -1, node1_sqr);
    assert(tr.randomize() with {
      can_fmt         == `CAN_ID_STD;
      id              == id11;
      dlc             == 4'd8;
      f_type          == `CAN_DATA_FRAME;
      data.size()     == 8;
      data[0]         == 8'h11;
      data[1]         == 8'h22;
      data[2]         == 8'h33;
      data[3]         == 8'h44;
      data[4]         == 8'h55;
      data[5]         == 8'h66;
      data[6]         == 8'h77;
      data[7]         == 8'h88;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("ARB_LOST_SEQ", "node1 arbitration TX randomization failed")
    finish_item(tr);
  endtask

  task automatic watch_irq_only(
    input  time  timeout,
    input  logic irq_baseline,
    output bit   irq_toggled
  );
    time start_t;

    irq_toggled = 1'b0;
    start_t = $time;

    while (($time - start_t) < timeout) begin
      if (vif.irq_on !== irq_baseline)
        irq_toggled = 1'b1;
      #100ns;
    end
  endtask

  // --------------------------------------------------------------------------
  // Main
  // --------------------------------------------------------------------------

  task body();
    byte unsigned ir_val;
    byte unsigned alc_before, alc_after;
    logic         irq_baseline;
    bit           irq_toggled;

    if (vif == null)
      `uvm_fatal("ARB_LOST_SEQ", "vif is null -- set from test")

    if (node1_sqr == null)
      `uvm_fatal("ARB_LOST_SEQ", "node1_sqr is null -- set from test")

    arb_irq_seen      = 1'b0;
    arb_ir_ali_seen   = 1'b0;
    arb_alc_captured  = 1'b0;
    arb_lost_ok       = 1'b0;

    // Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end
    `uvm_info("ARB_LOST_SEQ", "DUT initialised", UVM_LOW)

    force_dut_normal_mode();
    clear_status_regs();
    wait_tbs_high();

    set_alie_enable(1'b1);

    load_dut_tx_frame(DUT_ARB_LOSE_ID, 8'hD1);

    // Re-baseline immediately before contention
    clear_status_regs();
    vif.reg_read(ALC, alc_before);
    irq_baseline = vif.irq_on;

    `uvm_info("ARB_LOST_SEQ",
      $sformatf("Starting contention: DUT id=0x%03h (lose), node1 id=0x%03h (win), ALC_before=0x%02h",
                DUT_ARB_LOSE_ID, NODE1_WIN_ID, alc_before),
      UVM_LOW)

    // Launch both from the same fork point so they target the same arbitration window
    fork
      begin
        send_node1_arb_frame(NODE1_WIN_ID);
      end
      begin
        #(dut_tr_issue_delay);
        vif.reg_write(CMR, 8'h01); // TR
      end
      begin
        watch_irq_only(150us, irq_baseline, irq_toggled);
      end
    join

    arb_irq_seen = irq_toggled;

    // Read arbitration-lost status after contention
    vif.reg_read(IR,  ir_val);   // read-to-clear
    vif.reg_read(ALC, alc_after);

    arb_ir_ali_seen  = ir_val[IR_ALI_BIT];
    arb_alc_captured = (alc_after != alc_before);

    `uvm_info("ARB_LOST_SEQ",
      $sformatf("Post-contention: irq_seen=%0b IR=0x%02h (ALI=%0b) ALC_before=0x%02h ALC_after=0x%02h",
                arb_irq_seen, ir_val, ir_val[IR_ALI_BIT], alc_before, alc_after),
      UVM_LOW)

    if (!arb_irq_seen) begin
      `uvm_error("ARB_LOST_SEQ",
        "FAIL: arbitration-lost IRQ behavior not observed on irq_on")
    end

    if (!arb_ir_ali_seen) begin
      `uvm_error("ARB_LOST_SEQ",
        $sformatf("FAIL: IR.ALI was not set after expected arbitration loss (IR=0x%02h)", ir_val))
    end

    if (!arb_alc_captured) begin
      `uvm_error("ARB_LOST_SEQ",
        $sformatf("FAIL: ALC did not appear to capture arbitration loss location (before=0x%02h after=0x%02h)",
                  alc_before, alc_after))
    end

    if (arb_irq_seen && arb_ir_ali_seen && arb_alc_captured) begin
      arb_lost_ok = 1'b1;
      `uvm_info("ARB_LOST_SEQ",
        "PASS: DUT arbitration-lost scenario closed (IRQ + IR.ALI + ALC)",
        UVM_LOW)
    end

    `uvm_info("ARB_LOST_SEQ",
      $sformatf("Summary: IRQ=%0b IR.ALI=%0b ALC=%0b OVERALL=%0b",
                arb_irq_seen, arb_ir_ali_seen, arb_alc_captured, arb_lost_ok),
      UVM_LOW)

    `uvm_info("ARB_LOST_SEQ", "===== ARBITRATION LOST SEQUENCE COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif