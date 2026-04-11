`ifndef REG_BASE_SEQ_SV
`define REG_BASE_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// =============================================================================
// reg_base_seq
// =============================================================================
// Base sequence with write_reg / read_reg helper tasks.
// All reg_* sequences extend this.
// =============================================================================

class reg_base_seq extends uvm_sequence #(reg_transaction);
  `uvm_object_utils(reg_base_seq)

  function new(string name = "reg_base_seq");
    super.new(name);
  endfunction

  // -- Helper: write a register -----------------------------
  task write_reg(input bit [7:0] addr, input bit [7:0] data);
    reg_transaction t;
    t = reg_transaction::type_id::create("t_wr");
    t.kind  = REG_WRITE;
    t.addr  = addr;
    t.wdata = data;

    start_item(t);
    finish_item(t);

    if (!t.success)
      `uvm_error("REG_WRITE", $sformatf("Write to 0x%02h FAILED", addr))
  endtask

  // -- Helper: read a register ------------------------------
  task read_reg(input bit [7:0] addr, output bit [7:0] data);
    reg_transaction t;
    t = reg_transaction::type_id::create("t_rd");
    t.kind = REG_READ;
    t.addr = addr;

    start_item(t);
    finish_item(t);

    data = t.rdata;

    if (!t.success)
      `uvm_error("REG_READ", $sformatf("Read from 0x%02h FAILED", addr))
  endtask

  // Default empty body — subclasses override
  virtual task body();
    `uvm_warning("REG_BASE_SEQ", "Base sequence body() called — nothing to do")
  endtask

endclass : reg_base_seq

`endif // REG_BASE_SEQ_SV


// =============================================================================
// reg_init_seq
// =============================================================================
// Initializes the SJA1000 DUT into PeliCAN extended mode and exits reset.
// Mirrors what can_dut_init_seq does, but uses the reg_agent path.
// =============================================================================
`ifndef REG_INIT_SEQ_SV
`define REG_INIT_SEQ_SV

class reg_init_seq extends reg_base_seq;
  `uvm_object_utils(reg_init_seq)

  // Register addresses (PeliCAN mode)
  localparam byte MOD  = 8'h00;
  localparam byte CMD  = 8'h01;
  localparam byte SR   = 8'h02;
  localparam byte IR   = 8'h03;
  localparam byte IER  = 8'h04;
  localparam byte BTR0 = 8'h06;
  localparam byte BTR1 = 8'h07;
  localparam byte OCR  = 8'h08;
  localparam byte ACR0 = 8'h10;
  localparam byte AMR0 = 8'h14;
  localparam byte CDR  = 8'h1F;

  function new(string name = "reg_init_seq");
    super.new(name);
  endfunction

  task body();
    bit [7:0] rd;

    `uvm_info("REG_INIT", "Starting register-agent DUT init", UVM_LOW)

    // Step 1: Enter reset mode
    write_reg(MOD, 8'h01);

    // Step 2: Enable PeliCAN extended mode
    write_reg(CDR, 8'h80);

    // Step 3: Bus timing for ~3.125 Mbps @ 50MHz (matches CAN agent)
    write_reg(BTR0, 8'h00);
    write_reg(BTR1, 8'h14);

    // Step 4: Output control
    write_reg(OCR, 8'h1A);

    // Step 5: Acceptance filter — accept all
    write_reg(ACR0, 8'h00);
    write_reg(ACR0 + 1, 8'h00);
    write_reg(ACR0 + 2, 8'h00);
    write_reg(ACR0 + 3, 8'h00);
    write_reg(AMR0, 8'hFF);
    write_reg(AMR0 + 1, 8'hFF);
    write_reg(AMR0 + 2, 8'hFF);
    write_reg(AMR0 + 3, 8'hFF);

    // Step 6: Enable interrupts
    write_reg(IER, 8'hEF);

    // Step 7: Clear pending interrupts (read IR)
    read_reg(IR, rd);

    // Step 8: Exit reset mode
    write_reg(MOD, 8'h00);

    // Step 9: Verify DUT operational
    read_reg(SR, rd);
    if (rd[2] !== 1'b1)
      `uvm_error("REG_INIT",
        $sformatf("DUT not operational after init: SR=0x%02h", rd))
    else
      `uvm_info("REG_INIT",
        $sformatf("DUT operational: SR=0x%02h (TBS=1)", rd), UVM_LOW)

    `uvm_info("REG_INIT", "Register-agent DUT init COMPLETE", UVM_LOW)
  endtask

endclass : reg_init_seq

`endif // REG_INIT_SEQ_SV