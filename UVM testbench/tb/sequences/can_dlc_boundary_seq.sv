`ifndef CAN_DLC_BOUNDARY_SEQ_SV
`define CAN_DLC_BOUNDARY_SEQ_SV

class can_dlc_boundary_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dlc_boundary_seq)

  function new(string name = "can_dlc_boundary_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction tr;

    // Send frames with all DLC values 0-8 to achieve full DLC coverage
    for (int dlc_val = 0; dlc_val <= 8; dlc_val++) begin

      tr = can_transaction::type_id::create($sformatf("tr_dlc%0d", dlc_val));
      start_item(tr);
        tr.can_fmt         = `CAN_ID_STD;
        tr.f_type          = `CAN_DATA_FRAME;
        tr.id              = 11'h100 + dlc_val;
        tr.dlc             = dlc_val;
        tr.data            = new[dlc_val];
        // Fill data bytes with recognizable pattern
        foreach (tr.data[i]) tr.data[i] = byte'(dlc_val * 16 + i);
        tr.inj_crc_error   = 0;
        tr.inj_form_error  = 0;
        tr.inj_stuff_error = 0;
        tr.inj_ack_error   = 0;
        tr.force_midframe  = 0;
      finish_item(tr);

      if (!tr.ack_seen)
        `uvm_error("DLC_BOUNDARY",
          $sformatf("DLC=%0d frame not ACKed", dlc_val))
      else
        `uvm_info("DLC_BOUNDARY",
          $sformatf("PASS: DLC=%0d frame ACKed correctly", dlc_val),
          UVM_LOW)
    end

    // Also send DLC=8 extended frame for format x DLC cross coverage
    tr = can_transaction::type_id::create("tr_dlc8_ext");
    start_item(tr);
      tr.can_fmt         = `CAN_ID_EXT;
      tr.f_type          = `CAN_DATA_FRAME;
      tr.id              = 29'h1ABCDE1;
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

    if (!tr.ack_seen)
      `uvm_error("DLC_BOUNDARY", "DLC=8 EXT frame not ACKed")
    else
      `uvm_info("DLC_BOUNDARY", "PASS: DLC=8 EXT frame ACKed correctly", UVM_LOW)

    `uvm_info("DLC_BOUNDARY", "All DLC boundary frames complete (DLC 0-8 STD + DLC8 EXT)", UVM_LOW)
  endtask

endclass
`endif