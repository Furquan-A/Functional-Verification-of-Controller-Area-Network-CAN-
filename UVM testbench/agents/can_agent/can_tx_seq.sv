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
		
		tr.can_fmt = `CAN_ID_STD;
		tr.id = 11'h123;
		tr.f_type = `CAN_DATA_FRAME;
		tr.dlc = 4;
		tr.data = new[4];
		tr.data[0] = 8'hAA;
		tr.data[1] = 8'h55;
		tr.data[2] = 8'h0F;
		tr.data[3] = 8'hF0;
		
		start_item(tr);
		finish_item(tr);
		
		`uvm_info("CAN_TX_SEQ","Sent one CAN Frame ", UVM_LOW)
		
	endtask 
endclass
`endif

		
		