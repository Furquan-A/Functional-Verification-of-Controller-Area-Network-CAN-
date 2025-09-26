// can_if.sv — single interface for both modes
interface can_if (
  input  logic clk_i
`ifdef CAN_WISHBONE_IF
 ,input  logic wb_clk_i
`endif
);

  // -------- Always-present CAN pins --------
  logic rx_i;
  logic tx_o;
  logic bus_off_on;
  logic irq_on;
  logic clkout_o;

  // -------- Bus-specific pins --------
`ifdef CAN_WISHBONE_IF
  // Wishbone
  logic        wb_rst_i;
  logic [7:0]  wb_dat_i;
  logic [7:0]  wb_dat_o;
  logic        wb_cyc_i;
  logic        wb_stb_i;
  logic        wb_we_i;
  logic [7:0]  wb_adr_i;
  logic        wb_ack_o;

  clocking wb_cb @(posedge wb_clk_i);
    default input #1step output #1;
    output wb_cyc_i, wb_stb_i, wb_we_i, wb_adr_i, wb_dat_i;
    input  wb_ack_o, wb_dat_o;
  endclocking
`else
  // Legacy parallel
  logic        rst_i;
  logic        ale_i;
  logic        rd_i;
  logic        wr_i;
  tri   [7:0]  port_0_io;
  logic        cs_can_i;
`endif

  // -------- CAN-line clocking --------
  clocking can_cb @(posedge clk_i);
    default input #1step output #1;
    output rx_i;
    input  tx_o, irq_on, bus_off_on, clkout_o;
  endclocking

  // -------- Helper tasks --------
`ifdef CAN_WISHBONE_IF
  // Wishbone R/W
  task automatic wb_write(byte addr, byte data);
    wb_cb.wb_adr_i <= addr;  wb_cb.wb_dat_i <= data;
    wb_cb.wb_we_i  <= 1;     wb_cb.wb_cyc_i <= 1; wb_cb.wb_stb_i <= 1;
    @(posedge wb_clk_i iff wb_ack_o);
    wb_cb.wb_cyc_i <= 0; wb_cb.wb_stb_i <= 0; wb_cb.wb_we_i <= 0;
  endtask
  task automatic wb_read(byte addr, output byte data);
    wb_cb.wb_adr_i <= addr;  wb_cb.wb_we_i  <= 0;
    wb_cb.wb_cyc_i <= 1;     wb_cb.wb_stb_i <= 1;
    @(posedge wb_clk_i iff wb_ack_o);
    data = wb_dat_o;
    wb_cb.wb_cyc_i <= 0; wb_cb.wb_stb_i <= 0;
  endtask
`else
  // Legacy R/W
  task automatic legacy_write(byte addr, byte data);
    cs_can_i <= 1;  ale_i <= 1;  port_0_io <= addr;  @(posedge clk_i);
    ale_i    <= 0;  port_0_io <= data;                wr_i <= 1; @(posedge clk_i);
    wr_i     <= 0;  cs_can_i  <= 0;                   port_0_io <= 'z;
  endtask
  task automatic legacy_read(byte addr, output byte data);
    cs_can_i <= 1;  ale_i <= 1;  port_0_io <= addr;  @(posedge clk_i);
    ale_i    <= 0;  port_0_io <= 'z;                 rd_i <= 1; @(posedge clk_i);
    data = port_0_io; rd_i <= 0; cs_can_i <= 0;
  endtask
`endif

  // Mode-agnostic API for sequences
  task automatic reg_write(byte addr, byte data);
`ifdef CAN_WISHBONE_IF
    wb_write(addr, data);
`else
    legacy_write(addr, data);
`endif
  endtask

  task automatic reg_read(byte addr, output byte data);
`ifdef CAN_WISHBONE_IF
    wb_read(addr, data);
`else
    legacy_read(addr, data);
`endif
  endtask

  // CAN-line helpers
  parameter int BIT_HOLD_CYCLES = 20;
  task automatic drive_rx(bit b); can_cb.rx_i <= b; endtask
  task automatic hold_rx(bit b, int cycles = BIT_HOLD_CYCLES);
    can_cb.rx_i <= b; repeat (cycles) @(posedge clk_i);
  endtask

  // -------- Modports (relative to DUT) --------
`ifdef CAN_WISHBONE_IF
  modport dut (
    input  wb_clk_i, clk_i, wb_rst_i, wb_dat_i, wb_cyc_i, wb_stb_i, wb_we_i, wb_adr_i, rx_i,
    output wb_dat_o, wb_ack_o, tx_o, bus_off_on, irq_on, clkout_o
  );
`else
  modport dut (
    input  clk_i, rst_i, ale_i, rd_i, wr_i, cs_can_i, rx_i,
    inout  port_0_io,
    output tx_o, bus_off_on, irq_on, clkout_o
  );
`endif

  modport drv (clocking can_cb
`ifdef CAN_WISHBONE_IF
               , clocking wb_cb
`endif
  );
  modport mon (input clk_i, rx_i, tx_o, irq_on, bus_off_on, clkout_o
`ifdef CAN_WISHBONE_IF
               , wb_clk_i, wb_dat_o, wb_ack_o
`else
               , rst_i, ale_i, rd_i, wr_i, cs_can_i, port_0_io
`endif
  );

  // Optional banner
  localparam bit USE_WB =
`ifdef CAN_WISHBONE_IF
    1;
`else
    0;
`endif

  initial $display("[%0t] can_if built in %s mode",
                   $time, USE_WB ? "WISHBONE" : "LEGACY");

endinterface

interface can_if 