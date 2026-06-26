REPO_ROOT := $(abspath ../../..)

CROSS_COMPILE ?= riscv64-unknown-elf-
CC := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf

BUILD_DIR ?= $(REPO_ROOT)/build/software/opensbi-lite
TARGET := $(BUILD_DIR)/fw_jump

MARCH ?= rv32ima_zicsr_zifencei
MABI ?= ilp32
FW_BASE ?= 0x00000000
LINUX_ENTRY ?= 0x00400000
DTB_ADDR ?= 0x00800000
STACK_SIZE ?= 4096

ASFLAGS := -march=$(MARCH) -mabi=$(MABI) -mcmodel=medany -mstrict-align
ASFLAGS += -ffreestanding -nostdlib -nostartfiles
ASFLAGS += -DLINUX_ENTRY=$(LINUX_ENTRY) -DDTB_ADDR=$(DTB_ADDR)
LDFLAGS := -T linker.ld -Wl,--build-id=none
LDFLAGS += -Wl,--defsym=FW_BASE=$(FW_BASE)
LDFLAGS += -Wl,--defsym=STACK_SIZE=$(STACK_SIZE)
LDFLAGS += -Wl,-Map=$(TARGET).map

.PHONY: all clean check-tools

all: check-tools $(TARGET).elf $(TARGET).bin $(TARGET).dump $(TARGET).readelf

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

$(TARGET).readelf: $(TARGET).elf
	$(READELF) -a $< > $@

clean:
	rm -rf $(BUILD_DIR)
