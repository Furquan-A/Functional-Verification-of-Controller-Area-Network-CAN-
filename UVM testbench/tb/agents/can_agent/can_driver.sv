`ifndef CAN_DRIVER_SV
`define CAN_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_driver extends uvm_driver #(can_transaction);
  `uvm_component_utils(can_driver)

  uvm_analysis_port #(can_transaction) ap;

  can_agent_config c_cfg;
  virtual can_if   vif;

  time bit_time;
  time sp_offset;

  int unsigned max_retries = 5;

  // stuffing
  bit          stuff_en;
  bit          last_tx_bit;
  int unsigned same_cnt;

  // injection helper
  bit stuff_skip_once;

  // retry bookkeeping
  int unsigned attempt_ctr;

  // arbitration
  bit          in_arbitration;
  bit          lost_arbitration;
  int unsigned arb_bit_idx;

  // CRC
  bit        crc_en;
  bit [14:0] crc_reg;
  localparam bit [14:0] CAN_CRC15_POLY = 15'h4599;

  function new(string name="can_driver", uvm_component parent=null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_DRV", "cannot get can_agent_config (key='m_cfg')")

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_DRV", "Virtual can_if not found (key='vif')")

    void'(uvm_config_db#(int unsigned)::get(this, "", "max_retries", max_retries));
    if (max_retries == 0) max_retries = 5;

    bit_time  = c_cfg.bit_time_ns * 1ns;
    sp_offset = (c_cfg.bit_time_ns * c_cfg.sample_point_pct * 1ns) / 100;
    if (sp_offset >= bit_time)
      `uvm_fatal("CAN_DRV", "Invalid sample_point_pct (sp_offset >= bit_time)")

    `uvm_info("CAN_DRV",
      $sformatf("Driver ready: node_id=%0d bit_time=%0t sp_offset=%0t (%0d%%) max_retries=%0d",
                c_cfg.node_id, bit_time, sp_offset, c_cfg.sample_point_pct, max_retries),
      UVM_LOW);
  endfunction

  task run_phase(uvm_phase phase);
    can_transaction tr_local;
    bit success;
  
    drive_tx(1'b1);
  
    forever begin
      seq_item_port.get_next_item(tr_local);
        `uvm_info("CAN_DRV",$sformatf("[node%0d] DRV got item type=%s (ftype=%0d) id=0x%0h dlc=%0d",
            c_cfg.node_id, tr_local.ftype_str(), tr_local.f_type,
            tr_local.id, tr_local.dlc), UVM_LOW);

  
      tr_local.t_start  = $time;
      tr_local.src_node = c_cfg.node_id;
  
      // ---------------- SPECIAL FRAMES ----------------
      if ((tr_local.f_type == `CAN_ERROR_FRAME) || (tr_local.f_type == `CAN_OVERLOAD_FRAME)) begin
        
        c_cfg.last_special_valid = 1'b1;
        c_cfg.last_special_ftype = tr_local.f_type;
        
        c_cfg.is_tx_in_progress = 1'b1;
        
       // allow forcing mid-frame special transmission 
       if(tr_local.force_midframe) 
         send_special_flag_frame_now(tr_local.f_type); // no idle wait
       else
         send_special_flag_frame(tr_local.f_type); // exixting behavior
        
        c_cfg.is_tx_in_progress = 1'b0;

        tr_local.ack_seen = 1'b0;
        tr_local.t_end    = $time;
        
        // IMPORTANT: do NOT send to scoreboard expected queue unless you updated SB for specials
        // ap.write(tr_local);  // <-- leave OFF for now
        seq_item_port.item_done();
        continue;
      end
  
     // ---------------- NORMAL DATA/REMOTE PATH ----------------
      success = 0;
      
      for (int unsigned attempt = 0; attempt <= max_retries; attempt++) begin
        tr_local.arb_lost     = 1'b0;
        tr_local.arb_lost_bit = 0;
        tr_local.ack_seen     = 1'b0;
      
        if (attempt > 0) begin
          tr_local.inj_crc_error   = 1'b0;
          tr_local.inj_form_error  = 1'b0;
          tr_local.inj_stuff_error = 1'b0;
          tr_local.inj_ack_error   = 1'b0;
        end
      
        attempt_ctr++;
        tr_local.tx_attempt = attempt_ctr;
      
        c_cfg.is_tx_in_progress = 1'b1;
        send_frame(tr_local);
        c_cfg.is_tx_in_progress = 1'b0;
      
        // ------------------------------------------------------------
        // Arbitration loss is NOT a failure. Do not retry here.
        // Let the sequence/test schedule the next "round".
        // Also, stopping retries keeps this node in RX so it can ACK winner.
        // ------------------------------------------------------------
        if (tr_local.arb_lost) begin
          `uvm_info("CAN_ARB",
            $sformatf("node%0d item done due to ARB-LOSS (id=0x%0h) at bit=%0d",
                      c_cfg.node_id, tr_local.id, tr_local.arb_lost_bit),
            UVM_LOW);
          success = 0;
          break;
        end
      
        // Winner success: saw ACK
        if (tr_local.ack_seen) begin
          success = 1;
          break;
        end
      
        // Otherwise: NO-ACK -> retry
        `uvm_info("CAN_ARB",
          $sformatf("node%0d retrying due to NO-ACK (id=0x%0h) attempt %0d/%0d",
                    c_cfg.node_id, tr_local.id, attempt+1, max_retries),
          UVM_LOW);
      end
      
      // Only report failure for NO-ACK cases (not for ARB-LOSS)
      if (!success && !tr_local.arb_lost) begin
        `uvm_info("CAN_ARB",
          $sformatf("node%0d failed after %0d retries (NO-ACK) (id=0x%0h)",
                    c_cfg.node_id, max_retries, tr_local.id),UVM_LOW)
      end
      
      tr_local.t_end = $time;
      
      // Publish only if winner success
      if (success) ap.write(tr_local);
      
      seq_item_port.item_done();
    end
  endtask
  
  
  
    // ===========================================================================
    // primitives
    // ===========================================================================
    task automatic drive_tx(bit level);
      @vif.can_cb;
      vif.can_cb.tb_tx[c_cfg.node_id] <= level;
    endtask
  
    task automatic drive_raw_bit(bit level);
      bit bus_sample;
  
      @vif.can_cb;
      vif.can_cb.tb_tx[c_cfg.node_id] <= level;
  
      #(sp_offset);
      bus_sample = vif.rx_i;
  
      if (in_arbitration && !lost_arbitration) begin
        if ((level === 1'b1) && (bus_sample === 1'b0)) begin
          lost_arbitration = 1'b1;
          vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1; // release
        end
        arb_bit_idx++;
      end
  
      #(bit_time - sp_offset);
    endtask

  function void init_stuffing(bit first_bit);
    last_tx_bit = first_bit;
    same_cnt    = 1;
  endfunction

  task automatic drive_logical_bit(bit lb);

    if (stuff_en && (same_cnt == 5)) begin
      if (stuff_skip_once) begin
        stuff_skip_once = 0;
        `uvm_info("CAN_INJ",
          $sformatf("node%0d injected STUFF error (skipped stuff bit)", c_cfg.node_id),
          UVM_LOW);
      end
      else begin
        bit stuff_bit = ~last_tx_bit;
        drive_raw_bit(stuff_bit);
        if (lost_arbitration) return;
        last_tx_bit = stuff_bit;
        same_cnt    = 1;
      end
    end

    drive_raw_bit(lb);
    if (lost_arbitration) return;

    if (lb == last_tx_bit) same_cnt++;
    else begin
      last_tx_bit = lb;
      same_cnt    = 1;
    end
  endtask

  // CRC
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
  // helpers
  // ===========================================================================
  task automatic wait_for_idle_bus();
    time start_t = $time;
    while (vif.rx_i !== 1'b1) begin
      if (($time - start_t) > (bit_time * 200))
        `uvm_fatal("CAN_DRV", "Timeout waiting for idle bus")
      @vif.can_cb;
    end
    repeat (`CAN_INTERMISSION_BITS) drive_raw_bit(1'b1);
  endtask

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

    drive_tx(1'b1);
  endtask

  task automatic handle_arbitration_loss(ref can_transaction tr_in);
    tr_in.arb_lost = 1'b1;
    tr_in.arb_lost_bit = arb_bit_idx ;

    // become receiver immediately
    c_cfg.is_tx_in_progress = 1'b0;

    drive_tx(1'b1);

    in_arbitration = 1'b0;
    stuff_en       = 1'b0;
    crc_en         = 1'b0;

    `uvm_info("CAN_ARB",
      $sformatf("[LOSS] node%0d lost at arb_bit=%0d id=0x%0h",
                c_cfg.node_id, tr_in.arb_lost_bit, tr_in.id),
      UVM_LOW);

    wait_frame_end_after_loss();
  endtask
  
  // ===========================================================================
  // send_frame with injection hooks + ACK sampling + EOF
  // ===========================================================================
  task automatic send_frame(can_transaction tr_in);

    int unsigned dlc_clamped;
    int unsigned nbytes;
    bit          ack_sample;
    bit          rtr_bit;
  
    // ------------------------------------------------------------
    // Guard: only DATA/REMOTE supported in send_frame()
    // ------------------------------------------------------------
    if ((tr_in.f_type != `CAN_DATA_FRAME) && (tr_in.f_type != `CAN_REMOTE_FRAME)) begin
      `uvm_info("CAN_DRV",
                $sformatf("send_frame() unsupported f_type=%0d (id=0x%0h). Only DATA/REMOTE supported by this                     encoder. ERROR/OVERLOAD must use a dedicated task.",
                          tr_in.f_type, tr_in.id),
                UVM_LOW)
      return;
    end

  
    // RTR bit mapping
    case (tr_in.f_type)
      `CAN_DATA_FRAME:   rtr_bit = 1'b0;
      `CAN_REMOTE_FRAME: rtr_bit = 1'b1;
      default:           rtr_bit = 1'b0; // unreachable due to guard
    endcase
  
    dlc_clamped = (tr_in.dlc > 8) ? 8 : tr_in.dlc;
    nbytes      = (tr_in.data.size() < dlc_clamped) ? tr_in.data.size() : dlc_clamped;
  
    // per attempt reset
    in_arbitration   = 1'b0;
    lost_arbitration = 1'b0;
    arb_bit_idx      = 0;
  
    // stuffing injection: only on FIRST attempt if requested
    stuff_skip_once = (tr_in.inj_stuff_error && (tr_in.tx_attempt == 1));
  
    wait_for_idle_bus();
  
    // SOF (not stuffed)
    stuff_en = 1'b0;
    drive_raw_bit(1'b0);
    init_stuffing(1'b0);
  
    // CRC start (includes SOF in your model)
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
  
      // RTR (STD)
      drive_frame_bit(rtr_bit); // to decide the FRAME type , mapping is done above 
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
  
      // IDE=0
      drive_frame_bit(1'b0);
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
    end
    else begin
      for (int i = 28; i >= 18; i--) begin // ---------- EXTENDED FRAME
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
      end
  
      // SRR (always recessive in EXT)
      drive_frame_bit(1'b1);
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
  
      // IDE=1
      drive_frame_bit(1'b1);
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
  
      for (int i = 17; i >= 0; i--) begin
        drive_frame_bit(tr_in.id[i]);
        if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
      end
  
      // RTR (EXT)
      drive_frame_bit(rtr_bit);
      if (lost_arbitration) begin handle_arbitration_loss(tr_in); return; end
    end
  
    in_arbitration = 1'b0;
  
    // CONTROL
    
    if ((tr_in.can_fmt == `CAN_ID_EXT) && c_cfg.strict_ext_ctrl) begin
      drive_frame_bit(1'b0); // r1
    end
    drive_frame_bit(1'b0); // r0
    for (int i = 3; i >= 0; i--) drive_frame_bit(dlc_clamped[i]);

  
    // DATA (only for DATA frames)
    if (tr_in.f_type == `CAN_DATA_FRAME) begin
      for (int bi = 0; bi < nbytes; bi++) begin
        for (int b = 7; b >= 0; b--) drive_frame_bit(tr_in.data[bi][b]);
      end
    end
  
    `uvm_info("CAN_TX",
      $sformatf("TX attempt=%0d id=0x%0h inj_crc=%0b inj_form=%0b inj_stuff=%0b f_type=%0d",
                tr_in.tx_attempt, tr_in.id,
                tr_in.inj_crc_error, tr_in.inj_form_error, tr_in.inj_stuff_error, tr_in.f_type),
      UVM_LOW);
  
    // CRC field
    crc_stop();
  
    // CRC ERROR injection: flip one CRC bit before transmitting it
    if (tr_in.inj_crc_error) begin
      crc_reg[0] = ~crc_reg[0];
      tr_in.inj_crc_error = 1'b0; // consume so retries are clean
      `uvm_info("CAN_INJ",
        $sformatf("node%0d injected CRC error (flipped crc_reg[0])", c_cfg.node_id),
        UVM_LOW);
    end
  
    for (int i = 14; i >= 0; i--) drive_frame_bit(crc_reg[i]);
  
    // after CRC sequence, no stuffing on delimiter/ack/eof
    stuff_en = 1'b0;
  
    // CRC delimiter (FORM injection point)
    if (tr_in.inj_form_error) begin
      `uvm_info("CAN_INJ",
        $sformatf("node%0d injected FORM error (CRC delimiter dominant)", c_cfg.node_id),
        UVM_LOW);
      drive_raw_bit(1'b0);      // WRONG delimiter
      tr_in.inj_form_error = 0; // next retry becomes clean
    end
    else begin
      drive_raw_bit(1'b1); // correct delimiter
    end
  
    // ---------------- ACK SLOT + DELIMITER (TX releases + samples)
  
    // ACK SLOT: release and sample
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1; // release
    #(sp_offset);
    ack_sample = vif.rx_i;
    #(bit_time - sp_offset);
  
    tr_in.ack_seen = (ack_sample == 1'b0);
  
    // ACK DELIMITER: keep released for one bit
    @vif.can_cb;
    vif.can_cb.tb_tx[c_cfg.node_id] <= 1'b1;
    #(bit_time);
  
    // ---------------- EOF (7 recessive)
    repeat (7) drive_raw_bit(1'b1);
  
    // Release idle (safety)
    drive_tx(1'b1);
  
    `uvm_info("CAN_TX", $sformatf("[node%0d] TX %s id=0x%0h dlc=%0d attempt=%0d inj(CRC=%0b STUFF=%0b FORM=%0b ACK=%0b)",
            c_cfg.node_id, tr_in.ftype_str(), tr_in.id, dlc_clamped,
            tr_in.tx_attempt, tr_in.inj_crc_error, tr_in.inj_stuff_error,
            tr_in.inj_form_error, tr_in.inj_ack_error),
  UVM_LOW);

  endtask
  
 // ===================================================================
  // Special frames (minimal):
  // - Active flag = dominant (0), Passive = recessive (1)
  // - 6 flag bits, then 8 delimiter bits (recessive)
  // - then 3 intermission bits (recessive)
  // ===================================================================

  task automatic send_special_flag_frame(int unsigned ftype);

    wait_for_idle_bus();
  
    // Special flags are NOT stuffed, no CRC, no arbitration
    stuff_en        = 1'b0;
    crc_en          = 1'b0;
    in_arbitration  = 1'b0;
    lost_arbitration= 1'b0;
  
    // ACTIVE flag = 6 dominant bits
    repeat (6) drive_raw_bit(1'b0);
  
    // delimiter = 8 recessive bits
    repeat (8) drive_raw_bit(1'b1);
  
    // Intermission (3 recessive) helps monitors align
    repeat (`CAN_INTERMISSION_BITS) drive_raw_bit(1'b1);
  
    // release (idle)
    drive_tx(1'b1);
  
    `uvm_info("CAN_TX",$sformatf("[node%0d] TX SPECIAL type=%0d (6 dom + 8 delim + IFS)",
            c_cfg.node_id, ftype),UVM_LOW);  
  endtask
  
  // -------------------------------------------------------------------------------------
  
  task automatic send_special_flag_frame_now(int unsigned ftype);
  
    // start at next boundary and immediately drive the flag 
    @vif.can_cb;
    
    // 6 dominant bits ( active flag shape)
    repeat(6) drive_raw_bit(1'b0);
    
    // 8 Recessive Delimiter bits 
    repeat(8) drive_raw_bit(1'b1);
    
    //release + intermission 
    drive_raw_bit(1'b1);
    repeat(`CAN_INTERMISSION_BITS)drive_raw_bit(1'b1);
    
    `uvm_info("CAN_TX",
    $sformatf("node%0d FORCED mid-frame SPECIAL flag ftype=%0d", c_cfg.node_id, ftype),
    UVM_LOW);
  endtask

endclass : can_driver

`endif // CAN_DRIVER_SV
