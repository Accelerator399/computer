REPO_ROOT := $(abspath ../../..)

CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

BUILD_DIR ?= $(REPO_ROOT)/build/software/linux-smoke
TARGET := $(BUILD_DIR)/linux_smoke

MARCH ?= rv32ima_zicsr_zifencei
MABI ?= ilp32
PAYLOAD_BASE ?= 0x00400000
DTB_ADDR ?= 0x00800000

ASFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany -mstrict-align
ASFLAGS += -ffreestanding -nostdlib -nostartfiles
ASFLAGS += -DDTB_ADDR=$(DTB_ADDR)
LDFLAGS := -T linker.ld -Wl,--build-id=none -Wl,--defsym=PAYLOAD_BASE=$(PAYLOAD_BASE)
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
