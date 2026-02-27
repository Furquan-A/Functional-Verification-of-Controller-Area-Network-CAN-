`ifndef CAN_MONITOR_SV
`define CAN_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_monitor extends uvm_monitor;
  `uvm_component_utils(can_monitor)

  uvm_analysis_port #(can_transaction) ap;

  virtual can_if      vif;
  can_agent_config    c_cfg;

  typedef enum int {
    ST_IDLE = 0,
    ST_SOF,
    ST_ARB,
    ST_CTRL,
    ST_DATA,
    ST_CRC,
    ST_ACK,
    ST_EOF,
    ST_IFS
  } can_mon_state_e;

  can_mon_state_e state;
  can_transaction tr;

  // Stuffing (logical stream)
  bit          last_logical_bit;
  int unsigned same_cnt;
  bit          stuff_expected;
  bit enable_special_decode = 0;
  bit overload_seen = 0;

  // ---------------- CRC bookkeeping ----------------
  bit          crc_calc_en;
  bit [14:0]   crc_calc;   // locally calculated CRC
  bit [14:0]   crc_seq;    // observed CRC field (YOU asked to keep this name)
  localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;

  // Timing
  time bit_time;
  time sp_offset;

  function new(string name="can_monitor", uvm_component parent=null);
    super.new(name, parent);
    ap    = new("ap", this);
    state = ST_IDLE;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_MON","can_agent_config not found (key='m_cfg')");

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_MON","virtual interface can_if not found (key='vif')");

    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;

    if (sp_offset >= bit_time)
      `uvm_fatal("CAN_MON","Invalid sample_point_pct (sp_offset >= bit_time)");

    last_logical_bit = 1'b1;
    same_cnt         = 0;
    stuff_expected   = 0;

    `uvm_info("CAN_MON",
      $sformatf("Monitor ready: node_id=%0d bit_time=%0t sp_offset=%0t (%0d%%) ack_en=%0b",
                c_cfg.node_id, bit_time, sp_offset, c_cfg.sample_point_pct, c_cfg.ack_enable),
      UVM_LOW);
  endfunction

  task run_phase(uvm_phase phase);
    
    super.run_phase(phase);

    forever begin
      case (state)
          ST_IDLE: begin
          // ------------------------------------------------------------
          // Special frame detect (ERROR/OVERLOAD flag + delimiter)
          // ------------------------------------------------------------
          if (c_cfg.enable_special_decode && c_cfg.special_decode_idle) begin
            bit matched;
            int unsigned ft;
            bit delim_bad;
        
            matched = 1'b0;
            ft      = `CAN_DATA_FRAME;
        
            // Wait until bus goes dominant at a bit boundary
            wait_for_sof_boundary(); // returns when rx_i==0 on a can_cb edge
        
            // Try decoding special flag (consumes bits if it matches)
            try_decode_special_flag_frame(matched, ft,delim_bad);
        
            if (matched) begin
              // Only PUBLISH special frames when explicitly enabled
              if (c_cfg.publish_special_frames) begin
                start_new_frame();
                tr.f_type = ft;
                 if (delim_bad) tr.form_error_seen = 1'b1; // set it HERE safely
                // Optional: mark context if you have special_ctx
                //tr.special_ctx = (ft == `CAN_OVERLOAD_FRAME) ? SPEC_CTX_INTERMISSION
                //                                              : SPEC_CTX_IDLE;
        
                end_frame_and_publish();
                state=ST_IDLE;
                continue;
              end
        
              // Either way, we already consumed delimiter + resynced
              state = ST_IDLE;
              continue;
            end
        
            // Not a special flag; stay in IDLE and wait again
            state = ST_IDLE;
            continue;
          end
        
          // ------------------------------------------------------------
          // Normal path: start a real data/remote frame
          // ------------------------------------------------------------
          wait_for_sof_boundary();
          start_new_frame();
          state = ST_SOF;
        end

        ST_SOF: begin
          bit sof;
          sample_current_bit(sof);

          if (sof !== 1'b0) begin
            `uvm_warning("CAN_MON","SOF not dominant; resync to IDLE");
            state = ST_IDLE;
          end
          else begin
            init_logical_stream(sof);

            // CRC starts at SOF and includes SOF bit
            crc15_init();
            crc15_update(sof);

            state = ST_ARB;
          end
        end

        ST_ARB:  decode_arbitration();
        ST_CTRL: decode_control();
        ST_DATA: decode_data_field();
        ST_CRC:  decode_crc_field();
        ST_ACK:  decode_ack_field();
        ST_EOF:  decode_eof_field();
        
        ST_IFS: begin
          if (c_cfg.enable_special_decode && c_cfg.special_decode_ifs) begin
            decode_ifs_or_overload();
          end else begin
            // If not decoding IFS specials, just consume IFS bits and go idle
            bit b;
            repeat (`CAN_INTERMISSION_BITS) sample_next_bit(b);
            state = ST_IDLE;
          end
        end
        
        default: state = ST_IDLE;
      endcase
    end
  endtask

  // ===================================================================
  // BIT ENGINE (aligned)
  // ===================================================================
  task automatic sample_current_bit(output bit b);
    #(sp_offset);
    b = vif.rx_i;
    #(bit_time - sp_offset);
  endtask

  task automatic sample_next_bit(output bit b);
    @vif.can_cb;
    sample_current_bit(b);
  endtask

  function void init_logical_stream(bit first_bit);
    last_logical_bit = first_bit;
    same_cnt         = 1;
    stuff_expected   = 0;
  endfunction

  // ---------------------------------------------------------------------------------------
  
  task automatic get_logical_bit(output bit lb);
    bit rb;
    bit matched;
    int unsigned ft;
    bit delim_ok;
  
    forever begin
      sample_next_bit(rb);
  
      // consume stuff bit if expected
      if (stuff_expected) begin
        if (rb == last_logical_bit) begin
          // Stuff error suspected
          tr.stuff_error_seen = 1'b1;
  
          // Try if this is actually SPECIAL flag mid-frame
          try_decode_special_flag_midframe(matched, ft, delim_ok);
  
          if (matched) begin
            // delimiter issue => FORM error on the CURRENT frame (safe: tr exists)
            if (!delim_ok) tr.form_error_seen = 1'b1;
  
            // Publish the SPECIAL mid-frame event ONLY if enabled
            if (c_cfg.publish_special_frames) begin
              can_transaction sp;
              sp = can_transaction::type_id::create("sp_midframe");
              sp.t_start     = $time;
              sp.t_end       = $time;
              sp.src_node    = c_cfg.node_id;
              sp.f_type      = `CAN_ERROR_FRAME; // mid-frame => ERROR by definition
              sp.special_ctx = can_transaction::SPEC_CTX_MID_FRAME;
              ap.write(sp);
  
              `uvm_info("CAN_MON",
                $sformatf("[node%0d] OBS publish SPECIAL(MID_FRAME) ftype=%0d", c_cfg.node_id, sp.f_type),
                UVM_LOW);
            end
  
            // Always recover after a detected error flag
            state = ST_IDLE;
            return;
          end
  
          // fallback: original recovery path
          `uvm_warning("CAN_MON", "Stuff error suspected; resync to IDLE");
          recover_to_idle();
          state = ST_IDLE;
          return;
        end
  
        // It was a valid stuff bit, consume it and continue
        stuff_expected = 0;
        continue;
      end
  
      // normal (non-stuff) logical bit
      lb = rb;
  
      if (lb == last_logical_bit) same_cnt++;
      else same_cnt = 1;
  
      last_logical_bit = lb;
  
      if (same_cnt == 5) begin
        stuff_expected = 1;
        same_cnt       = 0;
      end
  
      return;
    end
  endtask

  // ---------------------------------------------------------------------------------------
    
  task automatic recover_to_idle();
    
    int unsigned recessive_cnt = 0;
    bit rb;
    
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1;
    
    // Wait for 11 consecutive recessive bits (EOF=7 + IFS=3 + margin)
    while (recessive_cnt < 11) begin
      @vif.can_cb;
      #(sp_offset);
      rb = vif.rx_i;
      #(bit_time - sp_offset);
  
      if (rb === 1'b1) recessive_cnt++;
      else             recessive_cnt = 0;
    end
  endtask


  // ===================================================================
  // CRC helpers (CALC uses crc_calc, OBS uses crc_seq)
  // ===================================================================
  function void crc15_init();
    crc_calc    = 15'h0000;
    crc_calc_en = 1'b1;
  endfunction

  function void crc15_stop();
    crc_calc_en = 1'b0;
  endfunction

  function void crc15_update(bit b);
    bit msb;
    if (!crc_calc_en) return;

    msb      = crc_calc[14] ^ b;
    crc_calc = {crc_calc[13:0], 1'b0};
    if (msb) crc_calc ^= CAN_CRC15_POLY;
  endfunction

  // ===================================================================
  // DECODE
  // ===================================================================
  task automatic decode_arbitration();
    bit        b;
    bit        rtr;
    bit        ide;
    bit [10:0] base_id;
    bit [28:0] can_id;

    base_id = '0;
    can_id  = '0;
    rtr     = 1'b0;

    // base ID 11 bits
    for (int i = 10; i >= 0; i--) begin
      get_logical_bit(b); if (state==ST_IDLE) return;
      crc15_update(b);
      base_id[i] = b;
    end

    // RTR/SRR
    get_logical_bit(b); if (state==ST_IDLE) return;
    crc15_update(b);

    // IDE
    get_logical_bit(ide); if (state==ST_IDLE) return;
    crc15_update(ide);

    if (ide == 1'b0) begin
      // STD
      can_id[10:0] = base_id;
      rtr          = b;

      tr.can_fmt = `CAN_ID_STD;
      tr.id      = can_id;
      tr.f_type  = (rtr==1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

      state = ST_CTRL;
    end
    else begin
      // EXT
      if (b !== 1'b1) begin
        tr.form_error_seen = 1'b1;
        `uvm_warning("CAN_MON","SRR in EXT frame not recessive (form error)");
      end

      can_id[28:18] = base_id;

      for (int i = 17; i >= 0; i--) begin
        get_logical_bit(b); if (state==ST_IDLE) return;
        crc15_update(b);
        can_id[i] = b;
      end

      // RTR (extended)
      get_logical_bit(b); if (state==ST_IDLE) return;
      crc15_update(b);
      rtr = b;

      tr.can_fmt = `CAN_ID_EXT;
      tr.id      = can_id;
      tr.f_type  = (rtr==1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

      state = ST_CTRL;
    end
  endtask

  // ---------------------------------------------------------------------------------------
    
  task automatic decode_control();
    bit b;
    bit r1;
    bit r0;
    bit [3:0] dlc_value;
    
    // EXT has r1 then r0 (if strict mode), STD only r0
    if ((tr.can_fmt == `CAN_ID_EXT) && c_cfg.strict_ext_ctrl) begin
      get_logical_bit(r1); 
      if (state==ST_IDLE) return;
      crc15_update(r1);
      if (r1 !== 1'b0) begin
        tr.form_error_seen = 1'b1;
        `uvm_warning("CAN_MON","EXT r1 not zero (form error)");
      end
    end
    
    get_logical_bit(r0); 
    if (state==ST_IDLE) return;
    crc15_update(r0);
    if (r0 !== 1'b0) begin
      tr.form_error_seen = 1'b1;
      `uvm_warning("CAN_MON","r0 not zero (form error)");
    end

    dlc_value = 4'd0;
    for (int i = 3; i >= 0; i--) begin
      get_logical_bit(b); 
      if (state==ST_IDLE) return;
      crc15_update(b);
      dlc_value[i] = b;
    end

    tr.dlc = (dlc_value > 8) ? 8 : dlc_value;

    if (tr.f_type == `CAN_REMOTE_FRAME)
      state = ST_CRC;
    else
      state = (tr.dlc == 0) ? ST_CRC : ST_DATA;
    
  endtask

  // ---------------------------------------------------------------------------------------
  
  task automatic decode_data_field();
    bit b;
    bit [7:0] cur_byte;

    tr.data = new[tr.dlc];

    for (int unsigned bi = 0; bi < tr.dlc; bi++) begin
      cur_byte = 8'h00;
      for (int bitpos = 7; bitpos >= 0; bitpos--) begin
        get_logical_bit(b); if (state==ST_IDLE) return;
        crc15_update(b);
        cur_byte[bitpos] = b;
      end
      tr.data[bi] = cur_byte;
    end

    state = ST_CRC;
  endtask

  // ---------------------------------------------------------------------------------------
    
  task automatic decode_crc_field();
    bit b;

    // CRC field is 15 bits, BUT NOT included in CRC calculation
    crc15_stop();
    crc_seq = 15'd0;
    for (int i = 14; i >= 0; i--) begin
      get_logical_bit(b); if (state==ST_IDLE) return;
      crc_seq[i] = b;
    end
    tr.crc_obs = crc_seq;

    // CRC mismatch detection
    tr.crc_error_seen = (crc_seq !== crc_calc);

    if (tr.crc_error_seen) begin
      `uvm_info("CAN_MON",
        $sformatf("CRC ERROR: calc=0x%0h obs=0x%0h id=0x%0h",
                  crc_calc, crc_seq, tr.id),UVM_LOW)
    end

     // CRC delimiter is a RAW bit (not stuffed, not included in CRC)
    sample_next_bit(b);
    if (b !== 1'b1) begin
      tr.form_error_seen = 1'b1;
      `uvm_info("CAN_MON","CRC delimiter not recessive (FORM error)",UVM_LOW);
    end
    state = ST_ACK;
  endtask

  // ===================================================================
  // ACK (deterministic + recording)
  // ===================================================================
  task automatic decode_ack_field();
    bit crc_ok;
    bit ack_slot;
    bit ack_delim;
    bit drive_ack;
    
    
    crc_ok = (crc_calc == tr.crc_obs);
    tr.crc_error_seen = ~crc_ok;
    
    // ACK slot boundary
    @vif.can_cb;

    // Receiver ACK rule:
    drive_ack = (c_cfg.ack_enable &&
              !c_cfg.expect_no_ack &&
             (c_cfg.is_tx_in_progress == 1'b0) &&
             (tr.crc_error_seen   == 1'b0) &&
             (tr.stuff_error_seen == 1'b0) &&
             (tr.form_error_seen  == 1'b0));

    tr.ack_driven = drive_ack;

    // Drive ACK at start of slot (dominant if receiver)
    vif.can_cb.tb_tx[c_cfg.node_id] <= (drive_ack ? 1'b0 : 1'b1);

    // Sample ACK slot
    #(sp_offset);
    ack_slot = vif.rx_i;

    // ack_seen=1 means ACK present (dominant)
    tr.ack_seen = (ack_slot == 1'b0);

    #(bit_time - sp_offset);

    // Release after slot
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1;

    // (Keep warning behavior simple; scoreboard decides pass/fail based on exp.inj_ack_error)
    if (ack_slot == 1'b1)
      `uvm_info("CAN_MON","ACK error (no dominant ACK observed)",UVM_LOW);

    // ACK delimiter
    #(sp_offset);
    ack_delim = vif.rx_i;
    #(bit_time - sp_offset);

    if (ack_delim !== 1'b1)
      `uvm_warning("CAN_MON","ACK delimiter not recessive");

    state = ST_EOF;
  endtask

  // ---------------------------------------------------------------------------------------
  
  task automatic decode_eof_field();
    bit b;

    for (int i = 0; i < 7; i++) begin
      sample_next_bit(b);
      if (b !== 1'b1) begin
        tr.form_error_seen = 1'b1;
        `uvm_warning("CAN_MON", $sformatf("EOF bit %0d not recessive (FORM error)", i));
      end
    end

    end_frame_and_publish();
    state = ST_IFS;
  endtask
  
  // ----------------------------------------------------------------------------------------
  task automatic decode_ifs_or_overload();
    bit b;
    bit matched;
    int unsigned ft_unused;
    bit delim_ok;
  
    // Intermission = 3 recessive bits
    for (int i = 0; i < `CAN_INTERMISSION_BITS + 2; i++) begin
      sample_next_bit(b);
  
      if (b === 1'b0) begin
        // Dominant inside Intermission => candidate OVERLOAD
        try_decode_special_flag_from_current_bit(matched, ft_unused, delim_ok);
  
        if (matched) begin
          if (c_cfg.publish_special_frames) begin
            can_transaction sp;
            sp = can_transaction::type_id::create("sp_ifs");
            sp.t_start     = $time;
            sp.t_end       = $time;
            sp.src_node    = c_cfg.node_id;
            sp.f_type      = `CAN_OVERLOAD_FRAME;
            sp.special_ctx = can_transaction::SPEC_CTX_INTERMISSION;
            // You can store delim_ok somewhere if you added a field; otherwise just warn
            ap.write(sp);
            `uvm_info("CAN_MON_DBG",
              $sformatf("[node%0d] wrote special sp.f_type=%0d (ERR=%0d OVL=%0d)",
                        c_cfg.node_id, sp.f_type, `CAN_ERROR_FRAME, `CAN_OVERLOAD_FRAME),
              UVM_LOW);
            `uvm_info("CAN_MON",
              $sformatf("[node%0d] OBS publish SPECIAL(INTERMISSION) ftype=%0d", c_cfg.node_id, sp.f_type),
              UVM_LOW);
          end
          
          overload_seen = 1;
          
          if (!delim_ok)
            `uvm_warning("CAN_MON", "OVERLOAD delimiter not clean (non-recessive seen)");
  
          state = ST_IDLE;
          return;
        end
  
        // Not matched => treat as noise/error and recover
        recover_to_idle();
        state = ST_IDLE;
        return;
      end
    end
  
    // Completed IFS normally => bus is truly idle
    state = ST_IDLE;
  endtask
  
   // ---------------------------------------------------------------------------------------

   task automatic try_decode_special_flag_frame(
    output bit          matched,
    output int unsigned ftype,
    output bit          delim_bad
  );
    bit b;
    int dom_cnt;
  
    matched   = 1'b0;
    ftype     = `CAN_DATA_FRAME;
    delim_bad = 1'b0;
  
    // Sample CURRENT bit (already aligned)
    sample_current_bit(b);
    if (b !== 1'b0) return;
  
    dom_cnt = 1;
  
    // Remaining 5 bits of the flag
    repeat (5) begin
      sample_next_bit(b);
      if (b === 1'b0) dom_cnt++;
    end
  
    if (dom_cnt != 6) begin
      matched = 1'b0;
      return;
    end
  
    matched = 1'b1;
  
    // Classify using driver hint if available
    ftype = `CAN_ERROR_FRAME; // IDLE-detected special => treat as ERROR
  
    // delimiter (8 recessive). Don't spam warnings.
    repeat (8) begin
      sample_next_bit(b);
      if (b !== 1'b1) delim_bad = 1'b1;
    end
  
    recover_to_idle();
  endtask
        
  // ---------------------------------------------------------------------------------------

  task automatic try_decode_special_flag_midframe(
    output bit          matched,
    output int unsigned ftype,
    output bit          delim_ok
  );
    bit b;
    int dom_cnt;
  
    matched  = 1'b0;
    ftype    = `CAN_ERROR_FRAME; // mid-frame => error by definition
    delim_ok = 1'b1;
  
    // Confirm 6 consecutive dominant bits (0)
    dom_cnt = 0;
    repeat (6) begin
      sample_next_bit(b);
      if (b === 1'b0) dom_cnt++;
    end
  
    if (dom_cnt != 6) begin
      matched = 1'b0;
      return;
    end
  
    // Delimiter: 8 recessive bits (1)
    repeat (8) begin
      sample_next_bit(b);
     if (b !== 1'b1) tr.form_error_seen = 1'b1;
    end
  
    matched = 1'b1;
    recover_to_idle();
  endtask
  
  // ----------------------------------------------------------------------------------------
  task automatic try_decode_special_flag_from_current_bit(
    output bit          matched,
    output int unsigned ftype,
    output bit          delim_ok
  );
    bit b;
    int dom_cnt;
  
    matched  = 1'b0;
    ftype    = `CAN_OVERLOAD_FRAME; // caller decides; for IFS you will publish OVERLOAD
    delim_ok = 1'b1;
  
    // We are called when we already saw the first dominant bit (0)
    // and we are aligned on a bit boundary.
  
    dom_cnt = 1;
  
    // Check next 5 bits to confirm 6 consecutive dominant bits total
    repeat (5) begin
      sample_next_bit(b);
      if (b === 1'b0) dom_cnt++;
      else begin
        // Not a special flag -> DO NOT recover; just return
        matched = 1'b0;
        return;
      end
    end
  
    // If we get here, we truly saw 6/6 dominant
    matched = 1'b1;
  
    // Delimiter: 8 recessive bits (must be all 1)
    repeat (8) begin
      sample_next_bit(b);
      if (b !== 1'b1) delim_ok = 1'b0;
    end
  
    // Only now we recover (we consumed an entire special flag + delimiter)
    recover_to_idle();
  
  endtask

  
  // ===================================================================
  // sync/lifecycle
  // ===================================================================
  task automatic wait_for_sof_boundary();
    forever begin
      @vif.can_cb;
      if (vif.rx_i === 1'b0) return;
    end
  endtask

  // ---------------------------------------------------------------------------------------
  
  task automatic start_new_frame();
    tr = can_transaction::type_id::create("tr");
    tr.t_start  = $time;
    tr.src_node = c_cfg.node_id;

    // reset observed flags
    tr.ack_seen         = 1'b0; // default: not seen yet
    tr.ack_driven       = 1'b0;
    tr.crc_error_seen   = 1'b0;
    tr.stuff_error_seen = 1'b0;
    tr.form_error_seen  = 1'b0;

    tr.f_type  = `CAN_DATA_FRAME;
    tr.can_fmt = `CAN_ID_STD;
    tr.id      = '0;
    tr.dlc     = 0;
    tr.data    = new[0];

    // CRC state reset for each frame (init will happen at SOF if valid)
    crc_calc_en = 1'b0;
    crc_calc    = 15'h0000;
    crc_seq     = 15'h0000;
  endtask

  // ---------------------------------------------------------------------------------------
  
  task automatic end_frame_and_publish();
    tr.t_end = $time;
    ap.write(tr);

    `uvm_info("CAN_MON",
  $sformatf("[node%0d] OBS publish type=%s (ftype=%0d) id=0x%0h dlc=%0d ack_seen=%0b crc_err=%0b form=%0b stuff=%0b",
            c_cfg.node_id, tr.ftype_str(), tr.f_type, tr.id, tr.dlc,
            tr.ack_seen, tr.crc_error_seen, tr.form_error_seen, tr.stuff_error_seen),
  UVM_LOW);

  endtask
  

 

endclass : can_monitor

`endif // CAN_MONITOR_SV
