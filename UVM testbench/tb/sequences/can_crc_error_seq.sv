`ifndef CAN_CRC_ERROR_SEQ_SV
`define CAN_CRC_ERROR_SEQ_SV

class can_crc_error_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_crc_error_seq)

  rand bit [28:0]        id  = 29'h00000123;
  rand int unsigned      dlc = 4;
  rand byte unsigned     payload[];

  // optional barrier
  bit use_go_event = 0;

  function new(string name = "can_crc_error_seq");
    super.new(name);
  endfunction

  // helper: fill payload deterministically
  function void fill_data(ref can_transaction tr);
    tr.data = new[tr.dlc];

    if (payload.size() == 0) begin
      for (int i = 0; i < tr.dlc; i++)
        tr.data[i] = byte'(8'hC0 + i);
    end
    else begin
      for (int i = 0; i < tr.dlc; i++) begin
        if (i < payload.size())
          tr.data[i] = payload[i];
        else
          tr.data[i] = 8'h00;
      end
    end
  endfunction

  task body();
    uvm_event go;
    can_transaction tr;

    if (use_go_event) begin
      go = uvm_event_pool::get_global("CRC_GO");
      go.wait_trigger();
    end

    // ------------------------------------------------------------
    // Send ONE frame with CRC injection.
    // Driver should see no-ACK and retry until success.
    // ------------------------------------------------------------
    tr = can_transaction::type_id::create("tr");

    tr.can_fmt = `CAN_ID_STD;
    tr.f_type  = `CAN_DATA_FRAME;
    tr.id      = this.id;
    tr.dlc     = this.dlc[3:0];

    tr.inj_stuff_error = 1'b0;
    tr.inj_crc_error   = 1'b1;
    tr.inj_form_error  = 1'b0;
    tr.inj_ack_error   = 1'b0;

    fill_data(tr);

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_CRC_ERR_SEQ",
      $sformatf("Sent CRC-BAD frame (inj_crc_error=1): id=0x%0h dlc=%0d", tr.id, tr.dlc),
      UVM_LOW);

  endtask

endclass : can_crc_error_seq

`endif // CAN_CRC_ERROR_SEQ_SV
