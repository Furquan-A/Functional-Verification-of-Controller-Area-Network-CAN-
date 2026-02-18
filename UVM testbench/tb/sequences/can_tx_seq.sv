`ifndef CAN_TX_SEQ_SV
`define CAN_TX_SEQ_SV

// This file is `include'd inside can_pkg.sv
// So: NO imports, NO `include "uvm_macros.svh" here.

class can_std_smoke_tx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_std_smoke_tx_seq)

  // Let the TEST control the arbitration ID
  rand bit [28:0] id;       // To be set by test
  rand int        can_fmt;  // To be set by test 
  rand int        dlc;      // To be set by test
  rand byte unsigned  data[];   // To be set by test
  rand bit [10:0] req_id = 11'h123;

  // Optional barrier (used for arbitration tests)
  bit use_go_event = 0;

  function new(string name = "can_std_smoke_tx_seq");
    super.new(name);
  endfunction
  
  
  
  
  task body();
  
    uvm_event e;
    can_transaction tr;
     `uvm_info("ARB_SYNC",
            $sformatf("%s: entered body(), use_go_event=%0b", get_full_name(), use_go_event),
            UVM_LOW)

      if (use_go_event) begin
        e = uvm_event_pool::get_global("ARB_GO");
        `uvm_info("ARB_SYNC", $sformatf("%s: waiting on ARB_GO", get_full_name()), UVM_LOW)
        e.wait_trigger();
        `uvm_info("ARB_SYNC", $sformatf("%s: released by ARB_GO", get_full_name()), UVM_LOW)
      end

    tr = can_transaction::type_id::create("tr");
    tr.can_fmt = this.can_fmt; 
    tr.id      = this.id;
    
    tr.dlc = (dlc < 0) ? 0 : dlc;
    if (tr.dlc > 8) tr.dlc = 8;
    
    tr.data = new[tr.dlc];
    for (int i = 0; i < tr.dlc; i++) begin
      tr.data[i] = (i < data.size()) ? data[i] : 8'h00;
    end
    tr.inj_crc_error   = 1'b0;
    tr.inj_stuff_error = 1'b0;
    tr.inj_form_error  = 1'b0;
    tr.inj_ack_error   = 1'b0;

    start_item(tr);
    finish_item(tr);

     `uvm_info("CAN_STD_SMOKE_SEQ",
              $sformatf("SEQ node TX request: %s", tr.convert2string()),
              UVM_LOW);
  endtask
endclass : can_std_smoke_tx_seq


class can_ext_smoke_tx_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_ext_smoke_tx_seq)

  // Let the TEST control arbitration ID (29-bit)
  rand bit [28:0] id;       // To be set by test
  rand int        can_fmt;  // To be set by test 
  rand int        dlc;      // To be set by test
  rand byte unsigned data[];   // To be set by test
  rand bit [28:0] req_id = 29'h1BC_D123;

  bit use_go_event = 0;

  function new(string name = "can_ext_smoke_tx_seq");
    super.new(name);
  endfunction

  task body();
    uvm_event e;
    can_transaction tr;

     `uvm_info("ARB_SYNC",
            $sformatf("%s: entered body(), use_go_event=%0b", get_full_name(), use_go_event),
            UVM_LOW)

      if (use_go_event) begin
        e = uvm_event_pool::get_global("ARB_GO");
        `uvm_info("ARB_SYNC", $sformatf("%s: waiting on ARB_GO", get_full_name()), UVM_LOW)
        e.wait_trigger();
        `uvm_info("ARB_SYNC", $sformatf("%s: released by ARB_GO", get_full_name()), UVM_LOW)
      end
      
    tr = can_transaction::type_id::create("tr");
    tr.can_fmt = this.can_fmt; 
    tr.id      = this.id;
    
    tr.dlc = (dlc < 0) ? 0 : dlc;
    if (tr.dlc > 8) tr.dlc = 8; // classic clamp for now

    tr.data = new[tr.dlc];
    for (int i = 0; i < tr.dlc; i++) begin
      tr.data[i] = (i < data.size()) ? data[i] : 8'h00;
    end

    start_item(tr);
    finish_item(tr);

    `uvm_info("CAN_EXT_SMOKE_SEQ",
              $sformatf("SEQ node TX request: %s", tr.convert2string()),
              UVM_LOW);
  endtask
endclass : can_ext_smoke_tx_seq

`endif // CAN_TX_SEQ_SV
