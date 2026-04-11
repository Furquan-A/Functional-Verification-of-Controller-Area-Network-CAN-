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
    run_test();
  end

endmodule

// =============================================================
// SVA Bind — MUST be outside module can_top_tb
// Signal names are internal wires of can_top — not vif.xxx
// rst is an internal wire: assign rst = wb_rst_i (WB mode)
//                          assign rst = rst_i    (8051 mode)
// =============================================================
bind can_top can_top_assertions u_can_top_assertions (
  .clk_i                    (clk_i),
  .rst                      (rst),
  .rx_i                     (rx_i),
  .tx_o                     (tx_o),
  .bus_off_on               (bus_off_on),
  .irq_on                   (irq_on),
  .clkout_o                 (clkout_o),
  .reset_mode               (reset_mode),
  .listen_only_mode         (listen_only_mode),
  .acceptance_filter_mode   (acceptance_filter_mode),
  .self_test_mode           (self_test_mode),
  .extended_mode            (extended_mode),
  .acceptance_code_0        (acceptance_code_0),
  .acceptance_code_1        (acceptance_code_1),
  .acceptance_code_2        (acceptance_code_2),
  .acceptance_code_3        (acceptance_code_3),
  .acceptance_mask_0        (acceptance_mask_0),
  .acceptance_mask_1        (acceptance_mask_1),
  .acceptance_mask_2        (acceptance_mask_2),
  .acceptance_mask_3        (acceptance_mask_3),
  .send_ack                 (send_ack),
  .node_bus_off             (node_bus_off),
  .error_status             (error_status),
  .tx_err_cnt               (tx_err_cnt),
  .rx_err_cnt               (rx_err_cnt),
  .error_warning_limit      (error_warning_limit),
  .node_error_passive       (node_error_passive),
  .node_error_active        (node_error_active),
  .tx_request               (tx_request),
  .abort_tx                 (abort_tx),
  .single_shot_transmission (single_shot_transmission),
  .tx_successful            (tx_successful),
  .self_rx_request          (self_rx_request),
  .overrun                  (overrun),
  .release_buffer           (release_buffer),
  .transmit_status          (transmit_status),
  .receive_status           (receive_status),
  .transmitting             (transmitting),
  .set_bus_error_irq        (set_bus_error_irq),
  .set_arbitration_lost_irq (set_arbitration_lost_irq),
  .arbitration_lost_capture  (arbitration_lost_capture),
  .error_passive_irq_en     (can_top.i_can_registers.error_passive_irq_en),
  .arbitration_lost_irq_en  (can_top.i_can_registers.arbitration_lost_irq_en),
  .bus_error_irq_en         (can_top.i_can_registers.bus_error_irq_en),
  .set_reset_mode           (set_reset_mode),
  .we                       (we),
  .rx_message_counter       (rx_message_counter),
  .sampled_bit              (sampled_bit),
  .error_capture_code       (error_capture_code),
  .hard_sync                (hard_sync),
  .sample_point             (sample_point),
  .go_rx_inter              (go_rx_inter),
  .rx_sync                  (rx_sync)
);