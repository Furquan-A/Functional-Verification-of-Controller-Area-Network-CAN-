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
    ST_EOF
  } can_mon_state_e;

  can_mon_state_e state;

  can_transaction tr;

  // Stuffing (logical stream)
  bit          last_logical_bit;
  int unsigned same_cnt;
  bit          stuff_expected;

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
          wait_for_sof_boundary();
          start_new_frame();
          state = ST_SOF;
        end

        ST_SOF: begin
          bit b;
          // already aligned to boundary
          sample_current_bit(b);
          if (b !== 1'b0) begin
            `uvm_warning("CAN_MON","SOF not dominant; resync to IDLE");
            state = ST_IDLE;
          end
          else begin
            init_logical_stream(b);
            state = ST_ARB;
          end
        end

        ST_ARB:  decode_arbitration();
        ST_CTRL: decode_control_std();
        ST_DATA: decode_data_field();
        ST_CRC:  decode_crc_field();
        ST_ACK:  decode_ack_field();
        ST_EOF:  decode_eof_field();

        default: state = ST_IDLE;
      endcase
    end
  endtask

  // ===========================================================================
  // BIT ENGINE (aligned)
  // ===========================================================================

  // sample within CURRENT bit (assumes we're already at start of bit)
  task automatic sample_current_bit(output bit b);
    #(sp_offset);
    b = vif.rx_i;
    #(bit_time - sp_offset);
  endtask

  // advance to NEXT bit boundary then sample that bit
  task automatic sample_next_bit(output bit b);
    @vif.can_cb;
    sample_current_bit(b);
  endtask

  function void init_logical_stream(bit first_bit);
    last_logical_bit = first_bit;
    same_cnt         = 1;
    stuff_expected   = 0;
  endfunction

  task automatic get_logical_bit(output bit lb);
    bit rb;

    forever begin
      sample_next_bit(rb);

      // consume stuff bit if expected
      if (stuff_expected) begin
        if (rb == last_logical_bit) begin
          `uvm_warning("CAN_MON","Stuff error suspected; resync to IDLE");
          state = ST_IDLE;
          return;
        end
        stuff_expected = 0;
        continue;
      end

      lb = rb;

      // update run-length on logical bits only
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

  // ===========================================================================
  // DECODE: Arbitration
  // ===========================================================================

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
      base_id[i] = b;
    end

    // RTR or SRR
    get_logical_bit(b);   if (state==ST_IDLE) return;

    // IDE
    get_logical_bit(ide); if (state==ST_IDLE) return;

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
      if (b !== 1'b1)
        `uvm_warning("CAN_MON","SRR in EXT frame not recessive (form error)");

      can_id[28:18] = base_id;

      for (int i = 17; i >= 0; i--) begin
        get_logical_bit(b); if (state==ST_IDLE) return;
        can_id[i] = b;
      end

      // RTR (extended)
      get_logical_bit(b); if (state==ST_IDLE) return;
      rtr = b;

      tr.can_fmt = `CAN_ID_EXT;
      tr.id      = can_id;
      tr.f_type  = (rtr==1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

      state = ST_CTRL;
    end
  endtask

  // ===========================================================================
  // CONTROL
  // ===========================================================================

  task automatic decode_control_std();
    bit b;
    bit r0;
    bit [3:0] dlc_value;

    get_logical_bit(r0); if (state==ST_IDLE) return;
    if (r0 !== 1'b0) `uvm_warning("CAN_MON","r0 not zero");

    dlc_value = 4'd0;
    for (int i = 3; i >= 0; i--) begin
      get_logical_bit(b); if (state==ST_IDLE) return;
      dlc_value[i] = b;
    end

    tr.dlc = dlc_value;
    if (tr.dlc > 8) begin
      `uvm_warning("CAN_MON",$sformatf("DLC=%0d > 8 (classic); clamping to 8", tr.dlc));
      tr.dlc = 8;
    end

    state = (tr.dlc == 0) ? ST_CRC : ST_DATA;
  endtask

  // ===========================================================================
  // DATA
  // ===========================================================================

  task automatic decode_data_field();
    bit b;
    bit [7:0] cur_byte;

    tr.data = new[tr.dlc];

    for (int unsigned bi = 0; bi < tr.dlc; bi++) begin
      cur_byte = 8'h00;
      for (int bitpos = 7; bitpos >= 0; bitpos--) begin
        get_logical_bit(b); if (state==ST_IDLE) return;
        cur_byte[bitpos] = b;
      end
      tr.data[bi] = cur_byte;
    end

    state = ST_CRC;
  endtask

  // ===========================================================================
  // CRC
  // ===========================================================================

  task automatic decode_crc_field();
    bit b;
    bit [14:0] crc_seq;

    crc_seq = 15'd0;

    for (int i = 14; i >= 0; i--) begin
      get_logical_bit(b); if (state==ST_IDLE) return;
      crc_seq[i] = b;
    end
    tr.crc_obs = crc_seq;

    // CRC delimiter is RAW (not stuffed)
    sample_next_bit(b);
    if (b !== 1'b1)
      `uvm_warning("CAN_MON","CRC delimiter not recessive");

    state = ST_ACK;
  endtask

  // ===========================================================================
  // ACK (NO FORK, DETERMINISTIC)
  // ===========================================================================

  task automatic decode_ack_field();
    bit ack_slot;
    bit ack_delim;
    bit drive_ack;

    // ---------------- ACK SLOT ----------------
    // Move to ACK-slot BIT BOUNDARY
    @vif.can_cb;

    // Receiver ACK rule:
    // Ack only if enabled AND this node is NOT currently transmitting.
    drive_ack = (c_cfg.ack_enable && (c_cfg.is_tx_in_progress == 1'b0));

    // Drive ACK at the START of the ACK slot
    vif.can_cb.tb_tx[c_cfg.node_id] <= (drive_ack ? 1'b0 : 1'b1);

    if (drive_ack) begin
      `uvm_info("CAN_ACK",
                $sformatf("Node%0d drives ACK (receiver)", c_cfg.node_id),
                UVM_LOW)
    end

    // Sample ACK slot at sample point
    #(sp_offset);
    ack_slot = vif.rx_i;

    // Finish the bit time
    #(bit_time - sp_offset);

    // Release immediately after ACK slot
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1;

    if (ack_slot == 1'b1)
      `uvm_warning("CAN_MON","ACK error (no dominant ACK observed)");

    // ---------------- ACK DELIMITER ----------------
    // Delimiter bit boundary
    // (We are already at boundary due to @can_cb above)
    #(sp_offset);
    ack_delim = vif.rx_i;
    #(bit_time - sp_offset);

    if (ack_delim !== 1'b1)
      `uvm_warning("CAN_MON","ACK delimiter not recessive");

    state = ST_EOF;
  endtask


  // ===========================================================================
  // EOF
  // ===========================================================================

  task automatic decode_eof_field();
    bit b;

    for (int i = 0; i < 7; i++) begin
      sample_next_bit(b);
      if (b !== 1'b1)
        `uvm_warning("CAN_MON", $sformatf("EOF bit %0d not recessive", i));
    end

    end_frame_and_publish();
    state = ST_IDLE;
  endtask

  // ===========================================================================
  // FRAME LIFECYCLE / SYNC
  // ===========================================================================

  // Wait for SOF on BIT BOUNDARY (drivers align their bits to @can_cb)
  task automatic wait_for_sof_boundary();
    forever begin
      @vif.can_cb;
      if (vif.rx_i === 1'b0) return;
    end
  endtask

  task automatic start_new_frame();
    tr = can_transaction::type_id::create("tr");
    tr.t_start  = $time;
    tr.src_node = c_cfg.node_id;

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
      UVM_LOW);
  endtask

endclass : can_monitor

`endif // CAN_MONITOR_SV
