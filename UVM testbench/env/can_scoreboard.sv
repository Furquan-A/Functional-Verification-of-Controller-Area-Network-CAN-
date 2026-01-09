`ifndef CAN_SCOREBOARD_SV
`define CAN_SCOREBOARD_SV

`include "uvm_macros.svh"
import uvm_pkg::*;


class can_scoreboard extends uvm_component;
	`uvm_component_utils(can_scoreboard)
	
	// analysis PORTS 
	uvm_analysis_imp #(can_transactions,can_scoreboard) exp_imp;
	uvm_analysis_imp #(can_transactions, can_scoreboard) obs_imp;
	
	// Queues of the expected and the observed transactions 
	can_transactions exp_q[$];
	can_transactions obs_q[$];
	
	// statistics 
	int pass_count;
	int fail_count;
	
	
	// ========================== Constructor ===========================================================
	
	function new(string name = "can_scoreboard", uvm_component parent = null);
		super.new(name,parent);
		exp_imp = new("exp_imp",this);
		obs_imp = new("obs_imp",this);
	endfunction 
	
	// ========================= Expected Transaction Callback ==========================================
	
	function void write_exp(can_transactions tr);
		exp_q.push_back(tr);
			`uvm_info("CAN_SB",$sformatf("Expected frame queued (ID = 0x%0h)",tr.id),UVM_LOW)
		compare_if_ready();
	endfunction
	
	// ========================= Observed Transaction Callback ==========================================
	
	function void write_obs(can_transactions tr);
		obs_q.push_back(tr);
			`uvm_info("CAN_SB",$sformatf("Observed frame queued (ID = 0x%0h)",tr.id),UVM_LOW)
		compare_if_ready();
	endfunction