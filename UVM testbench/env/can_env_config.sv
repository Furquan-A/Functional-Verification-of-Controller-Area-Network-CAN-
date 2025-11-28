class can_env_config extends uvm_config;

	`uvm_object_utils(can_env_config)
	
	bit has_can_agent         = 1;
	bit has_reg-agent         = 1;
	bit has_can_scoreboard    = 1;
	bit has_virtual_sequencer = 1;
	bit has_can_coverage      = 1;
	
	int no_of_can_agent = [$];
	int no_of_reg_agent = [$];
	
	can_agent_config c_cfg[];
	reg_agent_config r_cfg[];
	
	extern function new(string name = "can_env_config");
endclass 

function can_env_config::new(string name = "can_env_config");
	super.new(name);
endfunction 
