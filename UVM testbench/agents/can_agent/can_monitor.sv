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
						
				 
					ST_ARB :// ARBITRATION : Standard decode --> 11 bit ID + RTR + IDE
						begin 
							decode_arbitration_std();
							// if the decode is sucessfull, we go to CNTRL; otherwise resync to IDLE inside
						end
						 
					ST_CTRL: 
						begin 
							decode_control_std();
				
					ST_DATA: 	
						begin
							decode_data_field();
						end
						
					ST_CRC: 
						begin
						  decode_crc_field();
						end

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
					
	// =======================================================================================================================
	// Arbitration Decode (standard)
	// =======================================================================================================================
	
	task decode_arbitration_std();
		bit b;
		bit [10:0] sid;
		bit rtr;
		bit ide;
		
		sid = '0;
		
		// 11 bit standard Id ( MSB first on the wire )
		for (int i = 10; i >=0 ; i--)
			begin 
				get_logical_bit(b);
				if(state == ST_IDLE) return ; // sync Occured 
				sid[i] = b;
			end 
			
		// RTR 
		get_logical_bit(rtr);
		if(state == ST_IDLE) return ;
		
		// IDE ( must be zero for Std CAN 
		get_logical_bit(ide);
		if(state == ST_IDLE) return ;
		
		// Store into transaction 	
		tr.can_fmt = (ide == 1'b0) ? `CAN_ID_STD : `CAN_ID_EXT;
		tr.id = { 18'd0,sid};
		tr.f_type = (rtr == 1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;
		
		if(ide == 1'b1) 	
			begin 
				// Extended decode will come later; for now we stop here gracefully.
				`uvm_warning("CAN_MON", "Extended frame detected but EXT decode not implemented yet. Ending frame.")
				state = ST_EOF;
			end 
		else 
			begin
			  state = ST_CTRL;
			end
	endtask
  
    // =========================================================================================================================
	// CONTROL FIELD DECODE ( standard Frame ) 
	// =========================================================================================================================
  
	task decode_control_std();
		bit b;
		bit r0; // reserved reg in the CAN PROTOCL
		bit [3:0] dlc_value;
		
		// read ro ( reserved )
		get_logical_bit(r0);
		if(state == ST_IDLE) return 
		
		// optional check ( later can be form error )
		if(r0 != 1'b0)	
			begin 
				`uvm_warning("CAN_MON","r0 bit is not zero ( possible FORM ERROR )")
			end 
		
		// read DLC ( 4 bits , MSB first on the wire ) 
		dlc_value = 4'd0;
		for (int i = 3; i >= 0 ; i--)
			begin 
				get_logical_bit(b);
				if(state == ST_IDLE) return ;
				dlc_value[i] = b;
			end 
			
		// store into Transaction 
		tr.dlc = dlc_value;
		
		// prepare for next stage 
		bit_idx = 0;
		byte_idx = 0;
		cur_byte = 8'h00;
		
		// decide next stage 
		if(dlc_value == 1'b0)
			state = ST_IDLE;
		else 
			state = ST_DATA;
		
    endtask 
  
  
    // =========================================================================================================================
	// DECODE DATA FIELD ( standard Frame )
	// =========================================================================================================================
    task decode_data_field();
	
		bit b;
		
		// allocate payload array 
		tr.data = new[tr.dlc];
		
		// foreach data byte 
		foreach(byte_idx = 0 ; byte_idx < tr.dlc; byte_idx++)
			begin 
				cur_byte = 8'h00;
		
				// each byte is 8 bits, MSB first 
				for (bit_idx = 7; bit_idx >= 0; bit_idx--)
					begin 
						get_logical_bit(b);
						if(state = ST_IDLE) return ;
						
						cur_byte[bit_idx] = b;
					end 
					
					// store reconstructed byte 
					tr.data[byte_idx] = cur_byte;
			end 
			
			// All data bytes are received move to CRC state 
			state = ST_CRC;
	endtask 
  
	// =========================================================================================================================
	// DECODE CRC FIELD  ( standard Frame ) 
	// =========================================================================================================================
	task decode_crc_field();
	
		bit b;
		bit [14:0] crc_seq; // 15 bits crc value 
		bit crc_delimeter; // recessive (1)
		
		crc_seq = 15'd0;
		 
		 // Read CRC value ( MSB first )
		for(int i = 14 ; i>=0;i--)
			begin 
				get_logical_bit(b);
				if(state == ST_IDLE) return ; // resync occured 
				
				crc_seq[i] = b;
			end 
			
		// Optional strore the observed CRC in the transaction 
		tr.crc_obs = crc_seq;
		
		// Read Delimeter value 
		get_logical_bit(b);
		if(state == ST_IDLE) return;
		
		// check CRC Delimeter ( recessive )
		if(b != 1'b1)
			`uvm_warning("CAN_MON","CRC Delimeter not recessive (Possible Form Error)")
		
		// move to ACK state after reading CRC and Delimeter 
		state = ST_ACK;
		
	endtask 
	
	// =========================================================================================================================
	// DECODE CRC FIELD  ( standard Frame ) 
	// =========================================================================================================================
	task decode_ack_field();
		bit ack_slot;
		bit ack_delim;
		
		// read ACK SLOT
		get_logical_bit(ack_slot);
		if(state == ST_IDLE) return ;
		
		// ACK Slot Interpretation 
		// 0 = ack received ( at least One Node acknowledged)
		// 1 = ack error ( no node acknowledged)
		if(ack_slot == 1'b1)
			begin 
				`uvm_warning("CAN_MON","ACK error detected ( no dominant ack)")
				// Later mark ACK ack error in the transaction class if desired 
			end 
		
    //==========================================================================================================================
	// Frame lifecycle helpers
	//==========================================================================================================================
  
	task wait_for_sof();
	
		// Wait for idle recessive
		wait (vif.rx_i === 1'b1);
		// SOF begins when bus becomes dominant
		@(posedge vif.clk_i);
		wait (vif.rx_i === 1'b0);
	  endtask

	  task start_new_frame();
		tr = can_transaction::type_id::create("tr", this);
		tr.t_start = $time;

		// defaults
		tr.f_type  = `CAN_DATA_FRAME;
		tr.can_fmt = `CAN_ID_STD;
		tr.id      = '0;
		tr.dlc     = 0;
		tr.data    = new[0];
	  endtask

	  task end_frame_and_publish();
		tr.t_end = $time;
		ap.write(tr);
		`uvm_info("CAN_MON",
		  $sformatf("Observed frame: fmt=%s id=0x%0h type=%0d dlc=%0d bytes=%0d", (tr.can_fmt==`CAN_ID_STD)?"STD":"EXT",tr.id, tr.f_type, tr.dlc, tr.data.size()), UVM_LOW)
		  
	endtask

endclass : can_monitor

`endif // CAN_MONITOR_SV