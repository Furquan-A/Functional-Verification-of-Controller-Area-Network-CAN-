`ifndef REG_RANDOM_SEQ_SV
`define REG_RANDOM_SEQ_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// =============================================================================
// reg_random_seq
// =============================================================================
// Constraint-driven random register stimulus.
// Fires N random read/write transactions to the DUT to maximize toggle and
// condition coverage on i_can_registers, can_register_syn, and the TX buffer
// IBO modules.
//
// Smart constraints prevent the random stimulus from breaking the DUT:
//   - Skip Mode register (0x00) — writing 0x01 enters reset mode mid-test
//   - Skip Clock Divider (0x1F) — would switch BasicCAN/PeliCAN map
//   - Skip Command register (0x01) — would trigger TX/abort/etc unexpectedly
//   - Bias toward TX buffer (0x10–0x1C) for IBO coverage
//   - Mix 70% writes / 30% reads
//   - Use varied data patterns (all 256 possible byte values eligible)
// =============================================================================

class reg_random_seq extends reg_base_seq;
  `uvm_object_utils(reg_random_seq)

  // -- Knobs (set by test) -----------------------------------
  rand int unsigned n_txns = 500;

  // Hard limits on the random transaction count so it doesn't go wild
  constraint c_n_txns_range { n_txns inside {[100:2000]}; }

  function new(string name = "reg_random_seq");
    super.new(name);
  endfunction

  // -------------------------------------------------------------------
  task body();
    reg_transaction tr;

    `uvm_info("REG_RAND_SEQ",
      $sformatf("===== Starting REG RANDOM seq with %0d transactions =====", n_txns),
      UVM_LOW)

    for (int i = 0; i < n_txns; i++) begin
      tr = reg_transaction::type_id::create($sformatf("rtr_%0d", i));

      start_item(tr);

      // --- Constraint-driven randomization ----------------------------
      assert(tr.randomize() with {

        // -- Direction: 70% writes, 30% reads --
        // Writes drive toggle coverage. Reads exercise read-decode logic.
        kind dist { REG_WRITE := 7, REG_READ := 3 };

        // -- Address constraints --
        // Avoid these addresses entirely:
        //   0x00 = Mode register   ? writing 0x01 enters reset mode
        //   0x01 = Command register ? writes trigger TX, abort, RRB, etc
        //   0x1F = Clock Divider   ? switches BasicCAN ? PeliCAN map
        addr != 8'h00;
        addr != 8'h01;
        addr != 8'h1F;

        // Stay within the PeliCAN register window (0x00–0x1F)
        addr inside { [8'h02 : 8'h1E] };

        // -- Address weighting --
        // Bias toward TX buffer (0x10–0x1C in PeliCAN) to exercise IBO modules.
        // Acceptance filter regs (0x10–0x17) overlap when in reset mode but in
        // operating mode they map to TX buffer — both are good toggle targets.
        addr dist {
          [8'h10 : 8'h1C] := 6,   // TX buffer / acceptance filter — heavy weight
          [8'h02 : 8'h0F] := 2,   // status / IR / IER / BTR / OCR / ALC / ECC / EWLR / RXERR / TXERR
          [8'h1D : 8'h1E] := 1    // tail registers
        };

        // -- Write data: full byte range, no constraints --
        // (wdata is rand bit [7:0] in reg_transaction — all 256 values legal)

      }) else `uvm_fatal("REG_RAND_SEQ",
                         $sformatf("Randomization failed at iteration %0d", i))

      finish_item(tr);

      // Optional inline trace for debug — remove if too noisy
      if (i % 50 == 0)
        `uvm_info("REG_RAND_SEQ",
          $sformatf("Progress: %0d/%0d transactions sent", i+1, n_txns),
          UVM_LOW)
    end

    `uvm_info("REG_RAND_SEQ",
      $sformatf("===== REG RANDOM seq COMPLETE — %0d transactions sent =====", n_txns),
      UVM_LOW)
  endtask : body

endclass : reg_random_seq

`endif // REG_RANDOM_SEQ_SV