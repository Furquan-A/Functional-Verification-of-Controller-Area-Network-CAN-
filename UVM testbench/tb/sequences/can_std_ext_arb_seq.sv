`ifndef CAN_STD_EXT_ARB_SEQ_SV
`define CAN_STD_EXT_ARB_SEQ_SV

class can_std_ext_arb_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_std_ext_arb_seq)

  // -- node1 sequencer — set from test before calling start() --
  can_sequencer other_sqr;

  // -- Configurable fields --------------------------------------
  rand bit [10:0] base_id;        // shared base ID between STD and EXT
  rand bit [17:0] ext_lower_id;   // lower 18 bits of EXT ID (anything)

  // -- Results — read from test after sequence completes --------
  bit std_won;
  bit ext_lost;

  // -- Constraints ----------------------------------------------
  constraint valid_base_id { base_id != 11'h000; }  // avoid all-zeros

  function new(string name = "can_std_ext_arb_seq");
    super.new(name);
  endfunction

  task body();
    can_transaction     std_tr;
    can_transaction     ext_tr;
    uvm_sequencer_base  saved_sqr;

    // -- Guard ------------------------------------------------
    if (other_sqr == null)
      `uvm_fatal("STD_EXT_ARB", "other_sqr is null — set from test")

    // -- Create two separate transaction objects ---------------
    std_tr = can_transaction::type_id::create("std_tr");
    ext_tr = can_transaction::type_id::create("ext_tr");

    // -- Fill STD transaction (node0) -------------------------
    std_tr.can_fmt         = `CAN_ID_STD;
    std_tr.f_type          = `CAN_DATA_FRAME;
    std_tr.id              = {18'h0, base_id};   // bits[10:0] only used for STD
    std_tr.dlc             = 4;
    std_tr.data            = new[4];
    std_tr.data[0]         = 8'hAA;
    std_tr.data[1]         = 8'hBB;
    std_tr.data[2]         = 8'hCC;
    std_tr.data[3]         = 8'hDD;
    std_tr.inj_crc_error   = 0;
    std_tr.inj_form_error  = 0;
    std_tr.inj_stuff_error = 0;
    std_tr.inj_ack_error   = 0;
    std_tr.force_midframe  = 0;

    // -- Fill EXT transaction (node1) -------------------------
    // bits[28:18] = base_id (same as STD base)
    // bits[17:0]  = ext_lower_id (anything)
    ext_tr.can_fmt         = `CAN_ID_EXT;
    ext_tr.f_type          = `CAN_DATA_FRAME;
    ext_tr.id              = {base_id, ext_lower_id};
    ext_tr.dlc             = 4;
    ext_tr.data            = new[4];
    ext_tr.data[0]         = 8'h11;
    ext_tr.data[1]         = 8'h22;
    ext_tr.data[2]         = 8'h33;
    ext_tr.data[3]         = 8'h44;
    ext_tr.inj_crc_error   = 0;
    ext_tr.inj_form_error  = 0;
    ext_tr.inj_stuff_error = 0;
    ext_tr.inj_ack_error   = 0;
    ext_tr.force_midframe  = 0;

    `uvm_info("STD_EXT_ARB",
      $sformatf("Starting STD(id=0x%0h) vs EXT(id=0x%0h) — same base_id=0x%0h",
                std_tr.id, ext_tr.id, base_id),
      UVM_LOW)

    // -- Fire both simultaneously -----------------------------
    fork

      // node0 — STD frame on m_sequencer
      begin : NODE0_STD
        start_item(std_tr);
        finish_item(std_tr);
      end

      // node1 — EXT frame on other_sqr
      begin : NODE1_EXT
        saved_sqr   = m_sequencer;
        m_sequencer = other_sqr;
        start_item(ext_tr);
        finish_item(ext_tr);
        m_sequencer = saved_sqr;
      end

    join

    // -- Capture results --------------------------------------
    std_won  = !std_tr.arb_lost;
    ext_lost =  ext_tr.arb_lost;

    // -- Check STD won ----------------------------------------
    if (std_tr.arb_lost)
      `uvm_error("STD_EXT_ARB",
        $sformatf("FAIL: STD frame (id=0x%0h) lost arbitration — should always beat EXT at IDE bit",
                  std_tr.id))
    else
      `uvm_info("STD_EXT_ARB",
        $sformatf("PASS: STD frame (id=0x%0h) won arbitration as expected",
                  std_tr.id),
        UVM_LOW)

    // -- Check EXT lost ---------------------------------------
    if (!ext_tr.arb_lost)
      `uvm_error("STD_EXT_ARB",
        $sformatf("FAIL: EXT frame (id=0x%0h) did not lose arbitration — expected loss at IDE bit",
                  ext_tr.id))
    else
      `uvm_info("STD_EXT_ARB",
        $sformatf("PASS: EXT frame (id=0x%0h) lost at arb_lost_bit=%0d (expect 12)",
                  ext_tr.id, ext_tr.arb_lost_bit),
        UVM_LOW)

    // -- Check STD was ACKed ----------------------------------
    if (!std_tr.ack_seen)
      `uvm_error("STD_EXT_ARB",
        "FAIL: STD frame not ACKed after winning arbitration")
    else
      `uvm_info("STD_EXT_ARB",
        "PASS: STD frame ACKed correctly after winning",
        UVM_LOW)

    // -- arb_lost_bit check -----------------------------------
    // 11 ID bits (0-10) + RTR (11) + IDE (12) = bit 12
    if (ext_tr.arb_lost && ext_tr.arb_lost_bit != 12)
      `uvm_warning("STD_EXT_ARB",
        $sformatf("arb_lost_bit=%0d — expected 12 (IDE bit). Check driver arb_bit_idx counting",
                  ext_tr.arb_lost_bit))

    `uvm_info("STD_EXT_ARB",
      $sformatf("Summary: STD won=%0b  EXT lost=%0b  EXT arb_lost_bit=%0d  STD ack=%0b",
                std_won, ext_lost, ext_tr.arb_lost_bit, std_tr.ack_seen),
      UVM_LOW)

  endtask

endclass
`endif
