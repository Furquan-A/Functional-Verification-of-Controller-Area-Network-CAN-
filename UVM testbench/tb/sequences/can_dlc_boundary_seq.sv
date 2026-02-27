`ifndef CAN_DLC_BOUNDARY_SEQ_SV
`define CAN_DLC_BOUNDARY_SEQ_SV

class can_dlc_boundary_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dlc_boundary_seq)

  function new(string name = "can_dlc_boundary_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    // -- Frame 1: DLC=0 (zero-byte DATA frame) ----------------
    tr = can_transaction::type_id::create("tr_dlc0");
    start_item(tr);
      tr.can_fmt         = `CAN_ID_STD;
      tr.f_type          = `CAN_DATA_FRAME;
      tr.id              = 11'h111;
      tr.dlc             = 0;
      tr.data            = new[0];   // empty — no data field
      tr.inj_crc_error   = 0;
      tr.inj_form_error  = 0;
      tr.inj_stuff_error = 0;
      tr.inj_ack_error   = 0;
      tr.force_midframe  = 0;
    finish_item(tr);

    if(!tr.ack_seen)
      `uvm_error("DLC_BOUNDARY","DLC=0 frame not ACKed")
    else
      `uvm_info("DLC_BOUNDARY","PASS: DLC=0 frame ACKed correctly", UVM_LOW)

    // -- Frame 2: DLC=8 (maximum payload) ---------------------
    tr = can_transaction::type_id::create("tr_dlc8");
    start_item(tr);
      tr.can_fmt         = `CAN_ID_STD;
      tr.f_type          = `CAN_DATA_FRAME;
      tr.id              = 11'h222;
      tr.dlc             = 8;
      tr.data            = new[8];
      tr.data[0]         = 8'hDE;
      tr.data[1]         = 8'hAD;
      tr.data[2]         = 8'hBE;
      tr.data[3]         = 8'hEF;
      tr.data[4]         = 8'hCA;
      tr.data[5]         = 8'hFE;
      tr.data[6]         = 8'hBA;
      tr.data[7]         = 8'hBE;
      tr.inj_crc_error   = 0;
      tr.inj_form_error  = 0;
      tr.inj_stuff_error = 0;
      tr.inj_ack_error   = 0;
      tr.force_midframe  = 0;
    finish_item(tr);

    if(!tr.ack_seen)
      `uvm_error("DLC_BOUNDARY","DLC=8 frame not ACKed")
    else
      `uvm_info("DLC_BOUNDARY","PASS: DLC=8 frame ACKed correctly", UVM_LOW)

    `uvm_info("DLC_BOUNDARY","Both DLC boundary frames complete", UVM_LOW)

  endtask

endclass
`endif