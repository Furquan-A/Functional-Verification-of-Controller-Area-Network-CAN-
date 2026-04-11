`ifndef CAN_NODE_BUSY_SEQ_SV
`define CAN_NODE_BUSY_SEQ_SV

class can_node_busy_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_node_busy_seq)

  function new(string name = "can_node_busy_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt         == `CAN_ID_STD;
      id              == 11'h321;
      dlc             == 4'd8;
      f_type          == `CAN_DATA_FRAME;
      data.size()     == 8;
      data[0]         == 8'h11;
      data[1]         == 8'h22;
      data[2]         == 8'h33;
      data[3]         == 8'h44;
      data[4]         == 8'h55;
      data[5]         == 8'h66;
      data[6]         == 8'h77;
      data[7]         == 8'h88;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("NODE_BUSY_SEQ", "Randomization failed")
    finish_item(tr);
  endtask

endclass

`endif