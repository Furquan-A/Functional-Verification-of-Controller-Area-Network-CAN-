`ifndef CAN_DUT_BUS_OFF_SEQ_SV
`define CAN_DUT_BUS_OFF_SEQ_SV

class can_dut_bus_off_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_bus_off_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // Result flags for test
  bit           bus_off_reached;
  bit           recovery_done;
  bit           stalled_no_progress;
  int unsigned  bus_off_attempt;
  byte unsigned final_tec;
  byte unsigned final_rec;

  // PeliCAN registers
  localparam byte MOD   = 8'h00;
  localparam byte CMR   = 8'h01;
  localparam byte SR    = 8'h02;
  localparam byte IR    = 8'h03;
  localparam byte ECC   = 8'h0C;
  localparam byte RXERR = 8'h0E;
  localparam byte TXERR = 8'h0F;

  localparam byte TX_FI  = 8'h10;
  localparam byte TX_ID1 = 8'h11;
  localparam byte TX_ID2 = 8'h12;
  localparam byte TX_D0  = 8'h13;

  localparam int SR_TBS = 2;

  // Timing assumptions
  localparam time BIT_TIME = 320ns;

  // Tune this if needed
  localparam int EOF_JAM_OFFSET_BITS = 45;
  localparam int EOF_JAM_WIDTH_BITS  = 3;

  int unsigned max_attempts = 60;

  function new(string name = "can_dut_bus_off_seq");
    super.new(name);
  endfunction

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------

  task automatic release_node1();
    vif.tb_tx[1] = 1'b1; // recessive release
  endtask

  task automatic force_dut_normal_mode();
    byte unsigned mod;

    vif.reg_read(MOD, mod);

    // Enter reset mode first
    mod[0] = 1'b1; // RM=1
    vif.reg_write(MOD, mod);

    // Clear LOM / STM
    vif.reg_read(MOD, mod);
    mod[1] = 1'b0; // LOM=0
    mod[2] = 1'b0; // STM=0
    vif.reg_write(MOD, mod);

    // Exit reset mode
    mod[0] = 1'b0; // RM=0
    vif.reg_write(MOD, mod);

    vif.reg_read(MOD, mod);
    `uvm_info("BUS_OFF_SEQ",
      $sformatf("MOD after force_normal_mode = 0x%02h (RM=%0b LOM=%0b STM=%0b)",
                mod, mod[0], mod[1], mod[2]),
      UVM_LOW)
  endtask

  task automatic clear_stale_status();
    byte unsigned dummy;
    vif.reg_read(IR,  dummy);
    vif.reg_read(ECC, dummy);
  endtask

  task automatic wait_tbs(int unsigned timeout_iters = 20000);
    byte unsigned sr;
    int unsigned  t = 0;

    do begin
      vif.reg_read(SR, sr);
      if (sr[SR_TBS]) return;
      #100ns;
      t++;
    end while (t < timeout_iters);

    `uvm_fatal("BUS_OFF_SEQ", "Timeout waiting for SR.TBS=1")
  endtask

  task automatic wait_attempt_done(int unsigned timeout_iters = 8000);
    byte unsigned sr;
    int unsigned  t = 0;
    bit           saw_busy = 0;

    do begin
      vif.reg_read(SR, sr);

      if (!sr[SR_TBS])
        saw_busy = 1'b1;

      if (saw_busy && sr[SR_TBS])
        return;

      #100ns;
      t++;
    end while (t < timeout_iters);

    `uvm_warning("BUS_OFF_SEQ",
      "Timeout waiting for TX attempt completion (TBS low->high not fully observed)")
  endtask

  task automatic load_tx_frame(bit [10:0] id11, byte unsigned data0);
    vif.reg_write(TX_FI,  8'h01);             // FF=0 RTR=0 DLC=1
    vif.reg_write(TX_ID1, {id11[10:3]});
    vif.reg_write(TX_ID2, {id11[2:0], 5'b0});
    vif.reg_write(TX_D0,  data0);
  endtask

  // Dominant jam near ACK-delim / EOF to create transmit-side form error
  task automatic inject_form_error_once();
    release_node1();

    #(EOF_JAM_OFFSET_BITS * BIT_TIME);

    vif.tb_tx[1] = 1'b0; // dominant jam
    #(EOF_JAM_WIDTH_BITS * BIT_TIME);
    vif.tb_tx[1] = 1'b1; // release
  endtask

  // ------------------------------------------------------------
  // Main
  // ------------------------------------------------------------

  task body();
    byte unsigned tec, rec, mod;
    byte unsigned prev_tec;
    int unsigned  stagnant_count;
    int unsigned  attempt;
    int unsigned  poll_us;

    if (vif == null)
      `uvm_fatal("BUS_OFF_SEQ", "vif is null -- set from test")

    bus_off_reached    = 1'b0;
    recovery_done      = 1'b0;
    stalled_no_progress= 1'b0;
    bus_off_attempt    = 0;
    final_tec          = 8'h00;
    final_rec          = 8'h00;

    release_node1();

    // 1) Init DUT
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end
    `uvm_info("BUS_OFF_SEQ", "DUT initialised", UVM_LOW)

    // 2) Force normal mode
    force_dut_normal_mode();

    // 3) Clear stale status
    clear_stale_status();

    // 4) Baseline
    vif.reg_read(MOD,   mod);
    vif.reg_read(TXERR, tec);
    vif.reg_read(RXERR, rec);

    `uvm_info("BUS_OFF_SEQ",
      $sformatf("Baseline: MOD=0x%02h TEC=%0d REC=%0d bus_off_on=%0b",
                mod, tec, rec, vif.bus_off_on),
      UVM_LOW)

    // 5) Repeated DUT TX + external jam
    prev_tec       = tec;
    stagnant_count = 0;
    attempt        = 0;

    while (!bus_off_reached && (attempt < max_attempts)) begin
      attempt++;

      wait_tbs(20000);
      clear_stale_status();
      release_node1();

      load_tx_frame(11'h555, 8'h55);

      fork
        begin : jam_thread
          inject_form_error_once();
        end
      join_none

      vif.reg_write(CMR, 8'h03); // TR + AT

      wait_attempt_done(8000);
      #10us;
      release_node1();

      vif.reg_read(TXERR, tec);
      vif.reg_read(RXERR, rec);

      `uvm_info("BUS_OFF_SEQ",
        $sformatf("Attempt %0d: TEC=%0d REC=%0d bus_off_on=%0b",
                  attempt, tec, rec, vif.bus_off_on),
        UVM_LOW)

      if (!vif.bus_off_on) begin
        bus_off_reached = 1'b1;
        bus_off_attempt = attempt;

        vif.reg_read(MOD, mod);
        `uvm_info("BUS_OFF_SEQ",
          $sformatf("BUS-OFF snapshot: MOD=0x%02h (RM=%0b) TEC=%0d REC=%0d",
                    mod, mod[0], tec, rec),
          UVM_LOW)

        `uvm_info("BUS_OFF_SEQ",
          $sformatf("*** bus_off_on=0 at attempt %0d -- BUS-OFF achieved ***",
                    attempt),
          UVM_LOW)
        break;
      end

      if (tec == prev_tec)
        stagnant_count++;
      else
        stagnant_count = 0;

      prev_tec = tec;

      if (stagnant_count >= 4) begin
        stalled_no_progress = 1'b1;
        `uvm_warning("BUS_OFF_SEQ",
          $sformatf("TEC stopped progressing for %0d attempts (TEC=%0d). Tune EOF_JAM_OFFSET_BITS, current=%0d",
                    stagnant_count, tec, EOF_JAM_OFFSET_BITS))
      end
    end

    // 6) Bus-off entry result
    if (!bus_off_reached) begin
      vif.reg_read(TXERR, final_tec);
      vif.reg_read(RXERR, final_rec);

      `uvm_error("BUS_OFF_SEQ",
        $sformatf("Bus-off NOT achieved after %0d attempts. Final TEC=%0d REC=%0d bus_off_on=%0b",
                  attempt, final_tec, final_rec, vif.bus_off_on))
      release_node1();
      return;
    end

    // 7) Recovery
    release_node1();
    #10us;

    // On this core, bus-off likely forces RM=1.
    // Software must clear RM to allow recovery to begin.
    vif.reg_read(MOD, mod);
    `uvm_info("BUS_OFF_SEQ",
      $sformatf("After bus-off: MOD=0x%02h (RM=%0b) bus_off_on=%0b",
                mod, mod[0], vif.bus_off_on),
      UVM_LOW)

    if (mod[0]) begin
      mod[0] = 1'b0;
      vif.reg_write(MOD, mod);
      `uvm_info("BUS_OFF_SEQ",
        "Requested exit from reset mode by clearing MOD.RM",
        UVM_LOW)
    end

    #2us;
    vif.reg_read(MOD, mod);
    `uvm_info("BUS_OFF_SEQ",
      $sformatf("Post-clear MOD=0x%02h (RM=%0b)", mod, mod[0]),
      UVM_LOW)

    `uvm_info("BUS_OFF_SEQ",
      "Waiting for recovery (128 bus-free -> bus_off_on returning HIGH)...",
      UVM_LOW)

    poll_us = 0;
    while (!vif.bus_off_on && (poll_us < 3000)) begin
      #1us;
      poll_us++;
    end

    if (vif.bus_off_on) begin
      recovery_done = 1'b1;
      `uvm_info("BUS_OFF_SEQ",
        $sformatf("Recovery complete: bus_off_on=1 after %0dus", poll_us),
        UVM_LOW)
    end
    else begin
      recovery_done = 1'b0;
      vif.reg_read(MOD, mod);
      `uvm_warning("BUS_OFF_SEQ",
        $sformatf("Recovery window expired: bus_off_on=%0b MOD=0x%02h (RM=%0b)",
                  vif.bus_off_on, mod, mod[0]))
    end

    // 8) Final snapshot
    vif.reg_read(TXERR, final_tec);
    vif.reg_read(RXERR, final_rec);

    `uvm_info("BUS_OFF_SEQ",
      $sformatf("Final snapshot: TEC=%0d REC=%0d bus_off_on=%0b",
                final_tec, final_rec, vif.bus_off_on),
      UVM_LOW)

    if (recovery_done && (final_rec !== 8'd0))
      `uvm_warning("BUS_OFF_SEQ",
        $sformatf("REC=%0d after recovery; expected 0 in many implementations",
                  final_rec))

    `uvm_info("BUS_OFF_SEQ", "===== BUS-OFF SEQUENCE COMPLETE =====", UVM_LOW)

    release_node1();
  endtask

endclass

`endif