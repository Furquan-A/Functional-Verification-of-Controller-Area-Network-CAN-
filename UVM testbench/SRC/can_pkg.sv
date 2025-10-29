`timescale 1ns/1ps

// -------------------------------------------------------------------
// Global includes that are NOT classes should be compiled separately:
//   - if/*.sv (interfaces)
//   - bfm/*.sv (e.g., can_bus_model.sv)
//   - sva/*.sv (bind files)
// -------------------------------------------------------------------

// Make UVM available
`include "uvm_macros.svh"
import uvm_pkg::*;

// Your macro defines (addresses, masks, widths, IDs, etc.)
`include "can_defines.sv"   // <-- the backtick file we aligned to the RTL

// -------------------------------------------------------------------
// UVM Package: put ONLY classes in here
// -------------------------------------------------------------------
package can_pkg;

  // ----- Common source (classes only) -----
  `include "can_utils.sv"         // helper classes/functions (no modules)
  `include "can_transaction.sv"   // can_item seq_item (uses backtick macros)
  `include "can_config.sv"        // config objects/structs for env/agents

  // ----- Agents: Register/Host side (low-level, no RAL) -----
  `include "agents/reg_agent/reg_sequencer.sv"
  `include "agents/reg_agent/reg_driver.sv"
  `include "agents/reg_agent/reg_monitor.sv"
  `include "agents/reg_agent/reg_agent.sv"

  // ----- Agents: CAN node side (one agent = one node) -----
  `include "agents/can_agent/can_sequencer.sv"
  `include "agents/can_agent/can_driver.sv"
  `include "agents/can_agent/can_monitor.sv"
  `include "agents/can_agent/can_agent.sv"

  // ----- Environment / Scoreboard / Coverage -----
  // (virtual sequencer first so env can reference it)
  `include "env/can_virtual_sequencer.sv"
  `include "env/can_scoreboard.sv"
  `include "env/can_coverage.sv"
  `include "env/can_env.sv"

  // ----- Sequences (protocol + reg + virtual) -----
  `include "sequences/can_base_seq.sv"
  `include "sequences/reg_sequences.sv"
  `include "sequences/can_frame_sequences.sv"
  `include "sequences/can_virtual_sequences.sv"

  // ----- Base tests (keep concrete tests outside the package if you prefer) -----
  `include "tests/can_base_test.sv"
  `include "tests/can_basic_test.sv"
  `include "tests/can_error_test.sv"
  `include "tests/can_stress_test.sv"

endpackage : can_pkg