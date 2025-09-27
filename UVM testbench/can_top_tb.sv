`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

module can_top_tb;


//----clock generation ----------
bit clk_i = 0;
always #10 clk_i = ~clk_i; // 50 MHz

`ifdef CAN_WISHBONE_IF
bit wb_clk_i = 0;
always #10 wb_clk_i = ~ wb_clk_i;
`endif // we dont have any clock in the legacy mode. So no `else case 

// ------- Interface Instantiation-----
can_if vif(clk_i
`ifdef CAN_WISHBONE_IF
,wb_clk_i
`endif 
);


//--------------DUT Instantiation-------
can_top dut(
`ifdef CAN_WISHBONE_IF
.wb_clk_i(vif.wb_clk_i),
.wb_rst_i(vif.wb_rst_i),
.wb_dat_i(vif.wb_dat_i),
.wb_dat_o(vif.wb_dat_o),
.wb_cyc_i(vif.wb_cyc_i),
.wb_stb_i(vif.wb_stb_i),
.wb_we_i(vif.wb_we_i),
.wb_adr_i(vif.wb_adr_i),
.wb_ack_o(vif.wb_ack_o),
`else
.rst_i(vif.rst_i),
.ale_i(vif.ale_i),
.rd_i(vif.rd_i),
.wr_i(vif.wr_i),
.port_0_io(vif.port_0_io),
.cs_can_i(vif.cs_can_i);
`endif
.clk_i(vif.clk_i),
.rx_i(vif.rx_i),
.tx_o(vif.tx_o),
.bus_off_on(vif.bus_off_on),
.irq_on(vif.irq_on),
.clkout_o(vif.clkout_o);
)

// ---------- Set Interface in the config data_base------
initial begin 
uvm_config_db #(virtual can_if) :: set(null,"*","vif",vif);

// RUN Test 
run_test();
end 

// Optional dump waves 
initial begin 
$dumpfile("can_top_tb.vcd");
$dumpvars(0,can_top_tb);
end 


endmodule 