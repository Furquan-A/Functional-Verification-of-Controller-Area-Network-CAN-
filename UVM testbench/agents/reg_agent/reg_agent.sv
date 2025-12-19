`ifndef REG_AGENT_SV
`define REG_AGENT_SV

`include "uvm_macros_svh"
import uvm_pkg::*

class reg_agent extends uvm_agent;
	`uvm_component_utils(reg_agent);

	virtual can_if vif;

	//----Agent components and their Handles--
	reg_driver        rdrvh;
	reg_monitor       rmonh;
	reg_sequencer     rseqrh;
	reg_agent_config  m_cfg;

	uvm_analysis_port #(reg_txn) ap;


	// ========== UVM Factory Registration ==========
	`uvm_component_utils_begin(reg_agent)
	`uvm_field_object(m_cfg, UVM_DEFAULT)
	`uvm_component_utils_end
  
// ================================== new =================================================
 
function new (string name = "reg_agent", uvm_component parent);
	super.new(name,parent);
	ap = new("ap",this);
endfunction 

// ================================ build_phase =============================================

function void build_phase(uvm_phase phase);
	super.build_phase(phase);

	// get config from the config_db
	if(!uvm_config_db#(reg_agent_config) :: get(this,"","m_cfg",m_cfg)) begin 
		`uvm_info("REG_AGENT","No reg_agent_config found, creating default", UVM_LOW)
		m_cfg = reg_agent_config::type_id::create("m_cfg");
	end 

	// Now set the configuration for the sub components
	uvm_config_db #(reg_agent_config) ::set(this,"*","m_cfg",m_cfg);

	// create monitor which is always present in both ACTIVE and PASSIVE
	rmonh = reg_monitor::type_id::create("rmonh",this);

	// check the m_cfg and then create the driver and sequencer 
	if(m_cfg.is_active == UVM_ACTIVE) begin 
		rdrvh = reg_driver::type_id::create("rdrvh",this);
		rseqrh = reg_sequencer::type_id::create("rseqrh",this);
	end 

	`uvm_info("REG_AGENT",$sformatf("Built reg_agent in %s mode with %s bus",m_cfg.active.name(),m_cfg.bus_type.name()),UVM_MEDIUM)

endfunction : build_phase 

// ============================== connect_phase ==============================================

function void connect_phase(uvm_phase phase);
	super.connect_phase(phase);

	// connect analysis port to monitor 
	rmonh.ap.connect(ap);

	// connect driver to the sequencer if active 
	if(m_cfg.is_active == UVM_ACTIVE) begin 
	rdrvh.seq_item_port.connect(rseqrh.seq_item_export);
	end 
	
	`uvm_info("REG_AGENT","connected reg_agent components",UVM_HIGH)

endfunction : connect_phase

endclass : reg_agent

`endif // REG_AGENT_SV