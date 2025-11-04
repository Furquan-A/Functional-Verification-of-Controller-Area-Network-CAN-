typedef enum int {REG_BUS_AUTO = 0, REG_BUS_WB = 1, REG_BUS_LEGACY = 2} reg_bus_e;

class reg_agent_config extends uvm_objects;
`uvm_objects_utils(reg_agent_config)

uvm_active_passive_enum is_active = UVM_ACTIVE;  
 
rand reg_bus_e bus = REG_BUS_AUTO;

virtual can_if vif; // single handle for the can_if
bit checks_enable;
bit coverage_enable;
bit debug_mode;
time total_latency = 0;
time min_latency = 0;
time max_latency = 0;
int unsigned num_writes = 0; // writes count 
int unsigned num_reads = 0; // reads count 
int unsigned num_errors = 0; // errors count 




// tracing knobs (optional) but extremely helpful for the debugging while running the tb 
// trace_op tells the reg_driver and reg_monitor whether to print register operations
// rd_timeout ets a maximum number of bus cycles the driver will wait for a read acknowledgment (ACK).
rand  bit trace_op = 1'b1;
rand int unsigned rd_timeout = 1000; // driver can enforce a max retries/timeouts if needed

function new (string name = "reg_agent_config");
super.new(name);
endfunction 

/* VALIDATE ( Sanity - checker) 
--> a small helper inside a config class that double-checks your configuration 
	before simulation proceeds.
	*/
function bit validate(ref string why);
if (vif == null) begin 
	why = "can_if vif is null";
	return 0;
end 

//if user insists on the bus kind, check against interface banner 

bit use_wb = vif.USE_WB; // local param from the interface model 
if(expected_bus == REG_BUS_WB && ! use_wb) begin 
	why  = " expected WISHBONE but interface compiled in Legacy mode " ;
	return 0;
end 

if (expected_bus == REG_BUS_LEGACY && use_wb) begin 
	why = " expected Legacy but the interface compiled in wishbone mode";
	return 0;
end 
return 1;
endfunction

function string bus_name();
bit use_wb == (vif != null) ? vif.USE_WB : 1'bx;
return use_eb ? "WISHBONE" : "LEGACY";
endfunction

function string sprint();
return $sformatf("reg_cfg: bus=%s, trace=%0d, rd_timeout=%0d",
                     bus_name(), trace_ops, rd_timeout);
  endfunction
endclass


