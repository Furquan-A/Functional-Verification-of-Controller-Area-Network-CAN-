/*
	They will:
	Build reg_txn objects
	Fill in addr / data
	Send them to the sequencer
	Cause the driver to actually control the DUT
	Until you write sequences, nothing gets programmed in the DUT, so the CAN controller can’t even transmit or receive.
	So yes — REG SEQUENCES are the correct next step.
*/
`ifndef REG_BASE_SEQ_SV
`define REG_BASE_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "can_defines.sv"

class reg_base_seq  extends uvm_sequence #(reg_transaction);
	
	`uvm_object_utils(reg_base_seq)
	
	
	reg_agent_config r_cfg;
	can_env_config env_cfg;
	
	
	reg_sequencer p_sequencer;
	
	
	virtual can_if vif;
	
	// ============================= new ========================================================

	function  new(string name = "reg_base_seq");
		super.new(name);
	endfunction 
	 
	// =================== pre_body ============================================================
	/* 	pre_body() runs before the sequence’s body(), 
		after the sequence is started, and after the sequencer 
		is assigned to the sequence.
	*/
	virtual task pre_body();
		if (!$cast(p_sequencer, m_sequencer))
		  `uvm_fatal("REG_BASE_SEQ", "Could not cast p_sequencer!")
	endtask
  
	// ====================== Helper : write a register =======================================
	
	task write_reg(bit [7:0] addr, bit [7:0] data);
		reg_transaction t;
		t = reg_transaction::type_id::create("t_write");
		t.kind  = REG_WRITE;
		t.addr = addr;
		t.wdata = data;
		
		// start the transaction on driver through the sequencer 
		start_item(t); // <-- sends the transaction t to the sequencer 
		finish_item(t);// <-- passes the finalized transaction to the driver 
		
		if(!t.success)
			begin 
				`uvm_error("REG_WRITE",$sformatf("Write to 0x%02h FAILED", addr));
			end 
	endtask 
 
	// ==================== Helper: Read a register ==========================================
	
	task read_reg(bit [7:0] addr, output bit [7:0] data);
		reg_transaction t
		t = reg_transaction::type_id::create("t_read");
		t.kind = REG_READ;
		t.addr = addr;
		
		start_item(t);
		finish_item(t);
		
		data = t.rdata;
		
		if (!t.success)
			`uvm_error("REG_READ", $sformatf("Read from 0x%02h FAILED!", addr));
	endtask
	
	
	// default empty mody overrides 
	
	virtual task body();
	// sequence does not own any hardaware resourses so no need of getting the  config 
		`uvm_warning("REG_BASE_SEQ", "Base sequence body() called — nothing to do.");
	 endtask
	
endclass : reg_base_seq

`endif

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// WRITE SEQUENCES 
//`include "can_defines.sv"
class reg_write_seq extends reg_base_seq;

	`uvm_object_utils(reg_write_seq)
	 
	// inputs to the sequence 
	randc bit [7:0] addr;
	randc bit [7:0] data;
	
	function new (string name = "reg_write_seq");
		super.new(name);
	endfunction 
	
	// The body uses the simple base class helpers 
	virtual task body();
		`uvm_info("REG_WRITE_SEQ",$sformatf("WRITE: addr = 0x%02h data = 0x%02",addr,data),UVM_MEDIUM);
		
		write_reg(addr,data);
	endtask 
	
endclass : reg_write_seq


// ====================================================================================================================================================================
// ====================================================================================================================================================================
// READ SEQUENCES 
class reg_read_seq extends reg_base_seq;
	`uvm_object_utils(reg_read_seq)
	
	// input argument
	randc bit[7:0] addr;
	
	// output of the read 
	 bit[7:0] data_out;
	
	function new(string name = "reg_write_seq");
		super.new(name);
	endfunction 
	
	virtual task body();
		`uvm_info("REG_READ_SEQ",$sformatf("READ data at addr = 0x%02h",addr),UVM_MEDIUM);
		
		read_reg(addr,data_out);
		
		`uvm_info("REG_READ_SEQ",  $sformatf("READ: addr=0x%02h -> data=0x%02h", addr, data_out), UVM_MEDIUM);
	endtask 
	
endclass : reg_read_seq


// ====================================================================================================================================================================
// ====================================================================================================================================================================
//  REG INIT SEQUENCE
// WHAT IT DOES ? 
// Pts DUT into RESET
// programs BTR0 and BTR1 ( bit timing )
// Sets Acceptance filter (BASIC or EXTENDED)
// Enable extended mode 
// Exits RESET mode and gets back to the normal mode 

`ifndef REG_INIT_SEQ_SV
`define REG_INIT_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
 
//`include "can_defines.sv"

