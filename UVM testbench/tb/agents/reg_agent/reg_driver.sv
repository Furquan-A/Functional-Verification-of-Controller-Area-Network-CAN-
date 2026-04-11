`ifndef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_driver extends uvm_driver #(reg_transaction);

  `uvm_component_utils(reg_driver)

  // Single config handle
  reg_agent_config m_cfg;

  // virtual Interface
  virtual can_if vif;

  extern function new(string name = "reg_driver", uvm_component parent);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);
  extern task send_to_dut(reg_transaction req);

endclass : reg_driver

// ================================== new ==============================================================

function reg_driver::new(string name = "reg_driver", uvm_component parent);
  super.new(name, parent);
endfunction

// ================================= build_phase =======================================================

function void reg_driver::build_phase(uvm_phase phase);
  string why;
  super.build_phase(phase);

  // FIX 1: correct config_db::get arg order (this, instance, field, var)
  if (!uvm_config_db#(reg_agent_config)::get(this, "", "m_cfg", m_cfg))
    `uvm_fatal("REG_DRV", "Cannot get reg_agent_config from config_db (key='m_cfg'). Did you set it?")

  // sanity check config
  if (!m_cfg.validate(why))
    `uvm_fatal("REG_DRV", $sformatf("Invalid reg_agent_config: %s", why))

  // Cache Virtual Interface
  vif = m_cfg.vif;
  if (vif == null)
    `uvm_fatal("REG_DRV", "vif is null in the reg_driver")

  `uvm_info("REG_DRV",
    $sformatf("Driver ready on %s bus (trace_ops=%0b)", m_cfg.bus_name(), m_cfg.trace_ops),
    UVM_LOW)
endfunction

// ====================== run_phase ======================================================================

task reg_driver::run_phase(uvm_phase phase);
  reg_transaction req;
  `uvm_info("REG_DRV", "reg_driver started run_phase", UVM_LOW)

  forever begin
    // 1. block until the sequencer sends us a transaction
    // FIX 2: typo start_item_port -> seq_item_port
    seq_item_port.get_next_item(req);

    // call the send_to_dut method to perform the operation
    send_to_dut(req);

    // FIX 3: item_done() takes no argument
    seq_item_port.item_done();
  end
endtask

// ============================== send_to_dut ==========================================================

task reg_driver::send_to_dut(reg_transaction req);
  byte unsigned q;

  req.t_start = $time;

  if (req.is_write()) begin
    vif.reg_write(req.addr, req.wdata);
    m_cfg.wr_cnt++;
    if (m_cfg.trace_ops)
      `uvm_info("REG_DRV",
        $sformatf("[%s] WR @0x%02h = 0x%02h",
                  vif.USE_WB ? "WB" : "LEG", req.addr, req.wdata),
        UVM_LOW)
  end
  else begin
    vif.reg_read(req.addr, q);
    req.rdata = q;
    m_cfg.rd_cnt++;
    if (m_cfg.trace_ops)
      `uvm_info("REG_DRV",
        $sformatf("[%s] RD @0x%02h -> 0x%02h",
                  vif.USE_WB ? "WB" : "LEG", req.addr, req.rdata),
        UVM_LOW)
  end

  req.t_end = $time;
  req.success = 1'b1;
endtask

`endif // REG_DRIVER_SV