`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

//--------------------------------------------------------------------------------------------------
// can_driver (Phase-B Arbitration, Option-2 CLEAN)
// - Drives this node via vif.can_cb.tb_tx[node_id]
// - Arbitration check ONLY during arbitration field (ID/SRR/IDE/RTR)
// - Loss condition: we drove 1 but sampled 0 at sample point
// - After loss: stop transmitting, release bus, wait for EOF (7 recessive bits) then return
// - Sets c_cfg.is_tx_in_progress for monitor ACK gating
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
  int unsigned arb_bit_idx; // counts arbitration bits only

  // CRC
  bit        crc_en;
  bit [14:0] crc_reg;
  localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;

  function new(string name="can_driver", uvm_component parent=null);
    super.new(name,parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_DRV", "cannot get can_agent_config (key='m_cfg')")

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_DRV", "cannot get virtual can_if (key='vif')")

    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;

    if (sp_offset >= bit_time)
      `uvm_fatal("CAN_DRV", "Invalid sample point: sp_offset >= bit_time")

    `uvm_info("CAN_DRV",
      $sformatf("Driver ready: node_id=%0d bit_time=%0t sp_offset=%0t (%0d%%)",
                c_cfg.node_id, bit_time, sp_offset, c_cfg.sample_point_pct),
      UVM_LOW);
  endfunction

  task run_phase(uvm_phase phase);
    can_transaction tr_local;

    // release bus by default
    drive_tx(1'b1);

    forever begin
      seq_item_port.get_next_item(tr_local);

      tr_local.t_start      = $time;
      tr_local.src_node     = c_cfg.node_id;
      tr_local.arb_lost     = 1'b0;
      tr_local.arb_lost_bit = 0;

      send_frame(tr_local);

      tr_local.t_end = $time;

      // publish attempted TX (SB can ignore if arb_lost==1)
      ap.write(tr_local);

      seq_item_port.item_done();
    end
  endtask

  // ===============================================================================================
  // Low-level bus drive
  // ===============================================================================================
  task automatic drive_tx(bit level);
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= level;
  endtask

  // Plain physical bit (no arbitration check)
  task automatic drive_raw_bit(bit level);
    drive_tx(level);
    #(bit_time);
  endtask

  // Arbitration bit: drive, sample at sample point, detect loss
  task automatic drive_arb_bit(bit level, can_transaction tr_in);
    bit bus_sample;

    drive_tx(level);

    #(sp_offset);
    bus_sample = vif.rx_i;

    // Loss: sent recessive but saw dominant
    if (!lost_arbitration && (level === 1'b1) && (bus_sample === 1'b0)) begin
      lost_arbitration      = 1'b1;
      tr_in.arb_lost        = 1'b1;
      tr_in.arb_lost_bit    = arb_bit_idx;
    end

    #(bit_time - sp_offset);

    arb_bit_idx++;
  endtask

  // ===============================================================================================
  // Bit stuffing
  // ===============================================================================================
  function void init_stuffing(bit first_bit);
    last_tx_bit = first_bit;
    same_cnt    = 1;
  endfunction

  task automatic drive_logical_bit(bit lb);
    // insert stuff bit if needed
    if (stuff_en && (same_cnt == 5)) begin
      bit stuff_bit = ~last_tx_bit;

      // During arbitration, stuffing is active too, but arbitration only *conceptually*
      // matters for ID/SRR/IDE/RTR bits. We'll keep stuffing via drive_raw_bit.
      drive_raw_bit(stuff_bit);

      last_tx_bit = stuff_bit;
      same_cnt    = 1;
    end

    drive_raw_bit(lb);

    if (lb == last_tx_bit) same_cnt++;
    else begin
      last_tx_bit = lb;
      same_cnt    = 1;
    end
  endtask

  // ===============================================================================================
  // CRC helpers
  // ===============================================================================================
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

  // ===============================================================================================
  // Idle / wait
  // ===============================================================================================
  task automatic wait_for_idle_bus();
    time start_t = $time;

    while (vif.rx_i !== 1'b1) begin
      if (($time - start_t) > (bit_time * 200))
        `uvm_fatal("CAN_DRV", "Timeout waiting for idle bus (rx_i stuck non-1)")
      #(bit_time);
    end

    repeat (`CAN_INTERMISSION_BITS) drive_raw_bit(1'b1);
  endtask

  // After losing arbitration, wait until EOF (7 consecutive recessive bits)
  task automatic wait_frame_end_after_loss();
    int unsigned recessive_cnt = 0;
    bit b;

    // We do not drive anymore
    drive_tx(1'b1);

    while (recessive_cnt < 7) begin
      #(sp_offset);
      b = vif.rx_i;
      #(bit_time - sp_offset);

      if (b === 1'b1) recessive_cnt++;
      else            recessive_cnt = 0;
    end

    drive_tx(1'b1);
  endtask

  // ===============================================================================================
  // FRAME TX with arbitration
  // ===============================================================================================
  task automatic send_frame(can_transaction tr_in);
    bit rtr;
    bit rtr_e ;
    int unsigned dlc_clamped;
    int unsigned nbytes;

    dlc_clamped = (tr_in.dlc > 8) ? 8 : tr_in.dlc;
    nbytes      = (tr_in.data.size() < dlc_clamped) ? tr_in.data.size() : dlc_clamped;

    // reset arbitration tracking per frame
    in_arbitration   = 1'b0;
    lost_arbitration = 1'b0;
    arb_bit_idx      = 0;

    // mark TX in progress (monitor will use this later for ACK gating)
    c_cfg.is_tx_in_progress = 1'b1;

    wait_for_idle_bus();

    // ---------------- SOF (dominant)
    stuff_en = 1'b0;
    drive_raw_bit(1'b0);

    init_stuffing(1'b0);
    crc_start();
    crc15_update(1'b0);
    stuff_en = 1'b1;

    // ---------------- ARBITRATION FIELD
    // Enable arbitration checking only if this node participates
    in_arbitration = c_cfg.arbitration_enable;
    if (in_arbitration) arb_bit_idx = 0;

    if (tr_in.can_fmt == `CAN_ID_STD) begin
      for (int i = 10; i >= 0; i--) begin
        if (in_arbitration) drive_arb_bit(tr_in.id[i], tr_in);
        else                drive_frame_bit(tr_in.id[i]);

        if (lost_arbitration) begin
          `uvm_info("CAN_ARB",
            $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                      c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
            UVM_LOW);
          c_cfg.is_tx_in_progress = 1'b0;
          wait_frame_end_after_loss();
          return;
        end
      end

      // RTR
      rtr = (tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0;
      if (in_arbitration) drive_arb_bit(rtr, tr_in);
      else                drive_frame_bit(rtr);

      if (lost_arbitration) begin
        `uvm_info("CAN_ARB",
          $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                    c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
          UVM_LOW);
        c_cfg.is_tx_in_progress = 1'b0;
        wait_frame_end_after_loss();
        return;
      end

      // IDE=0
      if (in_arbitration) drive_arb_bit(1'b0, tr_in);
      else                drive_frame_bit(1'b0);

      if (lost_arbitration) begin
        `uvm_info("CAN_ARB",
          $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                    c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
          UVM_LOW);
        c_cfg.is_tx_in_progress = 1'b0;
        wait_frame_end_after_loss();
        return;
      end

    end
    else begin
      // EXT: base[28:18], SRR=1, IDE=1, ext[17:0], RTR
      for (int i = 28; i >= 18; i--) begin
        if (in_arbitration) drive_arb_bit(tr_in.id[i], tr_in);
        else                drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin
          `uvm_info("CAN_ARB",
            $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                      c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
            UVM_LOW);
          c_cfg.is_tx_in_progress = 1'b0;
          wait_frame_end_after_loss();
          return;
        end
      end

      if (in_arbitration) drive_arb_bit(1'b1, tr_in); // SRR
      else                drive_frame_bit(1'b1);
      if (lost_arbitration) begin
        `uvm_info("CAN_ARB",
          $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                    c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
          UVM_LOW);
        c_cfg.is_tx_in_progress = 1'b0;
        wait_frame_end_after_loss();
        return;
      end

      if (in_arbitration) drive_arb_bit(1'b1, tr_in); // IDE
      else                drive_frame_bit(1'b1);
      if (lost_arbitration) begin
        `uvm_info("CAN_ARB",
          $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                    c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
          UVM_LOW);
        c_cfg.is_tx_in_progress = 1'b0;
        wait_frame_end_after_loss();
        return;
      end

      for (int i = 17; i >= 0; i--) begin
        if (in_arbitration) drive_arb_bit(tr_in.id[i], tr_in);
        else                drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin
          `uvm_info("CAN_ARB",
            $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                      c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
            UVM_LOW);
          c_cfg.is_tx_in_progress = 1'b0;
          wait_frame_end_after_loss();
          return;
        end
      end

      rtr_e = (tr_in.f_type == `CAN_REMOTE_FRAME) ? 1'b1 : 1'b0;
      if (in_arbitration) drive_arb_bit(rtr_e, tr_in);
      else                drive_frame_bit(rtr_e);
      if (lost_arbitration) begin
        `uvm_info("CAN_ARB",
          $sformatf("[LOSS] node%0d lost arbitration at arb_bit=%0d (id=0x%0h)",
                    c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
          UVM_LOW);
        c_cfg.is_tx_in_progress = 1'b0;
        wait_frame_end_after_loss();
        return;
      end
    end

    // Arbitration over now
    in_arbitration = 1'b0;

    // ---------------- CONTROL FIELD
    drive_frame_bit(1'b0); // r0
    for (int i = 3; i >= 0; i--) drive_frame_bit(dlc_clamped[i]);

    // ---------------- DATA
    if (tr_in.f_type == `CAN_DATA_FRAME) begin
      for (int bi = 0; bi < nbytes; bi++) begin
        for (int b = 7; b >= 0; b--) drive_frame_bit(tr_in.data[bi][b]);
      end
    end

    // ---------------- CRC + delimiter
    crc_stop();
    for (int i = 14; i >= 0; i--) drive_frame_bit(crc_reg[i]);

    stuff_en = 1'b0;
    drive_raw_bit(1'b1);  // CRC delimiter

    // ---------------- ACK slot + delimiter (TX releases)
    drive_raw_bit(1'b1);
    drive_raw_bit(1'b1);

    // ---------------- EOF
    repeat (7) drive_raw_bit(1'b1);

    drive_tx(1'b1);
    c_cfg.is_tx_in_progress = 1'b0;

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
