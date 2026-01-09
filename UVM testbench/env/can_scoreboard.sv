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
	
	// ======================== Compare when Both sides are ready =======================================
	
	function void compare_if_ready();
		can_transactions exp;
		can_transactions obs;
		
		if(exp_q.size() == 0 || obs_q.size() == 0)
		return ;
		
		exp = exp_q.pop_front();
		obs_q.pop_front();
		
		if(compare_txn(exp,obs)) 
			begin 
				pass_count ++ ;
				`uvm_info("CAN_SB","CAN FRAME MATCHED ", UVM_LOW)
			end 
		else 
			begin 
				fail_count++;
				`uvm_info("CAN_SB","CAN FRAME MISMATCH ", UVM_LOW)
			end 
	endfunction 
	
	// ======================= FIELD-BY-FIELD comaprision ================================================
	
	function bit compare_txn(can_transactions exp, can_transactions obs);
		if(exp.can_fmt != obs.can_fmt) return 0;
		if (exp.id      != obs.id)      return 0;
		if (exp.f_type  != obs.f_type)  return 0;
		if (exp.dlc     != obs.dlc)     return 0;
		
		if(exp.data.size() != obs.data.size()) return ;
		
		foreach(exp.data[i])
			begin 
				if(exp.data[i] != obs.data[i])
				return 0;
			end 
	endfunction 
	
	// ======================= Report Phase ==============================================================
	
	function void report_phase(uvm_phase phase);
		`uvm_info("CAN_SB",$sformatf("Scoreboard summary: Pass = %0d, Fail = %0d", pass_count, fail_count),UVM_LOW)
	endfunction 
	
endclass : can_scoreboard
`endif 