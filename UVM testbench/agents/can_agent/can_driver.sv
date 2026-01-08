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
			
	endtask
	
	// wait for idle recessive for at least intermission bits ( simple ) 
	task wait_for_idle_bus();
		// wait until the bus is recessive 
		wait(vif.rx_i == 1'b1);
		
		// enforce intermission bits (3 recessive bits)
		repeat ( `CAN_INTERMISSION_BITS ) drive_raw_bit(1'b1);
	endtask 
	
	