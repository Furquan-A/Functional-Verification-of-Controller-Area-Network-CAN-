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
  localparam byte BTR0 = 8'h06;  // Bus Timing Register 0
  localparam byte BTR1 = 8'h07;  // Bus Timing Register 1
  localparam byte CDR  = 8'h1F;  // Clock Divider Register

  // ── Baud rate config ─────────────────────────────────────────
  // Target: 100kbps at 50MHz CAN clock
  // Prescaler = 24 (BTR0[5:0]) → tq = 2*(24+1)/50MHz = 1us
  // SJW = 1 (BTR0[7:6])
  // TSEG1 = 15 (BTR1[3:0])
  // TSEG2 = 7  (BTR1[6:4])
  // Bit time = (1 + TSEG1 + TSEG2) * tq = 23 * 1us ≈ 100kbps
  localparam byte BTR0_VAL = 8'h17;  // SJW=0(1tq) PRESC=23
  localparam byte BTR1_VAL = 8'h1C;  // TSEG2=3(4tq) TSEG1=12(13tq)

  function new(string name = "can_dut_init_seq");
    super.new(name);
  endfunction

  task body();
    byte unsigned rdata;

    if (vif == null)
      `uvm_fatal("DUT_INIT","vif is null — set from test")

    `uvm_info("DUT_INIT","Starting DUT initialization sequence", UVM_LOW)

    // ── Step 1: Assert reset mode ─────────────────────────────
    // MOD[0] = 1 → enter reset mode
    // Registers become writable in reset mode
    vif.wb_write(MOD, 8'h01);
    `uvm_info("DUT_INIT","Step 1: Reset mode asserted (MOD=0x01)", UVM_LOW)

    // ── Step 2: Enable PeliCAN extended mode ──────────────────
    // CDR[7] = 1 → extended mode (PeliCAN)
    // Must be done while in reset mode
    vif.wb_write(CDR, 8'h80);
    `uvm_info("DUT_INIT","Step 2: PeliCAN mode enabled (CDR=0x80)", UVM_LOW)

    // ── Step 3: Configure baud rate ───────────────────────────
    // Must be done while in reset mode
    vif.wb_write(BTR0, BTR0_VAL);
    vif.wb_write(BTR1, BTR1_VAL);
    `uvm_info("DUT_INIT",
      $sformatf("Step 3: Baud rate configured BTR0=0x%0h BTR1=0x%0h",
                BTR0_VAL, BTR1_VAL),
      UVM_LOW)

    // ── Step 4: Clear interrupts ──────────────────────────────
    vif.wb_read(IR, rdata);
    `uvm_info("DUT_INIT",
      $sformatf("Step 4: Interrupt register cleared IR=0x%0h", rdata),
      UVM_LOW)

    // ── Step 5: Exit reset mode → DUT becomes operational ─────
    // MOD[0] = 0 → normal operating mode
    vif.wb_write(MOD, 8'h00);
    `uvm_info("DUT_INIT","Step 5: Reset mode released (MOD=0x00)", UVM_LOW)

    // ── Step 6: Verify DUT is operational ─────────────────────
    // Allow DUT time to settle after reset release
    #1us;

    vif.wb_read(SR, rdata);
    `uvm_info("DUT_INIT",
      $sformatf("Step 6: Status Register SR=0x%0h", rdata),
      UVM_LOW)

    // SR[2] = TBS (TX Buffer Status) should be 1 — buffer free
    // SR[0] = RBS (RX Buffer Status) should be 0 — buffer empty
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