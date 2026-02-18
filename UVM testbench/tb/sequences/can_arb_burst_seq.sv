`ifndef CAN_ARB_BURST_SEQ_SV
`define CAN_ARB_BURST_SEQ_SV

// This file is `include'd inside can_pkg.sv
// So: NO imports, NO `include "uvm_macros.svh" here.

class can_arb_burst_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_arb_burst_seq)

  // Provided by test
  int unsigned node_id = 0;
  int unsigned num_rounds = 1;

  // ID plan for each round (size must be == num_rounds)
  rand bit [28:0] ids_per_round[];

  // Optional payload pattern (you can keep 2 bytes or expand)
  byte unsigned payload[];

  function new(string name="can_arb_burst_seq");
    super.new(name);
  endfunction

  task body();
    uvm_event go;
    can_transaction tr;

    go = uvm_event_pool::get_global("ARB_GO");

    if (ids_per_round.size() != num_rounds) begin
      `uvm_fatal("ARB_BURST_SEQ",
        $sformatf("ids_per_round.size(%0d) != num_rounds(%0d) for node%0d",
                  ids_per_round.size(), num_rounds, node_id))
    end

    for (int r = 0; r < num_rounds; r++) begin
      `uvm_info("ARB_BURST_SEQ",
        $sformatf("node%0d waiting for ARB_GO round%0d", node_id, r),
        UVM_LOW)

      go.wait_trigger();

      tr = can_transaction::type_id::create($sformatf("tr_n%0d_r%0d", node_id, r));

      tr.can_fmt = `CAN_ID_STD;
      tr.id      = ids_per_round[r];
      tr.f_type  = `CAN_DATA_FRAME;

      // Simple: use payload[] size as DLC; default to 2 bytes if empty
      if (payload.size() == 0) begin
        tr.dlc  = 2;
        tr.data = new[2];
        tr.data[0] = byte'(8'hA0 + node_id);
        tr.data[1] = byte'(8'h10 + r);
      end
      else begin
        tr.dlc  = payload.size();
        tr.data = new[tr.dlc];
        foreach (payload[i]) tr.data[i] = payload[i];
      end
      tr.inj_crc_error   = 1'b0;
      tr.inj_stuff_error = 1'b0;
      tr.inj_form_error  = 1'b0;
      tr.inj_ack_error   = 1'b0;
      start_item(tr);
      finish_item(tr);

      `uvm_info("ARB_BURST_SEQ",
        $sformatf("node%0d round%0d requested TX id=0x%0h dlc=%0d data=%p",
                  node_id, r, tr.id, tr.dlc, tr.data),
        UVM_LOW)
    end
  endtask

endclass : can_arb_burst_seq

`endif // CAN_ARB_BURST_SEQ_SV
