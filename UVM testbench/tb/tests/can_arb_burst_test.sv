`ifndef CAN_ARB_BURST_TEST_SV
`define CAN_ARB_BURST_TEST_SV

class can_arb_burst_test extends uvm_test;
  `uvm_component_utils(can_arb_burst_test)

  can_env        m_env;
  can_env_config env_cfg;
  virtual can_if vif;

  localparam int unsigned NUM_NODES  = 3;
  localparam int unsigned NUM_ROUNDS = 10;

  function new(string name="can_arb_burst_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual can_if)::get(this, "", "vif", vif))
      `uvm_fatal("ARB_BURST_TEST", "Cannot get vif from config_db (key='vif')")

    env_cfg = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(NUM_NODES, 0);
    env_cfg.has_reg_agent = 0;
    env_cfg.has_can_scoreboard = 1;
    


    foreach (env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active  = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id    = i;

      // ACK: allow receivers to ACK.
      // If your monitor uses is_tx_in_progress gating, this is safe even if all are active.
      env_cfg.c_cfg[i].ack_enable = 1'b1;
      env_cfg.c_cfg[i].enable_special_decode  = 0;
    env_cfg.c_cfg[i].publish_special_frames = 0;  
    end

    begin
      string why;
      if (!env_cfg.validate(why))
        `uvm_fatal("ARB_BURST_TEST", {"env_cfg validate failed: ", why})
    end

    uvm_config_db#(can_env_config)::set(this, "m_env", "can_env_config", env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);

  localparam int unsigned NUM_NODES  = 3;
  localparam int unsigned NUM_ROUNDS = 4;

  can_arb_burst_seq seqs[NUM_NODES];
  uvm_event go;

  phase.raise_objection(this);

  go = uvm_event_pool::get_global("ARB_GO");
  // go.reset();  // <-- REMOVE THIS

  // start sequences
  for (int n = 0; n < NUM_NODES; n++) begin
    automatic int nn = n;

    seqs[nn] = can_arb_burst_seq::type_id::create($sformatf("seq_node%0d", nn));
    seqs[nn].node_id    = nn;
    seqs[nn].num_rounds = NUM_ROUNDS;

    seqs[nn].ids_per_round = new[NUM_ROUNDS];
    for (int r = 0; r < NUM_ROUNDS; r++) begin
      int unsigned winner = (r % NUM_NODES);
      if (nn == winner)
        seqs[nn].ids_per_round[r] = 29'h00000100 + r;
      else
        seqs[nn].ids_per_round[r] = 29'h00000180 + (nn*8) + r;
    end

    seqs[nn].payload = '{ byte'(8'hA0 + nn), byte'(8'h10 + nn) };

    fork
      begin
        seqs[nn].start(m_env.c_agent[nn].seqrh);
      end
    join_none
  end

  #1us; // fine

  // trigger rounds (NO reset)
  for (int r = 0; r < NUM_ROUNDS; r++) begin
    `uvm_info("ARB_BURST_TEST", $sformatf("=== ROUND %0d GO ===", r), UVM_LOW)
    go.trigger();
    #300us;
  end

  wait fork;

  #200us;
  phase.drop_objection(this);
endtask



endclass : can_arb_burst_test

`endif // CAN_ARB_BURST_TEST_SV
