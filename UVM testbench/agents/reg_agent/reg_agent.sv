class reg_agent extends uvm_component;
`uvm_component_utils(reg_agent);

virtual can_if vif;

reg_driver        rdrvh;
reg_monitor       rmonh;
reg_sequencer     rseqrh;
reg_agent_config  m_cfg;


