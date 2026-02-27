`ifndef CAN_EXT_DATA_SEQ_SV
`define CAN_EXT_DATA_SEQ_SV

class can_ext_data_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_ext_data_seq)

  rand bit [28:0] ext_id;
  rand bit [3:0]  dlc;
  rand byte unsigned payload[];

  constraint c_dlc { dlc inside {[1:8]}; }
  constraint c_id  { ext_id inside {[29'h0001000 : 29'h1FFFFFFF]}; } // keep it truly "extended"
  constraint c_pl  { payload.size() == dlc; }

  function new(string name="can_ext_data_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;
    tr = can_transaction::type_id::create("tr");

    start_item(tr);
      tr.can_fmt = `CAN_ID_EXT;
      tr.f_type  = `CAN_DATA_FRAME;
      tr.id      = ext_id;
      tr.dlc     = dlc;

      tr.data = new[dlc];
      foreach (tr.data[i]) tr.data[i] = payload[i];

      tr.inj_crc_error   = 0;
      tr.inj_stuff_error = 0;
      tr.inj_form_error  = 0;
      tr.inj_ack_error   = 0;

      tr.force_midframe  = 0;
    finish_item(tr);

    `uvm_info("EXT_SEQ",
      $sformatf("Sent EXT DATA id=0x%0h dlc=%0d", tr.id, tr.dlc),
      UVM_LOW);
  endtask

endclass

`endif