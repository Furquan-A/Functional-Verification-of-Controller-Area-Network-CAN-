+incdir+../rtl
+incdir+../tb/interfaces
+incdir+../tb/pkg
+incdir+../tb/agents
+incdir+../tb/env
+incdir+../tb/sequences
+incdir+../tb/tests
# ===================== RTL =====================
../rtl/timescale.v
../rtl/can_defines.v
../rtl/can_acf.v
../rtl/can_bsp.v
../rtl/can_btl.v
../rtl/can_crc.v
../rtl/can_fifo.v
../rtl/can_ibo.v
../rtl/can_register.v
../rtl/can_register_asyn.v
../rtl/can_register_asyn_syn.v
../rtl/can_register_syn.v
../rtl/can_registers.v
../rtl/can_top.v

# ===================== TB: Interfaces =====================
../tb/interfaces/can_if.sv

# ===================== TB: Packages =====================
../tb/pkg/can_pkg.sv
../tb/pkg/can_defines.sv

# ===================== TB: Agents =====================
../tb/agents/reg_agent/reg_transaction.sv
../tb/agents/reg_agent/reg_agent_config.sv
../tb/agents/reg_agent/reg_driver.sv
../tb/agents/reg_agent/reg_monitor.sv
../tb/agents/reg_agent/reg_sequencer.sv
../tb/agents/reg_agent/reg_agent.sv

../tb/agents/can_agent/can_transaction.sv
../tb/agents/can_agent/can_agent_config.sv
../tb/agents/can_agent/can_driver.sv
../tb/agents/can_agent/can_monitor.sv
../tb/agents/can_agent/can_sequencer.sv
../tb/agents/can_agent/can_agent.sv

# ===================== TB: Environment =====================
../tb/env/can_scoreboard.sv
../tb/env/can_env_config.sv
../tb/env/can_env.sv
../tb/env/can_virtual_sequencer.sv

# ===================== TB: Sequences =====================
../tb/sequences/can_tx_seq.sv
../tb/sequences/reg_sequence.sv

# ===================== TB: Tests =====================
../tb/tests/can_smoke_test.sv
../tb/tests/reg_smoke_test.sv

# ===================== TB: Top =====================
../tb/top/can_top_tb.sv
