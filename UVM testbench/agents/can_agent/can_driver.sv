`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// If you compile via can_pkg.sv with correct order, prefer: import can_pkg::*; and remove includes below.
// Keeping them here only if you compile this file standalone.
//`include "can_defines.sv"
//`include "can_transaction.sv"
//`include "can_agent_config.sv"

//--------------------------------------------------------------------------------------------------
// can_driver (Phase-A ready)
// - Drives node transmit intent via vif.can_cb.tb_tx[node_id]
// - Does NOT drive vif.rx_i (bus model drives rx_i)
// - Adds idle-bus timeout to avoid infinite hang
// - Clamps DLC/bytes to classic CAN max (8)
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

  // CRC (kept as-is for now)
  bit        crc_en;
  bit [14:0] crc_reg;
  localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;
  
   //Arbitrationn Flags 
  bit in_arbitration;
  bit lost_arbitration;

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

    `uvm_info("CAN_DRV",
              $sformatf("Driver ready: node_id=%0d bit_time=%0t sp_offset=%0t (%0d%%)",
                        c_cfg.node_id, bit_time, sp_offset, c_cfg.sample_point_pct),
              UVM_LOW);
  endfunction

  task run_phase(uvm_phase phase);
    can_transaction tr_local;

    // Release bus (recessive) by default
    drive_tx(1'b1);

    forever begin
      seq_item_port.get_next_item(tr_local);

      tr_local.t_start = $time;
      send_frame(tr_local);
      tr_local.t_end   = $time;

      // Optional: publish what we drove (expected stream)
      ap.write(tr_local);

      seq_item_port.item_done();
    end
  endtask

  // ===============================================================================================
  // BUS DRIVER PRIMITIVES
  // ===============================================================================================

  // Drive THIS NODE'S tx intent into the TB bus model.
  // 1 = recessive (release), 0 = dominant (drive)
  task automatic drive_tx(bit level);
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= level;
  endtask

  // Drive one physical bit time (raw, no stuffing logic here)
  task automatic drive_raw_bit(bit level);
    drive_tx(level);
    #(bit_time);
  endtask

  function void init_stuffing(bit first_bit);
    last_tx_bit = first_bit;
    same_cnt    = 1;
  endfunction

  task automatic drive_logical_bit(bit lb);

    // Insert stuff bit if 5 identical logical bits already sent
    if (stuff_en && (same_cnt == 5)) begin
      bit stuff_bit = ~last_tx_bit;
      drive_raw_bit(stuff_bit);

      last_tx_bit = stuff_bit;
      same_cnt    = 1;
    end

    // Drive the actual logical bit
    drive_raw_bit(lb);

    // Update run-length tracking
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

  // Wait for idle recessive for at least intermission bits, with timeout protection
  task automatic wait_for_idle_bus();
    time start_t = $time;

    // Wait until resolved bus is recessive (idle)
    while (vif.rx_i !== 1'b1) begin
      if (($time - start_t) > (bit_time * 200)) begin
        `uvm_fatal("CAN_DRV", "Timeout waiting for bus to become idle/recessive (rx_i stuck non-1)")
      end
      #(bit_time);
    end

    // Enforce intermission bits (typically 3 recessive bits)
    repeat (`CAN_INTERMISSION_BITS) drive_raw_bit(1'b1);
  endtask

  // ===============================================================================================
  // FRAME TRANSMIT (SOF -> EOF)
  // ===============================================================================================
  task automatic send_frame(can_transaction tr_in);

    // Clamp classic CAN payload rules (Phase A)
    int unsigned dlc_clamped;
    int unsigned nbytes;

    dlc_clamped = (tr_in.dlc > 8) ? 8 : tr_in.dlc;
    nbytes      = (tr_in.data.size() < dlc_clamped) ? tr_in.data.size() : dlc_clamped;

    wait_for_idle_bus();

    // ---------------- SOF (dominant 0, not stuffed)
    stuff_en = 1'b0;
    drive_raw_bit(1'b0);

    init_stuffing(1'b0);

    // Start CRC and include SOF as first bit (as you intended)
    crc_start();
    crc15_update(1'b0);

    // Enable bit stuffing up to end of CRC sequence
    stuff_en = 1'b1;

    // ---------------- ARBITRATION FIELD
    if (tr_in.can_fmt == `CAN_ID_STD) begin
      for (int i = 10; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
      end
      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0); // RTR
      drive_frame_bit(1'b0); // IDE=0
    end
    else begin
      for (int i = 28; i >= 18; i--) begin
        drive_frame_bit(tr_in.id[i]);
      end
      drive_frame_bit(1'b1); // SRR=1
      drive_frame_bit(1'b1); // IDE=1
      for (int i = 17; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
      end
      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0); // RTR
    end

    // ---------------- CONTROL FIELD (classic CAN)
    drive_frame_bit(1'b0); // r0
    for (int i = 3; i >= 0; i--) begin
      drive_frame_bit(dlc_clamped[i]); // use clamped DLC on the wire
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

    stuff_en = 1'b0;      // disable stuffing after CRC sequence
    drive_raw_bit(1'b1);  // CRC delimiter

    // ---------------- ACK SLOT + ACK DELIMITER
    drive_raw_bit(1'b1);  // ACK slot (TX releases)
    drive_raw_bit(1'b1);  // ACK delimiter

    // ---------------- EOF (7 recessive bits)
    repeat (7) drive_raw_bit(1'b1);

    // Release to recessive idle
    drive_tx(1'b1);

    `uvm_info("CAN_DRV",
              $sformatf("Sent frame: fmt=%s id=0x%0h type=%0d dlc=%0d (clamped=%0d) bytes_sent=%0d",
                        (tr_in.can_fmt==`CAN_ID_STD) ? "STD" : "EXT",
                        tr_in.id, tr_in.f_type, tr_in.dlc, dlc_clamped, nbytes),
              UVM_LOW);
  endtask

endclass : can_driver

`endif // CAN_DRIVER_SV
