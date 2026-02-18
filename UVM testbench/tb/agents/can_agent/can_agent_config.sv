`ifndef CAN_AGENT_CONFIG_SV
`define CAN_AGENT_CONFIG_SV

`include "uvm_macros.svh"
//`include "can_defines.sv"

import uvm_pkg::*;

class can_agent_config extends uvm_object;

	`uvm_object_utils(can_agent_config)
	
	// agent mode (active or passive)
	uvm_active_passive_enum is_active = UVM_ACTIVE;
	
	// virtual can interface 
	virtual can_if vif;
	
	// logic node identifier 
	int unsigned node_id = 0;
  bit is_tx_in_progress = 0; //  set by driver, used by monitor for ACK gating
  bit enable_special_decode; // gate for ERROR and OVERLOAD Frame 
  
	int unsigned wr_cnt = 0;
	int unsigned rd_cnt = 0;
	
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
	bit ack_enable = 1'b0;
  bit expect_no_ack = 1'b0; // test sets this for ACK-error cases
	
	// whether this node participate in the arbitration 
	bit arbitration_enable = 1'b1;
	
	
	// ----------------------------------------------------------
	// ERROR_INJECTION CONTROL
	// ----------------------------------------------------------
	
	// enable any error injection 
	bit enable_error_injection = 1'b0; // OFF by default
	
	// fine grain error types 
	bit inject_crc_error = 1'b0;
	bit inject_stuff_error = 1'b0;
	bit inject_form_error = 1'b0;
	bit inject_ack_error = 1'b0;
	
	
	// ---------------------------------------------------------
	// DEBUG / TRACE 
	// ---------------------------------------------------------
	
	// print TX?RX activity 
	bit trace_enable = 1'b0;
	
	// verbose bit-level tracing ( very noisy)
	bit bit_trace_enable = 1'b0;
	
	// ===== Contructor ======================================
	
	function new(string name = "can_agent_config");
		super.new(name);
	endfunction 
	
	// =========================================================
	// VALIDATION FUNCTION (IMPORTANT IN TYPE-B)
	// =========================================================
	function bit validate(ref string reason);
		bit ok = 1;

		if (vif == null) begin
		  reason = "vif is null in can_agent_config";
		  ok = 0;
		end
		else if (bit_time_ns == 0) begin
		  reason = "bit_time_ns must be > 0";
		  ok = 0;
		end
		else if (sample_point_pct == 0 || sample_point_pct >= 100) begin
		  reason = "sample_point_pct must be between 0 and 100";
		  ok = 0;
		end
		else if (enable_error_injection &&
				!(inject_crc_error || inject_stuff_error ||
				  inject_form_error || inject_ack_error)) begin
		  reason = "enable_error_injection set but no error type selected";
		  ok = 0;
		end

		return ok;
	endfunction
	
	// =========================================================
	// STRINGIFY (FOR DEBUG PRINTS)
	// =========================================================
	function string sprint();
		return $sformatf(
		  "can_cfg(node=%0d, active=%s, bit_time=%0dns, ack=%0b, arb=%0b, err_inj=%0b)",
		  node_id,
		  (is_active == UVM_ACTIVE) ? "ACTIVE" : "PASSIVE",
		  bit_time_ns,
		  ack_enable,
		  arbitration_enable,
		  enable_error_injection
		);
	endfunction

endclass : can_agent_config

`endif // CAN_AGENT_CONFIG_SV