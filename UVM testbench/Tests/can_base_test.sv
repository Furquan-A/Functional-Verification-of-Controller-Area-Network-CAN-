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
	extern task run_phase(uvm_phase phase);
	
endclass 
`endif 

function reg_smoke_test :: new (string name  = "reg_smoke_test", uvm_component parent)l
	super.new(name,parent);
endfunction 

function reg_smoke_test :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	m_env = env :: type_id:: create("m_env",this);
	cfg = can_env_config::type_id::create("cfg");
	
	// only the reg agent is enabled for this smoke test 
	cfg.has_reg_agent = 1;
	cfg.no_of_reg_agent = 1;
	
	// disable all the can agent for now 
	cfg.has_can_agent = 0;
	cfg.has_scoreboard = 0;
	cfg.has_can_coverage = 0;
	cfg.has_virtual_sequencer = 0;
	
	cfg.r_cfg = new[cfg.no_of_reg_agent];
	cfg.r_cfg[0] = reg_agent_config::type_id::create("r_cfg0");
	cfg.r_cfg[0].is_active = UVM_ACTIVE;
	
	uvm_config_db #(virtual can_if)::get(this,"","vif",cfg.r_cfg[0].vif);
	
	// set the config for env 
	uvm_config_db #(can_env_config)::set(this,"m_env","can_env_config",cfg);
endfunction 

task reg_smoke_test :: run_phase(uvm_phase phase);
	super.run_phase(phase);
	
	phase.raise_objection(this);
	
	`uvm_info("REG_SMOKE_TEST","starting register smoke test ")
	
	// ----------------------------------------------------------------------
	// BASIC WRITE TEST 
	// ----------------------------------------------------------------------
	