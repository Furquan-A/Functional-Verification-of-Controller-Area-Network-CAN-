`ifndef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_driver extends uvm_driver #(reg_txn);

`uvm_component_utils(reg_driver)

virtual can_if vif;
reg_agent_config m_cfg;

//--------UVM-FACTORY------------
`uvm_component_utils_begin(reg_driver)
	`uvm_field_object(m_cfg,           UVM_DEFAULT)
	`uvm_field_int   (check_enable,    UVM_DEFAULT)
	`uvm_field_int   (coverage_enable, UVM_DEFAULT)
	`uvm_field_int   (debug_mode,      UVM_DEFAULT)
`uvm_component_utils_end



// --------Stats/knobs----------
time total_latency = 0;
time min_latency = 0;
time max_latency = 0;
int unsigned num_writes = 0; // writes count 
int unsigned num_reads = 0; // reads count 
int unsigned num_errors = 0; // errors count 

//-------Local Flags------------
bit checks_enable = 1'b1;
bit coverage_enable = 1'b1;
bit debug_mode = 1'b0;

//------Constructor-------------
function new (string name = "reg_driver", uvm_component parent);
super.new(name,parent);
min_latency = 1s; // large sentinel
endfunction 

//------Build-------------------
function void build_phase(uvm_phase phase);
super.build_phase(phase);

if(!uvm_config_db#(reg_agent_config)::get(this,"","m_cfg",m_cfg)) 
	 `uvm_fatal("REG_DRV", "reg_agent_config not found in config_db (key='m_cfg')")
	 
string why;
if (!m_cfg.validate(why))
     `uvm_fatal("REG_DRV", $sformatf("reg_agent_config invalid: %s", why))

vif = m_cfg.vif;

// pull local flags from the m_cfg
check_enable = m_cfg.checks_enable;
coverage_enable = m_cfg.coverage_enable;
debug_mode = m_cfg.debug_mode;

`uvm_info("REG_DRV",$sformatf("Built reg_driver for %s bus", m_cfg.bus_name()),UVM_MEDIUM)

endfunction
  
  
function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    `uvm_info("REG_DRV", $sformatf("=== Register Driver ===\nBus: %s\nChecks:%0d Coverage:%0d Debug:%0d", m_cfg.bus_name(), checks_enable, coverage_enable, debug_mode),UVM_LOW)
	
endfunction

//-------------run_phase------------
task run_phase(uvm_phase phase);
`uvm_info("REG_DRIVER","Register Drive started ", UVM_MEDIUM)

forever begin 
reg_txn txn;
seq_item_port.get_next_item(txn);
txn.t_start = $time ;
drive_transaction(txn); // this is basically a send_to_dut() task 
txn.t_end = $time ;
txn.latency = (txn.t_end - txn.t_start)/1ns;
update_latency_stats(txn.t_end - txn.t_start);
update_statistics(txn);
seq_item_port.item_done();

 if (debug_mode) begin
    `uvm_info("REG_DRV",$sformatf("DONE %s : success=%0b latency=%0dns", txn.convert2string(), txn.success, txn.latency), UVM_MEDIUM)
 end

add_inter_transaction_delay();
end
endtask : run_phase

//---------drive operation-----------
task drive_transaction(reg_txn txn);
bit transaction_successful = 1'b1;

if(m_cfg.trace_op)
	`uvm_info("REG_DRIVER",$sformatf("[%s] %s @0x%02h",vif.USE_WB ? "WB":"LEG",txn.is_write()?"WR":"RD",
             txn.addr),UVM_LOW)

 
