class can_env_config extends uvm_object;

	`uvm_object_utils(can_env_config)
	
	bit has_can_agent         = 1;
	bit has_reg_agent         = 1;
	bit has_can_scoreboard    = 1;
	bit has_virtual_sequencer = 1;
	bit has_can_coverage      = 1;
	
	int unsigned no_of_can_agent = 1;
	int unsigned no_of_reg_agent = 1;
	
	can_agent_config c_cfg[];
	reg_agent_config r_cfg[];
	
	virtual can_if vif;
	
	extern function new(string name = "can_env_config");
	extern function void resize(int unsigned n_can, int unsigned n_reg);
	extern function bit validate(ref string why);
	
endclass 

// ================================== new ====================================================

function can_env_config::new(string name = "can_env_config");
	super.new(name);
endfunction 

// ==========================================================================================
// ======================== resize() ========================================================

function void can_env_config :: resize(int unsigned n_can, int unsigned n_reg);

	no_of_can_agent = n_can;
	no_of_reg_agent = n_reg;
	
	c_cfg = new[no_of_can_agent];
	foreach(c_cfg[i])
		begin 	
			c_cfg = can_agent_config::type_id::create($sformatf("c_cfg[%0d]",i));
		end 
	
	r_cfg = new[no_of_reg_agent];
	foreach(r_cfg[i])
		begin 
			r_cfg[i] = reg_agent_config::type_id::create($sformatf("r_cfg[%0d]",i));
		end 
endfunction : resize

// ===========================================================================================
// ============================= Validate ====================================================

function bit can_env_config::validate(ref string why);
	if(has_can_agent && (c_cfg.size() != no_of_can_agent))
		begin 
			why = "c_cfg size mismatch";
			return 0;
		end 
	
	if(has_reg_agent && (r_cfg.size() != no_of_reg_agent))
		begin 
			why = "r_cfg size mismatch";
			return 0;
		end
		
	// basic VIF presence: each agent should have a vif
    if (has_can_agent) 
		foreach (c_cfg[i]) 
			if (c_cfg[i].vif == null) 
				begin
					why = $sformatf("c_cfg[%0d].vif is null", i);
					return 0;
				end
				
	if (has_reg_agent) 
		foreach(r_cfg[i]) 
			if (r_cfg[i].vif == null) 
				begin
					why = $sformatf("r_cfg[%0d].vif is null", i); 
					return 0;
				end 
	return 1;
	
endfunction : validate 