REPO_ROOT := $(abspath ../../..)

CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

BUILD_DIR ?= $(REPO_ROOT)/build/software/fwok-smoke
TARGET := $(BUILD_DIR)/fwok_smoke

MARCH ?= rv32ima_zicsr_zifencei
MABI ?= ilp32
FW_BASE ?= 0x00000000

ASFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany -mstrict-align
ASFLAGS += -ffreestanding -nostdlib -nostartfiles
LDFLAGS := -T linker.ld -Wl,--build-id=none -Wl,--defsym=FW_BASE=$(FW_BASE)
LDFLAGS += -Wl,-Map=$(TARGET).map

.PHONY: all clean check-tools

all: check-tools $(TARGET).elf $(TARGET).bin $(TARGET).dump

check-tools:
	@command -v $(CC) >/dev/null
	@command -v $(OBJCOPY) >/dev/null

$(BUILD_DIR):
	mkdir -p $@

$(TARGET).elf: start.S linker.ld | $(BUILD_DIR)
	$(CC) $(ASFLAGS) $(LDFLAGS) -o $@ start.S

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(TARGET).dump: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

clean:
	rm -rf $(BUILD_DIR)
