VERILATOR = verilator

# -------------------------- 通用配置 --------------------------
clean:
	rm -rf obj_dir sim ./*.vcd
	rm -f obj_dir/Vtop obj_dir/VysyxSoCFull
.PHONY: all run run1 run2 wave wave1 wave2 clean


# -------------------------- 默认目标（第二份配置） --------------------------
run: run2
wave: wave2


# -------------------------- 第一份配置（显式用 make run1/wave1） --------------------------
run1: TOP_MODULE = top
# 移除 --trace 选项关闭波形生成
run1: VERILATOR_FLAGS = -Wall -j 0 --cc --exe --build \
        --top-module $(TOP_MODULE) \
        --Mdir obj_dir \
        -Wno-fatal
run1: VERILOG_SRC = vsrc_test/*.v
run1: CPP_SRC = csrc_copy/main.cpp
run1: C_SRC = $(shell ls csrc/*.c | grep -v "memory_load.c")
run1: EXE = obj_dir/V$(TOP_MODULE)
run1:
	mkdir -p sim
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILOG_SRC) $(CPP_SRC) $(C_SRC)
	./$(EXE)

wave1: WAVE_FILE = sim/wave_top.vcd
wave1: WAVE_FILE_LAYOUT = wave_layout/wave_top_config.gtkw
wave1:
	@if [ -f $(WAVE_FILE) ]; then \
		gtkwave $(WAVE_FILE) $(WAVE_FILE_LAYOUT); \
	else \
		echo "Error: 第一份配置波形文件不存在（已关闭波形生成）"; \
	fi


# -------------------------- 第二份配置（默认用 make run/wave 或显式 make run2/wave2） --------------------------
run2: TOP_MODULE = ysyxSoCFull
# 移除 --trace 选项关闭波形生成
run2: VERILATOR_FLAGS = -Wall -j 0 --cc --exe --build \
        --top-module $(TOP_MODULE) \
        --Mdir obj_dir \
        -Wno-fatal \
        --timescale "1ns/1ns" \
        --no-timing \
        -I../ysyxSoC/perip/uart16550/rtl \
        -I../ysyxSoC/perip/spi/rtl
run2: VERILOG_NPC = ysyx_25080207/*.v
run2: VERILOG_SOC = \
        $(shell find ../ysyxSoC/perip -name "*.v" -print0 | xargs -0) \
        ../ysyxSoC/ready-to-run/D-stage/ysyxSoCFull.v
run2: VERILOG_SRC = $(VERILOG_NPC) $(VERILOG_SOC)
run2: CPP_SRC = csrc/main.cpp
run2: C_SRC = $(shell ls csrc/*.c | grep -v "memory_load.c")
run2: EXE = obj_dir/V$(TOP_MODULE)
run2:
	mkdir -p sim
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILOG_SRC) $(CPP_SRC) $(C_SRC)
	./$(EXE)

wave2: WAVE_FILE = sim/wave_soc.vcd
wave2: WAVE_FILE_LAYOUT = wave_layout/wave_soc_config.gtkw
wave2:
	@if [ -f $(WAVE_FILE) ]; then \
		gtkwave $(WAVE_FILE) $(WAVE_FILE_LAYOUT); \
	else \
		echo "Error: 第二份配置波形文件不存在（已关闭波形生成）"; \
	fi
