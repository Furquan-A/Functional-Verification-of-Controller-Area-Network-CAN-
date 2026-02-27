`ifndef CAN_ID_BOUNDARY_SEQ_SV
`define CAN_ID_BOUNDARY_SEQ_SV

class can_id_boundary_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_id_boundary_seq)

  function new(string name = "can_id_boundary_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    // -- Frame 1: ID=0x000 — highest priority on CAN bus ------
    tr = can_transaction::type_id::create("tr_id_min");
    start_item(tr);
      tr.can_fmt         = `CAN_ID_STD;
      tr.f_type          = `CAN_DATA_FRAME;
      tr.id              = 29'h000;
      tr.dlc             = 4;
      tr.data            = new[4];
      tr.data[0]         = 8'h00;
      tr.data[1]         = 8'h01;
      tr.data[2]         = 8'h02;
      tr.data[3]         = 8'h03;
      tr.inj_crc_error   = 0;
      tr.inj_form_error  = 0;
      tr.inj_stuff_error = 0;
      tr.inj_ack_error   = 0;
      tr.force_midframe  = 0;
    finish_item(tr);

    if (!tr.ack_seen)
      `uvm_error("ID_BOUNDARY","ID=0x000 frame not ACKed")
    else
      `uvm_info("ID_BOUNDARY","PASS: ID=0x000 (highest priority) ACKed correctly", UVM_LOW)

    // -- Frame 2: ID=0x7FF — lowest priority on CAN bus -------
    tr = can_transaction::type_id::create("tr_id_max");
    start_item(tr);
      tr.can_fmt         = `CAN_ID_STD;
      tr.f_type          = `CAN_DATA_FRAME;
      tr.id              = 29'h7FF;
      tr.dlc             = 4;
      tr.data            = new[4];
      tr.data[0]         = 8'hFF;
      tr.data[1]         = 8'hFE;
      tr.data[2]         = 8'hFD;
      tr.data[3]         = 8'hFC;
      tr.inj_crc_error   = 0;
      tr.inj_form_error  = 0;
      tr.inj_stuff_error = 0;
      tr.inj_ack_error   = 0;
      tr.force_midframe  = 0;
    finish_item(tr);

    if (!tr.ack_seen)
      `uvm_error("ID_BOUNDARY","ID=0x7FF frame not ACKed")
    else
      `uvm_info("ID_BOUNDARY","PASS: ID=0x7FF (lowest priority) ACKed correctly", UVM_LOW)

    `uvm_info("ID_BOUNDARY","Both ID boundary frames complete", UVM_LOW)

  endtask

endclass
`endif