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

