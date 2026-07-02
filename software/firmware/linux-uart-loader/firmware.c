typedef unsigned char u8;
typedef unsigned short u16;
typedef signed short s16;
typedef unsigned int u32;

#define UART_BASE      0x10010000u
#define UART_RBR       (*(volatile u32 *)(UART_BASE + 0x00u))
#define UART_THR       (*(volatile u32 *)(UART_BASE + 0x00u))
#define UART_LSR       (*(volatile u32 *)(UART_BASE + 0x14u))
#define UART_LSR_DR    0x01u
#define UART_LSR_THRE  0x20u

#define GPIO_AFEN      (*(volatile u32 *)0x1002000cu)
#define UART_PAD_MASK  0x00000600u

#define MTIMECMP_LO    (*(volatile u32 *)0x10004000u)
#define MTIMECMP_HI    (*(volatile u32 *)0x10004004u)

#define MAGIC          0x3158424cu
#define VERSION        1u
#define CHUNK_SIZE     256u
#define DDR_BASE       0x80000000u
#define DDR_END        0x88000000u

#define ACK_READY      'R'
#define ACK_HEADER     'H'
#define ACK_CHUNK      'C'
#define ACK_BOOT       'B'
#define ACK_ERROR      'E'

#define NET_STREAM_IMAGE 1u
#define NET_STREAM_DTB   2u

#define SBI_SUCCESS              0
#define SBI_ERR_FAILED          -1
#define SBI_ERR_NOT_SUPPORTED   -2
#define SBI_ERR_INVALID_PARAM   -3
#define SBI_ERR_INVALID_ADDRESS -5

#define SBI_EXT_BASE   0x00000010u
#define SBI_EXT_TIME   0x54494d45u
#define SBI_EXT_SRST   0x53525354u
#define SBI_EXT_DBCN   0x4442434eu

#define SBI_DBCN_WRITE      0u
#define SBI_DBCN_READ       1u
#define SBI_DBCN_WRITE_BYTE 2u

#define SBI_LEGACY_SET_TIMER 0u
#define SBI_LEGACY_PUTCHAR   1u
#define SBI_LEGACY_GETCHAR   2u
#define SBI_LEGACY_SHUTDOWN  8u

#define MEDELEG_VALUE 0x0000b1ffu
#define MEDELEG_MISALIGNED_MASK ((1u << 4) | (1u << 6))
#define MIDELEG_VALUE 0x00000222u

/*
 * Linux handles expected early MMU relocation page faults in S-mode.
 * S-mode Linux 6.6 treats load/store misaligned traps as fatal, so keep
 * those in M-mode and emulate them here like a tiny SBI firmware would.
 */
#define BOOT_MEDELEG_VALUE (MEDELEG_VALUE & ~MEDELEG_MISALIGNED_MASK)

#define MSTATUS_MPRV     (1u << 17)
#define MIP_STIP         (1u << 5)
#define MIE_MTIE         (1u << 7)

#define CAUSE_LOAD_MISALIGNED  4u
#define CAUSE_STORE_MISALIGNED 6u
#define CAUSE_MACHINE_TIMER    0x80000007u

#define OPCODE_LOAD  0x03u
#define OPCODE_STORE 0x23u

struct boot_header {
    u32 magic;
    u32 version;
    u32 image_load;
    u32 image_entry;
    u32 image_size;
    u32 dtb_load;
    u32 dtb_size;
    u32 flags;
    u32 crc;
};

void netboot_init(void);
int netboot_poll_header(struct boot_header *header);
int netboot_receive_region(u32 address, u32 total_size, u32 stream);
void netboot_send_boot_ack(void);
void boot_uart_put(u8 value);

static u8 chunk_buffer[CHUNK_SIZE];

static inline u32 csr_read_mcause(void)
{
    u32 value;
    __asm__ volatile ("csrr %0, mcause" : "=r"(value));
    return value;
}

static inline u32 csr_read_mepc(void)
{
    u32 value;
    __asm__ volatile ("csrr %0, mepc" : "=r"(value));
    return value;
}

static inline u32 csr_read_mtval(void)
{
    u32 value;
    __asm__ volatile ("csrr %0, mtval" : "=r"(value));
    return value;
}

static inline void csr_write_mepc(u32 value)
{
    __asm__ volatile ("csrw mepc, %0" :: "r"(value));
}

