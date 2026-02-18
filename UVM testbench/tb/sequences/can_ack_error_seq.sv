`ifndef CAN_ACK_ERROR_SEQ_SV
`define CAN_ACK_ERROR_SEQ_SV

// NOTE: If this file is `include'd inside can_pkg.sv, you do NOT need imports/includes here.
// Add `include "uvm_macros.svh" / import uvm_pkg::* only if compiling standalone.

class can_ack_error_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_ack_error_seq)

  // Test can override these directly after create()
  rand bit [28:0]        id      = 29'h0000_0123;
  rand int unsigned      dlc     = 4;
  rand byte unsigned     payload[]; // optional payload bytes (0..dlc)

  function new(string name = "can_ack_error_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    // ---- Frame setup ----
    tr.can_fmt = `CAN_ID_STD;
    tr.f_type  = `CAN_DATA_FRAME;

    tr.id  = id;

    // Clamp DLC to classic CAN range 0..8
    if (dlc > 8) tr.dlc = 8;
    else         tr.dlc = dlc[3:0];

    // Tell TB/scoreboard this is an ACK-error testcase (expect no dominant ACK)
    tr.inj_stuff_error = 1'b0;
    tr.inj_crc_error   = 1'b0;
    tr.inj_form_error  = 1'b0;
    tr.inj_ack_error   = 1'b1;

    // ---- Payload ----
    tr.data = new[tr.dlc];

    if (tr.dlc == 0) begin
      // no payload
    end
    else if (payload.size() == 0) begin
      // default pattern when no payload provided
      for (int i = 0; i < tr.dlc; i++) begin
        tr.data[i] = byte'(8'hA0 + i);
      end
    end
    else begin
      // copy what user provided; pad rest with 0
      for (int i = 0; i < tr.dlc; i++) begin
        if (i < payload.size())
          tr.data[i] = payload[i];
        else
          tr.data[i] = 8'h00;
      end
    end

    // ---- Send ----
    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_ACK_ERR_SEQ",
              $sformatf("Sent ACK-error frame: id=0x%0h dlc=%0d data_bytes=%0d inj_ack_error=%0b",
                        tr.id, tr.dlc, tr.data.size(), tr.inj_ack_error),
              UVM_LOW);
  endtask

endclass : can_ack_error_seq

`endif // CAN_ACK_ERROR_SEQ_SV
