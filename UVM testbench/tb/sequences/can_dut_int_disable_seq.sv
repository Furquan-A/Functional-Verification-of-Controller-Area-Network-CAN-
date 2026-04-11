`ifndef CAN_DUT_INT_DISABLE_SEQ_SV
`define CAN_DUT_INT_DISABLE_SEQ_SV

class can_dut_int_disable_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_int_disable_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // node1 sends a valid frame in RX-disable scenario
  uvm_sequencer #(can_transaction) node1_sqr;

  // Public results
  bit tx_int_dis_ok;
  bit rx_int_dis_ok;
  bit tx_event_seen;
  bit rx_event_seen;

  // PeliCAN register map
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;
  localparam byte IR    = 8'h03; // read-to-clear
  localparam byte IER   = 8'h04;
  localparam byte ECC   = 8'h0C; // read-to-clear
  localparam byte RXERR = 8'h0E;
  localparam byte TXERR = 8'h0F;

  localparam byte TX_FI  = 8'h10;
  localparam byte TX_ID1 = 8'h11;
  localparam byte TX_ID2 = 8'h12;
  localparam byte TX_D0  = 8'h13;

  // IR / IER bits
  localparam int RI_BIT = 0;
  localparam int TI_BIT = 1;

  // SR bits
  localparam int SR_RBS = 0;
  localparam int SR_TBS = 2;

  function new(string name = "can_dut_int_disable_seq");
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
    `uvm_info("INT_DIS_SEQ",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic soft_reset_cycle();
    byte unsigned mod;

    vif.reg_read(MOD, mod);
    mod[0] = 1'b1;
    vif.reg_write(MOD, mod);
    #2us;

    vif.reg_read(MOD, mod);
    mod[0] = 1'b0;
    vif.reg_write(MOD, mod);
    #2us;

    clear_status_regs();
  endtask

  task automatic clear_status_regs();
    byte unsigned dummy;
    vif.reg_read(IR,  dummy);
    vif.reg_read(ECC, dummy);
  endtask

  task automatic clear_rx_buffer_if_needed();
    byte unsigned sr;
    int unsigned  tries;

    tries = 0;
    vif.reg_read(SR, sr);

    while (sr[SR_RBS] && (tries < 20)) begin
      vif.reg_write(CMR, 8'h04); // RRB
      #500ns;
      vif.reg_read(SR, sr);
      tries++;
    end
  endtask

  task automatic load_tx_frame(bit [10:0] id11, byte unsigned data0);
    vif.reg_write(TX_FI,  8'h01);             // STD DATA, DLC=1
    vif.reg_write(TX_ID1, {id11[10:3]});
    vif.reg_write(TX_ID2, {id11[2:0], 5'b0});
    vif.reg_write(TX_D0,  data0);
  endtask

  task automatic set_ier_bits(bit rie, bit tie);
    byte unsigned ier_val;
    vif.reg_read(IER, ier_val);
    ier_val[RI_BIT] = rie;
    ier_val[TI_BIT] = tie;
    vif.reg_write(IER, ier_val);
    vif.reg_read(IER, ier_val);
    `uvm_info("INT_DIS_SEQ",
      $sformatf("IER programmed to 0x%02h (RIE=%0b TIE=%0b)",
                ier_val, ier_val[RI_BIT], ier_val[TI_BIT]),
      UVM_LOW)
  endtask

  task automatic send_node1_valid_frame();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    start_item(tr, -1, node1_sqr);
    assert(tr.randomize() with {
      can_fmt         == `CAN_ID_STD;
      id              == 11'h301;
      dlc             == 4'd8;
      f_type          == `CAN_DATA_FRAME;
      data.size()     == 8;
      data[0]         == 8'h10;
      data[1]         == 8'h20;
      data[2]         == 8'h30;
      data[3]         == 8'h40;
      data[4]         == 8'h50;
      data[5]         == 8'h60;
      data[6]         == 8'h70;
      data[7]         == 8'h80;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("INT_DIS_SEQ", "node1 valid TX randomization failed")
    finish_item(tr);
  endtask

  task automatic wait_tx_cycle_and_watch_irq(
    input  time  timeout,
    input  logic irq_baseline,
    output bit   tx_done,
    output bit   irq_toggled
  );
    byte unsigned sr;
    time          start_t;
    bit           saw_busy;

    tx_done      = 1'b0;
    irq_toggled  = 1'b0;
    saw_busy     = 1'b0;
    start_t      = $time;

    while (($time - start_t) < timeout) begin
      vif.reg_read(SR, sr);

      if (!sr[SR_TBS])
        saw_busy = 1'b1;

      if (saw_busy && sr[SR_TBS]) begin
        tx_done = 1'b1;
        return;
      end

      if (vif.irq_on !== irq_baseline)
        irq_toggled = 1'b1;

      #100ns;
    end
  endtask

  task automatic wait_rbs_and_watch_irq(
    input  time  timeout,
    input  logic irq_baseline,
    output bit   rx_done,
    output bit   irq_toggled
  );
    byte unsigned sr;
    time          start_t;

    rx_done      = 1'b0;
    irq_toggled  = 1'b0;
    start_t      = $time;

    while (($time - start_t) < timeout) begin
      vif.reg_read(SR, sr);

      if (sr[SR_RBS]) begin
        rx_done = 1'b1;
        return;
      end

      if (vif.irq_on !== irq_baseline)
        irq_toggled = 1'b1;

      #100ns;
    end
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
    bit           irq_baseline;
    bit           irq_toggled;
    bit           tx_done;
    bit           rx_done;

    if (vif == null)
      `uvm_fatal("INT_DIS_SEQ", "vif is null -- set from test")

    if (node1_sqr == null)
      `uvm_fatal("INT_DIS_SEQ", "node1_sqr is null -- set from test")

    tx_int_dis_ok = 1'b0;
    rx_int_dis_ok = 1'b0;
    tx_event_seen = 1'b0;
    rx_event_seen = 1'b0;

    // Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end
    `uvm_info("INT_DIS_SEQ", "DUT initialised", UVM_LOW)

    force_dut_normal_mode();
    clear_status_regs();
    clear_rx_buffer_if_needed();

    // =========================================================================
    // Scenario 1: TX interrupt disabled
    // Trigger a successful DUT transmission and prove irq_on does not assert.
    // =========================================================================
    `uvm_info("INT_DIS_SEQ",
      "Scenario 1: TX interrupt disabled, successful DUT TX must not toggle irq_on",
      UVM_LOW)

    set_ier_bits(1'b0, 1'b0);
    clear_status_regs();
    #2us;

    irq_baseline = vif.irq_on;

    load_tx_frame(11'h201, 8'h5A);
    vif.reg_write(CMR, 8'h01); // TR

    wait_tx_cycle_and_watch_irq(200us, irq_baseline, tx_done, irq_toggled);

    begin
      bit late_irq_toggled;
      watch_irq_only(10us, irq_baseline, late_irq_toggled);
      irq_toggled = irq_toggled | late_irq_toggled;
    end

    vif.reg_read(IR, ir_val); // informational only on this DUT

    if (tx_done) begin
      tx_event_seen = 1'b1;
      `uvm_info("INT_DIS_SEQ",
        $sformatf("S1 event seen: TX completed, IR=0x%02h, irq_toggled=%0b",
                  ir_val, irq_toggled),
        UVM_LOW)
    end
    else begin
      `uvm_error("INT_DIS_SEQ",
        $sformatf("FAIL S1: TX event not observed cleanly (tx_done=%0b IR=0x%02h)",
                  tx_done, ir_val))
    end

    if (tx_done && !irq_toggled) begin
      tx_int_dis_ok = 1'b1;
      `uvm_info("INT_DIS_SEQ",
        "PASS S1: TX interrupt disabled scenario closed",
        UVM_LOW)
    end
    else begin
      `uvm_error("INT_DIS_SEQ",
        $sformatf("FAIL S1: TX interrupt disabled check failed (tx_done=%0b irq_toggled=%0b IR=0x%02h)",
                  tx_done, irq_toggled, ir_val))
    end

    soft_reset_cycle();
    clear_rx_buffer_if_needed();

    // =========================================================================
    // Scenario 2: RX interrupt disabled
    // node1 sends a clean frame; DUT receives it; irq_on must not toggle.
    // =========================================================================
    `uvm_info("INT_DIS_SEQ",
      "Scenario 2: RX interrupt disabled, valid DUT receive must not toggle irq_on",
      UVM_LOW)

    set_ier_bits(1'b0, 1'b0);
    clear_status_regs();
    clear_rx_buffer_if_needed();
    #2us;

    irq_baseline = vif.irq_on;

    fork
      begin
        send_node1_valid_frame();
      end
    join_none

    wait_rbs_and_watch_irq(250us, irq_baseline, rx_done, irq_toggled);

    begin
      bit late_irq_toggled;
      watch_irq_only(10us, irq_baseline, late_irq_toggled);
      irq_toggled = irq_toggled | late_irq_toggled;
    end

    vif.reg_read(IR, ir_val); // informational only on this DUT

    if (rx_done) begin
      rx_event_seen = 1'b1;
      `uvm_info("INT_DIS_SEQ",
        $sformatf("S2 event seen: RX completed, IR=0x%02h, irq_toggled=%0b",
                  ir_val, irq_toggled),
        UVM_LOW)
    end
    else begin
      `uvm_error("INT_DIS_SEQ",
        $sformatf("FAIL S2: RX event not observed cleanly (rx_done=%0b IR=0x%02h)",
                  rx_done, ir_val))
    end

    if (rx_done && !irq_toggled) begin
      rx_int_dis_ok = 1'b1;
      `uvm_info("INT_DIS_SEQ",
        "PASS S2: RX interrupt disabled scenario closed",
        UVM_LOW)
    end
    else begin
      `uvm_error("INT_DIS_SEQ",
        $sformatf("FAIL S2: RX interrupt disabled check failed (rx_done=%0b irq_toggled=%0b IR=0x%02h)",
                  rx_done, irq_toggled, ir_val))
    end

    clear_rx_buffer_if_needed();

    `uvm_info("INT_DIS_SEQ",
      $sformatf("Summary: TX_INT_DIS=%0b RX_INT_DIS=%0b TX_EVENT=%0b RX_EVENT=%0b",
                tx_int_dis_ok, rx_int_dis_ok, tx_event_seen, rx_event_seen),
      UVM_LOW)

    `uvm_info("INT_DIS_SEQ", "===== INTERRUPT DISABLE SEQUENCE COMPLETE =====", UVM_LOW)
  endtask

endclass

`endif