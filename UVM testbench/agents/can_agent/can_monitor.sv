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
	bit stuff_expected; // when 1, next sampled bit is a stiff bit and must be skipped
	// Pre computed timing 
	time bit_time; // in simulation time unt  9e.g., ns)
	time sp_offset; // sample_point offset within bit_time 
	


	// =========== CONSTRUCTOR =======================================================================

	function new (string name = "can_monitor", uvm_component parent);
		super.new(name,parent);
		ap = new("ap",this);
	endfunction 

	// =========== BUILD_PHASE : get config + vif ===================================================

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		if(!uvm_config_db #(can_agent_config) :: get(this,""."m_cfg",m_cfg)
			`uvm_fatal("CAN_MON","can_agent_config not found ( key = 'm_cfg')")
		
		if(!uvm_config_db #(virtual can_if) :: get(this,""."vif",vif))
			`uvm_fatal("CAN_MON","virtual Interface can_if not found ( key = 'vif')")
			
		// cache timing in time units 
		bit_time = m_cfg.bit_time_ns * 1ns;
		sp_offset = (m_cfg.bit_time_ns * m_cfg.sample_point_pct * 1ns) / 100;
		
		/*
		state = ST_IDLE;
		bit_idx = 0;
		byte_idx = 0;
		cur_byte = 8'h00;
		last_bit = 1'b1; // bus idle is resessive 
		same_cnt = 0;*/
		
		// Initialize stuff tracking to Idle Bus ( recessive )
		last_logical_bit = 1'b1;
		same_cnt = 0;
		stuff_expected = 0;
		
		
		`uvm_info("CAN_MON",$sformatf("Monitor ready: bit_time = %0t, sample_point = %0t (%0d%%)", bit_time,sp_offset,m_cfg.sample_point_pct),UVM_LOW)
	endfunction 

	// =================== RUN_PHASE ( main MoNITOR LOOP SKELTON ) ====================================

	task run_phase(uvm_phase phase);
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
							sample_bit(b);
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
					// ARBITRATION (stub)
					ST_ARB : 
						begin 
							// TODO (next step):
							//  - sample 11 ID bits (de-stuffed)
							//  - sample RTR, IDE
							//  - decide std/ext, frame_type
							//
							// For skeleton, we’ll just consume a few bits then end (placeholder).
							// Replace this block with real decoding in next iteration.
							consume_n_bits(14); // placeholder: 11+RTR+IDE+1(r0)
							state = ST_EOF;     // placeholder
						end
						
					// EOF (stub): end frame and publish
					ST_EOF : 
						begin 
							 // TODO (later ) : verify 7 recessive EOF bits 
							 end_frame_and_publish();
							 state = ST_IDLE ;
						end 
						
					default : 
						begin 
							`uvm_warning("CAN_MON","unknown state : returning to IDLE ")
							state = ST_IDLE;
						end
				endcase 
			end 
	endtask 

	// =============== helper TASK/Functons (skeleton) ======================================================

	task wait_for_sof();
		// ensure we're in idle recessive 
		wait(vif.rx_i == 1'b1);
		// sof when bus becomes dominant 
		@(posedge vif.clk_i); // just to avoid zero time loop 
		wait(vif.rx_i == 1'b0);
	endtask

	task start_new_frame();
		tr = can_transactions :: type_id :: create("tr",this);
		
		tr.t_start = $time ;
		bit_idx = 0;
		byte_idx = 0;
		cur_byte = 8'h00;
		// default assumptions for now 
		tr.can_fmt = `CAN_ID_STD;
		tr.f_type = `CAN_DATA_FRAME;
		tr.id = '0;
		tr.dlc = 3'b000;
		tr.data = new[0];
	endtask 

	task end_frame_and_publish();
		tr.t_end = $time ;
		ap.write(tr);
		`uvm_info("CAN_MON", $sformatf("Observed frame: %s", tr.convert2string()), UVM_LOW)
	endtask


	  // Sample one CAN bit at the configured sample point.
	  // NOTE: In a more accurate model, you align to bit boundaries; for now we
	  // sample relative to clk_i and then wait the sample offset.
	  
	task sample_bit(output bit b);
		// allign to some referance edge( sample start )
		@(posedge vif.clk_i);
		#(sp_offset);
		b = vif.rx_i;
		// advance to next bit boundary 
		#(bit_time - sp_offset);
	endtask 
	
	function void reset_stuff_tracking( bit first_bit);
		last_bit = first_bit;
		same_cnt = 1;
	endfunction 
	
	 // Consume N raw sampled bits (placeholder until real decoding)
    task consume_n_bits(int unsigned n);
		bit b;
		repeat (n)
			begin
				sample_bit(b);
			end
	endtask

endclass : can_monitor
`endif // CAN_MONITOR_SV