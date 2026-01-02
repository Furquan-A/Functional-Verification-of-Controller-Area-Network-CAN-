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
	bit stuff_expected; // when 1, next sampled bit is a stuff bit and must be skipped
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
					
					// SOF :sample and validate 
					ST_SOF : 
						begin 
							// for now sample one bit and validate it is 0
							bit b;
							sample_raw_bit(b);
							if(b != 1'b0) 
								begin 
									`uvm_warning("CAN_MON","SOF was not dominant; re-syncing to IDLE")
									state = ST_IDLE;
								end 
							else 
								begin 
									// SOF is real bit ( not stuffed ) . Initialize logical stream tracking 
									init_logical_stream(b);
									state = ST_ARB;
									bit_idx = 0;
								end 
						end 
						
					// ARBITRATION : Standard decode --> 11 bit ID + RTR + IDE 
					ST_ARB : 
						begin 
							decode_arbitration_std();
							// if the decode is sucessfull, we go to CNTRL; otherwise resync to IDLE inside
						end
						 // -------------------------
							// CTRL/DATA/CRC/ACK/EOF will be implemented next steps
							// For now, after ARB we’ll just end frame to keep compiling
							// -------------------------
							
					ST_CTRL: 
						begin 
							// placeholder unitl next steps
							state = ST_EOF;
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

	
	// =================================================================================================================
	// BIT ENGINE ( raw sampling + logical de-stuffing )
	// =================================================================================================================
	
	// Raw bit sampling: sample rx+i at the sonfigured sample point of each bit time 
	task sample_raw_bit(output bit b);
		// allign to some clock edge for the repeatable timing; then at sp_offset 
		@(posedge vif.clk_i);
		#(sp_offset);
		b = vif.rx_i;
		#(bit_time - sp_offset);
	endtask 
	
	// Initialize the logical Stream tracking ( call at SOF ) 
	function void init_logical_stream(bit first_bit);
		last_logical_bit = first_bit;
		same_cnt = 1;
		stuff_expected = 0;
	endfunction 
	
	// Get next logical bit (de-stuffed), this will sample raw bits untill non_stuff bit is obtained 
	// update stuffing counters based on logical bits only 
	task get_logical_bit(output bit lb);
	bit rb;
	
	forever 
		begin 
			sample_raw_bit(rb);
			// if we are expecting a stuff bit we must SKIP it ( do not return it ) 
			if (stuff_expected) 
				begin 
					// stuff bit must be opposite of the last logical bit, if not, its a stuff error ( later ) 
					// for now we just warn and resync.
					if(rb == last_logical_bit)
						begin 
							`uvm_warning("CAN_MON","Stuff error suspected ( stuff bit same as preious logic bit )")
							state = ST_IDLE;
						return ;
					end 
					// Skip the stuff bit and clear expectation 
					stuff_expected = 0;
					// continue loop to fetch next logical bit 
					continue;
				end 
				
				lb = rb // this logic bit is the real logic bit 
				
				if(lb == last_logical_bit)
					same_cnt++;
				else 
					same_cnt = 1;
					
				last_logical_bit = lb;
				
				// after 5 consecutive identical logivc bits, next raw bit must be a stuff bit 
				if (same_cnt == 5)
					begin 
						stuff_expected = 1;
						same_cnt = 0;
					end 
			return;
		end 
endtask 				
					
					