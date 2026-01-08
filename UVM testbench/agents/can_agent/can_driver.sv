`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
`import uvm_pkg::*;

`include "can_defines.sv"
`include "can_transaction.sv"
`include "can_agent_config.sv"

class can_driver extends uvm_driver #(can_transaction);
	`uvm_component_utils(can_driver)
	
	can_transaction tr;
	can_agent_config c_cfg;
	
	virtual can_if vif;
	
	// Timing 
	time bit_time;
	time sp_offset;
	
	//bit stuffing bookkeeping ( driver side)
	bit stuff_en;
	bit last_tx_bit;
	int unsigned same_cnt;
	
	// CRC 
	bit crc_en;
	bit [14:0] crc_reg;
	localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;
	
	// ================================ Constructor ==============================================================
	function new (string name = "can_driver", uvm_component parent);
		super.new(name,parent);
	endfunction 
	
	// ============================ build_phase ==================================================================
	
	function build_phase (uvm_phase phase);
		super.build_phase(phase);
		
		if(!uvm_config_db #(can_agent_config) :: get(this,"","m_cfg",c_cfg)
			`uvm_fatal("CAN_DRV""cannot get the CONFIG from the DB.(key='m_cfg')")
		
		if(!uvm_config_db #(virtual can_if ) :: get (this,"","vif",vif))
			`uvm_fatal("CAN_DRV"."Virtual can_if not found (key = 'vif')")         
			
		// Cache timing 
		bit_time = c_cfg.bit_time_ns * 1ns;
		sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct*1ns)/100;
		
		`uvm_info("CAN_DRV", $sformatf("Driver ready: bit_time=%0t sp_offset=%0t (%0d%%)",bit_time, sp_offset, m_cfg.sample_point_pct),UVM_LOW)
	endfunction
	
	// ============================= run_phase ===================================================================
	
	task run_phase(uvm_phase phase);
		
		can_transaction tr;
		
		// default recessive bus 
		drive_bus(1'b1);
		
		forever 
			begin 
				seq_item_port.get_next_item(tr);
				
				tr.t_start = $time;
				
				send_frame(tr);
				
				tr.t_end = $time;
				
				seq_item_port.item_done();
			end 
	endtask 
	
	// =============================== BUS DRIVER PRIMITIVES ======================================================
	
	// drive the *bus level* seen by DUT(rx_i). for multi-node, replace this 
	// with driving your node's tx into can_bus_model 
	
	task drive_bus(bit level);
	
	@vif.can_cb;
	vif.can_cb.rx_i <= level;
	
	endtask 
	
	// Drive one Physical bit time (raw, no stuffing Logic here)
	task drive_raw_bit(bit level);
		// put the level on the bus to drive at start of the bit time 
		drive_bus(level);
		
		// hold it for full bit time ( alligh to clk for repeatability)
		@(posedge vif.clk_i);
		#(bit_time);
	endtask
	
	// initialize the stuffng counter at SOF ( SOF itself is not stuffed)
	function void init_stuffing(bit first_bit);
		last_tx_bit = first_bit;
		same_cnt = 1;
	endfunction 
	
	//drive one Logic bit with the optional stuffing ( stuffing enables only in 
	// Arbitration + Control + Data + CRC sequence )
	task drive_logical_bit(bit lb);
		// If stuffing enables and w e already sent 5 identical bits, insert bit 
		if(stuff_en && (same_cnt == 5))
			begin 
				bit stuff_bit = ~last_tx_bit;
				drive_raw_bit(stuff_bit);
				// after inserting a stuff bit , reset the stuff counter for the new run 
				same_cnt = 1;
				last_tx_bit = lb; // will be updated again below after driving lb
			end 
			
			// drive the actual Logical bit 
			drive_raw_bit(lb);
			
			// update consecutive count tracking (only when stuffing is enabled matters, 
			// but harmless to keep updated)
			if(lb == last_tx_bit) 
				same_cnt++;
			else 
				same_cnt--;
			
	endtask
	
	// CRC CALCATION 
	function void crc15_update(bit b);
		bit msb;
		msb = crc_reg[14]^b;
		crc_reg = {crc_reg[13:0],1'b0};
		if(msb)
			crc_reg = crc_reg ^ CAN_CRC15_POLY;
	endfunction 
	
	task crc_start();
		crc_reg = 15'h0000;
		crc_en = 1'b1;
	endtask 
	
	task crc_stop();
		crc_en = 1'b0;
	endtask 
	
	task drive_frame_bit(bit lb);
		if(crc_en);
			crc15_update(lb);
		drive_logical_bit(lb);
	endtask 
	
	// ============================== IDLE ==================================================================
	// wait for idle recessive for at least intermission bits ( simple ) 
	task wait_for_idle_bus();
		// wait until the bus is recessive 
		wait(vif.rx_i == 1'b1);
		
		// enforce intermission bits (3 recessive bits)
		repeat ( `CAN_INTERMISSION_BITS ) drive_raw_bit(1'b1);
	endtask 
	
	// ================================================================================================================
	// FRAME TRANSMIT ( SOF -> EOF ) 
	// ================================================================================================================
	
	task send_frame(can_transaction tr);

		wait_for_idle_bus();
		
		// ---------------  SOF  ( dominant 0 , Not stuffed )
		
		stuff_en = 1'b0;
		drive_raw_bit(1'b0); // dominant 0 always 
		init_stuffing(1'b0);
		
		crc_start();
		crc15_update(1'b0); // SOF  = 0  "first bit "
		
		// enable the bit stuffing for everything upto the CRC sequence 
		stuff_en = 1'b1;
		
		// --------------- ARBITRATION FIELD
		
		// STANDARD MODE 
		if(tr.can_fmt == `CAN_ID_STD) 
			begin 
				// 11 bit ID , MSB first : id[10:0]
				for ( int i = 10 ; i >= 0 ; i--)
					begin 
						drive_frame_bit(tr.id[i]);
					end 
				
				// RTR 1 bit . if RTR = 0 --> has DATA FRAME else REMOTE FRAME 
				drive_frame_bit((tr.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0);
				
				// IDE must be 0 for STANDARD FRAME type 
				drive_frame_bit(1'b0);
			end 
			
		// EXTENDED FRAME 
		else 
			begin 
				// EXTENDED FRAME has the ID of 29 bits [28:0], CLASSIC CAN 
				// base id[28:18] then SRR = 1, IDE = 1, ext ID[17:0], then RTR
				for(int i = 28; i >= 18; i--)
					drive_frame_bit(tr.id[i]); // 11 bits 
					
				// SRR = 1 ( replaces the RTR of the standarf frame. Only on the bus , its not of the ID)
				drive_frame_bit(1'b1); // always Recessive 
				
				// IDE must be 1 for extended Frame type 
				drive_frame_bit(1'b1);
				
				// extended ID[17:0] after the upper 11 bits win the arbitration 
				for(int i = 17; i >= 0; i--)
					drive_frame_bit(tr.id[i]) // 18 bits 
					
				// RTR bit 
				drive_frame_bit((tr.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0);
				
			end 
					
					
		// --------------- CONTROL FIELD (classis)
		
		// Here in the CONTROL FIELD we will drive the ro(reserved register 
		// and will drive the DLC bits 
		
		// r0 reserved bit 
		drive_frame_bit(1'b0); // r0 = 0 for classic CAN 
		
		// DLC [3:0] MSB first
		for(int i = 3; i >= 0 ; i--)
			drive_frame_bit(tr.dlc[i]);
			
		// --------------- DATA 
		if(tr.f_type == `CAN_DATA_FRAME) 
			begin 
				int nbytes = tr.data.size();
				if(nbytes > 8) 
					nbytes = 8; // setting the max limit 
				
				for ( int bi = 0 ; bi < nbytes; bi++)
					begin 
						for(int b = 7; b >=0 ; b--)
							drive_frame_bit([bi][b]);
					end 
			end 
			
		// --------------- CRC sequence and Delimeter 
		crc_stop();
		
		for(int i = 14 ; i>=0 ;i--) 
				drive_frame_bit(crc_reg[i]);
			
			// Stuffing DISABLE after the CRC sequence 
			stuff_en = 0;
			
			// CRC delimeter 
			drive_raw_bit(1'b1); // always recessive 
			
		// --------------- ACK slot and Delimeter 
		// Transmitter sends recessive; receiver(s) may drive dominant in real bus.
		// In this bring-up driver, we keep it recessive.
		drive_raw_bit(1'b1); // ACK slot 
		drive_raw_bit(1'b1); // ACK delimeter ( recessive) 
			
		// --------------- EOF ( 7 recessive bits ) 
		repeat(7) drive_raw_bit(1'b1);
		
		// release bus to the recessive idle 
		drive_bus(1'b1);
		
		`uvm_info("CAN_DRV", $sformatf("Sent frame: fmt=%s id=0x%0h type=%0d dlc=%0d bytes=%0d", (tr.can_fmt==`CAN_ID_STD)?"STD":"EXT", tr.id, tr.f_type, tr.dlc, tr.data.size()), UVM_LOW)
		
	endtask
endclass : can_driver
`endif // CAN_DRIVER_SV
			