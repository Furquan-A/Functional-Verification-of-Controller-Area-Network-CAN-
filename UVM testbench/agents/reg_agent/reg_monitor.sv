`ifder REG_MONITOR_SV
`defiine REG_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_monitor extends uvm_component;
	`uvm_component_utils(reg_monitor)
	
	uvm_analysis_port#(reg_transaction) ap;
	
	virtual can_if vif;
	reg_agent_config r_cfg;
	reg_transaction reg_txn;
	
	env_config env_cfg;
	
	extern function new(string name = "reg_monitor",uvm_component parent);
	extern void function build_phase(uvm_phase phase);
	extern task run_phase(uvm_phase phase);
	extern task ;
	
endclass : reg_monitor


function reg_monitor :: new (string name = "reg_monitor", uvm_component parent);
	super.new(name,parent);
	ap = new("ap",this);
endfunction 

function reg_monitor :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db#(reg_agent_config)::get(this,"","reg_agent_config","r_cfg"))
		uvm_fatal("REG_MONITOR","reg_agent_config not found in the config db. did you set it ?")
	
	// get VIF from the config 
	vif = r_cfg.vif;
	if(vif == null)
		`uvm_fatal("REG_MONITOR","vif is null in the reg_monitor")
endfunction 

task reg_monitor :: run_phase(uvm_phase phase)
	`uvm_info("REG_MONITOR","RUN_PHASE of the reg_monitor Started")
	
	forever 
		begin 
			// --- WISHBONE MODE ----
			`ifdef CAN_WISHBONE_IF
				@(posedge vif.wb_clk_i);
				
				// Detect active cycle 
				( if (vif.wb_cb.wb_cyc_i && vif.wb_cb.wb_stb_i && vif.wb_cb.wb_ack_o)
					begin
						reg_txn = reg_transaction::type_id::create("reg_txn");
						
						// write Operation 
						if(vif.wb_cb.wb_we_i)
							begin 
								t.kind = REG_WRITE;
								t.addr = vif.wb_cb.wb_adr_i;
								t.wdata = vif.wb_cb.wb_dat_i;
							end 
						else 
							begin 
								t.kind = REG_READ;
								t.addr = vif.wb_cb.wb_adr_i;
								t.rdata = vif.wb_cb.wb_dat_o;
							end 
							
							t.success = 1'b1;
							ap.write(t);
					end 
				`else // LEGACY MODE 
					@(posedge vif.lg_cb.clk_i);
					
				
	
	