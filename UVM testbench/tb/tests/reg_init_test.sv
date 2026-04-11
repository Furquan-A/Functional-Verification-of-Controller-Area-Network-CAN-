`ifndef REG_INIT_TEST_SV
`define REG_INIT_TEST_SV

// =============================================================================
// reg_init_test
// =============================================================================
// Runs ONLY reg_init_seq through the register agent.
// Use this for quick smoke-testing of the reg agent (driver/monitor/sequencer
// integration) without firing 500 random transactions.
//
// Expected behavior:
//   - DUT enters reset mode
//   - PeliCAN extended mode enabled (CDR=0x80)
//   - BTR/OCR/ACR/AMR/IER programmed
//   - DUT exits reset mode
//   - Final SR readback shows TBS=1 (TX buffer free ? DUT operational)
// =============================================================================

class reg_init_test extends uvm_test;
  `uvm_component_utils(reg_init_test)

  virtual can_if   vif;
  can_env          m_env;
  can_env_config   env_cfg;

  function new(string name = "reg_init_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("REG_INIT_TEST", "cannot get vif")

    // -- Env config: 0 CAN agents, 1 reg agent --
    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.has_can_agent      = 1'b0;
    env_cfg.has_can_scoreboard = 1'b0;
    env_cfg.has_reg_agent      = 1'b1;
    env_cfg.no_of_can_agent    = 0;
    env_cfg.no_of_reg_agent    = 1;

    // Allocate reg_agent_config
    env_cfg.r_cfg = new[1];
    env_cfg.r_cfg[0]            = reg_agent_config::type_id::create("r_cfg_0");
    env_cfg.r_cfg[0].vif        = vif;
    env_cfg.r_cfg[0].is_active  = UVM_ACTIVE;
    env_cfg.r_cfg[0].trace_ops  = 1'b1;

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);

    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    reg_init_seq init_seq;

    phase.raise_objection(this);

    `uvm_info("REG_INIT_TEST", "===== Starting REG INIT smoke test =====", UVM_LOW)

    init_seq = reg_init_seq::type_id::create("init_seq");
    init_seq.start(m_env.r_agent[0].rseqrh);

    #20us;

    `uvm_info("REG_INIT_TEST", "===== REG INIT smoke test COMPLETE =====", UVM_LOW)

    phase.drop_objection(this);
  endtask

endclass : reg_init_test

`endif // REG_INIT_TEST_SV