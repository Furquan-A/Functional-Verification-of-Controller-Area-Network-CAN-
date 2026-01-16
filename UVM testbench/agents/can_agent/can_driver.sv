`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

`include "can_defines.sv"
`include "can_transaction.sv"
`include "can_agent_config.sv"

//--------------------------------------------------------------------------------------------------
// can_driver
// - Updated to NOT drive vif.rx_i anymore
// - Drives node transmit intent via vif.can_cb.can_tx (TB-only signal you added in can_if)
//   where: 1 = recessive (release), 0 = dominant (drive)
// - Fixes: CRC enable bug, stuffing counter bug, DATA field bit bug, and a few typos.
//--------------------------------------------------------------------------------------------------
class can_driver extends uvm_driver #(can_transaction);
  `uvm_component_utils(can_driver)

  uvm_analysis_port #(can_transaction) ap;

  can_transaction  tr;
  can_agent_config c_cfg;

  virtual can_if vif;

  // Timing
  time bit_time;
  time sp_offset;

  // Bit stuffing bookkeeping (driver side)
  bit          stuff_en;
  bit          last_tx_bit;
  int unsigned same_cnt;

  // CRC
  bit        crc_en;
  bit [14:0] crc_reg;
  localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;

  // ------------------------------- Constructor --------------------------------
  function new(string name = "can_driver", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  // ------------------------------ build_phase ---------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_DRV", "cannot get CAN agent config from config_db (key='m_cfg')")

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_DRV", "Virtual can_if not found in config_db (key='vif')")

    // Cache timing
    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;

    `uvm_info("CAN_DRV",
              $sformatf("Driver ready: bit_time=%0t sp_offset=%0t (%0d%%)",
                        bit_time, sp_offset, c_cfg.sample_point_pct),
              UVM_LOW)
  endfunction

  // ------------------------------ run_phase -----------------------------------
  task run_phase(uvm_phase phase);
    can_transaction tr_local;

    // Default to recessive (release bus)
    drive_tx(1'b1);

    forever begin
      seq_item_port.get_next_item(tr_local);

      tr_local.t_start = $time;
      send_frame(tr_local);
      tr_local.t_end   = $time;

      // Optional: publish what we drove
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
    // You said you added can_tx to can_if; this assumes it is in can_cb as an output
    vif.can_cb.can_tx <= level;
  endtask

  // Drive one physical bit time (raw, no stuffing here)
  task automatic drive_raw_bit(bit level);
    // Drive intent immediately at bit start
    drive_tx(level);

    // Hold for a full bit time
    #(bit_time);
  endtask

  // Initialize stuffing counter at SOF (SOF itself not stuffed)
  function void init_stuffing(bit first_bit);
    last_tx_bit = first_bit;
    same_cnt    = 1;
  endfunction

  // Drive one logical bit with optional bit stuffing
  // Stuffing applies from Arbitration through CRC sequence (per your usage of stuff_en)
  task automatic drive_logical_bit(bit lb);

    // Insert stuff bit if we have already sent 5 identical bits
    if (stuff_en && (same_cnt == 5)) begin
      bit stuff_bit = ~last_tx_bit;
      drive_raw_bit(stuff_bit);

      // After transmitting stuff bit, it becomes the last bit and count resets
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
    if (crc_en) crc15_update(lb);   // FIXED: no stray semicolon
    drive_logical_bit(lb);
  endtask

  // ===============================================================================================
  // IDLE / BUS ACCESS
  // ===============================================================================================

  // Wait for idle recessive for at least intermission bits (simple)
  task automatic wait_for_idle_bus();
    // Wait until bus resolves recessive (idle)
    wait (vif.rx_i == 1'b1);

    // Enforce intermission bits (typically 3 recessive bits)
    repeat (`CAN_INTERMISSION_BITS) drive_raw_bit(1'b1);
  endtask

  // ===============================================================================================
  // FRAME TRANSMIT (SOF -> EOF)
  // ===============================================================================================
  task automatic send_frame(can_transaction tr_in);

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
      // 11-bit ID, MSB first: id[10:0]
      for (int i = 10; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
      end

      // RTR: 0=data frame, 1=remote frame
      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0);

      // IDE must be 0 for standard frame
      drive_frame_bit(1'b0);
    end
    else begin
      // Extended ID (29-bit): base id[28:18], SRR=1, IDE=1, ext id[17:0], RTR
      for (int i = 28; i >= 18; i--) begin
        drive_frame_bit(tr_in.id[i]);
      end

      // SRR=1 (recessive)
      drive_frame_bit(1'b1);

      // IDE=1
      drive_frame_bit(1'b1);

      // Extended ID lower 18 bits
      for (int i = 17; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
      end

      // RTR bit
      drive_frame_bit((tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0);
    end

    // ---------------- CONTROL FIELD (classic CAN)
    // r0 reserved bit = 0
    drive_frame_bit(1'b0);

    // DLC [3:0] MSB first
    for (int i = 3; i >= 0; i--) begin
      drive_frame_bit(tr_in.dlc[i]);
    end

    // ---------------- DATA FIELD
    if (tr_in.f_type == `CAN_DATA_FRAME) begin
      int nbytes = tr_in.data.size();
      if (nbytes > 8) nbytes = 8;

      for (int bi = 0; bi < nbytes; bi++) begin
        for (int b = 7; b >= 0; b--) begin
          drive_frame_bit(tr_in.data[bi][b]); // FIXED: use actual data byte
        end
      end
    end

    // ---------------- CRC SEQUENCE + CRC DELIMITER
    crc_stop();

    // Transmit CRC (MSB first)
    for (int i = 14; i >= 0; i--) begin
      drive_frame_bit(crc_reg[i]);
    end

    // Stuffing disabled after CRC sequence
    stuff_en = 1'b0;

    // CRC delimiter = recessive
    drive_raw_bit(1'b1);

    // ---------------- ACK SLOT + ACK DELIMITER
    // TX sends recessive in ACK slot. Receivers may drive dominant on real bus.
    drive_raw_bit(1'b1); // ACK slot
    drive_raw_bit(1'b1); // ACK delimiter

    // ---------------- EOF (7 recessive bits)
    repeat (7) drive_raw_bit(1'b1);

    // Release to recessive idle
    drive_tx(1'b1);

    `uvm_info("CAN_DRV",
              $sformatf("Sent frame: fmt=%s id=0x%0h type=%0d dlc=%0d bytes=%0d",
                        (tr_in.can_fmt==`CAN_ID_STD) ? "STD" : "EXT",
                        tr_in.id, tr_in.f_type, tr_in.dlc, tr_in.data.size()),
              UVM_LOW)
  endtask

endclass : can_driver

`endif // CAN_DRIVER_SV