class reg_init_seqs extends reg_base_seq; // Is essential for proper CAN Operation

	`uvm_object_utils(reg_init_seqs)
	
	// configuration fields ( can be randomized or assigned in TEST) ----
	rand bit use_extended_mode = 1'b1; // 0 = basic mode, 1 = extended mode 
	rand byte btr0_config; // packed BRP + SJW
	rand byte btr1_config; // packed TSEG1 + TSEG2 + Triple_samp
	rand byte acc_code0; // default acceptance code 
	rand byte acc_mask0; // default acceptance mask 
		
	function new(string name = "reg_init_seqs");
		super.new(name);
	endfunction
	
	// ---------------------------------------------------------------
	// Main initialization body()
	//----------------------------------------------------------------
	virtual task body();
		byte mode_reset;
		`uvm_info("REG_INIT_SEQ","Starting Can Controller initialization", UVM_MEDIUM);
		
		// ENTER RESET MODE 
		mode_reset = `CAN_MODE_RESET_M; // bit 0 = reset mode 
		write_reg(`CAN_MODE_REG,mode_reset);
		
		// PROGRAM BIT TIMING BTR0 and BTR1
		write_reg(`CAN_BUS_TIMING_0,btr0_config);
		write_reg(`CAN_BUS_TIMING_1,btr1_config);
		
		// PROGRAM ACCEPTANCE FILTER ( BASIC or EXTENDED)
		if(!use_extended_mode)
			begin 
				write_reg(`CAN_ACC_CODE0_BASIC,acc_code0);
				write_reg(`CAN_ACC_MASK0_BASIC,acc_mask0);
			end 
		else 
			begin 
				write_reg(`CAN_ACC_CODE0_EXT,acc_code0);
				write_reg(`CAN_ACC_MASK0_EXT,acc_mask0);
				// optonal: others to zero 
				write_reg(`CAN_ACC_CODE1_EXT, 8'h00); // 00 means any value can be passed 
				write_reg(`CAN_ACC_CODE2_EXT, 8'h00);
				write_reg(`CAN_ACC_CODE3_EXT, 8'h00);
				write_reg(`CAN_ACC_MASK1_EXT, 8'hFF); // FF means n value should be chaked and compared with the code 
				write_reg(`CAN_ACC_MASK2_EXT, 8'hFF);
				write_reg(`CAN_ACC_MASK3_EXT, 8'hFF);
			end
			
		// ENABLE EXTENDED MODE 
		if(use_extended_mode) 
			begin 
				/* Clock Divider (bit7 = extended_mode) must be written FIRST before any extended-mode
				registers can be programmed.It does NOT configure IRQs or filters; 
				it only switches the register map. 
				*/
				byte clkdiv = `CAN_CLKDIV_EXTENDED_M;
				write_reg(`CAN_CLOCK_DIVIDER,clkdiv);
				 `uvm_info("REG_INIT_SEQ", "Extended mode enabled", UVM_LOW);
			end 
			
		// EXIT RESET MODE -> Normal Operation 
		write_reg(`CAN_MODE_REG,8'h00); // clear reset bit 
		`uvm_info("REG_INIT_SEQ","CAN controller initialization COMPLETE",UVM_MEDIUM);
	endtask : body

endclass : reg_init_seqs

`endif
	
// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REG_LOAD_TX_BUFFER_SEQUENCE 

`ifndef REG_LOAD_TX_BUFFER_SEQUENCE_SV
`define REG_LOAD_TX_BUFFER_SEQUENCE_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "can_defines.sv"

class reg_load_tx_buffer_seq extends reg_base_seq;
	`uvm_object_utils(reg_load_tx_buffer_seq)
	
	rand bit can_fmt; // BASIC or EXTENDED 
	rand bit [28:0] can_id; // 11 bits for BASIC 29 bits for EXTENDED 
	rand bit [3:0] dlc; // data length 
	rand byte unsigned data[]; // ppayload array ( sixe == dlc)
	
	// extended mode flag 
	rand bit use_extended_mode = 0; // basic = 0 ,  extended = 1;
	
	function new (string name = " reg_load_tx_buffer_seq");
		super.new(name);
	endfunction 
	
	
	virtual task body();
		`uvm_info("REG_LOAD_TX_BUFFER_SEQUENCE",$sformatf("loading TX Buffer: ID = %0h DLC = %0d EXT = %0b",can_id,dlc,use_extended_mode),UVM_MEDIUM);
		
		// --------------- Validation -------------------
		if(dlc > 8)
			begin 
				`uvm_fatal("TXBUF_SEQ","DLC>8 is illigal for classic CAN !");
			end 
		if(data.size() != dlc) 
			begin 
				`uvm_fatal("TXBUF_SEQ","data[] size does not match the DLC ");
			end 
			
		// -------------------1. Write ID, Control fields into the TX buffer register -------------------
		// Your DUT uses TX_DATA0..TX_DATA9 (11-bit ID encoded in register bytes)
		// For standard CAN, ID is 11 bits → write into TX_DATA_0 and TX_DATA_1
		if(!use_extended_mode)
			begin 
			
				byte id_high = can_id[10:3];
				write_reg(`CAN_TX_DATA0_BASIC,id_high); // loading the upper bits of id into one data reg of 8 bits 
				write_reg(`CAN_TX_DATA0_BASIC+1,id_low | (can_fmt <<1)| 0); // it is basically can_id[2;0] + IDE + RTR
				
				
				// Now the DLC which has 4 bits 
				write_reg(`CAN_TX_DATA0_BASIC + 2, dlc);
				
				// Data bytes 
				foreach(data[i])
					begin 
						write_reg(`CAN_TX_DATA0_BASIC + 3 + i, data[i]);
					end 
			end 
		else // extended mode active 
			begin 
				// In EXT mode, your RTL maps TX_DATA0..TX_DATA12 at addresses 0x10..0x1C
				// write ID across Multiple bytes (29 bits)	
				write_reg(`CAN_TX_DATA0_EXT,can_id[28:21]);
				write_reg(`CAN_TX_DATA0_EXT+1,can_id[20:13]);
				write_reg(`CAN_TX_DATA0_EXT+2,can_id[12:5]);
				write_reg(`CAN_TX_DATA0_EXT+3,can_id[4:0],3'b000); // can_id[4:0] + padding after the frame  
				
				// DLC register 
				write_reg(`CAN_TX_DATA0_EXT+4,dlc);
				
				// DATA Bytes 
				foreach (data[i]) 
					begin
						write_reg(`CAN_TX_DATA0_EXT + 5 + i, data[i]);
					end
			end
		
		 `uvm_info("REG_LOAD_TX_BUF","TX buffer load complete.",UVM_MEDIUM);
	endtask : body
endclass 
`endif // REG_LOAD_TX_BUFFER_SEQUENCE_SV

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REG_TXREQ_SEQUENCE 
// here we are just using the txreq command as an action to be performed 
// We can use other commands like ABORT, OVERRUN based on the tests we are running 

`ifdef REG_TXREQ_SEQ_SV
`define REG_TXREQ_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "can_defines.sv"

class reg_txreq_seq extends reg_base_seq;
	`uvm_object_utils(reg_txreq_seq)
	
	function new(string name = "reg_txreq_seq");
		super.new(name);
	endfunction 
	
	virtual task body();
		`uvm_info("REG_TXREQ_SEQ","Issuing TXREQ command to CAN controller...",UVM_MEDIUM);
		
		// COMMAND register bit0 = TREQ ( CAN_CMD_TREQ_M)
		write_reg(`CAN_COMMAND_REG,`CAN_CMD_TXREQ_M);
		
		`uvm_info("REG_TXREQ_SEQ","TXREQ command sent successfully.", UVM_MEDIUM);
	endtask 
endclass: reg_txreq_seq
`endif

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REG_ABORT_TX_SEQ 

`ifndef REG_ABORT_TX_SEQ_SV
`define REG_ABORT_TX_SEQ_SV

//`include "uvm_macros.svh"
import uvm_pkg::*;

`include "can_defines.sv"

class reg_abort_tx_seq extends reg_base_seq;
	`uvm_object_utils(reg_abort_tx_seq)
	
	function new(string name = "reg_abort_tx_seq");
		super.new(name);
	endfunction 
	
	virtual task body();
		`uvm_info("REG_ABORT_TX_SEQ","Issuing ABORT_TX command to CAN controller...",UVM_MEDIUM);
		
		// COMMAND register bit0 = TREQ ( CAN_CMD_TREQ_M)
		write_reg(`CAN_COMMAND_REG,`CAN_CMD_ABORT_M);
		
		`uvm_info("REG_ABORT_TX_SEQ","ABORT_TX command sent successfully.", UVM_MEDIUM);
	endtask 
endclass : reg_abort_tx_seq
`endif
// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REG_RELEASE_RX_BUFFER_SEQ
// sequences/reg_release_rx_buffer_seq.sv

`ifndef REG_RELEASE_RX_BUFFER_SEQ_SV
`define REG_RELEASE_RX_BUFFER_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "can_defines.sv"

class reg_release_rx_buffer_seq extends reg_base_seq;
  `uvm_object_utils(reg_release_rx_buffer_seq)

  function new(string name="reg_release_rx_buffer_seq");
    super.new(name);
  endfunction

  // ---------------------- MAIN BODY ----------------------
  virtual task body();
    `uvm_info("REG_REL_RX_BUF_SEQ","Releasing RX buffer (COMMAND bit2)...", UVM_MEDIUM);

    // COMMAND bit2 = RELEASE_BUFFER
    write_reg(`CAN_COMMAND_REG, `CAN_CMD_REL_RX_M);

    `uvm_info("REG_REL_RX_BUF_SEQ","RX buffer released.", UVM_MEDIUM);
  endtask : body

endclass : reg_release_rx_buffer_seq

`endif // REG_RELEASE_RX_BUFFER_SEQ_SV

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// sequences/reg_clear_overrun_seq.sv

`ifndef REG_CLEAR_OVERRUN_SEQ_SV
`define REG_CLEAR_OVERRUN_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "can_defines.sv"

class reg_clear_overrun_seq extends reg_base_seq;
  `uvm_object_utils(reg_clear_overrun_seq)

  function new(string name="reg_clear_overrun_seq");
    super.new(name);
  endfunction

  // ---------------------- MAIN BODY ----------------------
  virtual task body();
    `uvm_info("REG_CLR_OVR_SEQ","Clearing RX overrun condition (COMMAND.CLR_OVR)...", UVM_MEDIUM);

    // COMMAND bit3 → CLEAR DATA OVERRUN
    write_reg(`CAN_COMMAND_REG, `CAN_CMD_CLR_OVR_M);

    `uvm_info("REG_CLR_OVR_SEQ", "RX overrun cleared.", UVM_MEDIUM);
	
  endtask : body

endclass : reg_clear_overrun_seq

`endif // REG_CLEAR_OVERRUN_SEQ_SV

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// sequences/reg_self_rx_seq.sv

`ifndef REG_SELF_RX_SEQ_SV
`define REG_SELF_RX_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
//`include "can_defines.sv"

class reg_self_rx_seq extends reg_base_seq;
  `uvm_object_utils(reg_self_rx_seq)

  function new(string name="reg_self_rx_seq");
    super.new(name);
  endfunction

  // ---------------------- MAIN BODY ----------------------
  virtual task body();
    `uvm_info("REG_SELF_RX_SEQ", "Triggering SELF-RECEPTION (COMMAND.SELF_RX_REQ)...", UVM_MEDIUM);

    // COMMAND bit4 → SELF RX REQUEST
    write_reg(`CAN_COMMAND_REG, `CAN_CMD_SELF_RX_M);

    `uvm_info("REG_SELF_RX_SEQ","SELF RX request issued.", UVM_MEDIUM);
  endtask : body

endclass : reg_self_rx_seq

`endif // REG_SELF_RX_SEQ_SV

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REG_ENABLE_IRQ_SEQ

class reg_enable_irq_seq extends reg_base_seq;
	`uvm_object_utils(reg_enable_irq_seq)
	
	rand byte irq_enable_mask = 8'hFF; // enable all by default 
	
	function new (string name = "reg_enable_irq_seq");
		super.new(name);
	endfunction 
	
	virtual task body();
		`uvm_info("REG_ENABLE_IRQ_SEQ", $sformatf("Enabling IRQs: mask=0x%02h", irq_enable_mask), UVM_MEDIUM);
		
		write_reg(`CAN_IRQ_EN_EXT,irq_enable_mask);
	endtask 
	
endclass

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REg_CLEAR_IRQ_SEQ

class reg_clear_irq_seq extends reg_base_seq;
  `uvm_object_utils(reg_clear_irq_seq)

  byte irq_value;

  function new(string name="reg_clear_irq_seq");
	super.new(name);
  endfunction

  virtual task body();
    `uvm_info("REG_CLEAR_IRQ_SEQ", "Clearing IRQ register...", UVM_MEDIUM);
	
    read_reg(`CAN_IRQ_REG, irq_value);
  endtask
  

// ====================================================================================================================================================================
// ====================================================================================================================================================================
// REG_LISTEN_ONLY_SEQ

class reg_set_listen_only_seq extends reg_base_seq;
  `uvm_object_utils(reg_set_listen_only_seq)

  function new(string name="reg_set_listen_only_seq"); 
	super.new(name); 
  endfunction

  virtual task body();
    `uvm_info("REG_LISTEN_ONLY_SEQ", "Entering LISTEN-ONLY mode", UVM_MEDIUM);
	
    write_reg(`CAN_MODE_REG, `CAN_MODE_LISTEN_ONLY_M);
  endtask
  
endclass

// ====================================================================================================================================================================
// ====================================================================================================================================================================
//  reg_clear_irq_seq  (read-to-clear behaviour)

class reg_clear_irq_seq extends reg_base_seq;
  `uvm_object_utils(reg_clear_irq_seq)

  byte irq_value;

  function new(string name="reg_clear_irq_seq"); super.new(name); endfunction

  virtual task body();
    `uvm_info("REG_CLEAR_IRQ_SEQ", "Clearing IRQ register...", UVM_MEDIUM);
    read_reg(`CAN_IRQ_REG, irq_value);
  endtask
endclass

// ============================================================================
//  reg_set_self_test_mode_seq (MODE bit2)
// ============================================================================
class reg_set_self_test_mode_seq extends reg_base_seq;
  `uvm_object_utils(reg_set_self_test_mode_seq)

  function new(string name="reg_set_self_test_mode_seq"); super.new(name); endfunction

  virtual task body();
    `uvm_info("REG_SELF_TEST_SEQ", "Enabling SELF-TEST mode", UVM_MEDIUM);
    write_reg(`CAN_MODE_REG, `CAN_MODE_SELF_TEST_M);
  endtask
endclass


// ============================================================================
//  reg_set_accept_all_seq  (accept EVERY ID)
// ============================================================================
class reg_set_accept_all_seq extends reg_base_seq;
  `uvm_object_utils(reg_set_accept_all_seq)

  function new(string name="reg_set_accept_all_seq"); super.new(name); endfunction

  virtual task body();
    `uvm_info("REG_ACC_ALL_SEQ", "Programming ACCEPT-ALL filters", UVM_MEDIUM);
    write_reg(`CAN_ACC_CODE0_BASIC, 8'h00);
    write_reg(`CAN_ACC_MASK0_BASIC, 8'hFF);   // ignore all bits → accept all
  endtask
endclass

// ============================================================================
//  reg_set_accept_none_seq  (ACCEPT **NO** ID except 0)
// ============================================================================
class reg_set_accept_none_seq extends reg_base_seq;
  `uvm_object_utils(reg_set_accept_none_seq)

	function new(string name="reg_set_accept_none_seq");
		super.new(name); 
	endfunction

  virtual task body();
    `uvm_info("REG_ACC_NONE_SEQ", "Programming ACCEPT-NONE filters", UVM_MEDIUM);
    write_reg(`CAN_ACC_CODE0_BASIC, 8'h00);
    write_reg(`CAN_ACC_MASK0_BASIC, 8'h00);   // compare all bits → only ID=0 accepted
  endtask
endclass


// ============================================================================
//  reg_poll_status_seq (simple, no timeouts)
// ============================================================================
class reg_poll_status_seq extends reg_base_seq;
  `uvm_object_utils(reg_poll_status_seq)

  byte status;
	function new(string name="reg_poll_status_seq");
		super.new(name);
	endfunction

  virtual task body();
    `uvm_info("REG_POLL_STATUS_SEQ",
              "Polling STATUS register until TX_COMPLETE or RX_READY...",
              UVM_MEDIUM);

    // Simple busy wait (Type A)
    repeat (1000) begin
      read_reg(`CAN_STATUS_REG, status);
      if (status[`CAN_ST_TX_COMPLETE_BIT] || status[`CAN_ST_RX_RDY_BIT])
		begin 
			break;
			#1ns;
		end 
    end
  endtask
endclass


// ============================================================================
//  reg_reset_seq  (enter RESET mode)
// ============================================================================
class reg_reset_seq extends reg_base_seq;
  `uvm_object_utils(reg_reset_seq)

  function new(string name="reg_reset_seq"); super.new(name); endfunction

  virtual task body();
    `uvm_info("REG_RESET_SEQ",
              "Asserting RESET mode on CAN controller.",
              UVM_MEDIUM);

    write_reg(`CAN_MODE_REG, `CAN_MODE_RESET_M);
  endtask
endclass