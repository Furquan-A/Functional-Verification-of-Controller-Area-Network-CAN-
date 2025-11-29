`include "uvm_macros.svh"
import uvm_pkg::*;

// Classic CAN only (STD 11-bit + EXT 29-bit), no CAN-FD
class can_transactions extends uvm_sequence_item;

  // ---------------- Factory ----------------
  `uvm_object_utils_begin(can_transactions)
    `uvm_field_int (can_fmt,        UVM_DEFAULT)
    `uvm_field_int (id,             UVM_DEFAULT | UVM_BIN)
    `uvm_field_int (dlc,            UVM_DEFAULT)
    `uvm_field_int (f_type,         UVM_DEFAULT)
    `uvm_field_array_int (data,     UVM_DEFAULT)
    `uvm_field_int (inj_crc_error,  UVM_DEFAULT | UVM_NOPACK)
    `uvm_field_int (inj_stuff_err,  UVM_DEFAULT | UVM_NOPACK)
    `uvm_field_int (inj_form_err,   UVM_DEFAULT | UVM_NOPACK)
    `uvm_field_int (inj_ack_err,    UVM_DEFAULT | UVM_NOPACK)
    `uvm_field_int (crc_obs,        UVM_DEFAULT | UVM_NOPACK)
  `uvm_object_utils_end

  // ---------------- Header fields ----------------
  rand bit            can_fmt;      // `CAN_ID_STD or `CAN_ID_EXT
  rand logic [28:0]   id;           // up to 29 bits (constrained below)
  rand logic [3:0]    dlc;          // 0..8 for classic CAN
  rand logic [1:0]    f_type;       // DATA/REMOTE/OVERLOAD/ERROR

  // ---------------- Payload ----------------
  rand byte unsigned  data[];       // sized in post_randomize / set_payload()

  // ---------------- Error-injection knobs ----------------
  rand bit inj_crc_error;
  rand bit inj_stuff_err;
  rand bit inj_form_err;
  rand bit inj_ack_err;

  // ---------------- Monitor-only observability ----------------
  time          t_start, t_end;
  logic [14:0]  crc_obs;

  // ---------------- Constraints ----------------
  // If standard ID, upper bits must be zero.
  constraint c_id_std_zeroes { (can_fmt == `CAN_ID_STD) -> (id[28:11] == '0); }

  // (Optional) Hard range guard so id is always within legal width
  constraint c_id_legal {
    (can_fmt == `CAN_ID_STD) -> (id < (1 << 11));
    (can_fmt == `CAN_ID_EXT) -> (id < (1 << 29));
  }

  // DLC legal for classic CAN
  constraint c_dlc_legal { dlc inside {[0:8]}; }

  // Non-data frames carry no payload
  constraint c_payload_vs_type {
    (f_type inside {`CAN_REMOTE_FRAME, `CAN_OVERLOAD_FRAME, `CAN_ERROR_FRAME}) -> data.size() == 0;
  }

  // For DATA frames, keep data.size consistent with dlc
  constraint c_data_size_matches_dlc {
    (f_type == `CAN_DATA_FRAME) -> data.size() == dlc;
  }

  // ---------------- Ctors ----------------
  function new(string name="can_transactions");
    super.new(name);
  endfunction

  // ---------------- Post-randomize fixups ----------------
  function void post_randomize();
    if (f_type == `CAN_DATA_FRAME) begin
      // Ensure array matches dlc (constraint already enforces, but safe)
      if (data.size() != dlc) data = new[dlc];
    end
    else begin
      // Non-data: clear payload & dlc
      if (data.size() != 0) data.delete();
      dlc = '0;
    end
  endfunction

  // ---------------- Helpers ----------------
  // Store payload bytes; clip to 8; mark as DATA frame
  function void set_payload(const ref byte unsigned bytes[$]);
    int unsigned n = (bytes.size() > 8) ? 8 : bytes.size();
    data = new[n];
    foreach (data[i]) data[i] = bytes[i];
    dlc   = n[3:0];
    f_type = `CAN_DATA_FRAME;
  endfunction

  function bit is_std();
	return (can_fmt == `CAN_ID_STD);
  endfunction
  
  
  function bit is_ext();      
	return (can_fmt == `CAN_ID_EXT);       
  endfunction
  
  function bit is_data();     
	return (f_type == `CAN_DATA_FRAME);    
  endfunction
  
  function bit is_remote();   
	return (f_type == `CAN_REMOTE_FRAME); 
  endfunction
  
  function bit is_err();      
	return (f_type == `CAN_ERROR_FRAME);   
  endfunction
  
  function bit is_overload(); 
	return (f_type == `CAN_OVERLOAD_FRAME);
  endfunction

  // ---------------- Pretty print ----------------
  function void do_print(uvm_printer p);
    super.do_print(p);
    p.print_string("can_fmt", is_std() ? "STD(11)" : "EXT(29)");
    p.print_field_int("id",   id, 29, UVM_HEX);
    p.print_field_int("dlc",  dlc, 4, UVM_DEC);

    string ft;
    case (f_type)
      `CAN_DATA_FRAME:     ft = "DATA";
      `CAN_ERROR_FRAME:    ft = "ERROR";
      `CAN_OVERLOAD_FRAME: ft = "OVERLOAD";
      `CAN_REMOTE_FRAME:   ft = "REMOTE";
      default:             ft = "UNKNOWN";
    endcase
    p.print_string("frame_type", ft);
    p.print_int("payload_bytes", data.size(), UVM_DEC);
  endfunction

endclass
