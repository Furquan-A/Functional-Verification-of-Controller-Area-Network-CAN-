// agents/can_bus_agent/can_agent.sv
`ifndef CAN_AGENT_SV
`define CAN_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_agent extends uvm_agent;

	`uvm_component_utils(can_agent)
	
	virtual can_if vif;
	
	can_driver drvh;
	can_monitor monh;
	can_sequencer seqrh;
	can_agent_config c_cfg;
	
	uvm_analysis_port #(can_item) ap;
	
	extern function new(string name = "can_agent", uvm_component parent);
	extern function void build_phase(uvm_phase phase);
	extern function void connect_phase(uvm_phase phase);
	
endclass 

// ================================= new ===================================================

function can_agent :: new(string name = " can_agent", uvm_component parent);
	super.new(name,parent);
	ap = new("ap",this);
endfunction 

// ============================= build_phase ==============================================

function void can_agent :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db#(can_agent_config)::get(this,"","m_cfg",c_cfg))
		`uvm_fatal("CAN AGENT CONFIG","Cannot get() the in_cfg from the config_db. did you set() it ?")
		
	// Make cfg available to all children before create()
    uvm_config_db#(can_agent_config)::set(this, "*", "m_cfg", c_cfg);
		
	monh = can_monitor::type_id::create("monh",this);
	
	if(c_cfg.is_active == UVM_ACTIVE)
		begin 
			drvh = can_driver::type_id::create("drvh",this);
			seqrh = can_sequencer::type_id::create("seqrh",this);
		end 
endfunction : build_phase

// ============================ connect_phase ==============================================

function void can_agent:: connect_phase(uvm_phase phase);
	super.connect_phase(phase);
	
    // Forward monitor's transactions to agent's AP
	monh.ap.connect(ap);
	
	if(c_cfg.is_active == UVM_ACTIVE)
		begin 
			drvh.seq_item_port.connect(seqrh.seq_item_export);
		end 
	
	vif = c_cfg.vif; 
	
endfunction : connect_phase

`endif // CAN_AGENT_SV