static inline void csr_set_mip(u32 mask)
{
    __asm__ volatile ("csrs mip, %0" :: "r"(mask));
}

static inline void csr_clear_mip(u32 mask)
{
    __asm__ volatile ("csrc mip, %0" :: "r"(mask));
}

static inline void csr_set_mie(u32 mask)
{
    __asm__ volatile ("csrs mie, %0" :: "r"(mask));
}

static inline void csr_clear_mie(u32 mask)
{
    __asm__ volatile ("csrc mie, %0" :: "r"(mask));
}

static inline u8 lower_priv_load_u8(u32 address)
{
    u32 value;
    u32 mprv = MSTATUS_MPRV;

    __asm__ volatile (
        "csrs mstatus, %2\n"
        "lbu %0, 0(%1)\n"
        "csrc mstatus, %2\n"
        : "=&r"(value)
        : "r"(address), "r"(mprv)
        : "memory"
    );
    return (u8)value;
}

static inline void lower_priv_store_u8(u32 address, u8 value)
{
    u32 mprv = MSTATUS_MPRV;

    __asm__ volatile (
        "csrs mstatus, %2\n"
        "sb %1, 0(%0)\n"
        "csrc mstatus, %2\n"
        :: "r"(address), "r"((u32)value), "r"(mprv)
        : "memory"
    );
}

static u32 lower_priv_load_u32(u32 address)
{
    u32 value = (u32)lower_priv_load_u8(address);
    value |= (u32)lower_priv_load_u8(address + 1u) << 8;
    value |= (u32)lower_priv_load_u8(address + 2u) << 16;
    value |= (u32)lower_priv_load_u8(address + 3u) << 24;
    return value;
}

static int emulate_misaligned_load(u32 *regs, u32 insn, u32 address)
{
    u32 funct3 = (insn >> 12) & 7u;
    u32 rd = (insn >> 7) & 31u;
    u32 bytes;
    u32 value;
    u32 index;

    if ((insn & 0x7fu) != OPCODE_LOAD) {
        return 0;
    }

    if (funct3 == 1u || funct3 == 5u) {
        bytes = 2u;
    } else if (funct3 == 2u) {
        bytes = 4u;
    } else {
        return 0;
    }

    value = 0u;
    for (index = 0u; index < bytes; index++) {
        value |= (u32)lower_priv_load_u8(address + index) << (index * 8u);
    }
    if (funct3 == 1u) {
        value = (u32)(int)(s16)value;
    }
    if (rd != 0u) {
        regs[rd] = value;
    }
    csr_write_mepc(csr_read_mepc() + 4u);
    return 1;
}

static int emulate_misaligned_store(u32 *regs, u32 insn, u32 address)
{
    u32 funct3 = (insn >> 12) & 7u;
    u32 rs2 = (insn >> 20) & 31u;
    u32 bytes;
    u32 value;
    u32 index;

    if ((insn & 0x7fu) != OPCODE_STORE) {
        return 0;
    }

    if (funct3 == 1u) {
        bytes = 2u;
    } else if (funct3 == 2u) {
        bytes = 4u;
    } else {
        return 0;
    }

    value = regs[rs2];
    for (index = 0u; index < bytes; index++) {
        lower_priv_store_u8(address + index, (u8)(value >> (index * 8u)));
    }
    csr_write_mepc(csr_read_mepc() + 4u);
    return 1;
}

static int emulate_misaligned_access(u32 *regs, u32 cause)
{
    u32 mepc = csr_read_mepc();
    u32 mtval = csr_read_mtval();
    u32 insn;

    insn = lower_priv_load_u32(mepc);
    if ((insn & 3u) != 3u) {
        return 0;
    }
    if (cause == CAUSE_LOAD_MISALIGNED) {
        return emulate_misaligned_load(regs, insn, mtval);
    }
    if (cause == CAUSE_STORE_MISALIGNED) {
        return emulate_misaligned_store(regs, insn, mtval);
    }
    return 0;
}

static void uart_put(u8 value)
{
    while ((UART_LSR & UART_LSR_THRE) == 0u) {
    }
    UART_THR = value;
}

void boot_uart_put(u8 value)
{
    uart_put(value);
}

static void uart_puts(const char *text)
{
    while (*text != 0) {
        uart_put((u8)*text);
        text++;
    }
}

