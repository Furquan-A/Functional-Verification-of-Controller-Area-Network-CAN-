`ifndef REG_MONITOR_SV
`define REG_MONITOR_SV

`include "uvm_macros.svh"
//import uvm_pkg::*;
//`include "can_defines.sv"

class reg_monitor extends uvm_component;
	`uvm_component_utils(reg_monitor)
	
	uvm_analysis_port#(reg_transaction) ap;
	
	virtual can_if vif;
	reg_agent_config r_cfg;
		
	
	
	extern function new(string name = "reg_monitor",uvm_component parent);
	extern function void  build_phase(uvm_phase phase);
	extern task run_phase(uvm_phase phase);

endclass : reg_monitor



function reg_monitor :: new (string name = "reg_monitor", uvm_component parent);
	super.new(name,parent);
	ap = new("ap",this);
endfunction 

function reg_monitor :: build_phase(uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db#(reg_agent_config)::get(this,"","m_cfg",r_cfg))
		begin 
			`uvm_fatal("REG_MONITOR","reg_agent_config not found in the config db. did you set it ?")
		end 
	// get VIF from the config 
	vif = r_cfg.vif;
	if(vif == null)
		begin 
			`uvm_fatal("REG_MONITOR","vif is null in the reg_monitor")
		end
endfunction 


task reg_monitor :: run_phase(uvm_phase phase);
	`uvm_info("REG_MONITOR","RUN_PHASE of the reg_monitor Started",UVM_LOW)
	
	forever 
		begin 
			// --- WISHBONE MODE ----
			`ifdef CAN_WISHBONE_IF
				@(posedge vif.wb_clk_i);
				
				// Detect active cycle 
				( if (vif.wb_cb.wb_cyc_i && vif.wb_cb.wb_stb_i && vif.wb_cb.wb_ack_o)
					begin
						reg_transaction t = reg_transaction::type_id::create("t");
						
						t.addr = vif.wb_cb.wb_adr_i;
						t.success = 1'b1;
						
						// write Operation 
						if(vif.wb_cb.wb_we_i)
							begin 
								t.kind = REG_WRITE;
								t.wdata = vif.wb_cb.wb_dat_i;
							end 
						else // Read operation 
							begin 
								t.kind = REG_READ;
								t.rdata = vif.wb_cb.wb_dat_o;
							end 
							
							
							ap.write(t);
					end 
			`else // ------ LEGACY MODE ------
				@(posedge vif.lg_cb.clk_i);
					
				// Write detected when write HIGH and Chip select HIGH 
				if (vif.lg_cb.cs_can_i && vif.lg_cb.wr_i) 
					begin
						reg_transaction t = reg_transaction::type_id::create("t");
							
						t.kind = REG_WRITE;
						t.addr = vif.lg_cb.port_0_o; // address phase
						t.wdata = vif.lg_cb.port_0_o;// data (shared bus)
							
						t.success = 1'b1;
						ap.write(t);
					end 
					
				// Read detected when RD is HIGH and Chip Select ACTIVE 
				if (vif.lg_cb.cs_can_i && vif.lg_cb.rd_i) 
					begin
						reg_transaction t = reg_transaction::type_id::create("t");
							
						t.kind = REG_READ;
						t.addr = vif.lg_cb.port_0_o; // address phase
						t.rdata = vif.lg_cb.port_0_i;
							
						t.success = 1'b1;
						ap.write(t);
					end 
			`endif
		end 
endtask 

`endif // REG_MONITOR_SV	
				
	
	