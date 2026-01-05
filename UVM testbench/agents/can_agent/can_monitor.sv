`ifndef CAN_MONITOR_SV
`define CAN_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "can_defines.sv"   // make sure filename matches

class can_monitor extends uvm_monitor;
  `uvm_component_utils(can_monitor)

  uvm_analysis_port #(can_transactions) ap;

  virtual can_if vif;
  can_agent_config c_cfg;

  // ------ State machine (monitor internal) ---------------
  typedef enum int {
    ST_IDLE = 0,
    ST_SOF,
    ST_ARB,     // arbitration: ID + RTR + IDE (extended later)
    ST_CTRL,    // control: r0 + DLC
    ST_DATA,    // data bytes
    ST_CRC,     // CRC + delimiter
    ST_ACK,     // ACK slot + delimiter
    ST_EOF      // EOF bits
  } can_mon_state_e;

  can_mon_state_e state;

  // ----------- Internal Decode Bookkeeping ----------------
  can_transactions tr;      // current frame being built

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

  // =========== CONSTRUCTOR ===========================================================================
  function new(string name="can_monitor", uvm_component parent=null);
    super.new(name, parent);
    ap = new("ap", this);
    state = ST_IDLE;
  endfunction

  // =========== BUILD_PHASE ===========================================================================
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
      $sformatf("Monitor ready: bit_time=%0t sp_offset=%0t (%0d%%)", bit_time, sp_offset, c_cfg.sample_point_pct), UVM_LOW)
	  
  endfunction

  // =================== RUN_PHASE =========================================================================
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

        ST_ARB: begin
          decode_arbitration_std(); // sets next state
        end

        ST_CTRL: begin
          decode_control_std();     // sets next state
        end

        ST_DATA: begin
          decode_data_field();      // sets next state
        end

        ST_CRC: begin
          decode_crc_field();       // sets next state
        end

        ST_ACK: begin
          decode_ack_field();       // sets next state
        end

        ST_EOF: begin
          decode_eof_field();       // publishes + returns to IDLE
        end

        default: begin
          `uvm_warning("CAN_MON","Unknown state; returning to IDLE")
          state = ST_IDLE;
        end
      endcase
    end
  endtask

  // =====================================================================================================
  // BIT ENGINE (raw sampling + logical de-stuffing)
  // =====================================================================================================
  task sample_raw_bit(output bit b);
    @(posedge vif.clk_i);
    #(sp_offset);
    b = vif.rx_i;
    #(bit_time - sp_offset);
  endtask

  function void init_logical_stream(bit first_bit);
    last_logical_bit = first_bit;
    same_cnt         = 1;
    stuff_expected   = 0;
  endfunction

  task get_logical_bit(output bit lb);
    bit rb;
    forever begin
      sample_raw_bit(rb);

      if (stuff_expected) begin
        if (rb == last_logical_bit) begin
          `uvm_warning("CAN_MON","Stuff error suspected; resync to IDLE")
          state = ST_IDLE;
          return;
        end
        stuff_expected = 0;
        continue; // fetch next logical bit
      end

      lb = rb;

      if (lb == last_logical_bit) 
		same_cnt++;
      else 
		same_cnt = 1;

      last_logical_bit = lb;

      if (same_cnt == 5) 
		  begin
			stuff_expected = 1;
			same_cnt       = 0;
		  end

      return;
    end
  endtask

  // =====================================================================================================
  // Arbitration Decode (standard)
  // =====================================================================================================
  task decode_arbitration_std();
    bit b;
    bit [10:0] sid;
    bit rtr;
    bit ide;

    sid = '0;

    for (int i = 10; i >= 0; i--) begin
      get_logical_bit(b);
      if (state == ST_IDLE) return;
      sid[i] = b;
    end

    get_logical_bit(rtr);
    if (state == ST_IDLE) return;

    get_logical_bit(ide);
    if (state == ST_IDLE) return;

    tr.can_fmt = (ide == 1'b0) ? `CAN_ID_STD : `CAN_ID_EXT;
    tr.id      = {18'd0, sid};
    tr.f_type  = (rtr == 1'b1) ? `CAN_REMOTE_FRAME : `CAN_DATA_FRAME;

    if (ide == 1'b1) begin
      `uvm_warning("CAN_MON","Extended frame detected; EXT decode not implemented yet")
      state = ST_EOF; // graceful stop
    end
    else begin
      state = ST_CTRL;
    end
  endtask

  // =====================================================================================================
  // CONTROL FIELD DECODE (standard)
  // =====================================================================================================
  task decode_control_std();
    bit b;
    bit r0;
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

    bit_idx  = 0;
    byte_idx = 0;
    cur_byte = 8'h00;

    if (tr.dlc == 0)
      state = ST_CRC;
    else
      state = ST_DATA;
  endtask

  // =====================================================================================================
  // DATA FIELD DECODE (standard)
  // =====================================================================================================
  task decode_data_field();
    bit b;

    tr.data = new[tr.dlc];

    for (byte_idx = 0; byte_idx < tr.dlc; byte_idx++) begin
      cur_byte = 8'h00;

      for (int bi = 7; bi >= 0; bi--) begin
        get_logical_bit(b);
        if (state == ST_IDLE) return;
        cur_byte[bi] = b;
      end

      tr.data[byte_idx] = cur_byte;
    end

    state = ST_CRC;
  endtask

  // =====================================================================================================
  // CRC FIELD DECODE
  // =====================================================================================================
  task decode_crc_field();
    bit b;
    bit [14:0] crc_seq;

    crc_seq = 15'd0;

    for (int i = 14; i >= 0; i--) begin
      sample_raw_bit(b);
      if (state == ST_IDLE) return;
      crc_seq[i] = b;
    end

    tr.crc_obs = crc_seq;

    // CRC delimiter
    sample_raw_bit(b);
    if (state == ST_IDLE) return;

    if (b !== 1'b1)
      `uvm_warning("CAN_MON","CRC delimiter not recessive (possible form error)")

    state = ST_ACK;
  endtask

  // =====================================================================================================
  // ACK FIELD DECODE
  // =====================================================================================================
  task decode_ack_field();
    bit ack_slot;
    bit ack_delim;

    sample_raw_bit(ack_slot);
    if (state == ST_IDLE) return;

    if (ack_slot == 1'b1)
      `uvm_warning("CAN_MON","ACK error (no dominant ACK)")

    sample_raw_bit(ack_delim);
    if (state == ST_IDLE) return;

    if (ack_delim !== 1'b1)
      `uvm_warning("CAN_MON","ACK delimiter not recessive (possible form error)")

    state = ST_EOF;
  endtask

  // =====================================================================================================
  // EOF FIELD DECODE (7 recessive bits)
  // Note: For strict correctness, stuffing should not be applied in EOF.
  // For v1, we still use get_logical_bit; upgrade later if needed.
  // =====================================================================================================
  task decode_eof_field();
    bit b;

    for (int i = 0; i < 7; i++) begin
      sample_raw_bit(b);
      if (state == ST_IDLE) return;

      if (b !== 1'b1)
        `uvm_warning("CAN_MON", $sformatf("EOF bit %0d not recessive", i))
    end

    end_frame_and_publish();
    state = ST_IDLE;
  endtask

  // =====================================================================================================
  // Frame lifecycle helpers
  // =====================================================================================================
  task wait_for_sof();
    wait (vif.rx_i === 1'b1);
    @(posedge vif.clk_i);
    wait (vif.rx_i === 1'b0);
  endtask

  task start_new_frame();
    tr = can_transactions::type_id::create("tr");
    tr.t_start = $time;

    tr.f_type  = `CAN_DATA_FRAME;
    tr.can_fmt = `CAN_ID_STD;
    tr.id      = '0;
    tr.dlc     = 0;
    tr.data    = new[0];
  endtask

  task end_frame_and_publish();
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
