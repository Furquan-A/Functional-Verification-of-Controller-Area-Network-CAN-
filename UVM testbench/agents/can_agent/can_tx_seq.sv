`ifndef CAN_TX_SEQ_SV
`define CAN_TX_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
`include "can_defines.sv"

class can_tx_seq extends uvm_sequence #(can_transactions);
	uvm_object_utils(can_tx_seq)
	
	// ===================== Constructor ============================================================
	
	function new(string name = " can_tx_seq");
		super.new(name);
	endfunction 
	
	task bosy();
		can_transactions tr;
		
		tr = can_transactions :: type_id :: create("tr");
		
		// ---------- Simple directed frame ---------------------
		