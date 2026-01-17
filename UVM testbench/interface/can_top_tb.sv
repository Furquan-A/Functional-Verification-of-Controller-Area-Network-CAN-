// can_top_tb.sv
`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*; // your env/sequences live here

module can_top_tb;

  // ---------------- Clocks ----------------
  bit clk_i = 0;
  always #10 clk_i = ~clk_i; // 50 MHz

`ifdef CAN_WISHBONE_IF
  bit wb_clk_i = 0;
  always #10 wb_clk_i = ~wb_clk_i; // 50 MHz (adjust if different)
`endif

  // ------------- Interface ----------------
  can_if vif (
    .clk_i(clk_i)
`ifdef CAN_WISHBONE_IF
   ,.wb_clk_i(wb_clk_i)
`endif
  );

  // ---------------- Reset -----------------
  initial begin
`ifdef CAN_WISHBONE_IF
    vif.wb_rst_i = 1'b1;
    repeat (10) @(posedge wb_clk_i);
    vif.wb_rst_i = 1'b0;
`else
    vif.rst_i = 1'b1;
    repeat (10) @(posedge clk_i);
    vif.rst_i = 1'b0;
`endif
  end

  // Classical CAN: wired-AND (dominant=0 wins).
  // Use '1 as recessive default. Any node driving 0 forces bus to 0.
  localparam int unsigned NUM_TB_NODES = 2;  // <--- change as you like

  // Resolved bus and a combined vector including DUT
  logic can_bus;
  logic [NUM_TB_NODES:0] can_tx_all; // [0]=DUT, [1..]=TB nodes

  // Default TB nodes to recessive (released bus)
  initial vif.tb_tx = '1;

  // Combine all drivers (wired-AND)
  always_comb begin
    can_tx_all[0] =  vif.tx_o; // DUT drives the bus
    for (int i = 0; i < NUM_TB_NODES; i++) begin
      can_tx_all[i+1] = vif.tb_tx[i];
    end
  end

  assign can_bus = &can_tx_all; // AND reduction => wired-AND
 assign vif.rx_i = can_bus;    // Everyone samples the resolved bus
  
  // --------------- DUT --------------------
  can_top dut (
`ifdef CAN_WISHBONE_IF
    .wb_clk_i (vif.wb_clk_i),
    .wb_rst_i (vif.wb_rst_i),
    .wb_dat_i (vif.wb_dat_i),
    .wb_dat_o (vif.wb_dat_o),
    .wb_cyc_i (vif.wb_cyc_i),
    .wb_stb_i (vif.wb_stb_i),
    .wb_we_i  (vif.wb_we_i),
    .wb_adr_i (vif.wb_adr_i),
    .wb_ack_o (vif.wb_ack_o),
`else
    .rst_i     (vif.rst_i),
    .ale_i     (vif.ale_i),
    .rd_i      (vif.rd_i),
    .wr_i      (vif.wr_i),
    .port_0_io (vif.port_0_io),
    .cs_can_i  (vif.cs_can_i),
`endif
    .clk_i     (vif.clk_i),
    .rx_i      (vif.rx_i),
    .tx_o      (vif.tx_o),
    .bus_off_on(vif.bus_off_on),
    .irq_on    (vif.irq_on),
    .clkout_o  (vif.clkout_o)
  );

  // ----------- Hand off to UVM -----------
  initial begin
    // If your agents use modports, you can also set those here specifically.
    // Generic handle works too if your components declare "virtual can_if".
    uvm_config_db#(virtual can_if)::set(null, "*", "vif", vif);
    uvm_root::get().set_report_verbosity_level_hier(UVM_LOW);
    run_test("can_smoke_test");
  end

  // -------- Optional Waves ---------------
  initial begin
    $dumpfile("can_top_tb.vcd");
    $dumpvars(0, can_top_tb);
  end

endmodule
