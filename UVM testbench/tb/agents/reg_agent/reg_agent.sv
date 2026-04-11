`ifndef REG_AGENT_SV
`define REG_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class reg_agent extends uvm_agent;
  `uvm_component_utils(reg_agent)

  // Cached virtual interface (also lives in m_cfg.vif)
  virtual can_if   vif;

  // ---- Agent components ----
  reg_driver       rdrvh;
  reg_monitor      rmonh;
  reg_sequencer    rseqrh;
  reg_agent_config m_cfg;

  // Agent-level analysis port (re-exposes monitor's ap)
  uvm_analysis_port #(reg_transaction) ap;

  function new(string name = "reg_agent", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  // ============================ build_phase ============================
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get config from db
    if (!uvm_config_db#(reg_agent_config)::get(this, "", "m_cfg", m_cfg))
      `uvm_fatal("REG_AGENT",
        "Cannot get reg_agent_config from config_db (key='m_cfg'). Did you set it?")

    // Validate
    begin
      string why;
      if (!m_cfg.validate(why))
        `uvm_fatal("REG_AGENT_CFG", why)
    end

    // Cache vif for convenience
    vif = m_cfg.vif;

    // Propagate config (and vif) down to children
    uvm_config_db#(reg_agent_config)::set(this, "*", "m_cfg", m_cfg);
    uvm_config_db#(virtual can_if)::set(this, "*", "vif", vif);

    // Monitor is always created (active or passive)
    rmonh = reg_monitor::type_id::create("rmonh", this);

    // Driver + sequencer only if active
    if (m_cfg.is_active == UVM_ACTIVE) begin
      rdrvh  = reg_driver::type_id::create("rdrvh", this);
      rseqrh = reg_sequencer::type_id::create("rseqrh", this);
    end

    `uvm_info("REG_AGENT",
      $sformatf("Built reg_agent in %s mode on %s bus",
                (m_cfg.is_active == UVM_ACTIVE) ? "ACTIVE" : "PASSIVE",
                m_cfg.bus_name()),
      UVM_MEDIUM)
  endfunction : build_phase

  // ============================ connect_phase ==========================
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Re-expose monitor analysis port at agent level
    rmonh.ap.connect(ap);

    // Connect driver to sequencer if active
    if (m_cfg.is_active == UVM_ACTIVE) begin
      rdrvh.seq_item_port.connect(rseqrh.seq_item_export);
    end

    `uvm_info("REG_AGENT", "Connected reg_agent components", UVM_HIGH)
  endfunction : connect_phase

endclass : reg_agent

`endif // REG_AGENT_SV