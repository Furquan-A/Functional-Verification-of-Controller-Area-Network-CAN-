`ifndef CAN_MONITOR_SV
`define CAN_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// NOTE: Prefer compiling via can_pkg.sv (so you don't need extra `include`s here).

class can_monitor extends uvm_monitor;
  `uvm_component_utils(can_monitor)

  uvm_analysis_port #(can_transaction) ap;

  virtual can_if      vif;
  can_agent_config    c_cfg;

  // ------ State machine (monitor internal) ---------------
  typedef enum int {
    ST_IDLE = 0,
    ST_SOF,
    ST_ARB,     // arbitration: ID + RTR/SRR + IDE + (extended id) + RTR
    ST_CTRL,    // control: r0 + DLC
    ST_DATA,    // data bytes
    ST_CRC,     // CRC + delimiter
    ST_ACK,     // ACK slot + delimiter
    ST_EOF      // EOF bits
  } can_mon_state_e;

  can_mon_state_e state;

  // ----------- Internal Decode Bookkeeping ----------------
  can_transaction tr;      // current frame being built

  int unsigned bit_idx;
  int unsigned byte_idx;
  bit [7:0]    cur_byte;

  // Stuff-bit tracking (logical stream)
  bit          last_logical_bit;
  int unsigned same_cnt;
  bit          stuff_expected;

  // Precomputed timing
  time bit_time;
  time sp_offset;

  // ===================== CONSTRUCTOR ======================
  function new(string name="can_monitor", uvm_component parent=null);
    super.new(name, parent);
    ap    = new("ap", this);
    state = ST_IDLE;
  endfunction

  // ===================== BUILD_PHASE ======================
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_MON","can_agent_config not found (key='m_cfg')")

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_MON","virtual interface can_if not found (key='vif')")

    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;

    // Initialize stuff tracking to idle bus (recessive)
    last_logical_bit = 1'b1;
    same_cnt         = 0;
    stuff_expected   = 0;

    `uvm_info("CAN_MON",
      $sformatf("Monitor ready: bit_time=%0t sp_offset=%0t (%0d%%)",
                bit_time, sp_offset, c_cfg.sample_point_pct),
      UVM_LOW)
  endfunction

  // ===================== RUN_PHASE ========================
  task run_phase(uvm_phase phase);
    super.run_phase(phase);

    forever begin
      case (state)

        ST_IDLE: begin
          wait_for_sof();
          start_new_frame();
          state = ST_SOF;
        end

        ST_SOF: begin
          bit b;
          // We are aligned to SOF start by wait_for_sof()
          sample_raw_bit(b);
          if (b !== 1'b0) begin
            `uvm_warning("CAN_MON","SOF not dominant; resync to IDLE")
            state = ST_IDLE;
          end
          else begin
            init_logical_stream(b);
            state   = ST_ARB;
            bit_idx = 0;
          end
        end

        ST_ARB:  decode_arbitration();
        ST_CTRL: decode_control_std();
        ST_DATA: decode_data_field();
        ST_CRC:  decode_crc_field();
        ST_ACK:  decode_ack_field();
        ST_EOF:  decode_eof_field();

        default: begin
          `uvm_warning("CAN_MON","Unknown state; returning to IDLE")
          state = ST_IDLE;
        end
      endcase
    end
  endtask

  // =====================================================================
  // BIT ENGINE (raw sampling + logical de-stuffing)
  // =====================================================================

  // Sample one RAW bus bit at the configured sample point.
  // IMPORTANT: This assumes the caller is aligned to the start of a bit time.
  task automatic sample_raw_bit(output bit b);
    #(sp_offset);
    b = vif.rx_i;
    #(bit_time - sp_offset);
  endtask

  function void init_logical_stream(bit first_bit);
    last_logical_bit = first_bit;
    same_cnt         = 1;
    stuff_expected   = 0;
  endfunction

  // Fetch next LOGICAL bit (destuffs raw stream).
  // On stuff error, it forces state back to IDLE and returns.
  task automatic get_logical_bit(output bit lb);
    bit rb;

    forever begin
      sample_raw_bit(rb);

      // If a stuff bit is expected, it must be the opposite of last logical bit.
      if (stuff_expected) begin
        if (rb == last_logical_bit) begin
          `uvm_warning("CAN_MON","Stuff error suspected; resync to IDLE")
          state = ST_IDLE;
          return;
        end
        stuff_expected = 0;
        continue; // stuff bit consumed, now fetch the next logical bit
      end

      lb = rb;

      // Update run-length tracking on logical bits only
      if (lb == last_logical_bit)
        same_cnt++;
      else
        same_cnt = 1;

      last_logical_bit = lb;

      if (same_cnt == 5) begin
        stuff_expected = 1;
        same_cnt       = 0; // next raw bit is a stuff bit (not a logical bit)
      end

      return;
    end
  endtask

  // =====================================================================
  // Arbitration Decode (STD + EXT)
  // =====================================================================
  task automatic decode_arbitration();
    bit        b;
    bit        rtr;
    bit        ide;
    bit [10:0] base_id;
    bit [28:0] can_id;

    base_id = '0;
    can_id  = '0;
    rtr     = 1'b0;

    // -------- BASE ID (11 bits), MSB..LSB
    for (int i = 10; i >= 0; i--) begin
      get_logical_bit(b);
      if (state == ST_IDLE) return;
      base_id[i] = b;
    end

    // -------- RTR (STD) or SRR (EXT placeholder)
    get_logical_bit(b);
    if (state == ST_IDLE) return;

    // -------- IDE
    get_logical_bit(ide);
    if (state == ST_IDLE) return;

    if (ide == 1'b0) begin
      // -------- STANDARD FRAME
      can_id[10:0] = base_id;
      rtr          = b;

      tr.can_fmt = `CAN_ID_STD;
      tr.id      = can_id; // upper bits 0
      tr.f_type  = (rtr == 1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

      state = ST_CTRL;
    end
    else begin
      // -------- EXTENDED FRAME
      // b is SRR (should be recessive 1)
      if (b !== 1'b1)
        `uvm_warning("CAN_MON","SRR in EXT frame is not recessive (form error)")

      can_id[28:18] = base_id;

      // Extended ID lower 18 bits
      for (int i = 17; i >= 0; i--) begin
        get_logical_bit(b);
        if (state == ST_IDLE) return;
        can_id[i] = b;
      end

      // RTR bit (for extended)
      get_logical_bit(b);
      if (state == ST_IDLE) return;
      rtr = b;

      tr.can_fmt = `CAN_ID_EXT;
      tr.id      = can_id;
      tr.f_type  = (rtr == 1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

      state = ST_CTRL;
    end
  endtask

  // =====================================================================
  // CONTROL FIELD DECODE (classic CAN)
  // =====================================================================
  task automatic decode_control_std();
    bit     b;
    bit     r0;
    bit [3:0] dlc_value;

    get_logical_bit(r0);
    if (state == ST_IDLE) return;

    if (r0 !== 1'b0)
      `uvm_warning("CAN_MON","r0 not zero (possible form error)")

    dlc_value = 4'd0;
    for (int i = 3; i >= 0; i--) begin
      get_logical_bit(b);
      if (state == ST_IDLE) return;
      dlc_value[i] = b;
    end

    tr.dlc = dlc_value;

    // For classic CAN, payload max is 8. Clamp to keep smoke robust.
    if (tr.dlc > 8) begin
      `uvm_warning("CAN_MON", $sformatf("DLC=%0d > 8 in classic CAN; clamping to 8 for decode", tr.dlc))
      tr.dlc = 8;
    end

    if (tr.dlc == 0)
      state = ST_CRC;
    else
      state = ST_DATA;
  endtask

  // =====================================================================
  // DATA FIELD DECODE
  // =====================================================================
  task automatic decode_data_field();
    bit b;

    tr.data = new[tr.dlc];

    for (int unsigned bi = 0; bi < tr.dlc; bi++) begin
      cur_byte = 8'h00;

      for (int bitpos = 7; bitpos >= 0; bitpos--) begin
        get_logical_bit(b);
        if (state == ST_IDLE) return;
        cur_byte[bitpos] = b;
      end

      tr.data[bi] = cur_byte;
    end

    state = ST_CRC;
  endtask

  // =====================================================================
  // CRC FIELD DECODE (CRC15 + delimiter)
  // =====================================================================
  task automatic decode_crc_field();
    bit b;
    bit [14:0] crc_seq;

    crc_seq = 15'd0;

    // CRC sequence bits are still subject to stuffing -> use logical bits
    for (int i = 14; i >= 0; i--) begin
      get_logical_bit(b);
      if (state == ST_IDLE) return;
      crc_seq[i] = b;
    end

    tr.crc_obs = crc_seq;

    // CRC delimiter is NOT stuffed -> raw
    sample_raw_bit(b);
    if (b !== 1'b1)
      `uvm_warning("CAN_MON","CRC delimiter not recessive (possible form error)")

    state = ST_ACK;
  endtask

  // =====================================================================
  // ACK FIELD DECODE (slot + delimiter)
  // =====================================================================
  task automatic decode_ack_field();
    bit ack_slot;
    bit ack_delim;

    // ACK slot is raw (not stuffed)
    sample_raw_bit(ack_slot);

    // For smoke, this warning is OK if you haven't implemented ACK driving yet.
    if (ack_slot == 1'b1)
      `uvm_warning("CAN_MON","ACK slot recessive (no dominant ACK observed)")

    sample_raw_bit(ack_delim);
    if (ack_delim !== 1'b1)
      `uvm_warning("CAN_MON","ACK delimiter not recessive (possible form error)")

    state = ST_EOF;
  endtask

  // =====================================================================
  // EOF FIELD DECODE (7 recessive bits, raw, not stuffed)
  // =====================================================================
  task automatic decode_eof_field();
    bit b;

    for (int i = 0; i < 7; i++) begin
      sample_raw_bit(b);
      if (b !== 1'b1)
        `uvm_warning("CAN_MON", $sformatf("EOF bit %0d not recessive", i))
    end

    end_frame_and_publish();
    state = ST_IDLE;
  endtask

  // =====================================================================
  // Frame lifecycle helpers
  // =====================================================================
  // Align to the START of SOF (first dominant edge).
  // After this returns, we are at the beginning of a bit time.
  task automatic wait_for_sof();
    // Ensure bus is idle first
    wait (vif.rx_i === 1'b1);

    // Wait for SOF dominant edge
    wait (vif.rx_i === 1'b0);

    // We don't know exact edge time vs our timebase; start sampling from here.
    // (Smoke-level alignment. You can refine later.)
  endtask

  task automatic start_new_frame();
    tr = can_transaction::type_id::create("tr");
    tr.t_start = $time;

    tr.f_type  = `CAN_DATA_FRAME;
    tr.can_fmt = `CAN_ID_STD;
    tr.id      = '0;
    tr.dlc     = 0;
    tr.data    = new[0];
  endtask

  task automatic end_frame_and_publish();
    tr.t_end = $time;
    ap.write(tr);

    `uvm_info("CAN_MON",
      $sformatf("Observed frame: fmt=%s id=0x%0h type=%0d dlc=%0d bytes=%0d",
                (tr.can_fmt==`CAN_ID_STD)?"STD":"EXT",
                tr.id, tr.f_type, tr.dlc, tr.data.size()),
      UVM_LOW)
  endtask

endclass : can_monitor

`endif // CAN_MONITOR_SV