static void uart_put_hex_digit(u32 digit)
{
    digit &= 0xfu;
    uart_put((u8)(digit < 10u ? ('0' + digit) : ('a' + digit - 10u)));
}

static void uart_put_hex32(u32 value)
{
    uart_put_hex_digit(value >> 28);
    uart_put_hex_digit(value >> 24);
    uart_put_hex_digit(value >> 20);
    uart_put_hex_digit(value >> 16);
    uart_put_hex_digit(value >> 12);
    uart_put_hex_digit(value >> 8);
    uart_put_hex_digit(value >> 4);
    uart_put_hex_digit(value);
}

static void uart_flush(void)
{
    while ((UART_LSR & UART_LSR_THRE) == 0u) {
    }
}

static u8 uart_get(void)
{
    while ((UART_LSR & UART_LSR_DR) == 0u) {
    }
    return (u8)UART_RBR;
}

static int uart_try_get(void)
{
    if ((UART_LSR & UART_LSR_DR) == 0u) {
        return -1;
    }
    return (int)(u8)UART_RBR;
}

static u32 crc32_update(u32 crc, u8 value)
{
    u32 bit;

    crc ^= value;
    for (bit = 0; bit < 8u; bit++) {
        crc = (crc >> 1) ^ ((0u - (crc & 1u)) & 0xedb88320u);
    }
    return crc;
}

static u32 crc32_bytes(const u8 *data, u32 size)
{
    u32 index;
    u32 crc = 0xffffffffu;

    for (index = 0; index < size; index++) {
        crc = crc32_update(crc, data[index]);
    }
    return ~crc;
}

static u32 recv_u32(void)
{
    u32 value = (u32)uart_get();
    value |= (u32)uart_get() << 8;
    value |= (u32)uart_get() << 16;
    value |= (u32)uart_get() << 24;
    return value;
}

static u32 recv_u32_after_first(u8 first)
{
    u32 value = (u32)first;
    value |= (u32)uart_get() << 8;
    value |= (u32)uart_get() << 16;
    value |= (u32)uart_get() << 24;
    return value;
}

static void send_error(u8 code)
{
    uart_put(ACK_ERROR);
    uart_put(code);
    uart_flush();
}

static int valid_region(u32 address, u32 size)
{
    u32 end = address + size;

    return size != 0u && end > address && address >= DDR_BASE && end <= DDR_END;
}

static int regions_overlap(u32 a, u32 a_size, u32 b, u32 b_size)
{
    return a < b + b_size && b < a + a_size;
}

static int validate_header(const struct boot_header *header)
{
    u32 dtb_end;

    if (header->magic != MAGIC || header->version != VERSION) {
        return 1;
    }
    if (crc32_bytes((const u8 *)header, 8u * 4u) != header->crc) {
        return 2;
    }
    if (!valid_region(header->image_load, header->image_size) ||
        !valid_region(header->dtb_load, header->dtb_size)) {
        return 3;
    }
    if ((header->image_load & 0x003fffffu) != 0u ||
        (header->image_entry & 3u) != 0u ||
        header->image_entry < header->image_load ||
        header->image_entry >= header->image_load + header->image_size) {
        return 4;
    }

    dtb_end = header->dtb_load + header->dtb_size - 1u;
    if ((header->dtb_load & 7u) != 0u ||
        header->dtb_size > 0x00200000u ||
        (header->dtb_load >> 21) != (dtb_end >> 21)) {
        return 5;
    }
    if (regions_overlap(header->image_load, header->image_size,
                        header->dtb_load, header->dtb_size)) {
        return 6;
    }
    if (header->flags != 0u) {
        return 7;
    }
    return 0;
}

static int receive_region(u32 address, u32 total_size)
{
    u32 written = 0u;

    while (written < total_size) {
        u32 index;
        u32 chunk_size = recv_u32();
        u32 crc = 0xffffffffu;
        u32 expected_crc;

        if (chunk_size == 0u || chunk_size > CHUNK_SIZE ||
            chunk_size > total_size - written) {
            return 8;
        }

        for (index = 0; index < chunk_size; index++) {
            chunk_buffer[index] = uart_get();
            crc = crc32_update(crc, chunk_buffer[index]);
        }
        expected_crc = recv_u32();
        if ((~crc) != expected_crc) {
            return 9;
        }

        for (index = 0; index < chunk_size; index++) {
            *(volatile u8 *)(address + written + index) = chunk_buffer[index];
        }
        written += chunk_size;
        uart_put(ACK_CHUNK);
    }
    return 0;
}

