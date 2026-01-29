# =========================
# Toolchain
# =========================
IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave

# =========================
# Directories
# =========================
SRC_DIR   := src
TB_DIR    := testbench
BUILD_DIR := build

# =========================
# Top testbench file
# (Đổi nếu bạn dùng file tb khác)
# =========================
TB_TOP := $(TB_DIR)/tb_master_apb.v

# =========================
# Source files
# =========================
SRC_FILES := \
	$(SRC_DIR)/APB_slave.v \
	$(SRC_DIR)/counter_control.v \
	$(SRC_DIR)/counter.v \
	$(SRC_DIR)/interrupt.v \
	$(SRC_DIR)/register.v \
	$(SRC_DIR)/top_module.v

TB_FILES := \
	$(TB_DIR)/master_apb.v \
	$(TB_TOP)

# =========================
# Build outputs
# =========================
OUT_VVP := $(BUILD_DIR)/sim.vvp
# VCD file name (testbench nên dump đúng tên này để "make wave" chạy ngon)
VCD     := $(BUILD_DIR)/wave.vcd

# =========================
# Flags
# =========================
IVERILOG_FLAGS ?= -g2012 -Wall -Wimplicit -Wportbind -I$(SRC_DIR) -I$(TB_DIR)

# =========================
# Targets
# =========================
.PHONY: all build run wave clean rebuild

all: run

build: $(OUT_VVP)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(OUT_VVP): $(SRC_FILES) $(TB_FILES) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(SRC_FILES) $(TB_FILES)

run: $(OUT_VVP)
	$(VVP) $(OUT_VVP)

wave:
	@if [ ! -f "$(VCD)" ]; then \
		echo "Không thấy $(VCD). Hãy chắc chắn testbench có \$dumpfile(\"$(VCD)\") và \$dumpvars;"; \
		exit 1; \
	fi
	$(GTKWAVE) $(VCD)

clean:
	rm -rf $(BUILD_DIR)

rebuild: clean build
