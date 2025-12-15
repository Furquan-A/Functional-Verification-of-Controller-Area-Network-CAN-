`ifdef REG_SMOKE_TEST_SV
`define REG_SMOKE_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
`include "can_defines.sv"

class reg_smoke_test extends uvm_test;
	`uvm_component_utils(reg_smoke_test)
	
	env m_env;
	env_config cfg;
	
	extern function new(string name = "reg_smoke_test", uvm_component parent);
	extern void function build_phase(uvm_phase phase);
endclass 
`endif 

function reg_smoke_test :: new (string name  = "reg_smoke_test", uvm_component parent)l
	super.new(name,parent);
	
	m_env = env :: type_id:: create("m_env",this);
	cfg = env_config::type_id::create("cfg");
	
	// only the reg agent is enabled for this smoke test 
	cfg.has_reg_agent = 1;
	cfg.no_of_reg_agent = 1;
	
	// disable all the can agent for now 
	cfg.has_can_agent = 0;
	cfg.has_scoreboard = 0;
	cfg.has_can_coverage = 0;
	cfg.has_virtual_sequencer = 0;
	
	cfg.r_cfg = new[cfg.no_of_reg_agent];