static void set_timer(u32 low, u32 high)
{
    MTIMECMP_HI = 0xffffffffu;
    MTIMECMP_LO = low;
    MTIMECMP_HI = high;
    csr_clear_mip(MIP_STIP);
    csr_set_mie(MIE_MTIE);
}

static int extension_available(u32 extension)
{
    return extension == SBI_EXT_BASE ||
           extension == SBI_EXT_TIME ||
           extension == SBI_EXT_SRST ||
           extension == SBI_EXT_DBCN ||
           extension == SBI_LEGACY_SET_TIMER ||
           extension == SBI_LEGACY_PUTCHAR ||
           extension == SBI_LEGACY_GETCHAR ||
           extension == SBI_LEGACY_SHUTDOWN;
}

static void platform_halt(void)
{
    for (;;) {
        __asm__ volatile ("wfi");
    }
}

static int dbcn_region_valid(u32 address, u32 size, u32 address_high)
{
    if (address_high != 0u) {
        return 0;
    }
    if (size == 0u) {
        return 1;
    }
    return valid_region(address, size);
}

static void handle_dbcn(u32 *regs)
{
    u32 function = regs[16];
    u32 count = regs[10];
    u32 address = regs[11];
    u32 address_high = regs[12];
    u32 transferred = 0u;

    if (function == SBI_DBCN_WRITE_BYTE) {
        uart_put((u8)count);
        regs[10] = SBI_SUCCESS;
        regs[11] = 0u;
        return;
    }
    if (function != SBI_DBCN_WRITE && function != SBI_DBCN_READ) {
        regs[10] = (u32)SBI_ERR_NOT_SUPPORTED;
        regs[11] = 0u;
        return;
    }
    if (!dbcn_region_valid(address, count, address_high)) {
        regs[10] = (u32)SBI_ERR_INVALID_ADDRESS;
        regs[11] = 0u;
        return;
    }

    if (function == SBI_DBCN_WRITE) {
        while (transferred < count) {
            uart_put(*(const volatile u8 *)(address + transferred));
            transferred++;
        }
    } else {
        while (transferred < count) {
            int value = uart_try_get();
            if (value < 0) {
                break;
            }
            *(volatile u8 *)(address + transferred) = (u8)value;
            transferred++;
        }
    }

    regs[10] = SBI_SUCCESS;
    regs[11] = transferred;
}

static void handle_sbi(u32 *regs)
{
    u32 extension = regs[17];
    u32 function = regs[16];
    int error = SBI_ERR_NOT_SUPPORTED;
    u32 value = 0u;

    if (extension == SBI_EXT_BASE) {
        error = SBI_SUCCESS;
        switch (function) {
            case 0: value = 0x02000000u; break;
            case 1: value = 0x7fffffffu; break;
            case 2: value = 1u; break;
            case 3: value = (u32)extension_available(regs[10]); break;
            case 4:
            case 5:
            case 6: value = 0u; break;
            default: error = SBI_ERR_NOT_SUPPORTED; break;
        }
        regs[10] = (u32)error;
        regs[11] = value;
        return;
    }

    if (extension == SBI_EXT_DBCN) {
        handle_dbcn(regs);
        return;
    }

    if (extension == SBI_EXT_TIME && function == 0u) {
        set_timer(regs[10], regs[11]);
        regs[10] = SBI_SUCCESS;
        regs[11] = 0u;
        return;
    }

    if (extension == SBI_EXT_SRST && function == 0u) {
        if (regs[10] == 0u && regs[11] <= 1u) {
            platform_halt();
        }
        regs[10] = (u32)SBI_ERR_NOT_SUPPORTED;
        regs[11] = 0u;
        return;
    }

    switch (extension) {
        case SBI_LEGACY_SET_TIMER:
            set_timer(regs[10], regs[11]);
            regs[10] = 0u;
            return;
        case SBI_LEGACY_PUTCHAR:
            uart_put((u8)regs[10]);
            regs[10] = 0u;
            return;
        case SBI_LEGACY_GETCHAR:
            regs[10] = (u32)uart_try_get();
            return;
        case SBI_LEGACY_SHUTDOWN:
            platform_halt();
            return;
        default:
            regs[10] = (u32)SBI_ERR_NOT_SUPPORTED;
            regs[11] = 0u;
            return;
    }
}

