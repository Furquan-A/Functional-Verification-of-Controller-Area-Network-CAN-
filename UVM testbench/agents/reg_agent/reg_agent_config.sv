// src/can_config.sv (updated reg_agent_config)
`ifndef REG_AGENT_CONFIG_SV
`define REG_AGENT_CONFIG_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

// Optional: keep this enum for explicit expectations/logs
typedef enum int { REG_BUS_AUTO=0, REG_BUS_WB=1, REG_BUS_LEGACY=2 } reg_bus_e;

class reg_agent_config extends uvm_object;
  `uvm_object_utils(reg_agent_config)

  // ---- UVM active/passive control (used by your reg_agent) ----
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // ---- Unified virtual interface (WB or Legacy behind the same can_if) ----
  virtual can_if        vif;

  // ---- Bus expectation (sanity/log) ----
  rand reg_bus_e        expect_bus = REG_BUS_AUTO;

  // ---- Tracing / behavior knobs ----
  rand bit              trace_ops        = 1'b1;
  rand bit              checks_enable    = 1'b0;
  rand bit              coverage_enable  = 1'b0;
  rand bit              debug_mode       = 1'b0;

  // ---- Inter-transaction delays (ns) ----
  rand bit              random_delays    = 1'b0;
  rand int unsigned     default_delay_ns = 0;
  rand int unsigned     min_delay_ns     = 0;
  rand int unsigned     max_delay_ns     = 0;

  // ---- Optional setup/hold around each txn (ns) ----
  rand int unsigned     default_setup_time = 0;
  rand int unsigned     default_hold_time  = 0;

  // ---- Timeout / error injection controls ----
  // max_wait_cycles=0 disables watchdog (driver then relies on can_if's internal timeouts)
  rand int unsigned     max_wait_cycles  = 0;
  rand bit              inject_bus_errors = 1'b0;
  // 0..100 percent chance per txn (only used if inject_bus_errors==1)
  rand int unsigned     error_rate       = 0;

  // ---- Ctor ----
  function new(string name="reg_agent_config");
    super.new(name);
  endfunction

  // ---- Validation: ensure VIF is set + optional bus expectation check ----
  function bit validate(ref string why);
    if (vif == null) begin
      why = "can_if vif is null"; return 0;
    end
    bit use_wb = vif.USE_WB;
    if (expect_bus == REG_BUS_WB     && !use_wb) begin why="Expected WB but interface is LEGACY"; return 0; end
    if (expect_bus == REG_BUS_LEGACY &&  use_wb) begin why="Expected LEGACY but interface is WB"; return 0; end

    // Delay sanity
    if (random_delays && (max_delay_ns < min_delay_ns)) begin
      why = $sformatf("random_delays set but max_delay_ns(%0d) < min_delay_ns(%0d)", max_delay_ns, min_delay_ns);
      return 0;
    end
    // Percent sanity
    if (error_rate > 100) begin
      why = "error_rate must be 0..100"; return 0;
    end
    return 1;
  endfunction

  // ---- Pretty bus name ----
  function string bus_name();
    if (vif == null) return "UNKNOWN";
    return vif.USE_WB ? "WISHBONE" : "LEGACY";
  endfunction

  // ---- Policy helpers used by driver pre/post checks (stub permissive) ----
  // You can refine these later using your actual register map if desired.
  function bit is_readable_reg(byte unsigned addr);
    // For now, allow all 0x00–0xFF; refine if you want stricter policy.
    return 1;
  endfunction

  function bit is_writable_reg(byte unsigned addr);
    // For now, allow all 0x00–0xFF; sequences should enforce reset-only writes for BTR/ACC.
    return 1;
  endfunction

  // ---- Summary ----
  function string sprint();
    return $sformatf(
      "reg_cfg: mode=%s bus=%s trace=%0d checks=%0d cover=%0d dbg=%0d delays(ns){rnd=%0d def=%0d min=%0d max=%0d} setup/hold(ns){%0d/%0d} watchdog(cyc)=%0d inject=%0d rate=%0d%%",
      (is_active==UVM_ACTIVE) ? "ACTIVE":"PASSIVE",
      bus_name(), trace_ops, checks_enable, coverage_enable, debug_mode,
      random_delays, default_delay_ns, min_delay_ns, max_delay_ns,
      default_setup_time, default_hold_time,
      max_wait_cycles, inject_bus_errors, error_rate
    );
  endfunction

endclass : reg_agent_config

`endif // REG_AGENT_CONFIG_SV
