`ifndef CAN_REMOTE_RESPONSE_SEQ_SV
`define CAN_REMOTE_RESPONSE_SEQ_SV

class can_remote_response_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_remote_response_seq)

  // node1's sequencer — set from test before calling start()
  can_sequencer other_sqr;

  // Configurable fields
  rand bit [10:0] req_id;
  rand bit [3:0]  req_dlc;
  rand bit [7:0]  resp_data[];  // data node1 will send back

  // Constraints
  constraint valid_dlc  { req_dlc inside {[1:8]}; }
  constraint data_size  { resp_data.size() == req_dlc; }

  function new(string name="can_remote_response_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction remote_tr;
    can_transaction data_tr;
    uvm_sequencer_base saved;

    if(other_sqr == null)
      `uvm_fatal("REM_RSP_SEQ","other_sqr is null — set from test")

    // -- Step 1: node0 sends REMOTE frame ----------------------
    remote_tr = can_transaction::type_id::create("remote_tr");
    start_item(remote_tr);
      remote_tr.can_fmt        = `CAN_ID_STD;
      remote_tr.f_type         = `CAN_REMOTE_FRAME;
      remote_tr.id             = req_id;
      remote_tr.dlc            = req_dlc;
      remote_tr.data           = new[0];   // REMOTE has no data field
      remote_tr.inj_crc_error  = 0;
      remote_tr.inj_form_error = 0;
      remote_tr.inj_stuff_error= 0;
      remote_tr.inj_ack_error  = 0;
      remote_tr.force_midframe = 0;
    finish_item(remote_tr);

    // Guard: REMOTE must be ACKed by node1
    if(!remote_tr.ack_seen) begin
      `uvm_error("REM_RSP_SEQ",
        $sformatf("REMOTE frame (id=0x%0h) not ACKed — response test aborted",
                  req_id))
      return;
    end

    `uvm_info("REM_RSP_SEQ",
      $sformatf("REMOTE sent (id=0x%0h dlc=%0d) — waiting for DATA response",
                req_id, req_dlc),
      UVM_LOW)

    // -- Step 2: node1 responds with DATA frame -----------------
    data_tr = can_transaction::type_id::create("data_tr");
    saved       = m_sequencer;   // save node0
    m_sequencer = other_sqr;     // swap to node1

    start_item(data_tr);
      data_tr.can_fmt        = `CAN_ID_STD;
      data_tr.f_type         = `CAN_DATA_FRAME;
      data_tr.id             = remote_tr.id;   // MUST match REMOTE id
      data_tr.dlc            = remote_tr.dlc;  // MUST match REMOTE dlc
      data_tr.data           = new[req_dlc];
      foreach(resp_data[i])
        data_tr.data[i]      = resp_data[i];
      data_tr.inj_crc_error  = 0;
      data_tr.inj_form_error = 0;
      data_tr.inj_stuff_error= 0;
      data_tr.inj_ack_error  = 0;
      data_tr.force_midframe = 0;
    finish_item(data_tr);

    m_sequencer = saved;          // restore node0

    // Guard: DATA response must be ACKed by node0
    if(!data_tr.ack_seen) begin
      `uvm_error("REM_RSP_SEQ",
        $sformatf("DATA response (id=0x%0h) not ACKed by node0",
                  req_id))
      return;
    end

    `uvm_info("REM_RSP_SEQ",
      $sformatf("DATA response received (id=0x%0h dlc=%0d) — test complete",
                req_id, req_dlc),
      UVM_LOW)

  endtask

endclass
`endif