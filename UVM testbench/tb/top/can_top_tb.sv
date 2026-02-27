`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

module can_top_tb;

  // -- Parameters -----------------------------------------------
  localparam int unsigned NUM_TB_NODES = 3;

  // -- Clocks ---------------------------------------------------
  bit clk_i = 0;
  always #10 clk_i = ~clk_i;  // 50MHz CAN clock

`ifdef CAN_WISHBONE_IF
  bit wb_clk_i = 0;
  always #5 wb_clk_i = ~wb_clk_i;  // 100MHz WB clock
`endif

  // -- Interface ------------------------------------------------
  can_if #(.NUM_TB_NODES(NUM_TB_NODES)) vif (.clk_i(clk_i)
`ifdef CAN_WISHBONE_IF
   ,.wb_clk_i(wb_clk_i)
`endif
  );

  // -- Reset ----------------------------------------------------
  initial begin
`ifdef CAN_WISHBONE_IF
    vif.wb_rst_i = 1'b1;
    repeat(10) @(posedge wb_clk_i);
    vif.wb_rst_i = 1'b0;
`else
    vif.rst_i = 1'b1;
    repeat(10) @(posedge clk_i);
    vif.rst_i = 1'b0;
`endif
  end

  // -- TB node default to recessive -----------------------------
  initial begin
    foreach(vif.tb_tx[i]) vif.tb_tx[i] = 1'b1;
  end

  // -- Wired-AND bus --------------------------------------------
  logic                    can_bus;
  logic [NUM_TB_NODES:0]   can_tx_all;

  always_comb begin
    can_tx_all[0] = vif.tx_o;
    for(int i = 0; i < NUM_TB_NODES; i++)
      can_tx_all[i+1] = vif.tb_tx[i];
  end

  assign can_bus  = &can_tx_all;
  assign vif.rx_i = can_bus;

  // -- DUT ------------------------------------------------------
  can_top dut (
`ifdef CAN_WISHBONE_IF
    .wb_clk_i  (vif.wb_clk_i),
    .wb_rst_i  (vif.wb_rst_i),
    .wb_dat_i  (vif.wb_dat_i),
    .wb_dat_o  (vif.wb_dat_o),
    .wb_cyc_i  (vif.wb_cyc_i),
    .wb_stb_i  (vif.wb_stb_i),
    .wb_we_i   (vif.wb_we_i),
    .wb_adr_i  (vif.wb_adr_i),
    .wb_ack_o  (vif.wb_ack_o),
`else
    .rst_i     (vif.rst_i),
    .ale_i     (vif.ale_i),
    .rd_i      (vif.rd_i),
    .wr_i      (vif.wr_i),
    .port_0_io (vif.port_0_io),
    .cs_can_i  (vif.cs_can_i),
`endif
    .clk_i     (clk_i),
    .rx_i      (vif.rx_i),
    .tx_o      (vif.tx_o),
    .bus_off_on(vif.bus_off_on),
    .irq_on    (vif.irq_on),
    .clkout_o  (vif.clkout_o)
  );

  // -- UVM start ------------------------------------------------
  initial begin
    uvm_config_db#(virtual can_if #(.NUM_TB_NODES(NUM_TB_NODES)))::set(
      null, "*", "vif", vif);
    uvm_root::get().set_report_verbosity_level_hier(UVM_LOW);
    run_test();  // Fix 1 — reads +UVM_TESTNAME from command line
  end

endmodule