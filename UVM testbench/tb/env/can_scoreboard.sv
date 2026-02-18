`ifndef CAN_SCOREBOARD_SV
`define CAN_SCOREBOARD_SV

import uvm_pkg::*;

// ------------------------------------------------------------------
// IMPORTANT:
// `uvm_analysis_imp_decl(_exp) and (_obs) must be declared ONLY ONCE
// in the whole project (either here OR in can_pkg.sv).
// If you already have them in can_pkg.sv, DO NOT repeat them here.
// ------------------------------------------------------------------
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_obs)

class can_scoreboard extends uvm_component;
  `uvm_component_utils(can_scoreboard)

  // analysis imps
  uvm_analysis_imp_exp #(can_transaction, can_scoreboard) exp_imp;
  uvm_analysis_imp_obs #(can_transaction, can_scoreboard) obs_imp;

  // queues
  can_transaction exp_q[$];
  can_transaction obs_q_by_node[int unsigned][$];

  int unsigned num_nodes = 1;
  int pass_count;
  int fail_count;

  function new(string name="can_scoreboard", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    exp_imp = new("exp_imp", this);
    obs_imp = new("obs_imp", this);

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
    int unsigned n;

    // Which node produced this OBS?
    // Your monitor sets tr.src_node = c_cfg.node_id, so use that.
    n = tr.src_node;

    obs_q_by_node[n].push_back(tr);

    `uvm_info("CAN_SB",
              $sformatf("OBS queued from node%0d id=0x%0h", n, tr.id),
              UVM_LOW)

    compare_if_ready();
  endfunction

  // ---------------- Compare when ready ----------------
 function void compare_if_ready();
  bit all_ok = 1;
  bit exp_is_injected;
  bit exp_ack_present;

  can_transaction exp;
  can_transaction obs;
  
  int match_idx[int unsigned]; // per-node index of OBS we will consume
  
  // Need an EXP to do anything
  if (exp_q.size() == 0) return;

  // Peek (DO NOT pop yet)
  exp = exp_q[0];

  exp_is_injected = (exp.inj_ack_error ||
                     exp.inj_crc_error ||
                     exp.inj_form_error ||
                     exp.inj_stuff_error);

  // For injected frame => expect NO ACK
  exp_ack_present = !exp_is_injected;

  // ------------------------------------------------------------
  // Phase 1: make sure we have a matching OBS candidate for EACH node
  //   - If EXP is clean: need a CLEAN obs (no crc/form/stuff error flags)
  //   - If EXP is injected: any obs is acceptable (it should be the injected one)
  // We DO NOT modify queues in this phase.
  // ------------------------------------------------------------
  

  for (int unsigned n = 0; n < num_nodes; n++) begin
    if (!obs_q_by_node.exists(n) || obs_q_by_node[n].size() == 0)
      return;

    match_idx[n] = -1;

    if (!exp_is_injected) begin
      // find first CLEAN obs
      for (int i = 0; i < obs_q_by_node[n].size(); i++) begin
        can_transaction tmp = obs_q_by_node[n][i];
        if (!(tmp.form_error_seen || tmp.crc_error_seen || tmp.stuff_error_seen)) begin
          match_idx[n] = i;
          break;
        end
      end
    end
    else begin
      // injected EXP: just take the head obs
      match_idx[n] = 0;
    end

    // If we can't find the needed OBS yet, wait for more OBS to arrive
    if (match_idx[n] < 0)
      return;
  end

  // ------------------------------------------------------------
  // Phase 2: NOW we are safe to consume
  // ------------------------------------------------------------
  void'(exp_q.pop_front());

  for (int unsigned n = 0; n < num_nodes; n++) begin
    int idx = match_idx[n];
    obs = obs_q_by_node[n][idx];
    obs_q_by_node[n].delete(idx);

    // ACK check
    // monitor meaning: ack_seen==1 means ACK PRESENT
    if (obs.ack_seen !== exp_ack_present) begin
      all_ok = 0;
      `uvm_error("CAN_SB_ACK",
        $sformatf("ACK mismatch node%0d id=0x%0h | exp_ack_present=%0b obs.ack_seen=%0b (inj_ack=%0b inj_crc=%0b inj_form=%0b inj_stuff=%0b)",
                  n, obs.id, exp_ack_present, obs.ack_seen,
                  exp.inj_ack_error, exp.inj_crc_error, exp.inj_form_error, exp.inj_stuff_error));
    end

    // Error expectations
    if (exp.inj_crc_error && (obs.crc_error_seen != 1'b1)) begin
      all_ok = 0;
      `uvm_error("CAN_SB_CRC",
        $sformatf("Expected CRC error but crc_error_seen=0 on node%0d (obs id=0x%0h)",
                  n, obs.id));
    end

    if (exp.inj_form_error && (obs.form_error_seen != 1'b1)) begin
      all_ok = 0;
      `uvm_error("CAN_SB_FORM",
        $sformatf("Expected FORM error but form_error_seen=0 on node%0d (obs id=0x%0h)",
                  n, obs.id));
    end

    if (exp.inj_stuff_error && (obs.stuff_error_seen != 1'b1)) begin
      all_ok = 0;
      `uvm_error("CAN_SB_STUFF",
        $sformatf("Expected STUFF error but stuff_error_seen=0 on node%0d (obs id=0x%0h)",
                  n, obs.id));
    end

    // Full compare only for clean frames
    if (!exp_is_injected) begin
      if (!compare_txn(exp, obs)) begin
        all_ok = 0;
        `uvm_error("CAN_SB",
          $sformatf("CAN FRAME MISMATCH (node=%0d)\n  EXP: %s\n  OBS: %s",
                    n, exp.convert2string(), obs.convert2string()));
      end
      else begin
        `uvm_info("CAN_SB_TXN",
          $sformatf("TIME=%0t | node=%0d | EXP=%s | OBS=%s | PASS",
                    $time, n, exp.convert2string(), obs.convert2string()),
          UVM_LOW);
      end
    end
    else begin
      `uvm_info("CAN_SB_ERR",
        $sformatf("TIME=%0t | node=%0d | EXP(injected)=%s | OBS=%s | (checked errors/ack only)",
                  $time, n, exp.convert2string(), obs.convert2string()),
        UVM_LOW);
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
