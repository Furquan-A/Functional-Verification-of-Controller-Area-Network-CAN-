`ifndef CAN_TRANSACTION_SV
`define CAN_TRANSACTION_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// -----------------------------------------------------------------------------
// Transaction now supports:
//  - DATA frame
//  - REMOTE frame
//  - ERROR frame
//  - OVERLOAD frame
//
// NOTE (important):
// Your driver/monitor currently compare against `CAN_DATA_FRAME / `CAN_REMOTE_FRAME.
// After this change, f_type is an enum (not a bit).
// Easiest compatibility fix: define these macros to match enum values:
//
//   `define CAN_DATA_FRAME      can_transaction::FT_DATA
//   `define CAN_REMOTE_FRAME    can_transaction::FT_REMOTE
//   `define CAN_ERROR_FRAME     can_transaction::FT_ERROR
//   `define CAN_OVERLOAD_FRAME  can_transaction::FT_OVERLOAD
//
// Put those defines in a common package/include (can_pkg.sv) BEFORE compiling
// driver/monitor/sequences.
// -----------------------------------------------------------------------------

class can_transaction extends uvm_sequence_item;

  
  // -------- Logical Frame Fields -------------
  rand bit             can_fmt;   // `CAN_ID_STD or `CAN_ID_EXT (only meaningful for DATA/REMOTE)
  rand bit [28:0]      id;        // valid bits depend on can_fmt (only meaningful for DATA/REMOTE)
  rand bit [3:0]       dlc;       // Classic CAN: 0..8 (only meaningful for DATA/REMOTE/REMOTE)
  rand logic[1:0] f_type;   // DATA/REMOTE/ERROR/OVERLOAD
  rand byte unsigned   data[];    // payload (DATA only)

  // ---------------- ERROR / OVERLOAD details ----------------
  // For ERROR and OVERLOAD frames, CAN transmits a flag then a delimiter.
  // At “transaction level” we keep simple knobs so you can:
  //  - generate Active vs Passive error flag (dominant vs recessive)
  //  - choose a reason (optional) for logging/coverage
  typedef enum int unsigned {
    ERR_NONE         = 0,
    ERR_CRC          = 1,
    ERR_STUFF        = 2,
    ERR_FORM         = 3,
    ERR_ACK          = 4,
    ERR_BIT0         = 5,
    ERR_BIT1         = 6,
    ERR_OTHER        = 7
  } can_error_reason_e;
  
  typedef enum int unsigned { 
    SPEC_CTX_NONE=0, 
    SPEC_CTX_MID_FRAME=1, 
    SPEC_CTX_INTERMISSION=2,
    SPEC_CTX_IDLE = 3
  } spec_ctx_e;
    
  spec_ctx_e special_ctx;

  


  rand bit              err_active;     // 1=Active Error Flag (dominant), 0=Passive (recessive)
  rand can_error_reason_e err_reason;   // Optional classification for error frame (coverage/logging)
  rand bit force_midframe; // =1 => driver sends special immediately ( no idle wait)

  // Overload frame “reason” is usually not modeled deeply; keep a knob anyway
  rand bit              ovl_active;     // 1=dominant overload flag (typical), 0=recessive (rare/useful for debu)

  // ---------- Error injection knobs -----------
  // (Used when you transmit a DATA/REMOTE frame and want to corrupt it)
  rand bit inj_crc_error;
  rand bit inj_stuff_error;
  rand bit inj_form_error;
  rand bit inj_ack_error;

  // ---------- Results/observability -----------
  time        t_start;
  time        t_end;
  bit [14:0]  crc_obs;

  int unsigned src_node;

  // Arbitration
  bit          arb_lost;
  int unsigned arb_lost_bit;

  // Retransmission attempt counter (per-node)
  int unsigned tx_attempt;

  // ACK bookkeeping (monitor fills these)
  // Keep your meaning consistent with your latest code:
  //   ack_seen = 1 means ACK was seen on bus (dominant 0)
  //   ack_seen = 0 means no ACK (recessive 1)
  bit ack_seen;
  bit ack_driven;

  // Error “seen” flags (monitor fills these)
  bit crc_error_seen;
  bit stuff_error_seen;
  bit form_error_seen;

  // -------------- UVM Automation --------------
  `uvm_object_utils_begin(can_transaction)
    `uvm_field_int(can_fmt,       UVM_DEFAULT)
    `uvm_field_int(id,            UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(dlc,           UVM_DEFAULT)
    `uvm_field_array_int(data,    UVM_DEFAULT)
    `uvm_field_int(f_type,           UVM_DEFAULT)

    `uvm_field_int(err_active,    UVM_DEFAULT)
    `uvm_field_enum(can_error_reason_e, err_reason, UVM_DEFAULT)
    `uvm_field_int(ovl_active,    UVM_DEFAULT)

    `uvm_field_int(inj_crc_error,    UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(inj_stuff_error,  UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(inj_form_error,   UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(inj_ack_error,    UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)

    `uvm_field_int(ack_seen,         UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(ack_driven,       UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)

    `uvm_field_int(crc_error_seen,   UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(stuff_error_seen, UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(form_error_seen,  UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)

    `uvm_field_int(crc_obs,          UVM_DEFAULT | UVM_NOPACK)
    `uvm_field_int(src_node,         UVM_DEFAULT | UVM_NOPACK)

    `uvm_field_int(arb_lost,         UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(arb_lost_bit,     UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(tx_attempt,       UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_enum(spec_ctx_e,special_ctx, UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(force_midframe,       UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
  `uvm_object_utils_end

  // ---------------- CONSTRAINTS ---------------
  // Standard ID: keep upper bits zero
  constraint c_id_std_range {
    (can_fmt == `CAN_ID_STD) -> (id[28:11] == '0);
  }

  constraint c_dlc_legal { dlc inside {[0:8]}; }

  // Payload rules
  constraint c_payload_vs_type {
    (f_type == `CAN_DATA_FRAME)   -> (data.size() == dlc);
    (f_type != `CAN_DATA_FRAME)   -> (data.size() == 0);
  }

  // Remote frames: dlc is legal, but no data
  // (already enforced by c_payload_vs_type)
  // For ERROR/OVERLOAD frames: dlc must be 0 and id/can_fmt are "don't care"
  constraint c_non_data_non_remote_fields {
    (f_type inside {`CAN_ERROR_FRAME, `CAN_OVERLOAD_FRAME}) -> (dlc == 0);
  }

  // If you explicitly send an ERROR or OVERLOAD frame, you generally do NOT
  // simultaneously request injection on it (injection is for DATA/REMOTE corruption).
  constraint c_injection_only_for_data_remote {
    (f_type inside {`CAN_ERROR_FRAME,`CAN_OVERLOAD_FRAME}) -> (
      inj_crc_error   == 0 &&
      inj_stuff_error == 0 &&
      inj_form_error  == 0 &&
      inj_ack_error   == 0
    );
  }

  // Default reasonable behavior for special frames
  constraint c_default_special_frame_knobs {
    (f_type == `CAN_ERROR_FRAME)    -> (err_active inside {0,1});
    (f_type == `CAN_OVERLOAD_FRAME) -> (ovl_active inside {0,1});
  }
  
  constraint c_force_midframe_only_special {
    (f_type inside {`CAN_DATA_FRAME,`CAN_REMOTE_FRAME}) -> (force_midframe ==0);}

  function new(string name = "can_transaction");
    super.new(name);
  endfunction

  // Pretty printing
  function string convert2string();
    string s;
    string fmt_s;
    string typ_s;

    fmt_s = (can_fmt==`CAN_ID_STD) ? "STD" : "EXT";
    
    case (f_type)
      `CAN_DATA_FRAME:     typ_s = "DATA";
      `CAN_REMOTE_FRAME:   typ_s = "REMOTE";
      `CAN_ERROR_FRAME:    typ_s = "ERROR";
      `CAN_OVERLOAD_FRAME: typ_s = "OVERLOAD";
      default:             typ_s = "UNK";
    endcase

    // For ERROR/OVERLOAD, id/dlc aren’t meaningful, but we still show them
    s = $sformatf("CAN[%s %s] id=0x%0h dlc=%0d bytes=%0d attempt=%0d",
                  fmt_s, typ_s, id, dlc, data.size(), tx_attempt);

    if (f_type == `CAN_ERROR_FRAME) begin
      s = {s, $sformatf(" err_active=%0b err_reason=%0d", err_active, err_reason)};
    end
    else if (f_type == `CAN_OVERLOAD_FRAME) begin
      s = {s, $sformatf(" ovl_active=%0b", ovl_active)};
    end

    if (data.size() > 0) begin
      s = {s, " data="};
      foreach (data[i]) s = {s, $sformatf("%02x ", data[i])};
    end

    // Observability flags (helpful in logs)
    s = {s,
         $sformatf(" | ack_seen=%0b ack_driven=%0b crc_err=%0b form=%0b stuff=%0b",
                   ack_seen, ack_driven, crc_error_seen, form_error_seen, stuff_error_seen)};

    return s;
  endfunction
  
  function string ftype_str();
    case (f_type)
      `CAN_DATA_FRAME:     return "DATA";
      `CAN_REMOTE_FRAME:   return "REMOTE";
      `CAN_ERROR_FRAME:    return "ERROR";
      `CAN_OVERLOAD_FRAME: return "OVERLOAD";
      default:             return $sformatf("UNK(%0d)", f_type);
    endcase
  endfunction

endclass : can_transaction

`endif // CAN_TRANSACTION_SV
