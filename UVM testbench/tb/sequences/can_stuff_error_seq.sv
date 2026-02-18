`ifndef CAN_STUFF_ERROR_SEQ_SV
`define CAN_STUFF_ERROR_SEQ_SV

class can_stuff_error_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_stuff_error_seq)

  rand bit [28:0]        id  = 29'h00000123;
  rand int unsigned      dlc = 4;
  rand byte unsigned     payload[];

  bit use_go_event = 0;

  function new(string name="can_stuff_error_seq");
    super.new(name);
  endfunction

  function void fill_data(ref can_transaction tr);
    tr.data = new[tr.dlc];

    // IMPORTANT: choose a payload that tends to create long runs
    // (but even if not, our driver skips the first required stuff bit it encounters)
    if (payload.size() == 0) begin
      for (int i=0; i<tr.dlc; i++) tr.data[i] = 8'h00; // lots of zeros => long runs
    end
    else begin
      for (int i=0; i<tr.dlc; i++) begin
        if (i < payload.size()) tr.data[i] = payload[i];
        else                    tr.data[i] = 8'h00;
      end
    end
  endfunction

  task body();
    uvm_event go;
    can_transaction tr;

    if (use_go_event) begin
      go = uvm_event_pool::get_global("STUFF_GO");
      go.wait_trigger();
    end

    tr = can_transaction::type_id::create("tr");

    tr.can_fmt = `CAN_ID_STD;
    tr.f_type  = `CAN_DATA_FRAME;
    tr.id      = this.id;
    tr.dlc     = this.dlc[3:0];
    
    tr.inj_stuff_error = 1'b1;
    tr.inj_crc_error   = 1'b0;
    tr.inj_form_error  = 1'b0;
    tr.inj_ack_error   = 1'b0;

    fill_data(tr);

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_STUFF_ERR_SEQ",
      $sformatf("Sent STUFF-BAD frame (inj_stuff_error=1): id=0x%0h dlc=%0d", tr.id, tr.dlc),
      UVM_LOW);

  endtask

endclass : can_stuff_error_seq

`endif // CAN_STUFF_ERROR_SEQ_SV
