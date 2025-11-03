// src/reg_transaction.sv
`ifndef REG_TRANSACTION_SV
`define REG_TRANSACTION_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// Simple 8-bit register access item for your host bus (WB/legacy)
typedef enum bit { REG_RD=0, REG_WR=1 } reg_kind_e;

class reg_txn extends uvm_sequence_item;
  // ---- Core fields (8-bit address space, 8-bit data) ----
  rand reg_kind_e   kind;          // REG_RD or REG_WR
  rand bit [7:0]    addr;          // matches RTL addr[7:0]
  rand bit [7:0]    wdata;         // valid when kind==WR
       bit [7:0]    rdata;         // filled by driver on READ

  // ---- Optional meta ----
  rand bit [0:0]    be;            // byte enable (always 1 for 8-bit; keep for extensibility)
       bit          success = 1'b1;// driver/monitor can toggle on error
       int unsigned latency = 0;   // cycles observed/assumed
       time         t_start, t_end;

  // ---- Factory ----
  `uvm_object_utils_begin(reg_txn)
    `uvm_field_enum (reg_kind_e, kind,   UVM_DEFAULT)
    `uvm_field_int  (addr,                UVM_DEFAULT | UVM_HEX)
    `uvm_field_int  (wdata,               UVM_DEFAULT | UVM_HEX)
    `uvm_field_int  (rdata,               UVM_DEFAULT | UVM_HEX | UVM_NOPACK)
    `uvm_field_int  (be,                  UVM_DEFAULT | UVM_BIN)
    `uvm_field_int  (success,             UVM_DEFAULT | UVM_NOPACK)
    `uvm_field_int  (latency,             UVM_DEFAULT | UVM_DEC   | UVM_NOPACK)
    // timestamps not packed/compared
  `uvm_object_utils_end

  // ---- Constraints (basic sanity) ----
  constraint c_be_one { be == 1'b1; } // 8-bit bus → always enabled

  // ---- Ctors / convenience ----
  function new(string name="reg_txn");
  super.new(name); 
  endfunction

  static function reg_txn make_write(bit [7:0] a, bit [7:0] d);
    reg_txn t = reg_txn::type_id::create("wr");
    t.kind = REG_WR; 
	t.addr = a; 
	t.wdata = d;
	return t;
  endfunction

  static function reg_txn make_read(bit [7:0] a);
    reg_txn t = reg_txn::type_id::create("rd");
    t.kind = REG_RD;
	t.addr = a;
	return t;
  endfunction

  function bit is_read();
  return kind==REG_RD; 
  endfunction
  
  function bit is_write();
  return kind==REG_WR;
  endfunction

  // ---- Niceties ----
  function void do_print(uvm_printer p);
    super.do_print(p);
    p.print_string("kind", is_write() ? "WR" : "RD");
    p.print_field_int("addr",  addr, 8, UVM_HEX);
    if (is_write()) p.print_field_int("wdata", wdata, 8, UVM_HEX);
    else            p.print_field_int("rdata", rdata, 8, UVM_HEX);
    p.print_field_int("latency", latency, 16, UVM_DEC);
  endfunction

endclass : reg_txn

`endif // REG_TRANSACTION_SV
