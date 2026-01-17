`ifndef CAN_TRANSACTION_SV
`define CAN_TRANSACTION_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class can_transaction extends uvm_sequence_item;

  // -------- Logical Frame Fields---------------
  rand bit         can_fmt;   // `CAN_ID_STD or `CAN_ID_EXT
  rand bit [28:0]  id;        // valid bits depend on can_fmt
  rand bit [3:0]   dlc;       // Classic CAN: 0..8
  rand bit         f_type;    // DATA/REMOTE (others later)
  rand byte unsigned data[];  // payload

  // ---------- Error injection knobs (driver may implement physically) ---
  rand bit inj_crc_error;
  rand bit inj_stuff_error;
  rand bit inj_form_error;
  rand bit inj_ack_error;

  // ------- Observability / debug (monitor can fill these) --------------
  time        t_start;
  time        t_end;
  bit [14:0]  crc_obs;

  // ------- Automation / Printing --------------------------------------
  `uvm_object_utils_begin(can_transaction)
    `uvm_field_int(can_fmt,       UVM_DEFAULT)
    `uvm_field_int(id,            UVM_DEFAULT | UVM_HEX)
    `uvm_field_int(dlc,           UVM_DEFAULT)
    `uvm_field_int(f_type,        UVM_DEFAULT)
    `uvm_field_array_int(data,    UVM_DEFAULT)

    // Keep these out of pack/compare by default
    `uvm_field_int(inj_crc_error,   UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(inj_stuff_error, UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(inj_form_error,  UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
    `uvm_field_int(inj_ack_error,   UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)

    `uvm_field_int(crc_obs,        UVM_DEFAULT | UVM_NOPACK)
  `uvm_object_utils_end

  // ---------- CONSTRAINTS ---------------------------------------------
  constraint c_id_std_range {
    (can_fmt == `CAN_ID_STD) -> (id[28:11] == '0);
  }

  constraint c_dlc_legal {
    dlc inside {[0:8]};
  }

  constraint c_payload_vs_type {
    (f_type == `CAN_DATA_FRAME)  -> (data.size() == dlc);
    (f_type != `CAN_DATA_FRAME)  -> (data.size() == 0);
  }

  // NOTE: ERROR/OVERLOAD not driven yet; keep for future but don't randomize in smoke tests
  constraint c_error_overload_sanity {
    (f_type inside {`CAN_ERROR_FRAME, `CAN_OVERLOAD_FRAME}) ->
      (dlc == 0 && can_fmt == `CAN_ID_STD && id == '0);
  }

  // -------- Constructor -----------------------------------------------
  function new(string name = "can_transaction");
    super.new(name);
  endfunction

  // -------- Helpers ----------------------------------------------------
  function bit is_std();      return (can_fmt == `CAN_ID_STD); endfunction
  function bit is_ext();      return (can_fmt == `CAN_ID_EXT); endfunction
  function bit is_data();     return (f_type  == `CAN_DATA_FRAME); endfunction
  function bit is_remote();   return (f_type  == `CAN_REMOTE_FRAME); endfunction
  function bit is_error();    return (f_type  == `CAN_ERROR_FRAME); endfunction
  function bit is_overload(); return (f_type  == `CAN_OVERLOAD_FRAME); endfunction

  // Set payload explicitly (also update dlc + force DATA frame)
  function void set_payload(const ref byte unsigned nbyte[$]);
    int n = nbyte.size();
    if (n > 8) n = 8;

    data = new[n];
    foreach (data[i]) data[i] = nbyte[i];

    dlc    = n[3:0];
    f_type = `CAN_DATA_FRAME;
  endfunction

  function string convert2string();
    string fmt_s  = is_std() ? "STD" : "EXT";
    string type_s;

    case (f_type)
      `CAN_DATA_FRAME:     type_s = "DATA";
      `CAN_REMOTE_FRAME:   type_s = "REMOTE";
      `CAN_ERROR_FRAME:    type_s = "ERROR";
      `CAN_OVERLOAD_FRAME: type_s = "OVERLOAD";
      default:             type_s = "UNKNOWN";
    endcase

    return $sformatf("CAN[%s %s] id=0x%0h dlc=%0d bytes=%0d",
                     fmt_s, type_s, id, dlc, data.size());
  endfunction

  function void do_print(uvm_printer printer);
    string ft;
    super.do_print(printer);

    
    case (f_type)
      `CAN_DATA_FRAME:     ft = "DATA";
      `CAN_REMOTE_FRAME:   ft = "REMOTE";
      `CAN_ERROR_FRAME:    ft = "ERROR";
      `CAN_OVERLOAD_FRAME: ft = "OVERLOAD";
      default:             ft = "UNKNOWN";
    endcase

    printer.print_string("frame_type", ft);
    printer.print_int("payload_bytes", data.size(), UVM_DEC);

    printer.print_field("inj_crc_error",   inj_crc_error,   1, UVM_BIN);
    printer.print_field("inj_stuff_error", inj_stuff_error, 1, UVM_BIN);
    printer.print_field("inj_form_error",  inj_form_error,  1, UVM_BIN);
    printer.print_field("inj_ack_error",   inj_ack_error,   1, UVM_BIN);

    printer.print_time("t_start", t_start);
    printer.print_time("t_end",   t_end);
    printer.print_field("crc_obs", crc_obs, 15, UVM_HEX);
  endfunction

endclass

`endif // CAN_TRANSACTION_SV
