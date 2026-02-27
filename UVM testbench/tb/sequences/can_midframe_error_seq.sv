`ifndef CAN_MIDFRAME_ERROR_SEQ_SV
`define CAN_MIDFRAME_ERROR_SEQ_SV

class can_midframe_error_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_midframe_error_seq)

  can_sequencer other_sqr;      // set by test (node1)
  time err_delay = 10us;        // when node1 injects error flag

  function new(string name="can_midframe_error_seq");
    super.new(name);
  endfunction

  task body();
    if (other_sqr == null)
      `uvm_fatal("MID_ERR_SEQ", "other_sqr is null. Set it from test (node1 sequencer).")

    fork
      // Node0: long DATA
      begin
        can_transaction tr;
        tr = can_transaction::type_id::create("long_data");
        start_item(tr);
          tr.can_fmt = `CAN_ID_STD;
          tr.id      = 11'h120;
          tr.dlc     = 8;
          tr.f_type  = `CAN_DATA_FRAME;
          tr.data    = new[8];
          foreach (tr.data[i]) tr.data[i] = $urandom_range(0,255);
          tr.inj_crc_error   = 0;
          tr.inj_stuff_error = 0;
          tr.inj_form_error  = 0;
          tr.inj_ack_error   = 0;
          tr.force_midframe  = 0;
        finish_item(tr);
        `uvm_info("MID_ERR_SEQ", "Started LONG DATA on node0", UVM_LOW);
      end

      // Node1: forced ERROR mid-frame
      begin
         can_transaction tr;
         uvm_sequencer_base saved = m_sequencer;
        #(err_delay);

       
        tr = can_transaction::type_id::create("err_mid");

        
        m_sequencer = other_sqr;

        start_item(tr);
          tr.can_fmt = `CAN_ID_STD;
          tr.id      = 0;
          tr.dlc     = 0;
          tr.data    = new[0];
          tr.f_type  = `CAN_ERROR_FRAME;
          tr.inj_crc_error   = 0;
          tr.inj_stuff_error = 0;
          tr.inj_form_error  = 0;
          tr.inj_ack_error   = 0;
          tr.force_midframe  = 1; // KEY: driver must skip wait_for_idle_bus()
        finish_item(tr);

        m_sequencer = saved;

        `uvm_info("MID_ERR_SEQ",
          $sformatf("Requested FORCED mid-frame ERROR after %0t", err_delay),
          UVM_LOW);
      end
    join
  endtask

endclass

`endif