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
  
  // --- SEQUENCES ----
  `include "sequences/can_id_boundary_seq.sv"
  `include "sequences/can_arb_burst_seq.sv"
  `include "sequences/can_ack_error_seq.sv"
  `include "sequences/can_crc_error_seq.sv"
  `include "sequences/can_stuff_error_seq.sv"
  `include "sequences/can_form_error_seq.sv"
  `include "sequences/can_ifs_overload_seq.sv"
  `include "sequences/can_midframe_error_seq.sv"
  `include "sequences/can_remote_response_seq.sv"
  `include "sequences/can_ext_data_seq.sv"
  `include "sequences/can_std_ext_arb_seq.sv"
  `include "sequences/can_dlc_boundary_seq.sv"
  `include "sequences/can_dut_init_seq.sv"
  `include "sequences/can_dut_tx_seq.sv"  
  `include "sequences/can_dut_rx_seq.sv"
  `include "sequences/can_dut_crc_err_seq.sv"
  `include "sequences/can_dut_stuff_err_seq.sv"
  `include "sequences/can_dut_ack_err_seq.sv"
  `include "sequences/can_dut_form_err_seq.sv"
  `include "sequences/can_dut_remote_rx_seq.sv"
  `include "sequences/can_dut_normal_mode_rx_seq.sv"
  `include "sequences/can_dut_listen_only_mode_seq.sv"
  `include "sequences/can_dut_self_test_mode_seq.sv"
  `include "sequences/can_dut_acceptance_filter_seq.sv"
  
  // --- TESTS ----
  `include "tests/can_id_boundary_test.sv"
  `include "tests/can_arb_burst_test.sv"
  `include "tests/can_ack_error_test.sv"
  `include "tests/can_crc_error_test.sv"
  `include "tests/can_stuff_error_test.sv"
  `include "tests/can_form_error_test.sv"
  `include "tests/can_ifs_overload_test.sv"
  `include "tests/can_midframe_error_test.sv"
  `include "tests/can_remote_response_test.sv"
  `include "tests/can_ext_frame_test.sv"
  `include "tests/can_std_ext_arb_test.sv"
  `include "tests/can_dlc_boundary_test.sv"
  `include "tests/can_dut_init_test.sv"
  `include "tests/can_dut_tx_test.sv"
  `include "tests/can_dut_rx_test.sv"
  `include "tests/can_dut_crc_err_test.sv"
  `include "tests/can_dut_stuff_err_test.sv"
  `include "tests/can_dut_ack_err_test.sv"
  `include "tests/can_dut_form_err_test.sv"
  `include "tests/can_dut_remote_rx_test.sv"
  `include "tests/can_dut_normal_mode_rx_test.sv"
  `include "tests/can_dut_listen_only_mode_test.sv"
  `include "tests/can_dut_self_test_mode_test.sv"
  `include "tests/can_dut_acceptance_filter_test.sv"
  
endpackage : can_pkg
`endif
