`ifndef CAN_SMOKE_TEST_SV
`define CAN_SMOKE_TEST_SV 
`include "uvm_macros.svh"

import uvm_pkg::*;

class can_smoke_test extends uvm_test;
	`uvm_component_utils(can_smoke_test)
	
	can_env m_env;
	
	function new ( string name = "can_smoke_test", uvm_component parent = null);
		super.new(name,parent);
	endfunction 
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		m_env = can_env :: type_id :: create("m_env",this);
	endfunction
	
	task run_phase(uvm_phase phase);
		can_tx_seq seq;
		
		phase.raise_objection(this);
		
		// create and start CAN sequence 
		seq = can_tx_seq :: type_id :: create("seq");
		seq.start(m_env.c_agent[0].seqrh);
		
		// allow some time for monitor + scoreboard 
		#100us;
		
		phase.drop_objecttion(this);
	endtask 
endclass 
`endif