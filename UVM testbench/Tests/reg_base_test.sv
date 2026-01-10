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
	
endclass : reg_smoke_test


// ====================== new ==============================================================

function reg_smoke_test :: new (string name  = "reg_smoke_test", uvm_component parent);
	super.new(name,parent);
endfunction 

// ======================= build_phase =======================================================

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

// ===================== run_phase ============================================================

task reg_smoke_test :: run_phase(uvm_phase phase);
	super.run_phase(phase);
	
	phase.raise_objection(this);
	
	`uvm_info("REG_SMOKE_TEST","starting register smoke test ")
	
	// ----------------------------------------------------------------------
	// BASIC WRITE TEST 
	// ----------------------------------------------------------------------
	reg_write_seq wr = reg_write_seq::type_id::create("wr_seq");
	
	wr.addr = `CAN_MODE_REG; // writing mode register 
	wr.data = 8'h01; // example value 
	wr.start(m_env.r_agent[0].rseqrh); // start on reg sequencer 
	
	// ----------------------------------------------------------------------
	// BASIC READ TEST 
	// ----------------------------------------------------------------------
	reg_read_seq rd = reg_read_seq :: type_id::create("rd_seq");
	
	rd.addr = `CAN_REG_MODE;
	rd.start(m_env.r_agent[0].rseqrh);
	
	`uvm_info("REG_SMOKE_TEST",$sformatf("Read MODE register returned = 0x%02h", rd.data_out),UVM_MEDIUM)
	
	phase.drop_objection(this);
endtask 

`endif //REG_SMOKE_TEST_SV