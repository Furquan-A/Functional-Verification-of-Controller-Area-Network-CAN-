`ifndef CAN_ARB_SMOKE_TEST_SV
`define CAN_ARB_SMOKE_TEST_SV

class can_arb_smoke_test extends uvm_test;
  `uvm_component_utils(can_arb_smoke_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  function new(string name="can_arb_smoke_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  // Good place to print topology
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("CAN_ARB_TEST", "Cannot get vif from config_db (key='vif')")

    // Create + setup env config
    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    // --------- 3 active CAN nodes ----------
    env_cfg.resize(3, 0);
    env_cfg.has_reg_agent = 0;

    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active  = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id    = i;

      // ACK behavior:
      // In real CAN: transmitter does NOT ACK itself; receivers ACK.
      // For arbitration smoke: let node1/node2 ACK; node0 (winner typically) no ACK.
      env_cfg.c_cfg[i].ack_enable = 1'b1;
      
      // Keep error injection OFF for arbitration bringup
      env_cfg.c_cfg[i].enable_error_injection = 1'b0;
      env_cfg.c_cfg[i].inject_crc_error       = 1'b0;
      env_cfg.c_cfg[i].inject_stuff_error     = 1'b0;
      env_cfg.c_cfg[i].inject_form_error      = 1'b0;
      env_cfg.c_cfg[i].inject_ack_error       = 1'b0;
    end

    // Keep scoreboard on
    env_cfg.has_can_scoreboard = 1;

    // Validate config
    begin
      string why;
      if (!env_cfg.validate(why))
        `uvm_fatal("CAN_ARB_TEST", {"env_cfg validate failed: ", why})
    end

    // Set env config
    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);

    // Create env
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
  
    can_std_smoke_tx_seq s0, s1, s2;
    uvm_event go;
    int timeout;
    phase.raise_objection(this);

    go = uvm_event_pool::get_global("ARB_GO");
    go.reset();
    
    // --------- Start 3 arbitration sequences (simultaneous) ----------
    // These sequences should use the global event "ARB_GO" to sync-start.
    s0 = can_std_smoke_tx_seq::type_id::create("s0");
    s1 = can_std_smoke_tx_seq::type_id::create("s1");
    s2 = can_std_smoke_tx_seq::type_id::create("s2");
    
    // Make sequences WAIT for the GO event (your seq must have use_go_event=1)
    s0.use_go_event = 1;
    s1.use_go_event = 1;
    s2.use_go_event = 1;
    
    // Choose IDs so arbitration has a clear winner:
    // Lower ID wins (dominant 0 overwrites recessive 1).
    //
    // Winner expected: node0 id=0x120 (lower than 0x123 and 0x12A)
    s0.can_fmt = `CAN_ID_STD;
    s0.id      = 29'h00000020;
    s0.dlc     = 4;
    s0.data    = '{8'h11, 8'h22, 8'h33, 8'h44};

    s1.can_fmt = `CAN_ID_STD;
    s1.id      = 29'h00000103;
    s1.dlc     = 4;
    s1.data    = '{8'hAA, 8'h55, 8'h0F, 8'hF0};

    s2.can_fmt = `CAN_ID_STD;
    s2.id      = 29'h00000012A;
    s2.dlc     = 4;
    s2.data    = '{8'hDE, 8'hAD, 8'hBE, 8'hEF};

    fork
      s0.start(m_env.c_agent[0].seqrh);
      s1.start(m_env.c_agent[1].seqrh);
      s2.start(m_env.c_agent[2].seqrh);
    join_none
    
    // Let them all reach wait_trigger(), then release them together
    // Wait until all 3 sequences are actually waiting
    timeout = 1000;
    while ((go.get_num_waiters() < 3) && (timeout > 0)) begin
      #1ns;
      timeout--;
    end
    
    `uvm_info("CAN_ARB_TEST",
              $sformatf("ARB_GO waiters before trigger = %0d", go.get_num_waiters()),
              UVM_LOW)
    
    if (go.get_num_waiters() < 3)
      `uvm_fatal("CAN_ARB_TEST", "Sequences did not reach wait_trigger() — waiters < 3")
    
    go.trigger();
    wait fork;
    
    // Let monitors decode EOF + scoreboard compare
    #300us;
    phase.drop_objection(this);
  endtask

endclass : can_arb_smoke_test

`endif // CAN_ARB_SMOKE_TEST_SV
