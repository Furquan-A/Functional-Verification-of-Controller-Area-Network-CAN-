`ifndef CAN_SEQUENCER_SV
`define CAN_SEQUENCER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_sequencer extends uvm_sequencer #(can_transaction) ;
	
	`uvm_component_utils(can_sequencer)
	
	extern function new(string name = "can_sequencer", uvm_component parent);
	extern function void build_phase(uvm_phase phase);
	
endclass 

function can_sequencer :: new(string name = "can_sequencer",uvm_component parent);
	super.new(name,parent);
endfunction 

function void can_sequencer :: build_phase(uvm_phase phase);	
	super.build_phase(phase);
	
	`uvm_info(get_full_name(), "Inside Build_phase", UVM_LOW)
endfunction 

`endif