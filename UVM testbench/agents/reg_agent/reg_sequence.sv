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


