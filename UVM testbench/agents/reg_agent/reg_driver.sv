`ifdef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_driver extends uvm_driver #(reg_transaction);

	`uvm_component_utils(reg_driver)
	
	can_env_config env_cfg;
	reg_agent_config reg_cfg;
	
	// virtual Interface 
	virtual can_if vif;
	
	extern function new( string name = "reg_driver", uvm_component parent );
	extern function void build_phase(uvm_phase phase);
	extern function void start_of_elaboration_phase(uvm_phase phase);
	extern task run_phase (uvm_phase phase);
	extern task send_to_dut();
	
endclass : reg_driver 

// ====================== new ===================================================================

function reg_driver :: new(string name = "reg_driver", uvm_component parent);
	super.new(name,parent);
endfunction 