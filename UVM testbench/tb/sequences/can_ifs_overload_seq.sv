`ifndef CAN_IFS_OVERLOAD_SEQ_SV
`define CAN_IFS_OVERLOAD_SEQ_SV

class can_ifs_overload_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_ifs_overload_seq)
  
  can_sequencer other_sqr;
  rand bit f_type;
  time gap_after_data = 0ns;
  
  function new (string name = "can_ifs_overload_seq");
    super.new(name);
  endfunction 
  
  task body();
  can_transaction data_tr;
  can_transaction ovl_tr;
  uvm_sequencer_base saved;

  if (other_sqr == null)
    `uvm_fatal("IFS_OVL_SEQ", "other_sqr is null, set it from TEST");

  // Primer DATA on node0
  data_tr = can_transaction::type_id::create("data_tr");
  start_item(data_tr);
    data_tr.can_fmt = `CAN_ID_STD;
    data_tr.id      = 11'h321;
    data_tr.dlc     = 1;
    data_tr.f_type  = `CAN_DATA_FRAME;
    data_tr.data    = new[1];
    data_tr.data[0] = 8'hA5;

    data_tr.inj_crc_error   = 0;
    data_tr.inj_stuff_error = 0;
    data_tr.inj_form_error  = 0;
    data_tr.inj_ack_error   = 0;
    data_tr.force_midframe  = 0;
  finish_item(data_tr);

  `uvm_info("IFS_OVL_SEQ", "Primer DATA requested", UVM_LOW);

  // Request OVERLOAD on node1 (driver will wait for idle/IFS alignment)
  ovl_tr = can_transaction::type_id::create("ovl_tr");
  saved = m_sequencer;
  m_sequencer = other_sqr;

  start_item(ovl_tr);
    ovl_tr.can_fmt = `CAN_ID_STD;
    ovl_tr.id      = 0;
    ovl_tr.dlc     = 0;
    ovl_tr.data    = new[0];
    ovl_tr.f_type  = `CAN_OVERLOAD_FRAME;

    ovl_tr.inj_crc_error   = 0;
    ovl_tr.inj_stuff_error = 0;
    ovl_tr.inj_form_error  = 0;
    ovl_tr.inj_ack_error   = 0;
    ovl_tr.force_midframe  = 0;
  finish_item(ovl_tr);

  m_sequencer = saved;

  `uvm_info("IFS_OVL_SEQ", "OVERLOAD requested on node1", UVM_LOW);
endtask

endclass

`endif