`ifdef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_driver extends uvm_driver #(reg_transaction);

	`uvm_component_utils(reg_driver)
	
	can_env_config env_cfg;
	reg_agent_config r_cfg;
	
	// virtual Interface 
	virtual can_if vif;
	
	extern function new( string name = "reg_driver", uvm_component parent );
	extern function void build_phase(uvm_phase phase);
	extern function void connect_phase(uvm_phase phase);
	extern function void start_of_elaboration_phase(uvm_phase phase);
	extern task run_phase (uvm_phase phase);
	extern task send_to_dut();
	
endclass : reg_driver 

// ================================== new ==============================================================

function reg_driver :: new(string name = "reg_driver", uvm_component parent);
	super.new(name,parent);
endfunction 

// ================================= build_phase =======================================================

function void reg_driver :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db#(can_env_config) :: get(this,"can_env_config",env_cfg)
		`uvm_fatal("ENV_CFG","cannot get the env_cfg from db. did you set it ?")
		
	if(!uvm_config_db#(reg_agent_config) :: get(this,"reg_agent_config",r_cfg)
		`uvm_fatal("DRIVER config ","cannot get the CONFIG from db. did you set it ?")

endfunction 

// ================================== connect_phase =====================================================

function void reg_driver :: connect_phase(uvm_phase phase);
	super.connect_phase(phase);
	vif = r_cfg.vif;
endfunction 

