+incdir+./rtl
+incdir+./tb
+incdir+./tb/pkg
+incdir+./tb/can_interface
+incdir+./tb/agents/can_agent
+incdir+./tb/env


./rtl/timescale.v
./rtl/can_registers.v
./rtl/can_register.v
./rtl/can_register_asyn.v
./rtl/can_register_asyn_syn.v

./rtl/can_btl.v
./rtl/can_bsp.v
./rtl/can_crc.v
./rtl/can_fifo.v
./rtl/can_ibo.v
./rtl/can_acf.v

./rtl/can_top.v

./tb/interfaces/can_if.sv
./tb/pkg/can_pkg.sv
//./tb/sequences/can_tx_seq.sv

./tb/top/can_top_tb.sv
