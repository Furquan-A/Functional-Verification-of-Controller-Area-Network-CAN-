class can_random_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_random_seq)
 
  int unsigned n_frames   = 100;
  bit          is_node0   = 1;   // node0 uses higher IDs, node1 uses lower IDs
 
  function new(string name = "can_random_seq");
    super.new(name);
  endfunction
 
  task body();
    can_transaction tr;
 
    for (int unsigned i = 0; i < n_frames; i++) begin
      tr = can_transaction::type_id::create($sformatf("tr_%0d", i));
      start_item(tr);
 
      // Randomize with constraints
      assert(tr.randomize() with {
 
        // Only DATA and REMOTE frames — agent drives bus
        f_type inside {`CAN_DATA_FRAME, `CAN_REMOTE_FRAME};
 
        // Both STD and EXT formats
        can_fmt inside {`CAN_ID_STD, `CAN_ID_EXT};
 
        // DLC 0-8
        dlc inside {[0:8]};
 
        // ID partitioning — node0 higher IDs, node1 lower IDs
        // This ensures natural arbitration when both transmit
        if (is_node0) {
          // node0: upper half of ID space
          (can_fmt == `CAN_ID_STD) -> id inside {[11'h400:11'h7FF]};
          (can_fmt == `CAN_ID_EXT) -> id inside {[29'h1000_0000:29'h1FFF_FFFF]};
        } else {
          // node1: lower half including boundaries
          (can_fmt == `CAN_ID_STD) -> id inside {
            11'h000,                    // min boundary
            11'h7FF,                    // max boundary
            [11'h001:11'h3FF]           // low range
          };
          (can_fmt == `CAN_ID_EXT) -> id inside {
            29'h0000_0000,              // min boundary
            29'h1FFF_FFFF,              // max boundary
            [29'h0000_0001:29'h0FFF_FFFF] // low range
          };
        }
 
        // Error injection — 30% chance of error
        // Only inject one error type at a time
        if (i % 10 < 3) {
          // inject error
          inj_crc_error   inside {0, 1};
          inj_stuff_error inside {0, 1};
          inj_form_error  inside {0, 1};
          inj_ack_error   == 0;   // keep ACK errors separate
          // only one error type at a time
          (inj_crc_error + inj_stuff_error + inj_form_error) <= 1;
        } else {
          // clean frame
          inj_crc_error   == 0;
          inj_stuff_error == 0;
          inj_form_error  == 0;
          inj_ack_error   == 0;
        }
 
        // DATA payload
        (f_type == `CAN_DATA_FRAME) -> data.size() == dlc;
        (f_type == `CAN_REMOTE_FRAME) -> data.size() == 0;
 
      }) else `uvm_fatal("CAN_RANDOM_SEQ", $sformatf("Randomization failed at frame %0d", i))
 
      finish_item(tr);
 
      `uvm_info("CAN_RANDOM_SEQ",
        $sformatf("[%0d/%0d] node%0s fmt=%s ftype=%s id=0x%0h dlc=%0d err(crc=%0b form=%0b stuff=%0b)",
                  i+1, n_frames,
                  is_node0 ? "0" : "1",
                  tr.can_fmt ? "EXT" : "STD",
                  tr.ftype_str(),
                  tr.id, tr.dlc,
                  tr.inj_crc_error, tr.inj_form_error, tr.inj_stuff_error),
        UVM_LOW)
    end
 
    `uvm_info("CAN_RANDOM_SEQ",
      $sformatf("===== RANDOM SEQ COMPLETE — %0d frames sent =====", n_frames),
      UVM_LOW)
  endtask
 
endclass