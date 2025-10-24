// can_if.sv — unified interface for Wishbone or Legacy (select via +define+CAN_WISHBONE_IF)
interface can_if (
  input  logic clk_i
`ifdef CAN_WISHBONE_IF
 ,input  logic wb_clk_i
`endif
);

  // ====== CAN pins (common) ======
  logic rx_i;          // to DUT (bus -> DUT)
  logic tx_o;          // from DUT (DUT -> bus)
  logic irq_on;        // from DUT
  logic bus_off_on;    // from DUT (1 = not bus-off)
  logic clkout_o;      // from DUT (matches can_top .clkout_o)

  // Optional CAN clocking (TB convenience)
  clocking can_cb @(posedge clk_i);
    default input #1step output #1step;
    output rx_i;
    input  tx_o, irq_on, bus_off_on, clkout_o;
  endclocking

`ifdef CAN_WISHBONE_IF
  // ====== WISHBONE signals (DUT is slave) ======
  logic        wb_rst_i;
  logic        wb_cyc_i, wb_stb_i, wb_we_i;
  logic [7:0]  wb_adr_i;
  logic [7:0]  wb_dat_i;
  logic [7:0]  wb_dat_o;
  logic        wb_ack_o;

  // Wishbone clocking block
  clocking wb_cb @(posedge wb_clk_i);
    default input #1step output #1step;
    output wb_rst_i, wb_cyc_i, wb_stb_i, wb_we_i, wb_adr_i, wb_dat_i;
    input  wb_dat_o, wb_ack_o;
  endclocking

  // ---- WB tasks ----
  task automatic wb_write (byte unsigned addr, byte unsigned data);
    int unsigned timeout = 0;
    @wb_cb;  wb_cb.wb_adr_i <= addr;
             wb_cb.wb_dat_i <= data;
             wb_cb.wb_we_i  <= 1'b1;
             wb_cb.wb_cyc_i <= 1'b1;
             wb_cb.wb_stb_i <= 1'b1;
    do begin
      @wb_cb; timeout++;
      if (timeout > 1000) $fatal(1, "WB write timeout @ addr=%02h", addr);
    end while (!wb_cb.wb_ack_o);
    @wb_cb;  wb_cb.wb_cyc_i <= 1'b0;
             wb_cb.wb_stb_i <= 1'b0;
             wb_cb.wb_we_i  <= 1'b0;
  endtask

  task automatic wb_read (byte unsigned addr, output byte unsigned data);
    int unsigned timeout = 0;
    @wb_cb;  wb_cb.wb_adr_i <= addr;
             wb_cb.wb_we_i  <= 1'b0;
             wb_cb.wb_cyc_i <= 1'b1;
             wb_cb.wb_stb_i <= 1'b1;
    do begin
      @wb_cb; timeout++;
      if (timeout > 1000) $fatal(1, "WB read timeout @ addr=%02h", addr);
    end while (!wb_cb.wb_ack_o);
    data = wb_cb.wb_dat_o; // sample on acked tick
    @wb_cb;  wb_cb.wb_cyc_i <= 1'b0;
             wb_cb.wb_stb_i <= 1'b0;
  endtask

`else
  // ====== LEGACY parallel bus ======
  logic       rst_i;
  logic       ale_i, rd_i, wr_i;
  logic       cs_can_i;

  // Tri-state multiplexed bus
  tri   [7:0] port_0_io;    // connect to DUT .port_0_io
  logic [7:0] port_0_o;     // TB driver
  logic       port_0_oe;    // TB output enable (1=drive)
  logic [7:0] port_0_i;     // sampled from bus

  // Tri-state bridge
  assign port_0_io = port_0_oe ? port_0_o : 'z;
  assign port_0_i  = port_0_io;

  // Legacy clocking block
  clocking lg_cb @(posedge clk_i);
    default input #1step output #1step;
    output rst_i, ale_i, rd_i, wr_i, cs_can_i, port_0_o, port_0_oe;
    input  port_0_i;
  endclocking

  // ---- LEGACY tasks ----
  // WRITE: address via ALE, then data via WR
  task automatic legacy_write (byte unsigned addr, byte unsigned data);
    @lg_cb;  lg_cb.cs_can_i  <= 1'b1;
             lg_cb.port_0_oe <= 1'b1;     // TB drives bus
             lg_cb.port_0_o  <= addr;
             lg_cb.ale_i     <= 1'b1;
    @lg_cb;  lg_cb.ale_i     <= 1'b0;     // latch address

    @lg_cb;  lg_cb.port_0_o  <= data;
             lg_cb.wr_i      <= 1'b1;
    @lg_cb;  lg_cb.wr_i      <= 1'b0;
             lg_cb.cs_can_i  <= 1'b0;
             lg_cb.port_0_oe <= 1'b0;     // release
  endtask
  
  // READ: address via ALE, release bus, RD to sample from DUT
  task automatic legacy_read (byte unsigned addr, output byte unsigned data);
    @lg_cb;  lg_cb.cs_can_i  <= 1'b1;
             lg_cb.port_0_oe <= 1'b1;
             lg_cb.port_0_o  <= addr;
             lg_cb.ale_i     <= 1'b1;
    @lg_cb;  lg_cb.ale_i     <= 1'b0;

    @lg_cb;  lg_cb.port_0_oe <= 1'b0;     // TB releases -> DUT drives
             lg_cb.rd_i      <= 1'b1;
    @lg_cb;  data            =  lg_cb.port_0_i; // sample during RD high
             lg_cb.rd_i      <= 1'b0;
             lg_cb.cs_can_i  <= 1'b0;
  endtask
