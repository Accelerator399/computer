BUILD_DIR ?= build
CROSS_COMPILE ?= riscv64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy

ARCH_FLAGS := -march=rv32ima_zicsr_zifencei -mabi=ilp32
CFLAGS := $(ARCH_FLAGS) -nostdlib -nostartfiles -ffreestanding -fno-pic -fno-pie -Wall -Wextra
LDFLAGS := $(ARCH_FLAGS) -nostdlib -nostartfiles -static -T linker.ld -Wl,--build-id=none

OUT_ELF := $(BUILD_DIR)/init
OUT_BIN := $(BUILD_DIR)/init.bin

.PHONY: all clean

all: $(OUT_ELF) $(OUT_BIN)

$(BUILD_DIR):
	mkdir -p $@

$(OUT_ELF): init.S linker.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ init.S

$(OUT_BIN): $(OUT_ELF)
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(BUILD_DIR)
