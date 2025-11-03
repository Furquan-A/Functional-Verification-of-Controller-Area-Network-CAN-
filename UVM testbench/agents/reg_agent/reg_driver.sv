`ifndef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh";
import uvm_pkg::*;

class reg_driver extends uvm_driver#(reg_txn);
`uvm_component_utils(reg_driver)

virtual can_if vif;
reg_agent_config m_cfg;

int unsigned wr_cnt, rd_cnt, err_cnt;

function new(string name = "reg_driver", uvm_component parent);
super.new(name,parent);
endfunction 

function void build_phase(uvm_phase phase);
super.build_phase(phase);

if(!uvm_config_db#(reg_agent_config) :: get(this,"","m_cfg",m_cfg);
`uvm_fatal("REG_DRIVER", "cannot get the interface from reg_agent_config. Did you set() it ?")

string why;

if(!m_cfg.validate(why)) begin 
	`uvm_fatal("M_CFG",$sformatf("reg_agent_config invalid : %s", why))
end
vif = m_cfg.vif;
endfunction 

function void start_of_simulation_phase(uvm_phase phase);
super.start_of_simulation_phase(phase);
 `uvm_info("REG_DRV", $sformatf("Starting reg_driver (%s). %s",vif.USE_WB ? "WISHBONE" : "LEGACY",cfg.sprint()),UVM_LOW)
endfunction


task run_phase(uvm_phase phase);
reg_txn t;
forever begin 
seq_item_port.get_next_item(t);
if(t.is_write())
	do_write(t);
else
	do_read(t);
end 
endtask


task do_write(ref reg_txn t);
