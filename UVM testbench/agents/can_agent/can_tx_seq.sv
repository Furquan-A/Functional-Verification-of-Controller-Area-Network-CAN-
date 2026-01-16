`ifndef CAN_STD_SMOKE_TX_SEQ_SV
`define CAN_STD_SMOKE_TX_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
// If your `CAN_* macros are not in can_pkg.sv, keep the next line.
// `include "can_defines.sv"

class can_std_smoke_tx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_std_smoke_tx_seq)

  function new(string name = "can_std_smoke_tx_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    // -------- Simple directed CLASSIC CAN STD data frame --------
    tr.can_fmt = `CAN_ID_STD;
    tr.id      = 29'h000_0123;          // keep it in [10:0] for STD
    tr.f_type  = `CAN_DATA_FRAME;
    tr.dlc     = 4;

    tr.data = new[tr.dlc];
    tr.data[0] = 8'hAA;
    tr.data[1] = 8'h55;
    tr.data[2] = 8'h0F;
    tr.data[3] = 8'hF0;

    // No error injection for smoke
    tr.inj_crc_error   = 1'b0;
    tr.inj_stuff_error = 1'b0;
    tr.inj_form_error  = 1'b0;
    tr.inj_ack_error   = 1'b0;

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_SMOKE_SEQ",
              $sformatf("Sent one CAN STD DATA frame: %s", tr.convert2string()),
              UVM_LOW);
  endtask

endclass : can_std_smoke_tx_seq

`endif // CAN_STD_SMOKE_TX_SEQ_SV


// ------------------------- EXTENDED FRAME SEQUENCES ----------------------------------------
`ifndef CAN_EXT_SMOKE_TX_SEQ_SV
`define CAN_EXT_SMOKE_TX_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_ext_smoke_tx_seq extends uvm_sequence #(can_transaction);
	`uvm_object_utils(can_ext_smoke_tx_seq)
	
	function new(string name  = "can_ext_smoke_tx_seq");
		super.new(name);
	endfunction 
	
	task body();
		can_transaction tr;
		
		tr = can_transaction::type_id::create("tr");
		
		tr.can_fmt = `CAN_ID_EXT;
		tr.id = 29'h1AB_CDE3; // ( any value < 2^29)
		tr.f_type = `CAN_DATA_FRAME;
		tr.dlc = 5;
		
		tr.data = new[tr.dlc];
		tr.data[0] = 8'hAA;
		tr.data[1] = 8'h44;
		tr.data[2] = 8'h22;
		tr.data[3] = 8'hA1;
		tr.data[4] = 8'h55;
		
		
		// No error injection for smoke
		tr.inj_crc_error   = 1'b0;
		tr.inj_stuff_error = 1'b0;
		tr.inj_form_error  = 1'b0;
		tr.inj_ack_error   = 1'b0;
		
		start_item(tr);
		finish_item(tr);
		
		`uv_info("CAN_SMOKE_SEQ",$sformatf("Sent one CAN EXT Frame: %s", tr.convert2string()),UVM_LOW);
	endtask 
	
endcalss 

`endif // CAN_EXT_SMOKE_TX_SEQ_SV