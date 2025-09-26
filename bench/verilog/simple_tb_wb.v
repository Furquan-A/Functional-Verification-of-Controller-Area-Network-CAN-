
`timescale 1ns/1ps
// Compile with: +define+CAN_WISHBONE_IF
// Files needed: can_top.v, can_registers.v, can_btl.v, can_bsp.v, can_crc.v, can_acf.v, can_fifo.v,
//               can_register.v, can_register_asyn.v, can_register_syn.v, can_ibo.v, can_defines.v, timescale.v

module simple_tb_wb;

  // Clocks & reset
  reg clk = 0;
  always #10 clk = ~clk;  // 50 MHz core & WB clock
  reg rstn = 0;           // active-high reset_n for TB; DUT sees wb_rst_i = ~rstn (active-high)

  // CAN wired-AND bus (dominant=0 wins)
  wire tx0, tx1;
  wire can_bus = tx0 & tx1;
  wire rx_bus  = can_bus;

  // Wishbone signals for node0
  reg  [7:0] wb_adr0;  reg [7:0] wb_dat_i0; wire [7:0] wb_dat_o0;
  reg        wb_cyc0, wb_stb0, wb_we0;      wire wb_ack0;
  // Wishbone signals for node1
  reg  [7:0] wb_adr1;  reg [7:0] wb_dat_i1; wire [7:0] wb_dat_o1;
  reg        wb_cyc1, wb_stb1, wb_we1;      wire wb_ack1;

  // DUT IOs
  wire irq0, irq1;
  wire clkout0, clkout1;
  wire bus_off0_on, bus_off1_on;  // 'on' = NOT bus-off

  // ALC temp for initial block (declare here to avoid Verilog-2001 ordering rule)
  reg [7:0] alc1;

  // === Register addresses (per can_registers.v) ===
  localparam MODE      = 8'h00;
  localparam COMMAND   = 8'h01;
  localparam STATUS    = 8'h02;
  localparam IR        = 8'h03;
  localparam BTR0      = 8'h06;
  localparam BTR1      = 8'h07;
  localparam ALC       = 8'h0B;   // Arbitration Lost Capture
  localparam REC       = 8'h1D;   // Receive Error Counter (assumed)
  localparam TEC       = 8'h1E;   // Transmit Error Counter (assumed)
  localparam CLKDIV    = 8'h1F;

  // Extended-mode acceptance registers (valid while reset_mode==1)
  localparam ACR0_EX   = 8'h10;
  localparam ACR1_EX   = 8'h11;
  localparam ACR2_EX   = 8'h12;
  localparam ACR3_EX   = 8'h13;
  localparam AMR0_EX   = 8'h14;
  localparam AMR1_EX   = 8'h15;
  localparam AMR2_EX   = 8'h16;
  localparam AMR3_EX   = 8'h17;

  // TX buffer addrs (0x10..0x1C)
  localparam TX0 = 8'h10;  // Frame Info (DLC[7:4], RTR[1], IDE[0])
  localparam TX1 = 8'h11;  // ID[10:3] for standard frame
  localparam TX2 = 8'h12;  // ID[2:0] in [2:0] for standard frame
  localparam TX3 = 8'h13;
  localparam TX4 = 8'h14;
  localparam TX5 = 8'h15;  // Data byte 0
  localparam TX6 = 8'h16;  // Data byte 1
  localparam TX7 = 8'h17;
  localparam TX8 = 8'h18;
  localparam TX9 = 8'h19;
  localparam TXA = 8'h1A;
  localparam TXB = 8'h1B;
  localparam TXC = 8'h1C;

  //---------------- Node 0 ----------------
  can_top u0 (
    .wb_clk_i(clk), .wb_rst_i(~rstn),
    .wb_dat_i(wb_dat_i0), .wb_dat_o(wb_dat_o0),
    .wb_cyc_i(wb_cyc0), .wb_stb_i(wb_stb0), .wb_we_i(wb_we0),
    .wb_adr_i(wb_adr0), .wb_ack_o(wb_ack0),
    .clk_i(clk), .rx_i(rx_bus), .tx_o(tx0),
    .bus_off_on(bus_off0_on), .irq_on(irq0), .clkout_o(clkout0)
  );

  //---------------- Node 1 ----------------
  can_top u1 (
    .wb_clk_i(clk), .wb_rst_i(~rstn),
    .wb_dat_i(wb_dat_i1), .wb_dat_o(wb_dat_o1),
    .wb_cyc_i(wb_cyc1), .wb_stb_i(wb_stb1), .wb_we_i(wb_we1),
    .wb_adr_i(wb_adr1), .wb_ack_o(wb_ack1),
    .clk_i(clk), .rx_i(rx_bus), .tx_o(tx1),
    .bus_off_on(bus_off1_on), .irq_on(irq1), .clkout_o(clkout1)
  );

  // ---------- Simple WB tasks (single-beat) with logging ----------
  task wb_write0(input [7:0] a, input [7:0] d);
    begin
      @(posedge clk); wb_adr0<=a; wb_dat_i0<=d; wb_we0<=1; wb_cyc0<=1; wb_stb0<=1;
      wait (wb_ack0===1);
      $display("[%0t] WB0 WRITE  A=%02h D=%02h", $time, a, d);
      @(posedge clk); wb_cyc0<=0; wb_stb0<=0; wb_we0<=0;
    end
  endtask
  task wb_read0(input [7:0] a, output [7:0] d);
    begin
      @(posedge clk); wb_adr0<=a; wb_we0<=0; wb_cyc0<=1; wb_stb0<=1;
      wait (wb_ack0===1); d = wb_dat_o0;
      $display("[%0t] WB0 READ   A=%02h D=%02h", $time, a, d);
      @(posedge clk); wb_cyc0<=0; wb_stb0<=0;
    end
  endtask

  task wb_write1(input [7:0] a, input [7:0] d);
    begin
      @(posedge clk); wb_adr1<=a; wb_dat_i1<=d; wb_we1<=1; wb_cyc1<=1; wb_stb1<=1;
      wait (wb_ack1===1);
      $display("[%0t] WB1 WRITE  A=%02h D=%02h", $time, a, d);
      @(posedge clk); wb_cyc1<=0; wb_stb1<=0; wb_we1<=0;
    end
  endtask
  task wb_read1(input [7:0] a, output [7:0] d);
    begin
      @(posedge clk); wb_adr1<=a; wb_we1<=0; wb_cyc1<=1; wb_stb1<=1;
      wait (wb_ack1===1); d = wb_dat_o1;
      $display("[%0t] WB1 READ   A=%02h D=%02h", $time, a, d);
      @(posedge clk); wb_cyc1<=0; wb_stb1<=0;
    end
  endtask

  // ---------- Monitors ----------
  initial begin
    $display("[%0t] Starting simple_tb_wb", $time);
    $monitor("[%0t] bus_off0_on=%0b bus_off1_on=%0b irq0=%0b irq1=%0b tx0=%0b tx1=%0b",
             $time, bus_off0_on, bus_off1_on, irq0, irq1, tx0, tx1);
  end

  // ---------- Helpers ----------
  task config_node0_basic;
    reg [7:0] r;
    begin
      // Enter reset mode
      wb_write0(MODE, 8'h01);
      // Extended mode enable (bit7=1), clkout bypass (cd=111), clock not forced off (bit3=0)
      wb_write0(CLKDIV, 8'h80 | 8'h07);
      // Bit timing (example; adjust as needed)
      wb_write0(BTR0, 8'h41);  // SJW=1, BRP=1
      wb_write0(BTR1, 8'h56);  // TSEG2=5, TSEG1=6, SAM=0
      // Accept-all (extended set) while in reset
      wb_write0(ACR0_EX, 8'h00); wb_write0(ACR1_EX, 8'h00);
      wb_write0(ACR2_EX, 8'h00); wb_write0(ACR3_EX, 8'h00);
      wb_write0(AMR0_EX, 8'hFF); wb_write0(AMR1_EX, 8'hFF);
      wb_write0(AMR2_EX, 8'hFF); wb_write0(AMR3_EX, 8'hFF);
      // Clear error counters
      wb_write0(REC, 8'h00);
      wb_write0(TEC, 8'h00);
      // Exit reset → normal
      wb_write0(MODE, 8'h00);
      // Readback a couple
      wb_read0(STATUS, r);
      wb_read0(CLKDIV, r);
    end
  endtask

  task config_node1_basic;
    reg [7:0] r;
    begin
      wb_write1(MODE, 8'h01);
      wb_write1(CLKDIV, 8'h80 | 8'h05);
      wb_write1(BTR0, 8'h41);
      wb_write1(BTR1, 8'h56);
      wb_write1(ACR0_EX, 8'h00); wb_write1(ACR1_EX, 8'h00);
      wb_write1(ACR2_EX, 8'h00); wb_write1(ACR3_EX, 8'h00);
      wb_write1(AMR0_EX, 8'hFF); wb_write1(AMR1_EX, 8'hFF);
      wb_write1(AMR2_EX, 8'hFF); wb_write1(AMR3_EX, 8'hFF);
      wb_write1(REC, 8'h00);
      wb_write1(TEC, 8'h00);
      wb_write1(MODE, 8'h00);
      wb_read1(STATUS, r);
      wb_read1(CLKDIV, r);
    end
  endtask

  task node0_send_std_2B(input [10:0] id, input [7:0] d0, input [7:0] d1);
    reg [7:0] id_hi;
    reg [7:0] id_lo3;
    begin
      id_hi  = id[10:3];         // TX1
      id_lo3 = {5'b0, id[2:0]};  // TX2[2:0]
      // Frame info: DLC=2 (0x2 << 4), RTR=0, IDE=0 (standard)
      wb_write0(TX0, 8'h20);
      wb_write0(TX1, id_hi);
      wb_write0(TX2, id_lo3);
      wb_write0(TX5, d0);
      wb_write0(TX6, d1);
      // Request transmission
      wb_write0(COMMAND, 8'h01);
    end
  endtask

  // ---------- Stimulus ----------
  initial begin
    // init WB lines
    {wb_adr0, wb_dat_i0, wb_cyc0, wb_stb0, wb_we0} = 0;
    {wb_adr1, wb_dat_i1, wb_cyc1, wb_stb1, wb_we1} = 0;

    // reset pulse
    rstn = 0;
    repeat (10) @(posedge clk);
    rstn = 1;

    // Configure nodes
    config_node0_basic();
    config_node1_basic();

    // === Clean TX/RX: Node0 sends ID=0x123, 2 data bytes ===
    node0_send_std_2B(11'h123, 8'hDE, 8'hAD);

    // Wait some time for TX/RX to complete
    repeat (4000) @(posedge clk);

    // === Arbitration demo: Node0(ID=0x111) vs Node1(ID=0x222) ===
    // Prepare both while in reset, then start both together
    wb_write0(MODE, 8'h01); wb_write1(MODE, 8'h01);
    // keep timing & filters
    // Node0 frame: lower ID => should WIN
    wb_write0(TX0, 8'h20);
    wb_write0(TX1, 8'h22);  // 0x111 -> ID[10:3]=0x22
    wb_write0(TX2, 8'h01);  // ID[2:0]=1
    wb_write0(TX5, 8'hAA);  wb_write0(TX6, 8'h55);
    // Node1 frame: higher ID => should LOSE
    wb_write1(TX0, 8'h20);
    wb_write1(TX1, 8'h44);  // 0x222 -> ID[10:3]=0x44
    wb_write1(TX2, 8'h02);  // ID[2:0]=2
    wb_write1(TX5, 8'h11);  wb_write1(TX6, 8'h22);
    // Exit reset and request both
    wb_write0(MODE, 8'h00); wb_write1(MODE, 8'h00);
    @(posedge clk);
    wb_write0(COMMAND, 8'h01);
    wb_write1(COMMAND, 8'h01);

    // Read Arbitration Lost Capture from Node1 (should be non-zero)
    wb_read1(ALC, alc1);
    $display("[%0t] Node1 ALC=%02h (nonzero => lost arbitration)", $time, alc1);

    repeat (4000) @(posedge clk);
    $display("[%0t] DONE.", $time);
    $finish;
  end

endmodule
