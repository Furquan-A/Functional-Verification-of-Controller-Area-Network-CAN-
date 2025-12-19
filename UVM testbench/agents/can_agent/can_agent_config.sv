`ifdef CAN_AGENT_CONFIG_SV
`define CAN_AGENT_CONFIG_SV

`include "uvm_macros.svh"
`include "can_defines.sv"

import uvm_pkg::*;

class can_agent_config extends uvm_object;

	`uvm_object_utils(can_agent_config)
	
	// agent mode (active or passive)
	uvm_active_passive_enum is_active = UVM_ACTIVE;
	
	// vrtual can interface 
	virtual can_if vif;
	
	// logic node identifier 
	int unsigned node_id = 0;
	
	// ----------------------------------------------------------------------------
	// BIT TIMING 
	// ---------------------------------------------------------------------------
	
	// Bit timing in nanoseconds ( used by the driver and the monitor)
	int unsigned bit_time_ns = 100;
	
	// optional Sample point ( percentage of the bit time ) 
	int unsigned 