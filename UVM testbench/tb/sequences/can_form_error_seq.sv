`ifndef CAN_FORM_ERROR_SEQ_SV
`define CAN_FORM_ERROR_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_form_error_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_form_error_seq)

  rand bit [28:0]    id  = 29'h00000123;
  rand int unsigned  dlc = 4;
  rand byte unsigned payload[];

  function new(string name="can_form_error_seq");
    super.new(name);
  endfunction

  function void fill_data(ref can_transaction tr);
    tr.data = new[tr.dlc];
    if (payload.size() == 0) begin
      for (int i = 0; i < tr.dlc; i++)
        tr.data[i] = byte'(8'hD0 + i);
    end
    else begin
      for (int i = 0; i < tr.dlc; i++)
        tr.data[i] = (i < payload.size()) ? payload[i] : 8'h00;
    end
  endfunction

  task body();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    tr.can_fmt = `CAN_ID_STD;
    tr.f_type  = `CAN_DATA_FRAME;
    tr.id      = this.id;
    tr.dlc     = this.dlc[3:0];

    // Inject FORM error (CRC delimiter). Driver will auto-clear after first attempt.
    tr.inj_stuff_error = 1'b0;
    tr.inj_crc_error   = 1'b0;
    tr.inj_form_error  = 1'b1;
    tr.inj_ack_error   = 1'b0;
    
    fill_data(tr);

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_FORM_ERR_SEQ",
      $sformatf("Sent FORM-BAD frame (inj_form_error=1, auto-clear on retry): id=0x%0h dlc=%0d",
                tr.id, tr.dlc),
      UVM_LOW);
  endtask

endclass : can_form_error_seq

`endif
