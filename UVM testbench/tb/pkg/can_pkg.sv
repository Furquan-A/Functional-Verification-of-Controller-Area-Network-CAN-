`ifndef CAN_PKG_SV
`define CAN_PKG_SV

package can_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  `include "pkg/can_defines.sv"
  
  
  `include "agents/can_agent/can_transaction.sv"
  `include "agents/can_agent/can_agent_config.sv"
  `include "agents/can_agent/can_sequencer.sv"
  `include "agents/can_agent/can_driver.sv"
  `include "agents/can_agent/can_monitor.sv"
  `include "agents/can_agent/can_agent.sv"
  
  
  `include "agents/reg_agent/reg_agent_config.sv"
  
  
  `include "env/can_scoreboard.sv"
  `include "env/can_env_config.sv"
  `include "env/can_env.sv"

  `include "sequences/can_tx_seq.sv"
  `include "sequences/can_arb_tx_seq.sv"
  `include "sequences/can_arb_burst_seq.sv"
  `include "sequences/can_ack_error_seq.sv"
  `include "sequences/can_crc_error_seq.sv"
  `include "sequences/can_stuff_error_seq.sv"
  `include "sequences/can_form_error_seq.sv"
  `include "tests/can_smoke_test.sv"
  `include "tests/can_arb_smoke_test.sv"
  `include "tests/can_arb_burst_test.sv"
  `include "tests/can_ack_error_test.sv"
  `include "tests/can_crc_error_test.sv"
  `include "tests/can_stuff_error_test.sv"
  `include "tests/can_form_error_test.sv"
endpackage : can_pkg
`endif
