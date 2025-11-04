// src/can_config.sv (minimal reg_agent_config for simple driver)
`ifndef REG_AGENT_CONFIG_SV
`define REG_AGENT_CONFIG_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum int { REG_BUS_AUTO=0, REG_BUS_WB=1, REG_BUS_LEGACY=2 } reg_bus_e;

class reg_agent_config extends uvm_object;
  `uvm_object_utils(reg_agent_config)

  // Agent mode (so your reg_agent can honor it)
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  // Unified interface (works for WB or Legacy)
  virtual can_if vif;

  // Optional: expected bus (for sanity/logs; can leave AUTO)
  rand reg_bus_e expect_bus = REG_BUS_AUTO;

  // Simple tracing toggle used by the driver
  rand bit trace_ops = 1'b1;

  function new(string name="reg_agent_config");
    super.new(name);
  endfunction

  // Check vif presence and optional bus expectation
  function bit validate(ref string why);
    if (vif == null) begin
      why = "can_if vif is null"; return 0;
    end
    bit use_wb = vif.USE_WB;
    if (expect_bus == REG_BUS_WB     && !use_wb) begin
      why = "Expected WISHBONE but interface is LEGACY"; return 0;
    end
    if (expect_bus == REG_BUS_LEGACY &&  use_wb) begin
      why = "Expected LEGACY but interface is WISHBONE"; return 0;
    end
    return 1;
  endfunction

  // Pretty name for logs
  function string bus_name();
    if (vif == null) return "UNKNOWN";
    return vif.USE_WB ? "WISHBONE" : "LEGACY";
  endfunction

  // Optional summary
  function string sprint();
    return $sformatf("reg_cfg: mode=%s bus=%s trace=%0d",
                     (is_active==UVM_ACTIVE) ? "ACTIVE" : "PASSIVE",
                     bus_name(), trace_ops);
  endfunction
endclass : reg_agent_config

`endif // REG_AGENT_CONFIG_SV
