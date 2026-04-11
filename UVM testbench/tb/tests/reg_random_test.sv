`ifndef REG_RANDOM_TEST_SV
`define REG_RANDOM_TEST_SV

// =============================================================================
// reg_random_test
// =============================================================================
// Runs:
//   1. reg_init_seq    — puts DUT in PeliCAN extended mode
//   2. reg_random_seq  — fires N random read/writes to register space
//
// This single test exercises:
//   - i_can_registers (line/cond/toggle)
//   - can_register_syn (currently 0%)
//   - i_ibo_tx_data_* (TX buffer write paths)
//   - Register decode logic in can_top
// =============================================================================

class reg_random_test extends uvm_test;
  `uvm_component_utils(reg_random_test)

  virtual can_if   vif;
  can_env          m_env;
  can_env_config   env_cfg;

  // Knob — number of random transactions
  int unsigned n_txns = 500;

  function new(string name = "reg_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("REG_RAND_TEST", "cannot get vif")

    // -- Env config --
    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // 0 CAN agents, 1 reg agent
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
    reg_init_seq    init_seq;
    reg_random_seq  rand_seq;

    phase.raise_objection(this);

    // -- Step 1: Init DUT via reg agent --
    init_seq = reg_init_seq::type_id::create("init_seq");
    init_seq.start(m_env.r_agent[0].rseqrh);

    // -- Step 2: Random reg traffic --
    rand_seq = reg_random_seq::type_id::create("rand_seq");
    rand_seq.n_txns = n_txns;
    if (!rand_seq.randomize() with { n_txns == local::n_txns; })
      `uvm_fatal("REG_RAND_TEST", "rand_seq randomize failed")
    rand_seq.start(m_env.r_agent[0].rseqrh);

    #50us;
    phase.drop_objection(this);
  endtask

endclass : reg_random_test

`endif // REG_RANDOM_TEST_SV