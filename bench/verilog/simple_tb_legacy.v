
`timescale 1ns/1ps
// Compile WITHOUT +define+CAN_WISHBONE_IF
// Files needed: can_top.v, can_registers.v, can_btl.v, can_bsp.v, can_crc.v, can_acf.v, can_fifo.v, can_register.v, can_register_asyn.v, can_register_syn.v, can_ibo.v, can_defines.v, timescale.v

module simple_tb_legacy;

  // Clocks & reset
  reg clk = 0; always #10 clk = ~clk;    // 50 MHz
  reg rst  = 1;

  // Legacy bus
  reg        cs0=0, cs1=0;
  reg        ale0=0, rd0=0, wr0=0;
  reg        ale1=0, rd1=0, wr1=0;
  tri [7:0]  port0;
  reg [7:0]  port0_drv; reg port0_en=0; assign port0 = port0_en ? port0_drv : 8'hZZ;

  // CAN wired-AND bus
  wire tx0, tx1;
  wire can_bus = tx0 & tx1;
  wire rx_bus  = can_bus;

  // Outputs
  wire irq0_n, irq1_n;
  wire bus_off0, bus_off1;
  wire clkout0, clkout1;

  // === Addresses (same as wishbone TB) ===
  localparam MODE      = 8'h00;
  localparam COMMAND   = 8'h01;
  localparam STATUS    = 8'h02;
  localparam IR        = 8'h03;
  localparam BTR0      = 8'h06;
  localparam BTR1      = 8'h07;
  localparam CLKDIV    = 8'h1F;
  localparam ACR0_EX   = 8'h10, ACR1_EX=8'h11, ACR2_EX=8'h12, ACR3_EX=8'h13;
  localparam AMR0_EX   = 8'h14, AMR1_EX=8'h15, AMR2_EX=8'h16, AMR3_EX=8'h17;
  localparam TX0 = 8'h10, TX1 = 8'h11, TX2 = 8'h12, TX3 = 8'h13, TX4 = 8'h14;
  localparam TX5 = 8'h15, TX6 = 8'h16, TX7 = 8'h17, TX8 = 8'h18, TX9 = 8'h19;
  localparam TXA = 8'h1A, TXB = 8'h1B, TXC = 8'h1C;

  // Node 0
  can_top u0 (
    .cs_can_i(cs0), .rst_i(rst), .ale_i(ale0), .rd_i(rd0), .wr_i(wr0), .port_0_io(port0),
    .clk_i(clk), .rx_i(rx_bus), .tx_o(tx0), .bus_off_on(bus_off0), .irq_on(irq0_n), .clkout_o(clkout0)
  );
  // Node 1
  can_top u1 (
    .cs_can_i(cs1), .rst_i(rst), .ale_i(ale1), .rd_i(rd1), .wr_i(wr1), .port_0_io(port0),
    .clk_i(clk), .rx_i(rx_bus), .tx_o(tx1), .bus_off_on(bus_off1), .irq_on(irq1_n), .clkout_o(clkout1)
  );

  // ----- Legacy bus tasks -----
  task p_write(input bit which, input [7:0] adr, input [7:0] data);
    begin
      // which: 0=node0, 1=node1
      @(posedge clk);
      port0_en <= 1; port0_drv <= adr;
      if (!which) begin cs0<=1; ale0<=1; end else begin cs1<=1; ale1<=1; end
      @(posedge clk);
      ale0<=0; ale1<=0;
      port0_drv <= data;
      if (!which) wr0<=1; else wr1<=1;
      @(posedge clk);
      wr0<=0; wr1<=0;
      port0_en <= 0;
      cs0<=0; cs1<=0;
    end
  endtask

  task p_read(input bit which, input [7:0] adr, output [7:0] data);
    begin
      @(posedge clk);
      port0_en <= 1; port0_drv <= adr;
      if (!which) begin cs0<=1; ale0<=1; end else begin cs1<=1; ale1<=1; end
      @(posedge clk);
      ale0<=0; ale1<=0;
      port0_en <= 0; // tri-state to read
      if (!which) rd0<=1; else rd1<=1;
      @(posedge clk);
      data = port0;
      rd0<=0; rd1<=0;
      cs0<=0; cs1<=0;
    end
  endtask

  // ----- Stimulus -----
  initial begin
    // reset
    repeat (5) @(posedge clk);
    rst = 1;
    repeat (5) @(posedge clk);
    rst = 0;  // active-high per your top? (adjust if needed)
    repeat (5) @(posedge clk);
    rst = 1;

    // Node 0 config (reset mode)
    p_write(0, MODE,   8'h01);
    p_write(0, CLKDIV, 8'h80 | 8'h07);
    p_write(0, BTR0,   8'h41);
    p_write(0, BTR1,   8'h56);
    p_write(0, ACR0_EX,8'h00); p_write(0, ACR1_EX,8'h00);
    p_write(0, ACR2_EX,8'h00); p_write(0, ACR3_EX,8'h00);
    p_write(0, AMR0_EX,8'hFF); p_write(0, AMR1_EX,8'hFF);
    p_write(0, AMR2_EX,8'hFF); p_write(0, AMR3_EX,8'hFF);
    p_write(0, MODE,   8'h00); // normal

    // Node 1 config (reset mode)
    p_write(1, MODE,   8'h01);
    p_write(1, CLKDIV, 8'h80 | 8'h07);
    p_write(1, BTR0,   8'h41);
    p_write(1, BTR1,   8'h56);
    p_write(1, ACR0_EX,8'h00); p_write(1, ACR1_EX,8'h00);
    p_write(1, ACR2_EX,8'h00); p_write(1, ACR3_EX,8'h00);
    p_write(1, AMR0_EX,8'hFF); p_write(1, AMR1_EX,8'hFF);
    p_write(1, AMR2_EX,8'hFF); p_write(1, AMR3_EX,8'hFF);
    p_write(1, MODE,   8'h00);

    // Prepare TX on node 0 (layout may need tweaks per core mapping)
    p_write(0, TX0, 8'h02);  // DLC=2
    p_write(0, TX1, 8'h24);  // ID bytes (placeholder)
    p_write(0, TX2, 8'h60);
    p_write(0, TX3, 8'h00);
    p_write(0, TX4, 8'h00);
    p_write(0, TX5, 8'hDE);
    p_write(0, TX6, 8'hAD);

    // Fire transmit
    p_write(0, COMMAND, 8'h01);

    repeat (2000) @(posedge clk);
    $finish;
  end

  // Monitors
  initial begin
    $monitor("[%0t] irq0_n=%b irq1_n=%b bus_off0=%b bus_off1=%b tx0=%b tx1=%b",
             $time, irq0_n, irq1_n, bus_off0, bus_off1, tx0, tx1);
  end

endmodule
