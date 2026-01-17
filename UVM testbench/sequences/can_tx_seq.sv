`ifndef CAN_TX_SEQ_SV
`define CAN_TX_SEQ_SV

// NOTE: This file is `include'd inside can_pkg.sv
// لذلك: no imports, no `include "uvm_macros.svh" here.

class can_std_smoke_tx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_std_smoke_tx_seq)

  function new(string name = "can_std_smoke_tx_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    tr.can_fmt = `CAN_ID_STD;
    tr.id      = 29'h00000123;
    tr.f_type  = `CAN_DATA_FRAME;
    tr.dlc     = 4;

    tr.data = new[tr.dlc];
    tr.data[0] = 8'hAA;
    tr.data[1] = 8'h55;
    tr.data[2] = 8'h0F;
    tr.data[3] = 8'hF0;

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_STD_SMOKE_SEQ",
              $sformatf("Sent STD frame: %s", tr.convert2string()),
              UVM_LOW);
  endtask

endclass : can_std_smoke_tx_seq

`endif // CAN_TX_SEQ_SV
