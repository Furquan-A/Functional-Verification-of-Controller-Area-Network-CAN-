class can_env extends uvm_env;

	`uvm_component_utils(can_env)
	
	virtual can_if vif; // Virtual Interface 
	
	// AGENTS 
	
	can_agent c_agent[]; 
	reg_agent r_agent[];
	
	can_scoreboard c_sb;
	// can_virtual_sequencer can_vseqrh;
	can_env_config m_cfg;
	// can_coverage c_cvg;
	
	extern function new(string name = "can_env", uvm_component parent);
	extern function void build_phase(uvm_phase phase);
	extern function void connect_phase(uvm_phase phase);
	
endclass

// ========================================================================================
// ============================ new =======================================================

function can_env :: new (string name = "can_env", uvm_component parent);
	super.new(name,parent);
endfunction 

// ========================================================================================
// ============================== build_phase =============================================

function void can_env :: build_phase (uvm_phase phase);
	super.build_phase(phase);
	
	if(!uvm_config_db#(can_env_config)::get(this,"","can_env_config",m_cfg))
		`uvm_fatal("ENV CONFIG","cannot get() the config from the config_db. did you set() it ?")
	
	if(m_cfg.has_can_agent)
		c_agent = new[m_cfg.no_of_can_agent];
		begin 
			foreach(c_agent[i])
				begin 
					c_agent[i] = can_agent::type_id::create($sformatf("c_agent%0d",i),this);
					// set per-agent config into that agent scope ( and its children )
					uvm_config_db#(can_agent_config)::set(this,$sformatf("c_agent%0d.*",i),"m_cfg",m_cfg.c_cfg[i]);
				end 
		end 
		
	if(m_cfg.has_reg_agent)
		begin 
			r_agent = new[m_cfg.no_of_reg_agent];
			foreach(r_agent[i])
				begin 
					r_agent[i] = reg_agent::type_id::create($sformatf("r_agent[%0d]",i),this);
					uvm_config_db#(reg_agent_config)::set(this,$sformatf("r_agent[%0d]*",i),"m_cfg",m_cfg.r_cfg[i]);
				end 
		end 
		/*
	if(m_cfg.has_can_coverage)
		begin 
			c_cvg = can_coverage::type_id::create("can_coverage",this);
		end 
	*/
	if(m_cfg.has_can_scoreboard)
		begin 
			c_sb = can_scoarboard::type_id::create("c_sb",this);
		end 
	/*
	if(m_cfg.has_virtual_sequencer)
		begin 
			can_vseqrh = can_virtaul_sequencer :: type_id::create("can_virtaul_sequencer",this);
		end 
		*/
endfunction : build_phase 

// ========================================================================================
// ============================== connect_phase ===========================================

function void can_env::connect_phase(uvm_phase phase);
	super.connect_phase(phase);
	
	if(c_sb != null)
		begin 
			foreach(c_agent[i])
				// Observed CAN frames → scoreboard
				c_agent[i].mon_ap.connect(c_sb.obs_imp); 
			foreach(c_agent[i])
				// Expected CAN frames → scoreboard
				c_agent[i].drv_ap.connect(c_sb.exp_imp);
		end 
		
	if(can_vseqrh != null)
		begin 
			foreach(r_agent[i])
				can_vseqrh.reg_sqrs[i] = r_agent[i].rseqrh;
			foreach 
				can_vseqrh.can_sqrs[i] = c_agent[i].cseqrh;
		end 
		
endfunction 

// =======================================================================================