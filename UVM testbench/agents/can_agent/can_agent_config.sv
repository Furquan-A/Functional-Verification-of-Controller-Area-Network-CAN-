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
	// eg. 75 means sample at 75% of bit . 
	int unsigned sample_point_pct = 75;
	
	// ----------------------------------------------------------
	// BUS_BEHAVIOR_CONTROL
	// ----------------------------------------------------------
	
	// whether this node transmits ACK
	bit ack_enable = 1'b1;
	
	// whether this node participate in the arbitration 
	bit arbitration_enable = 1'b1;
	
	
	// ----------------------------------------------------------
	// ERROR_INJECTION CONTROL
	// ----------------------------------------------------------
	
	// enable any error injection 
	bit enable_error_injection = 1'b1;
	
	// fine grain error types 
	bit inject_crc_error = 1'b0;
	bit inject_stuff_error = 1'b0;;
	bit inject_form_error = 1'b1;
	bit inject_ack_error = 1'b0;
	
	
	// ---------------------------------------------------------
	// DEBUG / TRACE 
	// ---------------------------------------------------------
	
	// print TX?RX activity 
	bit trace_enable = 1'b0;
	
	// verbose bit-level tracing ( very noisy)
	bit bit_trace_encable = 1'b0;
	
	