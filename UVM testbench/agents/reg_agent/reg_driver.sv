// agents/reg_agent/reg_driver.sv
`ifndef REG_DRIVER_SV
`define REG_DRIVER_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_driver extends uvm_driver #(reg_txn);
  `uvm_component_utils(reg_driver)

  // Config + unified interface (WB/Legacy hidden behind can_if)
  reg_agent_config m_cfg;
  virtual can_if   vif;

  // Simple counters (optional)
  int unsigned wr_cnt, rd_cnt;

  function new(string name="reg_driver", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  // Get config once, cache the VIF
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(reg_agent_config)::get(this, "", "m_cfg", m_cfg))
      `uvm_fatal("REG_DRV", "reg_agent_config not found (key='m_cfg')")

    string why;
    if (!m_cfg.validate(why))
      `uvm_fatal("REG_DRV", $sformatf("Invalid reg_agent_config: %s", why))

    vif = m_cfg.vif;

    `uvm_info("REG_DRV",
      $sformatf("Driver ready on %s bus", m_cfg.bus_name()),
      UVM_LOW)
  endfunction

  // Minimal main loop: get item -> do op -> item_done
  task run_phase(uvm_phase phase);
    reg_txn t;
    forever begin
      seq_item_port.get_next_item(t);

      if (t.is_write()) begin
        vif.reg_write(t.addr, t.wdata);
        wr_cnt++;
        if (m_cfg.trace_ops)
          `uvm_info("REG_DRV",
            $sformatf("[%s] WR @0x%02h = 0x%02h",
                      vif.USE_WB ? "WB":"LEG", t.addr, t.wdata),
            UVM_LOW)
      end
      else begin
        byte unsigned q;
        vif.reg_read(t.addr, q);
        t.rdata = q;
        rd_cnt++;
        if (m_cfg.trace_ops)
          `uvm_info("REG_DRV",
            $sformatf("[%s] RD @0x%02h -> 0x%02h",
                      vif.USE_WB ? "WB":"LEG", t.addr, t.rdata),
            UVM_LOW)
      end

      t.success = 1'b1; // keep simple; interface tasks fatal on timeout
      seq_item_port.item_done();
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("REG_DRV",
      $sformatf("Summary: writes=%0d reads=%0d", wr_cnt, rd_cnt),
      UVM_LOW)
  endfunction

endclass : reg_driver

`endif // REG_DRIVER_SV
