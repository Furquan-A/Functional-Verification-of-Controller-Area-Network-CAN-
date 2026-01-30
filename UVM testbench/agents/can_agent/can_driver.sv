`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

//--------------------------------------------------------------------------------------------------
// can_driver (Phase-B Arbitration, Option-2, TIMING ALIGNED)
// - Drives node intent via vif.can_cb.tb_tx[node_id]
// - Aligns EVERY bit to @vif.can_cb
// - Samples bus at sample-point during arbitration bits only
// - Detects arbitration loss: sent recessive(1) but bus sampled dominant(0)
// - On loss: releases bus, records arb_lost + bit index, waits for EOF then returns
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
  bit          in_arbitration;
  bit          lost_arbitration;
  int unsigned arb_bit_idx; // increments once per arbitration PHYSICAL bit we drive

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
      `uvm_fatal("CAN_DRV", "cannot get can_agent_config from config_db (key='m_cfg')")

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_DRV", "Virtual can_if not found in config_db (key='vif')")

    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;

    if (sp_offset >= bit_time)
      `uvm_fatal("CAN_DRV", "Invalid sample_point_pct (sp_offset >= bit_time)")

    `uvm_info("CAN_DRV",
      $sformatf("Driver ready: node_id=%0d bit_time=%0t sp_offset=%0t (%0d%%)",
                c_cfg.node_id, bit_time, sp_offset, c_cfg.sample_point_pct),
      UVM_LOW);
  endfunction

  task run_phase(uvm_phase phase);
    can_transaction tr_local;

    // Release by default
    drive_tx(1'b1);

    forever begin
      seq_item_port.get_next_item(tr_local);

      tr_local.t_start       = $time;
      tr_local.src_node      = c_cfg.node_id;
      tr_local.arb_lost      = 1'b0;
      tr_local.arb_lost_bit  = 0;
      
      c_cfg.is_tx_in_progress = 1'b1;
      send_frame(tr_local);
      c_cfg.is_tx_in_progress = 1'b0;
      
      tr_local.t_end = $time;

      // publish what we attempted
      ap.write(tr_local);

      seq_item_port.item_done();
    end
  endtask

  // ===========================================================================
  // BUS PRIMITIVES (ALIGNED)
  // ===========================================================================

  task automatic drive_tx(bit level);
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= level;
  endtask

  // Drive one PHYSICAL bit aligned to @can_cb, optionally do arbitration check
  task automatic drive_raw_bit(bit level);
    bit bus_sample;

    // Align to common boundary
    @vif.can_cb;

    // Drive at start of bit
    vif.can_cb.tb_tx[c_cfg.node_id] <= level;

    // Sample at sample-point
    #(sp_offset);
    bus_sample = vif.rx_i;

    // Arbitration loss check (only during arbitration)
    if (in_arbitration && !lost_arbitration) begin
      if ((level === 1'b1) && (bus_sample === 1'b0)) begin
        lost_arbitration = 1'b1;
        // release immediately
        vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1;
      end
      arb_bit_idx++;
    end

    // Finish the bit time
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
      if (lost_arbitration) return;

      last_tx_bit = stuff_bit;
      same_cnt    = 1;
    end

    // Drive actual logical bit
    drive_raw_bit(lb);
    if (lost_arbitration) return;

    // Update run-length tracking
    if (lb == last_tx_bit) begin
      same_cnt++;
    end
    else begin
      last_tx_bit = lb;
      same_cnt    = 1;
    end
  endtask

  // ---------------- CRC ----------------
  function void crc15_update(bit b);
    bit msb;
    msb     = crc_reg[14] ^ b;
    crc_reg = {crc_reg[13:0], 1'b0};
    if (msb) crc_reg ^= CAN_CRC15_POLY;
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

  // ===========================================================================
  // IDLE / END-OF-FRAME HELPERS
  // ===========================================================================

  task automatic wait_for_idle_bus();
    time start_t = $time;

    while (vif.rx_i !== 1'b1) begin
      if (($time - start_t) > (bit_time * 200))
        `uvm_fatal("CAN_DRV", "Timeout waiting for idle/recessive bus")
      @vif.can_cb;
    end

    repeat (`CAN_INTERMISSION_BITS) begin
      drive_raw_bit(1'b1);
    end
  endtask

  // Wait for 7 consecutive recessive bits on the resolved bus (EOF heuristic)
  task automatic wait_frame_end_after_loss();
    int unsigned recessive_cnt = 0;
    bit b;

    while (recessive_cnt < 7) begin
      @vif.can_cb;
      #(sp_offset);
      b = vif.rx_i;
      #(bit_time - sp_offset);

      if (b === 1'b1) recessive_cnt++;
      else            recessive_cnt = 0;
    end

    // release
    drive_tx(1'b1);
  endtask

  // ===========================================================================
  // ARBITRATION LOSS HANDLER  (*** THIS WAS MISSING IN YOUR FILE ***)
  // ===========================================================================
  task automatic handle_arbitration_loss(ref can_transaction tr_in);

    // THIS NODE IS NO LONGER A TRANSMITTER
    c_cfg.is_tx_in_progress = 1'b0;
  
    tr_in.arb_lost = 1'b1;
    if (arb_bit_idx == 0) tr_in.arb_lost_bit = 0;
    else                  tr_in.arb_lost_bit = arb_bit_idx - 1;
  
    drive_tx(1'b1);
  
    in_arbitration = 1'b0;
    stuff_en       = 1'b0;
    crc_en         = 1'b0;
  
    `uvm_info("CAN_ARB",
      $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h) -> released bus",
                c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
      UVM_LOW);
  
    wait_frame_end_after_loss();
  endtask

  // ===========================================================================
  // FRAME TRANSMIT (ARBITRATION SUPPORTED)
  // ===========================================================================
  task automatic send_frame(can_transaction tr_in);
    
    
    int unsigned dlc_clamped;
    int unsigned nbytes;
    c_cfg.is_tx_in_progress = 1'b1;
    dlc_clamped = (tr_in.dlc > 8) ? 8 : tr_in.dlc;
    nbytes      = (tr_in.data.size() < dlc_clamped) ? tr_in.data.size() : dlc_clamped;

    // reset per frame attempt
    in_arbitration   = 1'b0;
    lost_arbitration = 1'b0;
    arb_bit_idx      = 0;

    wait_for_idle_bus();

    // ---------------- SOF (dominant 0, not stuffed)
    stuff_en = 1'b0;
    drive_raw_bit(1'b0);
    init_stuffing(1'b0);

    crc_start();
    crc15_update(1'b0);

    stuff_en = 1'b1;

    // ---------------- ARBITRATION FIELD
    in_arbitration = 1'b1;

    if (tr_in.can_fmt == `CAN_ID_STD) begin
      for (int i = 10; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
      end

      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0); // RTR
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end

      drive_frame_bit(1'b0); // IDE=0
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
    end
    else begin
      for (int i = 28; i >= 18; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
      end

      drive_frame_bit(1'b1); // SRR
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end

      drive_frame_bit(1'b1); // IDE=1
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end

      for (int i = 17; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
      end

      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0); // RTR
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
    end

    in_arbitration = 1'b0;

    // ---------------- CONTROL
    drive_frame_bit(1'b0); // r0
    for (int i = 3; i >= 0; i--) drive_frame_bit(dlc_clamped[i]);

    // ---------------- DATA
    if (tr_in.f_type == `CAN_DATA_FRAME) begin
      for (int bi = 0; bi < nbytes; bi++) begin
        for (int b = 7; b >= 0; b--) begin
          drive_frame_bit(tr_in.data[bi][b]);
        end
      end
    end

    // ---------------- CRC + delimiter
    crc_stop();
    for (int i = 14; i >= 0; i--) drive_frame_bit(crc_reg[i]);

    stuff_en = 1'b0;
    drive_raw_bit(1'b1); // CRC delimiter

    // ---------------- ACK slot + delimiter (TX releases)
    drive_raw_bit(1'b1);
    drive_raw_bit(1'b1);

    // ---------------- EOF
    repeat (7) drive_raw_bit(1'b1);

    // release idle
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

  endtask

endclass : can_driver

`endif // CAN_DRIVER_SV
