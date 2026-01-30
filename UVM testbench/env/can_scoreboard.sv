`ifndef CAN_SCOREBOARD_SV
`define CAN_SCOREBOARD_SV
import uvm_pkg::*;
// IMPORTANT:
// - This file is intended to be `include`d from can_pkg.sv
// - Do NOT put `uvm_analysis_imp_decl() here if it's already in the package
// - Do NOT put `include "uvm_macros.svh" here if the package already includes it
// These types exist ONLY if you declared:
  `uvm_analysis_imp_decl(_exp)
  `uvm_analysis_imp_decl(_obs)
class can_scoreboard extends uvm_component;
  `uvm_component_utils(can_scoreboard)

 
  // in can_pkg.sv (ONE place only)
  uvm_analysis_imp_exp #(can_transaction, can_scoreboard) exp_imp;
  uvm_analysis_imp_obs #(can_transaction, can_scoreboard) obs_imp;

  // queues
  can_transaction exp_q[$];
  can_transaction obs_q_by_node[int unsigned][$];

  int unsigned num_nodes = 1;

  int pass_count;
  int fail_count;

  function new(string name = "can_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    exp_imp = new("exp_imp", this);
    obs_imp = new("obs_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    void'(uvm_config_db#(int unsigned)::get(this, "", "num_nodes", num_nodes));
    if (num_nodes == 0) num_nodes = 1;

    `uvm_info("CAN_SB",
              $sformatf("Scoreboard expecting %0d OBS per EXP", num_nodes),
              UVM_LOW)
  endfunction

  // ---------------- Expected (from drivers) ----------------
  function void write_exp(can_transaction tr);

    // Ignore loser attempts in arbitration mode
    if (tr.arb_lost) begin
      `uvm_info("CAN_SB",
                $sformatf("Ignoring EXP (arb_lost) from node%0d id=0x%0h lost_bit=%0d",
                          tr.src_node, tr.id, tr.arb_lost_bit),
                UVM_LOW)
      return;
    end

    `uvm_info("CAN_SB_ARB",
              $sformatf("[WINNER] node%0d EXP accepted as winner id=0x%0h",
                        tr.src_node, tr.id),
              UVM_LOW)

    exp_q.push_back(tr);
    `uvm_info("CAN_SB",
              $sformatf("Expected frame queued (ID=0x%0h)", tr.id),
              UVM_LOW)

    compare_if_ready();
  endfunction

  // ---------------- Observed (from monitors) ----------------
  function void write_obs(can_transaction tr);
    obs_q_by_node[tr.src_node].push_back(tr);

    `uvm_info("CAN_SB",
              $sformatf("OBS queued from node%0d id=0x%0h", tr.src_node, tr.id),
              UVM_LOW)

    compare_if_ready();
  endfunction

  // ---------------- Compare when ready ----------------
  function void compare_if_ready();
    bit all_ok = 1;

    can_transaction exp;
    can_transaction obs;

    if (exp_q.size() == 0) return;

    // Need at least one observed frame from EVERY node
    for (int unsigned n = 0; n < num_nodes; n++) begin
      if (!obs_q_by_node.exists(n) || (obs_q_by_node[n].size() == 0))
        return;
    end

    exp = exp_q.pop_front();

    for (int unsigned n = 0; n < num_nodes; n++) begin
      obs = obs_q_by_node[n].pop_front();

      if (!compare_txn(exp, obs)) begin
        all_ok = 0;
        `uvm_error("CAN_SB",
                   $sformatf("CAN FRAME MISMATCH (node=%0d)\n  EXP: %s\n  OBS: %s",
                             n, exp.convert2string(), obs.convert2string()))
      end
      else begin
        `uvm_info("CAN_SB_TXN",
                  $sformatf("TIME=%0t | node=%0d | EXP=%s | OBS=%s | PASS",
                            $time, n, exp.convert2string(), obs.convert2string()),
                  UVM_LOW)
      end
    end

    if (all_ok) pass_count++;
    else        fail_count++;
  endfunction

  // ---------------- Field compare ----------------
  function bit compare_txn(can_transaction exp, can_transaction obs);
    if (exp.can_fmt != obs.can_fmt) return 0;
    if (exp.id      != obs.id)      return 0;
    if (exp.f_type  != obs.f_type)  return 0;
    if (exp.dlc     != obs.dlc)     return 0;

    if (exp.data.size() != obs.data.size()) return 0;

    foreach (exp.data[i]) begin
      if (exp.data[i] != obs.data[i]) return 0;
    end

    return 1;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("CAN_SB",
              $sformatf("Scoreboard summary: Pass=%0d Fail=%0d", pass_count, fail_count),
              UVM_LOW)
  endfunction

endclass : can_scoreboard

`endif // CAN_SCOREBOARD_SV
