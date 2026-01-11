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
	
	uvm_analysis_port #(can_transactions) drv_ap;
	uvm_analysis_port #(can_transactions) mon_ap;
	
	extern function new(string name = "can_agent", uvm_component parent);
	extern function void build_phase(uvm_phase phase);
	extern function void connect_phase(uvm_phase phase);
	
endclass 

// ================================= new ===================================================

function can_agent :: new(string name , uvm_component parent);
	super.new(name,parent);
	drv_ap = new("drv_ap",this);
	mon_ap = new("mon_ap",this);
endfunction 

// ============================= build_phase ==============================================

function void can_agent :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db#(can_agent_config)::get(this,"","m_cfg",c_cfg))
		`uvm_fatal("CAN_AGENT","Cannot get() the in_cfg from the config_db. did you set() it ?")
		
	// Make cfg available to all children before create()
    uvm_config_db#(can_agent_config)::set(this, "*", "m_cfg", c_cfg);
	
	// create Moitor which is always Present in the active or passive agent 
	monh = can_monitor::type_id::create("monh",this);
	
	// check is the m_cfg is present and then create the driver and the sequencer 
	if(c_cfg.is_active == UVM_ACTIVE)
		begin 
			drvh = can_driver::type_id::create("drvh",this);
			seqrh = can_sequencer::type_id::create("seqrh",this);
		end 
	
	`uvm_info("CAN_AGENT",$sformatf("Built can_agent in %s mode ",m_cfg.active.name()),UVM_MEDIUM)
endfunction : build_phase

// ============================ connect_phase ==============================================

function void can_agent:: connect_phase(uvm_phase phase);
	super.connect_phase(phase);
	
    // Forward monitor's and Driver's transactions to agent's AP
	drvh.ap.connect(drv_ap);
	monh.ap.connect(mon_ap);
	
	if(c_cfg.is_active == UVM_ACTIVE)
		begin 
			drvh.seq_item_port.connect(seqrh.seq_item_export);
		end 
	
	vif = c_cfg.vif; 
	
endfunction : connect_phase

`endif // CAN_AGENT_SV