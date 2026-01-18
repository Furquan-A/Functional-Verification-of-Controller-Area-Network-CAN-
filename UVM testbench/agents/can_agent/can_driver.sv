`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

//--------------------------------------------------------------------------------------------------
// can_driver (Phase-B Arbitration, Option-2)
// - Drives node transmit intent via vif.can_cb.tb_tx[node_id]
// - Samples vif.rx_i at sample point during arbitration field
// - Detects arbitration loss: sent recessive(1) but saw dominant(0)
// - On loss: releases bus immediately, marks tr_in.arb_lost, stops TX, waits frame end
//--------------------------------------------------------------------------------------------------
class can_driver extends uvm_driver #(can_transaction);
  `uvm_component_utils(can_driver)

  uvm_analysis_port #(can_transaction) ap;

  can_agent_config c_cfg;
  virtual can_if   vif;

  // Timing
  time bit_time;
  time sp_offset;

  // Bit stuffing bookkeeping
  bit          stuff_en;
  bit          last_tx_bit;
  int unsigned same_cnt;

  // Arbitration flags
  bit in_arbitration;
  bit lost_arbitration;
  int unsigned arb_bit_idx; // counts arbitration bits (logical bits)

  // CRC
  bit        crc_en;
  bit [14:0] crc_reg;
  localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;

  function new(string name = "can_driver", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_DRV", "cannot get CAN agent config from config_db (key='m_cfg')")

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_DRV", "Virtual can_if not found in config_db (key='vif')")

    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;

    if (sp_offset >= bit_time)
      `uvm_fatal("CAN_DRV", "sample_point_pct makes sp_offset >= bit_time (invalid)")

    `uvm_info("CAN_DRV",
              $sformatf("Driver ready: node_id=%0d bit_time=%0t sp_offset=%0t (%0d%%)",
                        c_cfg.node_id, bit_time, sp_offset, c_cfg.sample_point_pct),
              UVM_LOW);
  endfunction

  task run_phase(uvm_phase phase);
    can_transaction tr_local;

    // Release bus by default
    drive_tx(1'b1);

    forever begin
      seq_item_port.get_next_item(tr_local);

      tr_local.t_start = $time;

      // default arbitration outcome
	  tr_local.src_node     = c_cfg.node_id;
      tr_local.arb_lost     = 1'b0;
      tr_local.arb_lost_bit = 0;

      send_frame(tr_local);

      tr_local.t_end = $time;

      // publish what we attempted (scoreboard can ignore arb_lost==1)
      ap.write(tr_local);

      seq_item_port.item_done();
    end
  endtask

  // ===============================================================================================
  // BUS DRIVER PRIMITIVES
  // ===============================================================================================

  task automatic drive_tx(bit level);
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= level;
  endtask

  // Drive one physical bit and optionally check arbitration at sample point.
  // - If in_arbitration and we lose, sets lost_arbitration and releases bus.
  task automatic drive_raw_bit(bit level);
    bit bus_sample;

    // Drive at start of bit time
    drive_tx(level);

    // Sample at sample point
    #(sp_offset);
    bus_sample = vif.rx_i;

    if (in_arbitration && !lost_arbitration) begin
      // Arbitration loss condition: we sent 1 but bus is 0
      if ((level === 1'b1) && (bus_sample === 1'b0)) begin
        lost_arbitration = 1'b1;
        // release immediately
        drive_tx(1'b1);
      end
      arb_bit_idx++;
    end

    // Finish bit time
    #(bit_time - sp_offset);
  endtask

  function void init_stuffing(bit first_bit);
    last_tx_bit = first_bit;
    same_cnt    = 1;
  endfunction

  task automatic drive_logical_bit(bit lb);

    // Insert stuff bit if needed
    if (stuff_en && (same_cnt == 5)) begin
      bit stuff_bit = ~last_tx_bit;
      drive_raw_bit(stuff_bit);

      // If we lost arbitration while sending stuff bit, stop immediately
      if (lost_arbitration) return;

      last_tx_bit = stuff_bit;
      same_cnt    = 1;
    end

    drive_raw_bit(lb);
    if (lost_arbitration) return;

    if (lb == last_tx_bit) begin
      same_cnt++;
    end
    else begin
      last_tx_bit = lb;
      same_cnt    = 1;
    end
  endtask

  // -------------------------------- CRC ---------------------------------------
  function void crc15_update(bit b);
    bit msb;
    msb     = crc_reg[14] ^ b;
    crc_reg = {crc_reg[13:0], 1'b0};
    if (msb)
      crc_reg = crc_reg ^ CAN_CRC15_POLY;
  endfunction

  task automatic crc_start();
    crc_reg = 15'h0000;
    crc_en  = 1'b1;
  endtask

  task automatic crc_stop();
    crc_en = 1'b0;
  endtask

  task automatic drive_frame_bit(bit lb);
    if (crc_en) crc15_update(lb);
    drive_logical_bit(lb);
  endtask

  // ===============================================================================================
  // IDLE / BUS ACCESS
  // ===============================================================================================

  task automatic wait_for_idle_bus();
    time start_t = $time;

    while (vif.rx_i !== 1'b1) begin
      if (($time - start_t) > (bit_time * 200)) begin
        `uvm_fatal("CAN_DRV", "Timeout waiting for bus idle/recessive (rx_i stuck non-1)")
      end
      #(bit_time);
    end

    repeat (`CAN_INTERMISSION_BITS) drive_raw_bit(1'b1);
  endtask

  // Wait until current frame ends (simple heuristic):
  // wait for 7 consecutive recessive bits (EOF) after we've lost arbitration.
  task automatic wait_frame_end_after_loss();
    int unsigned recessive_cnt = 0;
    bit b;

    // We assume we're already inside a frame. Track raw bits on bus.
    while (recessive_cnt < 7) begin
      // sample each bit at sample point
      #(sp_offset);
      b = vif.rx_i;
      #(bit_time - sp_offset);

      if (b === 1'b1) recessive_cnt++;
      else recessive_cnt = 0;
    end

    // After EOF, bus will go idle; we keep released.
    drive_tx(1'b1);
  endtask

  // ===============================================================================================
  // FRAME TRANSMIT (SOF -> EOF) with arbitration support
  // ===============================================================================================
  task automatic send_frame(can_transaction tr_in);

    int unsigned dlc_clamped;
    int unsigned nbytes;

    dlc_clamped = (tr_in.dlc > 8) ? 8 : tr_in.dlc;
    nbytes      = (tr_in.data.size() < dlc_clamped) ? tr_in.data.size() : dlc_clamped;

    // reset arbitration tracking for this frame attempt
    in_arbitration    = 1'b0;
    lost_arbitration  = 1'b0;
    arb_bit_idx       = 0;

    wait_for_idle_bus();

    // ---------------- SOF (dominant 0, not stuffed)
    stuff_en = 1'b0;
    drive_raw_bit(1'b0);
    if (lost_arbitration) begin
      // SOF loss is unlikely here but handle anyway
      tr_in.arb_lost     = 1'b1;
      tr_in.arb_lost_bit = arb_bit_idx;
	  
	  `uvm_info("CAN_ARB",
            $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h) -> released bus",
                      c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
            UVM_LOW);
      wait_frame_end_after_loss();
      return;
    end

    init_stuffing(1'b0);

    crc_start();
    crc15_update(1'b0);

    stuff_en = 1'b1;

    // ---------------- ARBITRATION FIELD (enable arbitration checking)
    in_arbitration = 1'b1;

    if (tr_in.can_fmt == `CAN_ID_STD) begin
      for (int i = 10; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) return;
		
      end
      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0); // RTR
      if (lost_arbitration) return;

      drive_frame_bit(1'b0); // IDE=0
      if (lost_arbitration) return;
    end
    else begin
      for (int i = 28; i >= 18; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) return;
      end
      drive_frame_bit(1'b1); // SRR=1
      if (lost_arbitration) return ;

      drive_frame_bit(1'b1); // IDE=1
      if (lost_arbitration) return;

      for (int i = 17; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) return;
      end
      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0); // RTR
      if (lost_arbitration) return;
    end

    // Arbitration done after RTR/IDE bits
    in_arbitration = 1'b0;

    // ---------------- CONTROL FIELD (classic CAN)
    drive_frame_bit(1'b0); // r0
    for (int i = 3; i >= 0; i--) begin
      drive_frame_bit(dlc_clamped[i]);
    end

    // ---------------- DATA FIELD
    if (tr_in.f_type == `CAN_DATA_FRAME) begin
      for (int bi = 0; bi < nbytes; bi++) begin
        for (int b = 7; b >= 0; b--) begin
          drive_frame_bit(tr_in.data[bi][b]);
        end
      end
    end

    // ---------------- CRC SEQUENCE + CRC DELIMITER
    crc_stop();

    for (int i = 14; i >= 0; i--) begin
      drive_frame_bit(crc_reg[i]);
    end

    stuff_en = 1'b0;
    drive_raw_bit(1'b1);  // CRC delimiter

    // ---------------- ACK SLOT + ACK DELIMITER
    drive_raw_bit(1'b1);  // ACK slot
    drive_raw_bit(1'b1);  // ACK delimiter

    // ---------------- EOF (7 recessive)
    repeat (7) drive_raw_bit(1'b1);

    drive_tx(1'b1);
	
	`uvm_info("CAN_ARB",
          $sformatf("[WIN ] node%0d won arbitration and completed TX (id=0x%0h)",
                    c_cfg.node_id, tr_in.id),
          UVM_LOW);
    `uvm_info("CAN_DRV",
              $sformatf("TX DONE: node=%0d fmt=%s id=0x%0h dlc=%0d (clamped=%0d) bytes_sent=%0d",
                        c_cfg.node_id,
                        (tr_in.can_fmt==`CAN_ID_STD) ? "STD" : "EXT",
                        tr_in.id, tr_in.dlc, dlc_clamped, nbytes),
              UVM_LOW);
    return;

  LOST:
    // Arbitration loss handling
    tr_in.arb_lost     = 1'b1;
    tr_in.arb_lost_bit = arb_bit_idx;

    // release and wait for winner frame to finish
    drive_tx(1'b1);

    `uvm_info("CAN_ARB",
              $sformatf("Node%0d LOST arbitration at arb_bit=%0d (released bus). id=0x%0h",
                        c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
              UVM_LOW);

    wait_frame_end_after_loss();
    return;

  endtask

endclass : can_driver

`endif // CAN_DRIVER_SV
