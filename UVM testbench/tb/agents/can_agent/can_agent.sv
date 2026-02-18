// agents/can_bus_agent/can_agent.sv
`ifndef CAN_AGENT_SV
`define CAN_AGENT_SV

`include "uvm_macros.svh"
import uvm_pkg::*;


class can_agent extends uvm_agent;
  `uvm_component_utils(can_agent)

  virtual can_if       vif;

  can_driver           drvh;
  can_monitor          monh;
  can_sequencer        seqrh;
  can_agent_config     c_cfg;

  // Agent-level analysis ports (to env/scoreboard)
  uvm_analysis_port #(can_transaction) drv_ap;
  uvm_analysis_port #(can_transaction) mon_ap;

  function new(string name = "can_agent", uvm_component parent = null);
    super.new(name, parent);
    drv_ap = new("drv_ap", this);
    mon_ap = new("mon_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Get config
    if (!uvm_config_db#(can_agent_config)::get(this, "", "m_cfg", c_cfg))
      `uvm_fatal("CAN_AGENT", "Cannot get() can_agent_config from config_db (key='m_cfg'). Did you set() it?")

    // Validate config early (optional but recommended)
    begin
      string reason;
      if (!c_cfg.validate(reason))
        `uvm_fatal("CAN_AGENT_CFG", reason)
    end

    // Cache vif for convenience (also keep in cfg)
    vif = c_cfg.vif;

    // Make cfg (and optionally vif) available to all children
    uvm_config_db#(can_agent_config)::set(this, "*", "m_cfg", c_cfg);
    uvm_config_db#(virtual can_if)::set(this, "*", "vif", vif);

    // Monitor is always present
    monh = can_monitor::type_id::create("monh", this);

    // Create driver/sequencer only if active
    if (c_cfg.is_active == UVM_ACTIVE) begin
      drvh  = can_driver::type_id::create("drvh", this);
      seqrh = can_sequencer::type_id::create("seqrh", this);
    end

    `uvm_info("CAN_AGENT",
              $sformatf("Built can_agent in %s mode (node_id=%0d). %s",
                        (c_cfg.is_active == UVM_ACTIVE) ? "ACTIVE" : "PASSIVE",
                        c_cfg.node_id,
                        c_cfg.sprint()),
              UVM_MEDIUM)
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect monitor analysis port to agent analysis port
    monh.ap.connect(mon_ap);

    // Active-only connections
    if (c_cfg.is_active == UVM_ACTIVE) begin
      drvh.seq_item_port.connect(seqrh.seq_item_export);
      drvh.ap.connect(drv_ap);
    end
  endfunction : connect_phase

endclass : can_agent

`endif // CAN_AGENT_SV
