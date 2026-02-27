`ifndef CAN_DUT_INIT_TEST_SV
`define CAN_DUT_INIT_TEST_SV

class can_dut_init_test extends uvm_test;
  `uvm_component_utils(can_dut_init_test)

  virtual can_if #(.NUM_TB_NODES(3)) vif;
  can_env        m_env;
  can_env_config env_cfg;

  function new(string name="can_dut_init_test", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if(!uvm_config_db#(virtual can_if #(.NUM_TB_NODES(3)))::get(this,"","vif",vif))
      `uvm_fatal("DUT_INIT_TEST","cannot get vif")

    env_cfg     = can_env_config::type_id::create("env_cfg");
    env_cfg.vif = vif;

    env_cfg.resize(2, 0);
    env_cfg.has_can_scoreboard = 0;

    foreach(env_cfg.c_cfg[i]) begin
      env_cfg.c_cfg[i].is_active              = UVM_ACTIVE;
      env_cfg.c_cfg[i].node_id               = i;
      env_cfg.c_cfg[i].enable_special_decode = 0;
      env_cfg.c_cfg[i].special_decode_idle   = 0;
      env_cfg.c_cfg[i].special_decode_ifs    = 0;
      env_cfg.c_cfg[i].publish_special_frames= 0;
      env_cfg.c_cfg[i].expect_no_ack         = 0;
      env_cfg.c_cfg[i].ack_enable            = 1'b1;
    end

    uvm_config_db#(can_env_config)::set(this,"m_env","can_env_config",env_cfg);
    m_env = can_env::type_id::create("m_env", this);
  endfunction

  task run_phase(uvm_phase phase);
    can_dut_init_seq init_seq;

    phase.raise_objection(this);

    init_seq     = can_dut_init_seq::type_id::create("init_seq");
    init_seq.vif = vif;
    init_seq.start(null);  // no sequencer needed — directly drives vif

    #10us;
    phase.drop_objection(this);
  endtask

endclass
`endif
