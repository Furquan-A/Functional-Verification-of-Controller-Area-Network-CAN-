`ifndef REG_SEQUENCER_SV
`define REG_SEQUENCER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_sequencer extends uvm_sequencer#(reg_transactions);
`uvm_component_utils(reg_sequencer)

function new(string name = "reg_sequencer", uvm_component parent);
super.new(name,parent);
endfunction 

function void build_phase(uvm_phase phase);
super.build_phase(phase);
`uvm_info(get_full_name(), "Inside Build_phase", UVM)
endfunction 

endclass 

`endif