void machine_trap(u32 *regs)
{
    u32 cause = csr_read_mcause();

    if (cause == CAUSE_MACHINE_TIMER) {
        csr_clear_mie(MIE_MTIE);
        csr_set_mip(MIP_STIP);
        return;
    }
    if (cause == 9u) {
        handle_sbi(regs);
        csr_write_mepc(csr_read_mepc() + 4u);
        return;
    }
    if ((cause == CAUSE_LOAD_MISALIGNED || cause == CAUSE_STORE_MISALIGNED) &&
        emulate_misaligned_access(regs, cause)) {
        return;
    }

    __asm__ volatile ("csrw mie, zero");
    uart_put('\r');
    uart_put('\n');
    uart_put('T');
    uart_put_hex_digit(cause);
    uart_put(' ');
    uart_puts("\r\nMTRAP mcause=");
    uart_put_hex32(cause);
    uart_puts(" mepc=");
    uart_put_hex32(csr_read_mepc());
    uart_puts(" mtval=");
    uart_put_hex32(csr_read_mtval());
    uart_puts(" a0=");
    uart_put_hex32(regs[10]);
    uart_puts(" a1=");
    uart_put_hex32(regs[11]);
    uart_puts("\r\n");
    platform_halt();
}

__attribute__((noreturn))
static void enter_supervisor(u32 entry, u32 dtb)
{
    u32 mstatus;

    __asm__ volatile ("csrw mie, zero");
    __asm__ volatile ("csrw mip, zero");
    __asm__ volatile ("csrw satp, zero");
    __asm__ volatile ("sfence.vma");
    __asm__ volatile ("fence.i");
    __asm__ volatile ("csrw medeleg, %0" :: "r"(BOOT_MEDELEG_VALUE));
    __asm__ volatile ("csrw mideleg, %0" :: "r"(MIDELEG_VALUE));
    __asm__ volatile ("csrw mcounteren, %0" :: "r"(7u));
    __asm__ volatile ("csrw scounteren, %0" :: "r"(7u));
    __asm__ volatile ("csrr %0, mstatus" : "=r"(mstatus));
    mstatus &= ~(3u << 11);
    mstatus |= 1u << 11;
    __asm__ volatile ("csrw mstatus, %0" :: "r"(mstatus));
    __asm__ volatile ("csrw mepc, %0" :: "r"(entry));
    __asm__ volatile (
        "mv a0, zero\n"
        "mv a1, %0\n"
        "mret\n"
        :: "r"(dtb)
        : "a0", "a1", "memory"
    );
    __builtin_unreachable();
}

void boot_main(void)
{
    struct boot_header header;
    u32 *words = (u32 *)&header;
    u32 index;
    int error;
    int first;
    int use_network = 0;

    GPIO_AFEN = UART_PAD_MASK;
    netboot_init();
    uart_put(ACK_READY);

    for (;;) {
        first = uart_try_get();
        if (first >= 0) {
            words[0] = recv_u32_after_first((u8)first);
            for (index = 1u; index < 9u; index++) {
                words[index] = recv_u32();
            }
            break;
        }
        if (netboot_poll_header(&header)) {
            use_network = 1;
            break;
        }
    }

    if (!use_network) {
        error = validate_header(&header);
        if (error != 0) {
            send_error((u8)error);
            platform_halt();
        }
        uart_put(ACK_HEADER);
    }

    error = use_network ?
        netboot_receive_region(header.image_load, header.image_size, NET_STREAM_IMAGE) :
        receive_region(header.image_load, header.image_size);
    if (error != 0) {
        if (!use_network) {
            send_error((u8)error);
        }
        platform_halt();
    }
    error = use_network ?
        netboot_receive_region(header.dtb_load, header.dtb_size, NET_STREAM_DTB) :
        receive_region(header.dtb_load, header.dtb_size);
    if (error != 0) {
        if (!use_network) {
            send_error((u8)error);
        }
        platform_halt();
    }

    __asm__ volatile ("fence rw, rw");
    __asm__ volatile ("fence.i");
    if (use_network) {
        netboot_send_boot_ack();
    } else {
        uart_put(ACK_BOOT);
        uart_flush();
    }
    enter_supervisor(header.image_entry, header.dtb_load);
}
