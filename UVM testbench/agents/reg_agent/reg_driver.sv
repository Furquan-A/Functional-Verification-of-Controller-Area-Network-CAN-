`ifndef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_driver extends uvm_driver #(reg_transaction);

	`uvm_component_utils(reg_driver)
	
	
	reg_agent_config r_cfg;
	
	// virtual Interface 
	virtual can_if vif;
	
	
	
	extern function new( string name = "reg_driver", uvm_component parent );
	extern function void build_phase(uvm_phase phase);
	extern function void connect_phase(uvm_phase phase);
	extern function void start_of_elaboration_phase(uvm_phase phase);
	extern task run_phase (uvm_phase phase);
	extern task send_to_dut(reg_transaction req);
	
endclass : reg_driver 
`endif // REG_DRIVER_SV
// ================================== new ==============================================================

function reg_driver :: new(string name = "reg_driver", uvm_component parent);
	super.new(name,parent);
endfunction 

// ================================= build_phase =======================================================

function void reg_driver :: build_phase(uvm_phase phase);
	string why; // all the declarations must be before any executional statement
	super.build_phase(phase);
		
	if(!uvm_config_db#(reg_agent_config) :: get(this,"m_cfg",r_cfg))
		`uvm_fatal("DRIVER config ","cannot get the CONFIG from db. did you set it ?")
		
	// sanity check config 
	
	if(!r_cfg.validate(why))
		`uvm_fatal("REG_DRIVER",$sformaatf("Invalid reg_agent_config: %s",why))
	
	// Cache Virtual Interface 
	vif = r_cfg.vif;
	if(vif==null)
		`uvm_fatal("REG_DRIVER","vif is null in the reg_driver")
		
	`uvm_info("REG_DRV", $sformatf("Driver ready on %s bus (trace_ops=%0b)", m_cfg.bus_name(), m_cfg.trace_ops), UVM_LOW)
	
 endfunction

// ====================== run_phase ======================================================================
task reg_driver :: run_phase(uvm_phase phase);
	reg_transaction req;
	`uvm_info("REG_DRIVER","reg_driver started run_phase",UVM_LOW);
	
	forever
		begin 
			// 1. block until the seequence sends us a transaction 
			start_item_port_get_next_item(req);
			
			// call the send to dut method to perform the operations 
			send_to_dut(req); // <-- All DUT actions are handled here 
			
			// tell the sequencer we're done
			seq_item_port.item_done(req);
		end 
endtask 
			
// ============================== send_to_dut ==========================================================

task reg_driver :: send_to_dut(reg_transaction req);

	
	// perform the operation via interface 
	t.t_start = $time;
	if(req.is_write())
		begin 
			vif.reg_write(req.addr,req.wdata);
			r_cfg.wr_cnt++;
		if(r_cfg.trace_ops)
			begin 
				`uvm_info("REG_DRV",$sformatf("[%s] WR @0x%02h = 0x%02h",vif.USE_WB ? "WB" : "LEG",t.addr, t.wdata),UVM_LOW)
			end
		end
	else 
		begin 
			byte unsigned q;
			vif.reg_read(req.addr,q);
			req.rdata = q;
			r_cfg.rd_cnt++;
					
			if (m_cfg.trace_ops) 
				begin
					`uvm_info("REG_DRV",$sformatf("[%s] RD @0x%02h -> 0x%02h",vif.USE_WB ? "WB" : "LEG", t.addr, t.rdata),UVM_LOW)
				end 
		end 
		
	t.t_end = $time;
	req.success = 1'b1; // mark transaction is successful	
endtask 
		
