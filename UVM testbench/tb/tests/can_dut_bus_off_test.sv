`ifndef CAN_DUT_BUS_OFF_TEST_SV
`define CAN_DUT_BUS_OFF_TEST_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

// =============================================================================
// can_dut_bus_off_test
// =============================================================================
// Runs can_dut_bus_off_seq, where:
//   - DUT is the transmitter
//   - tb node 1 directly jams the bus during ACK-delim / EOF window
//   - DUT TEC should rise due to transmit-side form error
//   - sequence reports:
//       bus_off_reached
//       recovery_done
//       stalled_no_progress
//
// PASS criteria:
//   1) bus_off_reached == 1
//   2) recovery_done   == 1   (can be relaxed if you want entry-only testing)
//
// Notes:
// - Do NOT require ack_seen/no_ack counts for pass/fail here.
//   With EOF / ACK-delim jamming, ACK visibility can be distorted by the
//   injected dominant error flag.
// =============================================================================

class can_dut_bus_off_test extends uvm_test;
  `uvm_component_utils(can_dut_bus_off_test)

  virtual can_if     vif;
  can_env            m_env;
  can_env_config     env_cfg;

  uvm_tlm_analysis_fifo #(can_transaction) mon_fifo;

  function new(string name = "can_dut_bus_off_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("BUS_OFF_TEST", "Cannot get vif from config_db")

    mon_fifo = new("mon_fifo", this);

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // Two passive agents:
    //   node0 -> passive monitor
    //   node1 -> passive monitor only; tb_tx[1] is driven directly by sequence
    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 1'b0;

    // Node 0 monitor
    env_cfg.c_cfg[0].is_active              = UVM_PASSIVE;
    env_cfg.c_cfg[0].node_id                = 0;
    env_cfg.c_cfg[0].bit_time_ns            = 320;
    env_cfg.c_cfg[0].sample_point_pct       = 75;
    env_cfg.c_cfg[0].ack_enable             = 1'b0;
    env_cfg.c_cfg[0].expect_no_ack          = 1'b0;
    env_cfg.c_cfg[0].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[0].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[0].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[0].publish_special_frames = 1'b0;

    // Node 1 monitor
    env_cfg.c_cfg[1].is_active              = UVM_PASSIVE;
    env_cfg.c_cfg[1].node_id                = 1;
    env_cfg.c_cfg[1].bit_time_ns            = 320;
    env_cfg.c_cfg[1].sample_point_pct       = 75;
    env_cfg.c_cfg[1].ack_enable             = 1'b0;
    env_cfg.c_cfg[1].expect_no_ack          = 1'b0;
    env_cfg.c_cfg[1].enable_special_decode  = 1'b0;
    env_cfg.c_cfg[1].special_decode_idle    = 1'b0;
    env_cfg.c_cfg[1].special_decode_ifs     = 1'b0;
    env_cfg.c_cfg[1].publish_special_frames = 1'b0;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    m_env.c_agent[0].monh.ap.connect(mon_fifo.analysis_export);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_bus_off_seq bo_seq;
    can_transaction     obs_tr;
    int unsigned        frames_total;
    int unsigned        data_frames;
    int unsigned        error_frames;
    int unsigned        ack_seen_cnt;
    int unsigned        errors;

    phase.raise_objection(this);

    frames_total = 0;
    data_frames  = 0;
    error_frames = 0;
    ack_seen_cnt = 0;
    errors       = 0;

    // Keep jammer node released before starting
    vif.tb_tx[1] = 1'b1;

    bo_seq              = can_dut_bus_off_seq::type_id::create("bo_seq");
    bo_seq.vif          = vif;
    bo_seq.max_attempts = 60;

    `uvm_info("BUS_OFF_TEST", "Starting DUT-transmit bus-off test", UVM_LOW)
    bo_seq.start(null);

    // Small drain time for monitor / assertions / status sampling
    #100us;

    while (mon_fifo.try_get(obs_tr)) begin
      frames_total++;
      if (obs_tr.f_type == `CAN_DATA_FRAME)
        data_frames++;
      else
        error_frames++;

      if (obs_tr.ack_seen)
        ack_seen_cnt++;
    end

    `uvm_info("BUS_OFF_TEST",
      $sformatf("Monitor stats: total=%0d data=%0d non_data=%0d ack_seen=%0d",
                frames_total, data_frames, error_frames, ack_seen_cnt),
      UVM_LOW)

    // Main verdict
    if (!bo_seq.bus_off_reached) begin
      if (bo_seq.stalled_no_progress) begin
        `uvm_error("BUS_OFF_TEST",
          $sformatf({"Bus-off was NOT reached because TEC stopped progressing. ",
                     "Final TEC=%0d REC=%0d bus_off_on=%0b. ",
                     "Tune EOF jam timing in can_dut_bus_off_seq."},
                    bo_seq.final_tec, bo_seq.final_rec, vif.bus_off_on))
      end
      else begin
        `uvm_error("BUS_OFF_TEST",
          $sformatf("Bus-off was NOT reached. Final TEC=%0d REC=%0d bus_off_on=%0b",
                    bo_seq.final_tec, bo_seq.final_rec, vif.bus_off_on))
      end
      errors++;
    end
    else begin
      `uvm_info("BUS_OFF_TEST",
        $sformatf("Bus-off reached at attempt %0d", bo_seq.bus_off_attempt),
        UVM_LOW)
    end

    if (bo_seq.bus_off_reached && !bo_seq.recovery_done) begin
      `uvm_error("BUS_OFF_TEST",
        $sformatf("Bus-off entry happened, but recovery did not complete. Final TEC=%0d REC=%0d",
                  bo_seq.final_tec, bo_seq.final_rec))
      errors++;
    end
    else if (bo_seq.bus_off_reached && bo_seq.recovery_done) begin
      `uvm_info("BUS_OFF_TEST",
        "Recovery completed successfully after bus-off",
        UVM_LOW)
    end

    // Informational only: do not make exact TEC value a hard fail here
    `uvm_info("BUS_OFF_TEST",
      $sformatf("Final status: TEC=%0d REC=%0d bus_off_on=%0b",
                bo_seq.final_tec, bo_seq.final_rec, vif.bus_off_on),
      UVM_LOW)

    if (errors == 0)
      `uvm_info("BUS_OFF_TEST", "PASS: Bus-off test completed", UVM_LOW)
    else
      `uvm_error("BUS_OFF_TEST",
        $sformatf("FAIL: %0d violation(s)", errors))

    `uvm_info("BUS_OFF_TEST", "===== BUS-OFF TEST COMPLETE =====", UVM_LOW)

    // Always release jammer line
    vif.tb_tx[1] = 1'b1;

    phase.drop_objection(this);
  endtask

endclass

`endif