`endif

  // -------- Mode-agnostic API for sequences --------
  task automatic reg_write (byte unsigned addr, byte unsigned data);
`ifdef CAN_WISHBONE_IF
    wb_write(addr, data);
`else
    legacy_write(addr, data);
`endif
  endtask

  task automatic reg_read (byte unsigned addr, output byte unsigned data);
`ifdef CAN_WISHBONE_IF
    wb_read(addr, data);
`else 
    legacy_read(addr, data);
`endif
  endtask

  // ---------------- MODPORTS ----------------
`ifdef CAN_WISHBONE_IF
  // DUT hookup (Wishbone)
  modport dut_wb (
    input  clk_i, wb_clk_i, wb_rst_i, wb_cyc_i, wb_stb_i, wb_we_i, wb_adr_i, wb_dat_i, rx_i,
    output wb_dat_o, wb_ack_o, tx_o, irq_on, bus_off_on, clkout_o,
    inout
  );
  // TB driver (Wishbone)
  modport wb_master (clocking wb_cb, output rx_i, input tx_o, irq_on, bus_off_on, clkout_o);
`else
  // DUT hookup (Legacy)
  modport dut_legacy (
    input  clk_i, rst_i, ale_i, rd_i, wr_i, cs_can_i, rx_i,
    inout  port_0_io,
    output tx_o, irq_on, bus_off_on, clkout_o
  );
  // TB driver (Legacy)
  modport lg_host (clocking lg_cb, output rx_i, input tx_o, irq_on, bus_off_on, clkout_o);
`endif

  // Passive monitor modport (common + per-bus)
`ifdef CAN_WISHBONE_IF
  modport monitor_all (
    input clk_i, wb_clk_i,
          rx_i, tx_o, irq_on, bus_off_on, clkout_o,
          wb_rst_i, wb_cyc_i, wb_stb_i, wb_we_i, wb_adr_i, wb_dat_i, wb_dat_o, wb_ack_o
  );
`else
  modport monitor_all (
    input clk_i,
          rx_i, tx_o, irq_on, bus_off_on, clkout_o,
          rst_i, ale_i, rd_i, wr_i, cs_can_i,
          port_0_i, port_0_o, port_0_oe, port_0_io
  );
`endif

  // Banner
  localparam bit USE_WB =
`ifdef CAN_WISHBONE_IF
    1;
`else
    0;
`endif

  initial $display("[%0t] can_if built in %s mode",
                   $time, USE_WB ? "WISHBONE" : "LEGACY");

endinterface : can_if
