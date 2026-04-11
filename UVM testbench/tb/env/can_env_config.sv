class can_env_config extends uvm_object;

  `uvm_object_utils(can_env_config)

  bit has_can_agent         = 1;
  bit has_reg_agent         = 0;
  bit has_can_scoreboard    = 1;
  bit has_virtual_sequencer = 0; // enable later
  bit has_can_coverage      = 0;

  int unsigned no_of_can_agent = 1;
  int unsigned no_of_reg_agent = 0;

  can_agent_config c_cfg[];
  reg_agent_config r_cfg[];

  virtual can_if vif;

  function new(string name = "can_env_config");
    super.new(name);
  endfunction

  // --------------------------------------------------------------------------
  // resize(): allocate and initialize per-agent configs
  // --------------------------------------------------------------------------
  function void resize(int unsigned n_can, int unsigned n_reg);

    no_of_can_agent = n_can;
   // no_of_reg_agent = n_reg;

    // ---------------- CAN agent configs ----------------
    if (has_can_agent) begin
      c_cfg = new[no_of_can_agent];
      foreach (c_cfg[i]) begin
        c_cfg[i] = can_agent_config::type_id::create($sformatf("c_cfg_%0d", i));
        c_cfg[i].node_id = i;   // CRITICAL
        c_cfg[i].vif     = vif; // propagate interface
      end
    end

    // ---------------- REG agent configs ----------------
   if (has_reg_agent) begin
      r_cfg = new[no_of_reg_agent];
      foreach (r_cfg[i]) begin
        r_cfg[i] = reg_agent_config::type_id::create($sformatf("r_cfg_%0d", i));
        r_cfg[i].vif = vif;
      end
    end
  endfunction : resize

  // --------------------------------------------------------------------------
  // validate(): sanity checks before build
  // --------------------------------------------------------------------------
  function bit validate(ref string why);

    if (has_can_agent && (c_cfg.size() != no_of_can_agent)) begin
      why = "c_cfg size mismatch";
      return 0;
    end

   // if (has_reg_agent && (r_cfg.size() != no_of_reg_agent)) begin
    //  why = "r_cfg size mismatch";
    //  return 0;
   // end

    if (has_can_agent) begin
      foreach (c_cfg[i]) begin
        if (c_cfg[i].vif == null) begin
          why = $sformatf("c_cfg[%0d].vif is null", i);
          return 0;
        end
        if (c_cfg[i].node_id != i) begin
          why = $sformatf("c_cfg[%0d].node_id mismatch (expected %0d)", i, i);
          return 0;
        end
      end
    end

    //if (has_reg_agent) begin
    //  foreach (r_cfg[i]) begin
     //   if (r_cfg[i].vif == null) begin
      //    why = $sformatf("r_cfg[%0d].vif is null", i);
      //    return 0;
      //  end
     // end
   // end

    return 1;
  endfunction : validate

endclass
