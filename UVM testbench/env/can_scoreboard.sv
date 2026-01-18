`ifndef CAN_SCOREBOARD_SV
`define CAN_SCOREBOARD_SV

//`include "uvm_macros.svh"
import uvm_pkg::*;
//import can_pkg::*; // so can_transaction + analysis_imp decls are visible
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_obs)
class can_scoreboard extends uvm_component;
  `uvm_component_utils(can_scoreboard)

  // analysis imps (declared via `uvm_analysis_imp_decl(_exp/_obs) in can_pkg.sv)
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
  endfunction


  function void write_exp(can_transaction tr);
    exp_q.push_back(tr);
    `uvm_info("CAN_SB", $sformatf("Expected frame queued (ID=0x%0h)", tr.id), UVM_LOW);
    compare_if_ready();
  endfunction

  function void write_obs(can_transaction tr);
	  obs_q_by_node[tr.src_node].push_back(tr);
	  `uvm_info("CAN_SB", $sformatf("OBS queued from node%0d id=0x%0h", tr.src_node, tr.id), UVM_LOW)
	  compare_if_ready();
  endfunction


 function void compare_if_ready();
  can_transaction exp;
  can_transaction obs;
  bit ok;
  string msg;

  if (exp_q.size() == 0 || obs_q.size() == 0)
    return;

  exp = exp_q.pop_front();
  obs = obs_q.pop_front();

  ok = compare_txn(exp, obs);

  msg = $sformatf("TIME=%0t | EXP=%s | OBS=%s | RESULT=%s",
                $time,
                exp.convert2string(),
                obs.convert2string(),
                ok ? "PASS" : "FAIL");
  `uvm_info("CAN_SB_TXN", msg, UVM_LOW);


  if (ok) begin
    pass_count++;
  end
  else begin
    fail_count++;
    `uvm_error("CAN_SB", "CAN FRAME MISMATCH (see CAN_SB_TXN block above)")
  end
endfunction



  function bit compare_txn(can_transaction exp, can_transaction obs);
    if (exp.can_fmt != obs.can_fmt) return 0;
    if (exp.id      != obs.id)      return 0;
    if (exp.f_type  != obs.f_type)  return 0;
    if (exp.dlc     != obs.dlc)     return 0;

    if (exp.data.size() != obs.data.size()) return 0; // FIXED

    foreach (exp.data[i]) begin
      if (exp.data[i] != obs.data[i]) return 0;
    end

    return 1; // FIXED
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("CAN_SB",
              $sformatf("Scoreboard summary: Pass=%0d Fail=%0d", pass_count, fail_count),
              UVM_LOW);
  endfunction

endclass : can_scoreboard

`endif // CAN_SCOREBOARD_SV
