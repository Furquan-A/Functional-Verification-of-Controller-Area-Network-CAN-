`ifdef CAN_MONITOR_SV
`define CAN_MONITOR_SV

`include "can_macros.svh"
import uvm_pkg::*;

`include "can_defines.sv"

class can_monitor extends uvm_monitor;
	`uvm_component_utils(can_monitor)
	
	uvm_analyisi_port #(can_transactions) ap;
	
	virtual can_if vif;
	can_agent_config c_cfg;
	
	// ------ State machine ( Monitor internal ) ---------------
	typedef enum int {
		ST_IDLE = 0,
		ST_SOF,
		ST_ARB, //arbitration: ID + RTR + IDE( + extended later )
		ST_CNTRL, // control: r0 + DLC
		ST_DATA, // data bytes 
		ST_CRC, // CRC + Delimiter 
		ST_ACK, // ACK solot + Delimiter 
		ST_EOF // EOF Bis 
		} can_mon_state_e;
		
	can_mon_state_e state;
	
	// ----------- Internal Decode Bookkeeping ----------------
	can_transactions tr; // current frame bing built 
	
	int unsigned bit_idx; // counts legal (de-stuffed) bits in the field 
	int unsigned byte_idx; // data byte index
	
	bit [7:0] cur_byte;// assembling current byte 
	
	// stuff bit tracing (applies across most states once enabled)
	bit last_bit;
	int unsigned same_cnt; // how many consecutive identical bits are seen 
	
	// Pre computed timing 
	time bit_time; // in simulation time unt  9e.g., ns)
	time sp_offset; // sample_point offset within bit_time 
	
	
	extern function new (string name = "can_monitor", uvm_component parent);
	extern function void build_phase(uvm_phase phase);
	extern task run_phase(uvm_phase phase);
	
endclass : can_monitor
`endif : CAN_MONITOR_SV

// =========== CONSTRUCTOR =======================================================================

function can_monitor :: new (string name = "can_monitor", uvm_component parent);
	super.new(name,parent);
endfunction 

// =========== BUILD_PHASE : get config + vif ===================================================

function void can_monitor :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db #(can_agent_config) :: get(this,""."m_cfg",m_cfg)
		`uvm_fatal("CAN_MON","can_agent_config not found ( key = 'm_cfg')")
	
	if(!uvm_config_db #(virtual can_if) :: get(this,""."vif",vif))
		`uvm_fatal("CAN_MON","virtual Interface can_if not found ( key = 'vif')")
		
	// cache timing in time units 
	bit_time = m_cfg.bit_time_ns * 1ns;
	sp_offset = (m_cfg.bit_time_ns * m_cfg.sample_point_pct * 1ns) / 100;
	
	
	state = ST_IDLE;
	bit_idx = 0;
	byte_idx = 0;
	cur_byte = 8'h00;
	last_bit = 1'b1; // bus idle is resessive 
	same_cnt = 0;
	
	`uvm_info("CAN_MON",$sformatf("Monitor ready: bit_time = %0t, sample_point = %0t (%0d%%)", bit_time,sp_offset,m_cfg.sample_point_pct),UVM_LOW)
endfunction 

// =================== RUN_PHASE ( main MoNITOR LOOP SKELTON ) ====================================

task can_monitor :: run_phase(uvm_phase phase);
	super.run_phase(phase);
	
	forever 
		begin 
			case(state)
				// IDLE : Wait for SOF ( 1-> 0) 
				ST_IDLE :
					begin 
						wait_for_sof();
						start_new_frame();
						state = ST_SOF;
					end 
				
				// SOF : Confirm first bit is Dominant and move on 
				ST_SOF : 
					begin 
						// for now sample one bit and validate it is 0
						bit b;
						if(b != 1'b0) 
							begin 
								`uvm_warning("CAN_MON","SOF was not dominant; re-syncing to IDLE")
								state = ST_IDLE;
							end 
						else 
							begin 
								// version 1: jump to arbitration decode next 
								reset_stuff_tracking(b);
								state = ST_ARB;
								bit_idx = 0;
							end 
					end 
					