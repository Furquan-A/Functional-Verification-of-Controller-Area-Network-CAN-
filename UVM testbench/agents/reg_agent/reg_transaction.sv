// This is the only transaction type the reg_agent ever needs 

`ifndef REG_TRANSACTION_SV
`define REG_TRANSACTION_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit {REG_READ = 0 , REG_WRITE = 1} reg_kind_e;

class reg_transaction extends uvm_sequence_item;

	`uvm_object_utils(reg_transaction)
	`uvm_field_enum (reg_kind_e, kind,   UVM_DEFAULT)
    `uvm_field_int  (addr,               UVM_DEFAULT | UVM_HEX)
    `uvm_field_int  (wdata,              UVM_DEFAULT | UVM_HEX)
    `uvm_field_int  (rdata,              UVM_DEFAULT | UVM_HEX | UVM_NOPACK)
    `uvm_field_int  (success,            UVM_DEFAULT | UVM_NOPACK)
	`uvm_object_utils_end
	
	rand reg_kind_e kind; // read or write 
	rand bit [7:0] addr; // register address 
	rand bit [7:0] wdata; // write data (valid only for write)
	bit [7:0] rdata; // read data (driver fills the read)
	bit success; // 1 = OK, 0 = timeout/Failure
	
	/* 
	✔ These timestamps are optional metadata
	They allow you to measure:
	How long a register operation takes
	Time spacing between operations
	When a reg request was issued vs when CAN events occurred
L	atency correlation between reg ops and CAN bus behavior
	*/
	
	time t_start;
	time t_end;
	
	 // Constraints
	constraint c_addr_range { addr inside {[8'h00 : 8'hFF]}; }
	
	extern function new(string name = "reg_transaction");
	extern function bit is_read();
	extern function bit is_write();
	extern function do_print(uvm_printer printer);

endclass 

function reg_transaction :: new(string name = "reg_transaction");
	super.new(name);
endfunction 

function bit reg_transaction :: is_read();
	return (kind == REG_READ);
endfunction 

function bit reg_transaction :: is_write();
	return (kind == REG_WRITE);
endfunction 

function void reg_transaction :: do_print(uvm_printer printer);
	super.do_print(printer);
	
	printer.print_string("kind",  is_write() ? "WRITE" : "READ");
    printer.print_field_int("addr",  addr, 8, UVM_HEX);
    if (is_write())
      printer.print_field_int("wdata", wdata, 8, UVM_HEX);
    else
      printer.print_field_int("rdata", rdata, 8, UVM_HEX);
    printer.print_field_int("success", success, 1, UVM_BIN);
  endfunction
	
`endif // REG_TRANSACTION_SV