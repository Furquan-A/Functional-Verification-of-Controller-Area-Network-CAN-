`ifndef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh";
import uvm_pkg::*;

class reg_driver extends uvm_component;
`uvm_component_utils(reg_driver)

virtual can_if vif;
reg_agent_config m_cfg;

function new(string name = "reg_driver", uvm_component parent);
super.new(name,parent);
endfunction 

function void build_phase(uvm_phase phase);
super.build_phase(phase);

if(!uvm_config_db#(reg_agent_config) :: get(this,"","m_cfg",m_cfg);
`uvm_fatal("REG_DRIVER", "cannot get the interface from reg_agent_config. Did you set() it ?",UVM_LOW)


