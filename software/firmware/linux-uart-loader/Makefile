REPO_ROOT := $(abspath ../../..)

CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf
PYTHON ?= python3

BUILD_DIR ?= $(REPO_ROOT)/build/software/linux-uart-loader
TARGET := $(BUILD_DIR)/linux_uart_loader

MARCH ?= rv32ima_zicsr_zifencei
MABI ?= ilp32

COMMON_FLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany -mstrict-align
COMMON_FLAGS += -ffreestanding -nostdlib -nostartfiles -fno-pic -fno-pie
COMMON_FLAGS += -fno-builtin -fno-jump-tables -msmall-data-limit=0
CFLAGS := $(COMMON_FLAGS) -Os -Wall -Wextra $(EXTRA_CFLAGS)
ASFLAGS := $(COMMON_FLAGS)
LDFLAGS := -T linker.ld -Wl,--build-id=none -Wl,-Map=$(TARGET).map

.PHONY: all clean check-tools

all: check-tools $(TARGET).elf $(TARGET).bin $(TARGET).dump $(TARGET).readelf \
     $(BUILD_DIR)/boot_rom.hex $(BUILD_DIR)/boot_ram.hex

check-tools:
	@command -v $(CC) >/dev/null
	@command -v $(OBJCOPY) >/dev/null
	@command -v $(PYTHON) >/dev/null

$(BUILD_DIR):
	mkdir -p $@

$(TARGET).elf: startup.S firmware.c netboot.c linker.ld | $(BUILD_DIR)
	$(CC) $(ASFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ startup.S firmware.c netboot.c

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).text.bin: $(TARGET).elf
	$(OBJCOPY) -O binary -j .text $< $@

$(TARGET).dmem.bin: $(TARGET).elf
	$(OBJCOPY) -O binary -j .rodata -j .data $< $@

$(BUILD_DIR)/boot_rom.hex: $(TARGET).text.bin
	$(PYTHON) $(REPO_ROOT)/software/scripts/bin_to_mem32.py --input $< --output $@

$(BUILD_DIR)/boot_ram.hex: $(TARGET).dmem.bin
	$(PYTHON) $(REPO_ROOT)/software/scripts/bin_to_mem32.py --input $< --output $@

$(TARGET).dump: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

$(TARGET).readelf: $(TARGET).elf
	$(READELF) -a $< > $@

clean:
	rm -rf $(BUILD_DIR)
