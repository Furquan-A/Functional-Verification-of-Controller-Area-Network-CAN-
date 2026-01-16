class can_env extends uvm_env;

  `uvm_component_utils(can_env)

  // AGENTS
  can_agent  c_agent[];
  reg_agent  r_agent[];

  can_scoreboard  c_sb;
  // can_virtual_sequencer can_vseqrh; // enable later when you’re ready
  can_env_config  m_cfg;

  function new(string name = "can_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(can_env_config)::get(this, "", "can_env_config", m_cfg))
      `uvm_fatal("ENV_CFG", "Cannot get can_env_config from config_db (key='can_env_config')")

    // ---------------- CAN agents ----------------
    if (m_cfg.has_can_agent) begin
      c_agent = new[m_cfg.no_of_can_agent];

      foreach (c_agent[i]) begin
        // Create agent with safe instance name (no brackets)
        c_agent[i] = can_agent::type_id::create($sformatf("c_agent%0d", i), this);

        // Set per-agent config into that agent scope (and its children)
        uvm_config_db#(can_agent_config)::set(
          this,
          $sformatf("c_agent%0d.*", i),
          "m_cfg",
          m_cfg.c_cfg[i]
        );
      end
    end

    // ---------------- REG agents ----------------
    if (m_cfg.has_reg_agent) begin
      r_agent = new[m_cfg.no_of_reg_agent];

      foreach (r_agent[i]) begin
        r_agent[i] = reg_agent::type_id::create($sformatf("r_agent%0d", i), this);

        uvm_config_db#(reg_agent_config)::set(
          this,
          $sformatf("r_agent%0d.*", i),
          "m_cfg",
          m_cfg.r_cfg[i]
        );
      end
    end

    // ---------------- Scoreboard ----------------
    if (m_cfg.has_can_scoreboard) begin
      c_sb = can_scoreboard::type_id::create("c_sb", this);
    end

    // Virtual sequencer/coverage can be enabled later after smoke passes
    // if (m_cfg.has_virtual_sequencer) begin
    //   can_vseqrh = can_virtual_sequencer::type_id::create("can_vseqrh", this);
    // end
  endfunction : build_phase

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect analysis ports to scoreboard
    if (c_sb != null) begin
      foreach (c_agent[i]) begin
        c_agent[i].mon_ap.connect(c_sb.obs_imp); // observed
        c_agent[i].drv_ap.connect(c_sb.exp_imp); // expected (what driver sent)
      end
    end

    // Enable later when you actually create can_vseqrh and define arrays inside it
    // if (can_vseqrh != null) begin
    //   foreach (r_agent[i]) can_vseqrh.reg_sqrs[i] = r_agent[i].seqrh;
    //   foreach (c_agent[i]) can_vseqrh.can_sqrs[i] = c_agent[i].seqrh;
    // end
  endfunction : connect_phase

endclass
