`include "uvm_macros.svh"
import uvm_pkg::*;

class can_transactions extends uvm_sequence_item;

`uvm_object_utils(can_transactions)

//--HEADER Fields--
rand bit can_fmt; // `CAN_ID_STD or `CAN_ID_EXT
rand logic [28:0] id; // constrain to 11 bit is standard can_fmt
rand logic [3:0] dlc; // 4 bit DLC to decide the data bytes 
rand logic [1:0] f_type; // decides frame type DATA,ERROR,OVERLOAD or REMOTE

//-- PAYLOAD--
rand byte data[]; // its a dynamic . and set it as data = new[dlc] in randomize()

// -- error injection knobs --
rand bit inj_crc_error,
rand bit inj_stuff_err,
rand bit inj_form_err,
rand bit inj_ack_err;

//monitor observability --
time t_start, t_end
logic [14:0] crc_obs;

// --Factory / automation --
`uvm_object_utils_begin(can_transactions)

`uvm_field_int (can_fmt, UVM_DEFAULT)
`uvm_field_int (id, UVM_DEFAULT | UVM_BIN)
`uvm_field_int (dlc, UVM_DEFAULT)
`uvm_field_int (f_type, UVM_DEFAULT)
`uvm_field_array_int (data, UVM_DEFAULT)
`uvm_field_int (inj_crc_error, UVM_DEFAULT | UVM_NOPACK)
`uvm_field_int (inj_stuff_err, UVM_DEFAULT | UVM_NOPACK)
`uvm_field_int (inj_form_err,  UVM_DEFAULT | UVM_NOPACK)
`uvm_field_int (inj_ack_err,   UVM_DEFAULT | UVM_NOPACK)
`uvm_field_int (crc_obs,       UVM_DEFAULT | UVM_NOPACK)

`uvm_object_utils_end

// -- CONSTRAINTS --
// If STD, zero upper bits beyonfd 11
constraint c_id_std_range { (can_fmt == `CAN_ID_STD) -> id[28:11] == `0;}

// DLC legal for Classic CAN 
constraint c_dlc_legal { dlc inside {[0:8]};}

// NON-Data frames carry no payloads 
constraints c_payload_vs_type {(  f_type == `CAN_REMOTE_FRAME || f_type == `CAN_OVERLOAD_FRAME || f_type == `CAN_ERROR_FRAME) -> data.size() == 0;}

// -- METHODS--

function new ( string name = "can_transactions");
super.new(name);
endfunction 

// Post_randomize sizing for DATA frames 
function void Post_randomize();
if(f_type = `CAN_DATA_FRAME) 
	begin 
	data = new[dlc];
	end 
endfunction 

// Helpers 
// Purpose: store the payload bytes and update DLC accordingly
function void set_payload(byte unsigned bytes[$]);
  
  // 1) Create a data array with the same size as input
  data = new[bytes.size()];

  // 2) Copy each byte from the input array to our data array
  foreach (bytes[i])
    data[i] = bytes[i];

  // 3) Update DLC (data length code)
  //    DLC = number of data bytes, limited to 8 (since classic CAN max 8)
  if (bytes.size() > 8)
    dlc = 8;
  else
    dlc = bytes.size();

  // 4) This is a DATA frame (not remote/error)
  ftype = `CAN_DATA_FRAME;

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

// print 
function void do_print(uvm_printer printer);
super.do_print(printer);
p.print_string("can_fmt" , is_std() ? "STD(11)" : "EXT(29)");
p.print_field_int("id"   , id, 28, UVM_HEX);
p.print_field_int("dlc"  ,dlc, 4, UVM_DEC);

string ft;

case(f_type)
	`CAN_DATA_FRAME     :  ft = "DATA";
	`CAN_ERROR_FRAME    :  ft = "ERROR";
	`CAN_OVERLOAD_FRAME :  ft = "OVERLOAD";
	`CAN_REMOTE_FRAME   :  ft = "REMOTE";
	default             :  ft = "ERROR";
endcase

p.print_string("Frame_type", ft);
p.print_int("payload_bytes", data.size(), UVM_DEC);

endfunction 

endclass
