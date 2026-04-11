`ifndef REG_MONITOR_SV
`define REG_MONITOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_monitor extends uvm_component;
  `uvm_component_utils(reg_monitor)

  uvm_analysis_port #(reg_transaction) ap;

  virtual can_if      vif;
  reg_agent_config    m_cfg;

  extern function new(string name = "reg_monitor", uvm_component parent);
  extern function void build_phase(uvm_phase phase);
  extern task run_phase(uvm_phase phase);

endclass : reg_monitor

// ================================== new ==================================

function reg_monitor::new(string name = "reg_monitor", uvm_component parent);
  super.new(name, parent);
  ap = new("ap", this);
endfunction

// ================================ build_phase ==============================

function void reg_monitor::build_phase(uvm_phase phase);
  super.build_phase(phase);

  if (!uvm_config_db#(reg_agent_config)::get(this, "", "m_cfg", m_cfg))
    `uvm_fatal("REG_MON", "reg_agent_config not found in config_db (key='m_cfg')")

  vif = m_cfg.vif;
  if (vif == null)
    `uvm_fatal("REG_MON", "vif is null in reg_monitor")

  `uvm_info("REG_MON",
    $sformatf("Monitor ready on %s bus", m_cfg.bus_name()),
    UVM_LOW)
endfunction

// ================================ run_phase ================================

task reg_monitor::run_phase(uvm_phase phase);
  reg_transaction t;

  `uvm_info("REG_MON", "reg_monitor started run_phase", UVM_LOW)

  forever begin

`ifdef CAN_WISHBONE_IF
    // ============== WISHBONE MODE ==============
    @(posedge vif.wb_clk_i);

    // Detect a completed bus cycle: cyc + stb + ack all high
    if (vif.wb_cyc_i && vif.wb_stb_i && vif.wb_ack_o) begin
      t = reg_transaction::type_id::create("t");
      t.addr    = vif.wb_adr_i;
      t.success = 1'b1;
      t.t_start = $time;
      t.t_end   = $time;

      if (vif.wb_we_i) begin
        t.kind  = REG_WRITE;
        t.wdata = vif.wb_dat_i;
      end
      else begin
        t.kind  = REG_READ;
        t.rdata = vif.wb_dat_o;
      end

      ap.write(t);

      if (m_cfg.trace_ops)
        `uvm_info("REG_MON",
          $sformatf("[WB] %s @0x%02h data=0x%02h",
                    t.kind.name(), t.addr,
                    (t.kind == REG_WRITE) ? t.wdata : t.rdata),
          UVM_HIGH)
    end

`else
    // ============== LEGACY MODE ==============
    // ALE rising edge latches the address; then RD or WR strobe gives data
    @(posedge vif.clk_i);

    // Sample WRITE: cs + wr both active
    if (vif.cs_can_i && vif.wr_i) begin
      t = reg_transaction::type_id::create("t");
      t.kind    = REG_WRITE;
      t.addr    = vif.port_0_io;   // address was latched on ALE
      t.wdata   = vif.port_0_io;   // data on bus during WR
      t.success = 1'b1;
      t.t_start = $time;
      t.t_end   = $time;
      ap.write(t);

      if (m_cfg.trace_ops)
        `uvm_info("REG_MON",
          $sformatf("[LEG] WR @0x%02h = 0x%02h", t.addr, t.wdata),
          UVM_HIGH)
    end

    // Sample READ: cs + rd both active
    if (vif.cs_can_i && vif.rd_i) begin
      t = reg_transaction::type_id::create("t");
      t.kind    = REG_READ;
      t.addr    = vif.port_0_io;
      t.rdata   = vif.port_0_io;
      t.success = 1'b1;
      t.t_start = $time;
      t.t_end   = $time;
      ap.write(t);

      if (m_cfg.trace_ops)
        `uvm_info("REG_MON",
          $sformatf("[LEG] RD @0x%02h -> 0x%02h", t.addr, t.rdata),
          UVM_HIGH)
    end
`endif

  end // forever
endtask

`endif // REG_MONITOR_SV