`ifndef CAN_SCOREBOARD_SV
`define CAN_SCOREBOARD_SV

import uvm_pkg::*;

// IMPORTANT:
// `uvm_analysis_imp_decl(_exp) and `uvm_analysis_imp_decl(_obs)
// should be declared ONCE in can_pkg.sv (not here).

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
    super.new(name,parent);
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

    // Print a header once (table-style)
    `uvm_info("CAN_SB_TXN",
      "TIME        | EXP(src) | OBS(node) | FMT | ID         | DLC | DATA",
      UVM_LOW)
    `uvm_info("CAN_SB_TXN",
      "------------+----------+-----------+-----+------------+-----+--------------------------------",
      UVM_LOW)
  endfunction

  // -------------------------
  // Formatting helpers
  // -------------------------

  function string fmt_fmt(bit can_fmt);
    return (can_fmt == `CAN_ID_STD) ? "STD" : "EXT";
  endfunction

  function string bytes_to_hex_str(const ref byte unsigned data[]);
    string s;
    s = "";
    foreach (data[i]) begin
      // Print as 2-digit hex bytes
      s = {s, $sformatf("%02x", data[i])};
      if (i != data.size()-1) s = {s, " "};
    end
    return s;
  endfunction

  function string fmt_txn_short(can_transaction tr);
    // Keep it compact: FMT + ID + DLC + DATA
    return $sformatf("%s | %08h | %0d  | %s",
                     fmt_fmt(tr.can_fmt),
                     tr.id,
                     tr.dlc,
                     bytes_to_hex_str(tr.data));
  endfunction

  // -------------------------
  // Analysis callbacks
  // -------------------------

  function void write_exp(can_transaction tr);
    // Ignore losers
    if (tr.arb_lost) begin
      `uvm_info("CAN_SB",
        $sformatf("Ignoring EXP (arb_lost) from node%0d id=0x%0h lost_bit=%0d",
                  tr.src_node, tr.id, tr.arb_lost_bit),
        UVM_MEDIUM)
      return;
    end

    `uvm_info("CAN_SB_ARB",
      $sformatf("[WINNER] node%0d EXP accepted as winner id=0x%0h",
                tr.src_node, tr.id),
      UVM_LOW)

    exp_q.push_back(tr);
    `uvm_info("CAN_SB",
      $sformatf("Expected frame queued (ID=0x%0h)", tr.id),
      UVM_MEDIUM)

    compare_if_ready();
  endfunction

  function void write_obs(can_transaction tr);
    obs_q_by_node[tr.src_node].push_back(tr);
    `uvm_info("CAN_SB",
      $sformatf("OBS queued from node%0d id=0x%0h", tr.src_node, tr.id),
      UVM_MEDIUM)

    compare_if_ready();
  endfunction

  // -------------------------
  // Compare engine
  // -------------------------

  function void compare_if_ready();
    bit all_ok = 1;
    can_transaction exp;
    can_transaction obs;

    if (exp_q.size() == 0) return;

    // Need at least one observed frame from EVERY node
    for (int unsigned n = 0; n < num_nodes; n++) begin
      if (!obs_q_by_node.exists(n) || obs_q_by_node[n].size() == 0)
        return;
    end

    exp = exp_q.pop_front();

    // Compare EXP with OBS from each node
    for (int unsigned n = 0; n < num_nodes; n++) begin
      obs = obs_q_by_node[n].pop_front();

      if (!compare_txn(exp, obs)) begin
        all_ok = 0;

        `uvm_error("CAN_SB_TXN",
          $sformatf("%-11t | EXP(%0d)  | OBS(%0d)    | %s | FAIL",
                    $time, exp.src_node, obs.src_node, fmt_txn_short(obs)))

        `uvm_error("CAN_SB",
          $sformatf("MISMATCH DETAILS\n  EXP: %s\n  OBS: %s",
                    exp.convert2string(), obs.convert2string()))
      end
      else begin
        `uvm_info("CAN_SB_TXN",
          $sformatf("%-11t | EXP(%0d)  | OBS(%0d)    | %s | PASS",
                    $time, exp.src_node, obs.src_node, fmt_txn_short(obs)),
          UVM_LOW)
      end
    end

    if (all_ok) pass_count++;
    else        fail_count++;
  endfunction

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
