`ifndef CAN_ARB_TX_SEQ_SV
`define CAN_ARB_TX_SEQ_SV

// Parameterized arbitration TX sequence
// You configure the fields before start()
class can_arb_tx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_arb_tx_seq)

  // knobs you set from the test
  bit        cfg_fmt;          // `CAN_ID_STD or `CAN_ID_EXT
  bit [28:0] cfg_id;
  bit        cfg_remote;       // 1 => remote frame, 0 => data frame
  byte unsigned cfg_data[];    // for data frame
  int unsigned  cfg_dlc;       // will be clamped to 0..8

  function new(string name="can_arb_tx_seq");
    super.new(name);
  endfunction

  // Helper: build one transaction
  task body();
    can_transaction tr;

    tr = can_transaction::type_id::create("tr");

    tr.can_fmt = cfg_fmt;
    tr.id      = cfg_id;

    tr.f_type  = (cfg_remote) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

    // DLC / payload
    if (tr.f_type == `CAN_DATA_FRAME) begin
      int unsigned n;
      n = cfg_data.size();
      if (n > 8) n = 8;

      tr.data = new[n];
      foreach (tr.data[i]) tr.data[i] = cfg_data[i];

      tr.dlc = n[3:0]; // match payload by default
      if (cfg_dlc <= 8) tr.dlc = cfg_dlc[3:0]; // allow override
    end
    else begin
      tr.data = new[0];
      tr.dlc  = (cfg_dlc <= 8) ? cfg_dlc[3:0] : 4'd0;
    end

    // Disable error injection for arbitration smoke
    tr.inj_crc_error   = 1'b0;
    tr.inj_stuff_error = 1'b0;
    tr.inj_form_error  = 1'b0;
    tr.inj_ack_error   = 1'b0;

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_ARB_SEQ",
              $sformatf("Started TX for arbitration: %s",
                        tr.convert2string()),
              UVM_LOW);
  endtask

endclass : can_arb_tx_seq

`endif // CAN_ARB_TX_SEQ_SV



`ifndef CAN_STD_ARB_SMOKE_SEQ_SV
`define CAN_STD_ARB_SMOKE_SEQ_SV

class can_std_arb_smoke_seq extends can_arb_tx_seq;
  `uvm_object_utils(can_std_arb_smoke_seq)

  function new(string name="can_std_arb_smoke_seq");
    super.new(name);
    cfg_fmt = `CAN_ID_STD;
  endfunction
endclass

`endif


`ifndef CAN_EXT_ARB_SMOKE_SEQ_SV
`define CAN_EXT_ARB_SMOKE_SEQ_SV

class can_ext_arb_smoke_seq extends can_arb_tx_seq;
  `uvm_object_utils(can_ext_arb_smoke_seq)

  function new(string name="can_ext_arb_smoke_seq");
    super.new(name);
    cfg_fmt = `CAN_ID_EXT;
  endfunction
endclass

`endif
