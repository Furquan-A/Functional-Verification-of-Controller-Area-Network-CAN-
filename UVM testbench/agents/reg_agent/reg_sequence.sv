/*
	They will:
	Build reg_txn objects
	Fill in addr / data
	Send them to the sequencer
	Cause the driver to actually control the DUT
	Until you write sequences, nothing gets programmed in the DUT, so the CAN controller can’t even transmit or receive.
	So yes — REG SEQUENCES are the correct next step.
*/
`ifndef REG_BASE_SEQ_SV
`define REG_BASE_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_base_seq  extends uvm_sequence #(reg_transaction);
	
	`uvm_object_utils(reg_sequence)
	
	
	reg_agent_config r_cfg;
	env_config env_cfg;
	
	
	reg_sequencer p_sequencer;
	
	
	interface can_if vif;
	
	// ============================= new ========================================================

	function reg_sequence_base :: new(string name = "reg_sequence");
		super.new(name);
	endfunction 
	 
	// =================== pre_body ============================================================
	/* 	pre_body() runs before the sequence’s body(), 
		after the sequence is started, and after the sequencer 
		is assigned to the sequence.
	*/
	virtual task pre_body();
    if (!$cast(p_sequencer, m_sequencer))
      `uvm_fatal("REG_BASE_SEQ", "Could not cast p_sequencer!");
	endtask
  
	// ====================== Helper : write a register =======================================
	
	task write_reg(bit [7:]0 addr, bit [7:0] data);
		
		reg_transaction t; = reg_transaction::type_id::create("t_write");
		t.kind  = REG_WRITE;
		t.addr = addr;
		t.wdata = data;
		
		// start the transaction on driver through the sequencer 
		start_item(t); // <-- sends the transaction t to the sequencer 
		finish_item(t);// <-- passes the finalized transaction to the driver 
		
		if(!t.success)
			begin 
				`uvm_error("REG_WRITE",$sformatf("Write to 0x%02h FAILED", addr))
			end 
	endtask 
 
	// ==================== Helper: Read a register ==========================================
	
	task read_reg(bit [7:0] addr, output bit [7:0] data);
		
		reg_transaction t; = reg_transaction::type_id::create("t_read");
		t.kind = REG_READ;
		t.addr = addr;
		
		start_item(t);
		finish_item(t);
		
		data = t.rdata;
		
		if (!t.success)
			`uvm_error("REG_READ", $sformatf("Read from 0x%02h FAILED!", addr));
	endtask
	
	
	// default empty mody overrides 
	
	virtual task body();
	
	// sequence does not own any hardaware resourses so need need of getting the  config 
		`uvm_warning("REG_BASE_SEQ", "Base sequence body() called — nothing to do.");
	 endtask
	
endclass : reg_base_seq

`endif

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// WRITE SEQUENCES 

class reg_write_seq extends reg_base_seq;

	`uvm_object_utils(reg_write_seq);
	 
	// inputs to the sequence 
	randc bit [7:0] addr;
	randc bit [7:0] data;
	
	function new (string name = "reg_write_seq");
		super.new(name);
	endfunction 
	
	// The body uses the simple base class helpers 
	virtual task body();
		`uvm_info("REG_WRITE_SEQ",$sformatf("WRITE: addr = 0x%02h data = 0x%02",addr,data),UVM_MEDIUM)
		
		write_reg(addr,data);
	endtask 
	
endclass : reg_write_seq


// ====================================================================================================================================================================
// ====================================================================================================================================================================
// READ SEQUENCES 
class reg_read_seq extends reg_base_seq;
	`uvm_object_utils(reg_read_seq)
	
	// input argument
	randc bit[7:0] addr;
	
	// output of the read 
	output bit[7:0] data_out;
	
	function new(string name = "reg_write_seq");
		super.new(name);
	endfunction 
	
	virtual task body();
		`uvm_info("REG_READ_SEQ",$sformatf("READ data at addr = 0x%02h",addr),UVM_MEDIUM)
		
		read_reg(addr,data_out);
		
		`uvm_info("REG_READ_SEQ",  $sformatf("READ: addr=0x%02h -> data=0x%02h", addr, data_out), UVM_MEDIUM)
	endtask 
	
endclass : reg_read_seq


// ====================================================================================================================================================================
// ====================================================================================================================================================================
//  REG INIT SEQUENCE

`ifndef REG_INIT_SEQ_SV
`define REG_INIT_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
 
`include "can_defines.sv"

class reg_init_seqs extends reg_base_seq; // Is essential for proper CAN Operation

	`uvm_object_utils(reg_init_seqs)
	
	// configuration fields ( can be randomized or assigned in TEST) ----
	rand bit use_extended_mode = 1'b1; // 0 = basic mode, 1 = extended mode 
	rand byte btr0_config; // packed BRP + SJW
	rand byte btr1_config; // packed TSEG1 + TSEG2 + Triple_samp
	rand byte acc_code0; // default acceptance code 
	rand byte acc_mask0; // default acceptance mask 
		
	function new(string name = "reg_init_seqs");
		super.new(name);
	endfunction
	
	// ---------------------------------------------------------------
	// Main initialization body()
	//----------------------------------------------------------------
	virtual task body();
		`uvm_info("REG_INIT_SEQ","Starting Can Controller initialization", UVM_MEDIUM)
		
		// ENTER RESET MODE 
		byte mode_reset = `CAN_MODE_RESET_M; // bit 0 = reset mode 
		write_reg(`CAN_MODE_REG,mode_reset);
		
		// PROGRAM BIT TIMING BTR0 and BTR1
		write_reg(`CAN_BUS_TIMING_0,btr0_config);
		write_reg(`CAN_BUS_TIMING_1,btr1_config);
		
		// PROGRAM ACCEPTANCE FILTER ( BASIC or EXTENDED)
		if(!use_extended_mode)
			begin 
				write_reg(`CAN_ACC_CODE0_BASIC,acc_code0);
				write_reg(`CAN_ACC_MASK0_BASIC,acc_mask0);
			end 
		else 
			begin 
				write_reg(`CAN_ACC_CODE0_EXT,acc_code0);
				write_reg(`CAN_ACC_MASK0_EXT,acc_mask0);
				// optonal: others to zero 
				write_reg(`CAN_ACC_CODE1_EXT, 8'h00); // 00 means any value can be passed 
				write_reg(`CAN_ACC_CODE2_EXT, 8'h00);
				write_reg(`CAN_ACC_CODE3_EXT, 8'h00);
				write_reg(`CAN_ACC_MASK1_EXT, 8'hFF); // FF means n value should be chaked and compared with the code 
				write_reg(`CAN_ACC_MASK2_EXT, 8'hFF);
				write_reg(`CAN_ACC_MASK3_EXT, 8'hFF);
			end
			
		// ENABLE EXTENDED MODE 
		if(use_extended_mode) 
			begin 
				/* Clock Divider (bit7 = extended_mode) must be written FIRST before any extended-mode
				registers can be programmed.It does NOT configure IRQs or filters; 
				it only switches the register map. 
				*/
				byte clkdiv = `CAN_CLKDIV_EXTENDED_M;
				write_reg(`CAN_CLOCK_DIVIDER,clkdiv);
				
			end 
	