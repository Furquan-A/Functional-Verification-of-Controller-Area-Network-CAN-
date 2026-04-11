`ifndef CAN_DUT_INIT_SEQ_SV
`define CAN_DUT_INIT_SEQ_SV

class can_dut_init_seq extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(can_dut_init_seq)

  // ── Virtual interface — set from test ────────────────────────
  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // ── Register addresses (PeliCAN mode) ────────────────────────
  localparam byte MOD  = 8'h00;  // Mode Register
  localparam byte CMD  = 8'h01;  // Command Register
  localparam byte SR   = 8'h02;  // Status Register
  localparam byte IR   = 8'h03;  // Interrupt Register
  localparam byte IER  = 8'h04;  // Interrupt Enable Register
  localparam byte BTR0 = 8'h06;  // Bus Timing Register 0
  localparam byte BTR1 = 8'h07;  // Bus Timing Register 1
  localparam byte CDR  = 8'h1F;  // Clock Divider Register

  // ── Acceptance filter registers (PeliCAN extended mode) ──────
  localparam byte ACR0 = 8'h10;  // Acceptance Code Register 0
  localparam byte ACR1 = 8'h11;  // Acceptance Code Register 1
  localparam byte ACR2 = 8'h12;  // Acceptance Code Register 2
  localparam byte ACR3 = 8'h13;  // Acceptance Code Register 3
  localparam byte AMR0 = 8'h14;  // Acceptance Mask Register 0
  localparam byte AMR1 = 8'h15;  // Acceptance Mask Register 1
  localparam byte AMR2 = 8'h16;  // Acceptance Mask Register 2
  localparam byte AMR3 = 8'h17;  // Acceptance Mask Register 3

  // ── Baud rate config ─────────────────────────────────────────
  // Target: ~1 Mbps at 50 MHz CAN clock (fast sim)
  //   BTR0 = 0x00 → BRP=0  → tq = 2*(0+1)/50MHz = 40ns
  //                  SJW=0  → SJW = 1 tq
  //   BTR1 = 0x14 → TSEG1=4 → 5 tq,  TSEG2=1 → 2 tq,  SAM=0
  //   Bit time = (1 + 5 + 2) * 40ns = 320ns  (~3.125 Mbps)
  //
  // NOTE: Agent bit_time_ns and sample_point_pct MUST match these
  //       values.  The DUT integration test sets them in build_phase.
  //       Sync + TSEG1 = 6 tq → sample point = 6/8 = 75 %
  localparam byte BTR0_VAL = 8'h00;  // SJW=0(1tq)  BRP=0(tq=40ns)
  localparam byte BTR1_VAL = 8'h14;  // SAM=0 TSEG2=1(2tq) TSEG1=4(5tq)

  function new(string name = "can_dut_init_seq");
    super.new(name);
  endfunction

  task body();
    byte unsigned rdata;

    if (vif == null)
      `uvm_fatal("DUT_INIT","vif is null — set from test")

    `uvm_info("DUT_INIT","Starting DUT initialization sequence", UVM_LOW)

    // ── Step 1: Assert reset mode ─────────────────────────────
    vif.wb_write(MOD, 8'h01);
    `uvm_info("DUT_INIT","Step 1: Reset mode asserted (MOD=0x01)", UVM_LOW)

    // ── Step 2: Enable PeliCAN extended mode ──────────────────
    vif.wb_write(CDR, 8'h80);
    `uvm_info("DUT_INIT","Step 2: PeliCAN mode enabled (CDR=0x80)", UVM_LOW)

    // ── Step 3: Configure baud rate ───────────────────────────
    vif.wb_write(BTR0, BTR0_VAL);
    vif.wb_write(BTR1, BTR1_VAL);
    `uvm_info("DUT_INIT",
      $sformatf("Step 3: Baud rate configured BTR0=0x%0h BTR1=0x%0h",
                BTR0_VAL, BTR1_VAL),
      UVM_LOW)

    // ── Step 4: Configure acceptance filter — accept ALL ──────
    //   ACR = don't care,  AMR = 0xFF (all bits masked → accept all)
    vif.wb_write(ACR0, 8'h00);
    vif.wb_write(ACR1, 8'h00);
    vif.wb_write(ACR2, 8'h00);
    vif.wb_write(ACR3, 8'h00);
    vif.wb_write(AMR0, 8'hFF);
    vif.wb_write(AMR1, 8'hFF);
    vif.wb_write(AMR2, 8'hFF);
    vif.wb_write(AMR3, 8'hFF);
    `uvm_info("DUT_INIT","Step 4: Acceptance filter set to accept ALL frames", UVM_LOW)

    // ── Step 5: Enable interrupts (RX + TX + error) ───────────
    //   IER[0] = RI  (Receive Interrupt)
    //   IER[1] = TI  (Transmit Interrupt)
    //   IER[2] = EI  (Error Warning Interrupt)
    //   IER[3] = DOI (Data Overrun Interrupt)
    //   IER[7] = BEI (Bus Error Interrupt)
    vif.wb_write(IER, 8'hEF);  // added EPIE(bit5) + ALIE(bit6): 0x8F | 0x20 | 0x40 = 0xEF
      `uvm_info("DUT_INIT","Step 5: Interrupts enabled (IER=0xEF)", UVM_LOW)

    // ── Step 6: Clear pending interrupts ──────────────────────
    vif.wb_read(IR, rdata);
    `uvm_info("DUT_INIT",
      $sformatf("Step 6: Interrupt register cleared IR=0x%0h", rdata),
      UVM_LOW)

    // ── Step 7: Exit reset mode → DUT operational ─────────────
    vif.wb_write(MOD, 8'h00);
    `uvm_info("DUT_INIT","Step 7: Reset mode released (MOD=0x00)", UVM_LOW)

    // ── Step 8: Verify DUT is operational ─────────────────────
    #1us;

    vif.wb_read(SR, rdata);
    `uvm_info("DUT_INIT",
      $sformatf("Step 8: Status Register SR=0x%0h", rdata),
      UVM_LOW)

    if (rdata[2] !== 1'b1)
      `uvm_error("DUT_INIT",
        $sformatf("DUT not operational — TBS bit not set SR=0x%0h", rdata))
    else
      `uvm_info("DUT_INIT",
        "PASS: DUT operational — TBS=1 TX buffer free",
        UVM_LOW)

    `uvm_info("DUT_INIT","DUT initialization complete", UVM_LOW)

  endtask

endclass
`endif
