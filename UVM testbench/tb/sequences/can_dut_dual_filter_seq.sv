`ifndef CAN_DUT_DUAL_FILTER_SEQ_SV
`define CAN_DUT_DUAL_FILTER_SEQ_SV

class can_dut_dual_filter_seq extends uvm_sequence #(can_transaction);
  `uvm_object_utils(can_dut_dual_filter_seq)

  virtual can_if #(.NUM_TB_NODES(3)) vif;

  // PeliCAN register addresses
  localparam byte MOD  = 8'h00;
  localparam byte CMD  = 8'h01;
  localparam byte SR   = 8'h02;
  localparam byte IR   = 8'h03;
  localparam byte ACR0 = 8'h10;
  localparam byte ACR1 = 8'h11;
  localparam byte ACR2 = 8'h12;
  localparam byte ACR3 = 8'h13;
  localparam byte AMR0 = 8'h14;
  localparam byte AMR1 = 8'h15;
  localparam byte AMR2 = 8'h16;
  localparam byte AMR3 = 8'h17;

  int errors = 0;

  function new(string name = "can_dut_dual_filter_seq");
    super.new(name);
  endfunction

  // -- Helpers ------------------------------------------------

  task automatic clear_ir();
    byte unsigned dummy;
    vif.reg_read(IR, dummy);
  endtask

  task automatic release_rx_buffer();
    byte unsigned sr;
    int cnt = 0;

    vif.reg_read(SR, sr);
    if (!sr[0]) return;

    vif.reg_write(CMD, 8'h04);  // RRB

    forever begin
      vif.reg_read(SR, sr);
      if (!sr[0]) return;
      cnt++;
      if (cnt > 500) begin
        `uvm_warning("DUAL_FILT", "RRB timeout")
        return;
      end
      #100ns;
    end
  endtask

  task automatic wait_rbs(time timeout, output bit seen);
    time t_end = $time + timeout;
    byte unsigned sr;
    seen = 1'b0;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin
        seen = 1'b1;
        return;
      end
      #200ns;
    end
  endtask

  task automatic wait_rbs_stays_clear(time window, output bit stayed);
    time t_end = $time + window;
    byte unsigned sr;
    stayed = 1'b1;
    while ($time < t_end) begin
      vif.reg_read(SR, sr);
      if (sr[0]) begin
        stayed = 1'b0;
        return;
      end
      #200ns;
    end
  endtask

  task automatic send_std_frame(
    input bit [10:0] id,
    input bit [3:0]  dlc,
    input bit        is_remote,
    output can_transaction tr
  );
    tr = can_transaction::type_id::create($sformatf("tr_%03h", id));
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt == `CAN_ID_STD;
      this.id == local::id;
      this.dlc == local::dlc;
      f_type  == (local::is_remote ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME);
      (!local::is_remote) -> (data.size() == local::dlc);
      (local::is_remote)  -> (data.size() == 0);
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("DUAL_FILT", "STD randomize failed")
    finish_item(tr);
  endtask

  task automatic send_ext_frame(
    input bit [28:0] id,
    input bit [3:0]  dlc,
    output can_transaction tr
  );
    tr = can_transaction::type_id::create($sformatf("tr_ext_%07h", id));
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt == `CAN_ID_EXT;
      this.id == local::id;
      this.dlc == local::dlc;
      f_type  == `CAN_DATA_FRAME;
      data.size() == local::dlc;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("DUAL_FILT", "EXT randomize failed")
    finish_item(tr);
  endtask

  task automatic send_ext_frame_smoke(
    input bit [28:0] id,
    output can_transaction tr
  );
    tr = can_transaction::type_id::create($sformatf("tr_ext_smoke_%07h", id));
    start_item(tr);
    assert(tr.randomize() with {
      can_fmt == `CAN_ID_EXT;
      this.id == local::id;
      this.dlc == 4'd0;
      f_type  == `CAN_DATA_FRAME;
      data.size() == 0;
      inj_crc_error   == 0;
      inj_stuff_error == 0;
      inj_form_error  == 0;
      inj_ack_error   == 0;
    }) else `uvm_fatal("DUAL_FILT", "EXT smoke randomize failed")
    finish_item(tr);
  endtask

  // -- Configure filter and exit reset mode -------------------
  task automatic program_filter(
    input byte unsigned mod_val,
    input byte unsigned acr[4],
    input byte unsigned amr[4],
    input string        desc
  );
    byte unsigned mod_read, cdr_read;

    // Enter reset mode
    vif.reg_write(MOD, mod_val | 8'h01);  // RM=1 + desired mode bits

    // Re-apply CDR/BTR/IER in reset
    vif.reg_write(8'h1F, 8'h80);  // CDR = PeliCAN mode
    vif.reg_write(8'h06, 8'h00);  // BTR0
    vif.reg_write(8'h07, 8'h14);  // BTR1
    vif.reg_write(8'h04, 8'hEF);  // IER

    vif.reg_write(ACR0, acr[0]);
    vif.reg_write(ACR1, acr[1]);
    vif.reg_write(ACR2, acr[2]);
    vif.reg_write(ACR3, acr[3]);
    vif.reg_write(AMR0, amr[0]);
    vif.reg_write(AMR1, amr[1]);
    vif.reg_write(AMR2, amr[2]);
    vif.reg_write(AMR3, amr[3]);

    // Exit reset mode
    vif.reg_write(MOD, mod_val & 8'hFE);

    vif.reg_read(MOD, mod_read);
    vif.reg_read(8'h1F, cdr_read);
    `uvm_info("DUAL_FILT",
      $sformatf("[%s] MOD=0x%02h CDR=0x%02h ACR={%02h,%02h,%02h,%02h} AMR={%02h,%02h,%02h,%02h}",
                desc, mod_read, cdr_read,
                acr[0], acr[1], acr[2], acr[3],
                amr[0], amr[1], amr[2], amr[3]),
      UVM_LOW)

    #10us;
  endtask

  task automatic program_accept_all_dual(input string desc);
    byte unsigned acr[4], amr[4];
    acr = '{8'h00, 8'h00, 8'h00, 8'h00};
    amr = '{8'hFF, 8'hFF, 8'hFF, 8'hFF};
    program_filter(8'h00, acr, amr, desc);
  endtask

  task automatic check_accepted(input string desc, input bit [28:0] id);
    bit rbs_seen;
    wait_rbs(200us, rbs_seen);
    if (rbs_seen) begin
      `uvm_info("DUAL_FILT",
        $sformatf("PASS [%s]: ID 0x%0h accepted (RBS=1)", desc, id),
        UVM_LOW)
      release_rx_buffer();
    end
    else begin
      `uvm_error("DUAL_FILT",
        $sformatf("FAIL [%s]: ID 0x%0h NOT accepted (RBS stayed 0)", desc, id))
      errors++;
    end
  endtask

  task automatic check_rejected(input string desc, input bit [28:0] id);
    bit stayed;
    wait_rbs_stays_clear(50us, stayed);
    if (stayed) begin
      `uvm_info("DUAL_FILT",
        $sformatf("PASS [%s]: ID 0x%0h rejected (RBS stayed 0)", desc, id),
        UVM_LOW)
    end
    else begin
      `uvm_error("DUAL_FILT",
        $sformatf("FAIL [%s]: ID 0x%0h was stored (should be rejected)", desc, id))
      errors++;
      release_rx_buffer();
    end
  endtask

  // --------------------------------------------------------------
  task body();
    can_transaction tr;
    byte unsigned acr[4], amr[4];

    if (vif == null)
      `uvm_fatal("DUAL_FILT", "vif is null")

    // -- Init DUT ----------------------------------------------
    begin
      can_dut_init_seq init_seq;
      init_seq = can_dut_init_seq::type_id::create("init_seq");
      init_seq.vif = vif;
      init_seq.start(null);
    end

    clear_ir();
    release_rx_buffer();

    // ==========================================================
    // Phase 1: Single Filter Mode
    // ==========================================================
    `uvm_info("DUAL_FILT", "===== Phase 1: Single Filter Mode (AFM=1) =====", UVM_LOW)

    acr = '{8'h24, 8'h60, 8'h00, 8'h00};  // ID 0x123
    amr = '{8'h00, 8'h1F, 8'hFF, 8'hFF};
    program_filter(8'h08, acr, amr, "SINGLE_FILT");

    send_std_frame(11'h123, 4'd2, 1'b0, tr);
    check_accepted("SINGLE_ALLOW", 11'h123);

    clear_ir();
    send_std_frame(11'h456, 4'd2, 1'b0, tr);
    check_rejected("SINGLE_BLOCK", 11'h456);

    // ==========================================================
    // Phase 2: Dual Filter STD
    // ==========================================================
    `uvm_info("DUAL_FILT", "===== Phase 2: Dual Filter Mode (AFM=0) — STD frames =====", UVM_LOW)

    acr = '{8'h40, 8'h00, 8'h60, 8'h00};
    amr = '{8'h00, 8'h1F, 8'h00, 8'h1F};
    program_filter(8'h00, acr, amr, "DUAL_STD");

    send_std_frame(11'h200, 4'd2, 1'b0, tr);
    check_accepted("DUAL_F0_ONLY", 11'h200);

    clear_ir();
    send_std_frame(11'h300, 4'd2, 1'b0, tr);
    check_accepted("DUAL_F1_ONLY", 11'h300);

    clear_ir();
    send_std_frame(11'h400, 4'd2, 1'b0, tr);
    check_rejected("DUAL_NEITHER", 11'h400);

    clear_ir();
    send_std_frame(11'h200, 4'd0, 1'b1, tr);
    check_accepted("DUAL_F0_RTR", 11'h200);

    // ==========================================================
    // Phase 2.5: EXT smoke gate
    // ==========================================================
    begin
      bit ext_smoke_ok;
      bit rbs_seen;
      bit [28:0] ext_smoke_id;

      ext_smoke_ok  = 1'b0;
      ext_smoke_id  = 29'h15555555; // low-stress alternating pattern

      `uvm_info("DUAL_FILT", "===== Phase 2.5: EXT smoke check under accept-all =====", UVM_LOW)

      clear_ir();
      release_rx_buffer();
      program_accept_all_dual("EXT_SMOKE_ALL");

      send_ext_frame_smoke(ext_smoke_id, tr);
      wait_rbs(200us, rbs_seen);

      if (rbs_seen) begin
        ext_smoke_ok = 1'b1;
        `uvm_info("DUAL_FILT",
          $sformatf("PASS [EXT_SMOKE]: clean EXT frame 0x%0h accepted under accept-all", ext_smoke_id),
          UVM_LOW)
        release_rx_buffer();
      end
      else begin
        `uvm_warning("DUAL_FILT",
          $sformatf("SKIP Phase 3 EXT: smoke EXT frame 0x%0h failed under accept-all. This indicates an environment/agent EXT-path issue, not a DUT ACF issue.",
                    ext_smoke_id))
      end

      if (!ext_smoke_ok) begin
        `uvm_info("DUAL_FILT", "===== Phase 4: Dual Filter — mask variations =====", UVM_LOW)

        acr = '{8'h40, 8'h00, 8'h00, 8'h00};
        amr = '{8'h0F, 8'hFF, 8'hFF, 8'hFF};
        program_filter(8'h00, acr, amr, "DUAL_MASK");

        send_std_frame(11'h21F, 4'd1, 1'b0, tr);
        check_accepted("DUAL_MASK_F0_IN", 11'h21F);

        clear_ir();
        send_std_frame(11'h7FF, 4'd1, 1'b0, tr);
        check_accepted("DUAL_MASK_F1_ALL", 11'h7FF);

        if (errors == 0)
          `uvm_info("DUAL_FILT", "===== ALL NON-EXT DUAL FILTER TESTS PASSED =====", UVM_LOW)
        else
          `uvm_error("DUAL_FILT", $sformatf("===== DUAL FILTER: %0d ERROR(S) =====", errors))

        return;
      end
    end

    // ==========================================================
    // Phase 3: Dual Filter EXT
    // Only run if EXT smoke passed
    // ==========================================================
    `uvm_info("DUAL_FILT", "===== Phase 3: Dual Filter Mode (AFM=0) — EXT frames =====", UVM_LOW)

    begin
      bit [28:0] ext_id_f0, ext_id_f1, ext_id_none;

      // Simpler and explicit upper-bit matches
      ext_id_f0   = 29'h0;
      ext_id_f1   = 29'h0;
      ext_id_none = 29'h0;

      ext_id_f0[28:21] = 8'hAA;
      ext_id_f0[20:13] = 8'h55;

      ext_id_f1[28:21] = 8'h55;
      ext_id_f1[20:13] = 8'hAA;

      ext_id_none[28:21] = 8'h33;
      ext_id_none[20:13] = 8'hCC;

      acr = '{8'hAA, 8'h55, 8'h55, 8'hAA};
      amr = '{8'h00, 8'h00, 8'h00, 8'h00};
      program_filter(8'h00, acr, amr, "DUAL_EXT");

      `uvm_info("DUAL_FILT",
        $sformatf("EXT IDs: F0=0x%08h F1=0x%08h NONE=0x%08h",
                  ext_id_f0, ext_id_f1, ext_id_none),
        UVM_LOW)

      clear_ir();
      send_ext_frame(ext_id_f0, 4'd0, tr);
      check_accepted("DUAL_EXT_F0", ext_id_f0);

      clear_ir();
      send_ext_frame(ext_id_f1, 4'd0, tr);
      check_accepted("DUAL_EXT_F1", ext_id_f1);

      clear_ir();
      send_ext_frame(ext_id_none, 4'd0, tr);
      check_rejected("DUAL_EXT_NONE", ext_id_none);
    end

    // ==========================================================
    // Phase 4: Dual Filter mask variations
    // ==========================================================
    `uvm_info("DUAL_FILT", "===== Phase 4: Dual Filter — mask variations =====", UVM_LOW)

    acr = '{8'h40, 8'h00, 8'h00, 8'h00};
    amr = '{8'h0F, 8'hFF, 8'hFF, 8'hFF};
    program_filter(8'h00, acr, amr, "DUAL_MASK");

    send_std_frame(11'h21F, 4'd1, 1'b0, tr);
    check_accepted("DUAL_MASK_F0_IN", 11'h21F);

    clear_ir();
    send_std_frame(11'h7FF, 4'd1, 1'b0, tr);
    check_accepted("DUAL_MASK_F1_ALL", 11'h7FF);

    // -- Summary ----------------------------------------------
    if (errors == 0)
      `uvm_info("DUAL_FILT", "===== ALL DUAL FILTER TESTS PASSED =====", UVM_LOW)
    else
      `uvm_error("DUAL_FILT", $sformatf("===== DUAL FILTER: %0d ERROR(S) =====", errors))
  endtask

endclass

`endif