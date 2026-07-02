typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

void boot_uart_put(u8 value);

#define ETH_BASE      0x10440000u
#define DDR_BASE      0x80000000u
#define DDR_END       0x88000000u

#define MAGIC          0x3158424cu
#define VERSION        1u

#define NET_MAGIC      0x314e4343u
#define NET_VERSION    1u
#define NET_TYPE_HEADER 1u
#define NET_TYPE_DATA   2u
#define NET_TYPE_ACK    3u
#define NET_TYPE_BOOT   4u
#define NET_STREAM_IMAGE 1u
#define NET_STREAM_DTB   2u
#define NET_CHUNK_SIZE 1024u
#define NET_STATUS_OK      0u
#define NET_STATUS_BAD     1u
#define NET_STATUS_CRC     2u
#define NET_STATUS_RANGE   3u
#define NET_STATUS_ORDER   4u

#define XEL_TXBUFF_OFFSET       0x0000u
#define XEL_TXPONG_OFFSET       0x0800u
#define XEL_TXPONG_TPLR_OFFSET  0x0ff4u
#define XEL_TXPONG_TSR_OFFSET   0x0ffcu
#define XEL_RXBUFF_OFFSET       0x1000u
#define XEL_RXPONG_OFFSET       0x1800u
#define XEL_RXPONG_RSR_OFFSET   0x1ffcu
#define XEL_MDIOADDR_OFFSET     0x07e4u
#define XEL_MDIOWR_OFFSET       0x07e8u
#define XEL_MDIORD_OFFSET       0x07ecu
#define XEL_MDIOCNTR_OFFSET     0x07f0u
#define XEL_TPLR_OFFSET         0x07f4u
#define XEL_TSR_OFFSET          0x07fcu
#define XEL_RSR_OFFSET          0x17fcu
#define XEL_TSR_XMIT_BUSY_MASK  0x00000001u
#define XEL_TSR_PROG_MAC_ADDR   0x00000003u
#define XEL_RSR_RECV_DONE_MASK  0x00000001u
#define XEL_MDIOADDR_PHY_SHIFT  5u
#define XEL_MDIOADDR_OP_READ    0x00000400u
#define XEL_MDIOCNTR_STATUS     0x00000001u
#define XEL_MDIOCNTR_ENABLE     0x00000008u

#define PHY_BMSR_REG            1u
#define PHY_BMSR_LINK_STATUS    0x0004u
#define ETH_LINK_WAIT_POLLS     4096u
#define ETH_LINK_POLL_DELAY     5000u

#define ETH_TYPE_ARP 0x0806u
#define ETH_TYPE_IP  0x0800u
#define IP_PROTO_UDP 17u
#define NET_PORT     62000u

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

struct net_packet_header {
    u32 magic;
    u32 version;
    u32 type;
    u32 seq;
    u32 stream;
    u32 offset;
    u32 length;
    u32 crc;
};

struct net_peer {
    u8 mac[6];
    u32 ip;
    u16 port;
};

static u8 net_rx_buffer[1536];
static u8 net_tx_buffer[1536];
static struct net_peer net_peer;
static u32 net_completed_image_size;
static u32 net_completed_dtb_size;
static const u8 net_local_mac[6] = {0x02u, 0xccu, 0x00u, 0x00u, 0x00u, 0x01u};
/* 169.254.5.67, matching the current Windows APIPA address on Ethernet. */
static const u32 net_local_ip = 0xa9fe0543u;

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

static u16 load_be16(const u8 *data)
{
    return (u16)(((u16)data[0] << 8) | data[1]);
}

static u32 load_be32(const u8 *data)
{
    return ((u32)data[0] << 24) |
           ((u32)data[1] << 16) |
           ((u32)data[2] << 8) |
           data[3];
}

static u32 load_le32(const u8 *data)
{
    return (u32)data[0] |
           ((u32)data[1] << 8) |
           ((u32)data[2] << 16) |
           ((u32)data[3] << 24);
}

static void store_be16(u8 *data, u16 value)
{
    data[0] = (u8)(value >> 8);
    data[1] = (u8)value;
}

static void store_be32(u8 *data, u32 value)
{
    data[0] = (u8)(value >> 24);
    data[1] = (u8)(value >> 16);
    data[2] = (u8)(value >> 8);
    data[3] = (u8)value;
}

static void store_le32(u8 *data, u32 value)
{
    data[0] = (u8)value;
    data[1] = (u8)(value >> 8);
    data[2] = (u8)(value >> 16);
    data[3] = (u8)(value >> 24);
}

static void copy_bytes(u8 *dst, const u8 *src, u32 size)
{
    u32 index;
    for (index = 0; index < size; index++) {
        dst[index] = src[index];
    }
}

static void zero_bytes(u8 *dst, u32 size)
{
    u32 index;
    for (index = 0; index < size; index++) {
        dst[index] = 0u;
    }
}

static u16 ip_checksum(const u8 *data, u32 size)
{
    u32 sum = 0u;
    u32 index;

    for (index = 0; index + 1u < size; index += 2u) {
        sum += load_be16(data + index);
    }
    if (index < size) {
        sum += (u32)data[index] << 8;
    }
    while (sum >> 16) {
        sum = (sum & 0xffffu) + (sum >> 16);
    }
    return (u16)~sum;
}

static volatile u32 *eth_reg(u32 offset)
{
    return (volatile u32 *)(ETH_BASE + offset);
}

static u32 eth_read_reg(u32 offset)
{
    return *eth_reg(offset);
}

static void eth_write_reg(u32 offset, u32 value)
{
    *eth_reg(offset) = value;
}

static void eth_write_buffer(u32 offset, const u8 *data, u32 size)
{
    u32 index = 0u;

    while (index < size) {
        u32 value = (u32)data[index];
        if (index + 1u < size) {
            value |= (u32)data[index + 1u] << 8;
        }
        if (index + 2u < size) {
            value |= (u32)data[index + 2u] << 16;
        }
        if (index + 3u < size) {
            value |= (u32)data[index + 3u] << 24;
        }
        eth_write_reg(offset + index, value);
        index += 4u;
    }
}

static void eth_read_buffer(u32 offset, u8 *data, u32 size)
{
    u32 index = 0u;

    while (index < size) {
        u32 value = eth_read_reg(offset + index);
        data[index] = (u8)value;
        if (index + 1u < size) {
            data[index + 1u] = (u8)(value >> 8);
        }
        if (index + 2u < size) {
            data[index + 2u] = (u8)(value >> 16);
        }
        if (index + 3u < size) {
            data[index + 3u] = (u8)(value >> 24);
        }
        index += 4u;
    }
}

static void eth_program_mac_one(u32 buffer_off, u32 length_off, u32 status_off)
{
    eth_write_reg(status_off, 0u);
    eth_write_buffer(buffer_off, net_local_mac, 6u);
    eth_write_reg(length_off, 6u);
    eth_write_reg(status_off, XEL_TSR_PROG_MAC_ADDR);
    while ((eth_read_reg(status_off) & XEL_TSR_PROG_MAC_ADDR) != 0u) {
    }
}

static void eth_delay_cycles(u32 cycles)
{
    volatile u32 index;

    for (index = 0u; index < cycles; index++) {
        __asm__ volatile ("" ::: "memory");
    }
}

static int eth_mdio_wait(void)
{
    u32 tries;

    for (tries = 0u; tries < 100000u; tries++) {
        if ((eth_read_reg(XEL_MDIOCNTR_OFFSET) & XEL_MDIOCNTR_STATUS) == 0u) {
            return 1;
        }
    }
    return 0;
}

static u16 eth_mdio_read(u32 phy, u32 reg)
{
    u32 ctrl;

    if (!eth_mdio_wait()) {
        return 0xffffu;
    }
    eth_write_reg(
        XEL_MDIOADDR_OFFSET,
        XEL_MDIOADDR_OP_READ |
            ((phy & 0x1fu) << XEL_MDIOADDR_PHY_SHIFT) |
            (reg & 0x1fu)
    );
    ctrl = eth_read_reg(XEL_MDIOCNTR_OFFSET) | XEL_MDIOCNTR_ENABLE;
    eth_write_reg(XEL_MDIOCNTR_OFFSET, ctrl | XEL_MDIOCNTR_STATUS);
    if (!eth_mdio_wait()) {
        return 0xffffu;
    }
    return (u16)eth_read_reg(XEL_MDIORD_OFFSET);
}

static void eth_wait_link(void)
{
    u32 phy;
    u32 tries;
    u16 status;
    int saw_phy = 0;

    eth_write_reg(XEL_MDIOCNTR_OFFSET, XEL_MDIOCNTR_ENABLE);
    eth_delay_cycles(50000u);
    for (tries = 0u; tries < ETH_LINK_WAIT_POLLS; tries++) {
        for (phy = 0u; phy < 32u; phy++) {
            (void)eth_mdio_read(phy, PHY_BMSR_REG);
            status = eth_mdio_read(phy, PHY_BMSR_REG);
            if (status != 0xffffu && status != 0x0000u) {
                saw_phy = 1;
            }
            if (status != 0xffffu &&
                status != 0x0000u &&
                (status & PHY_BMSR_LINK_STATUS) != 0u) {
                boot_uart_put('L');
                return;
            }
        }
        eth_delay_cycles(ETH_LINK_POLL_DELAY);
    }
    boot_uart_put(saw_phy ? 'p' : 'l');
    eth_delay_cycles(500000u);
}

void netboot_init(void)
{
    eth_program_mac_one(XEL_TXBUFF_OFFSET, XEL_TPLR_OFFSET, XEL_TSR_OFFSET);
    eth_program_mac_one(
        XEL_TXPONG_OFFSET,
        XEL_TXPONG_TPLR_OFFSET,
        XEL_TXPONG_TSR_OFFSET
    );
    eth_write_reg(XEL_RSR_OFFSET, 0u);
    eth_write_reg(XEL_RXPONG_RSR_OFFSET, 0u);
    eth_wait_link();
}

static int eth_send_frame(const u8 *frame, u32 size)
{
    u32 buffer_off;
    u32 length_off;
    u32 status_off;
    u32 send_size = size < 60u ? 60u : size;

    while ((eth_read_reg(XEL_TSR_OFFSET) & XEL_TSR_XMIT_BUSY_MASK) != 0u &&
           (eth_read_reg(XEL_TXPONG_TSR_OFFSET) & XEL_TSR_XMIT_BUSY_MASK) != 0u) {
    }
    if ((eth_read_reg(XEL_TSR_OFFSET) & XEL_TSR_XMIT_BUSY_MASK) == 0u) {
        buffer_off = XEL_TXBUFF_OFFSET;
        length_off = XEL_TPLR_OFFSET;
        status_off = XEL_TSR_OFFSET;
    } else {
        buffer_off = XEL_TXPONG_OFFSET;
        length_off = XEL_TXPONG_TPLR_OFFSET;
        status_off = XEL_TXPONG_TSR_OFFSET;
    }

    eth_write_buffer(buffer_off, frame, send_size);
    eth_write_reg(length_off, send_size & 0xffffu);
    eth_write_reg(status_off, eth_read_reg(status_off) | XEL_TSR_XMIT_BUSY_MASK);
    return 1;
}

static int eth_receive_frame(u8 *frame, u32 max_size)
{
    u32 status_off;
    u32 buffer_off;
    u32 status;
    u32 size = max_size > 1518u ? 1518u : max_size;

    status = eth_read_reg(XEL_RSR_OFFSET);
    if ((status & XEL_RSR_RECV_DONE_MASK) != 0u) {
        status_off = XEL_RSR_OFFSET;
        buffer_off = XEL_RXBUFF_OFFSET;
    } else {
        status = eth_read_reg(XEL_RXPONG_RSR_OFFSET);
        if ((status & XEL_RSR_RECV_DONE_MASK) == 0u) {
            return 0;
        }
        status_off = XEL_RXPONG_RSR_OFFSET;
        buffer_off = XEL_RXPONG_OFFSET;
    }

    eth_read_buffer(buffer_off, frame, size);
    eth_write_reg(status_off, status & ~XEL_RSR_RECV_DONE_MASK);
    return (int)size;
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

static void net_store_packet_header(
    u8 *data,
    u32 type,
    u32 seq,
    u32 stream,
    u32 offset,
    u32 length,
    u32 crc
)
{
    store_le32(data + 0u, NET_MAGIC);
    store_le32(data + 4u, NET_VERSION);
    store_le32(data + 8u, type);
    store_le32(data + 12u, seq);
    store_le32(data + 16u, stream);
    store_le32(data + 20u, offset);
    store_le32(data + 24u, length);
    store_le32(data + 28u, crc);
}

static void net_load_packet_header(struct net_packet_header *header, const u8 *data)
{
    header->magic = load_le32(data + 0u);
    header->version = load_le32(data + 4u);
    header->type = load_le32(data + 8u);
    header->seq = load_le32(data + 12u);
    header->stream = load_le32(data + 16u);
    header->offset = load_le32(data + 20u);
    header->length = load_le32(data + 24u);
    header->crc = load_le32(data + 28u);
}

static void net_send_udp_status(u32 seq, u32 acked_type, u32 status)
{
    u32 udp_payload_len = 32u;
    u32 udp_len = 8u + udp_payload_len;
    u32 ip_len = 20u + udp_len;
    u32 frame_len = 14u + ip_len;
    u8 *ip = net_tx_buffer + 14u;
    u8 *udp = ip + 20u;
    u8 *payload = udp + 8u;

    zero_bytes(net_tx_buffer, frame_len < 60u ? 60u : frame_len);
    copy_bytes(net_tx_buffer + 0u, net_peer.mac, 6u);
    copy_bytes(net_tx_buffer + 6u, net_local_mac, 6u);
    store_be16(net_tx_buffer + 12u, ETH_TYPE_IP);

    ip[0] = 0x45u;
    ip[1] = 0u;
    store_be16(ip + 2u, (u16)ip_len);
    store_be16(ip + 4u, (u16)seq);
    store_be16(ip + 6u, 0u);
    ip[8] = 64u;
    ip[9] = IP_PROTO_UDP;
    store_be16(ip + 10u, 0u);
    store_be32(ip + 12u, net_local_ip);
    store_be32(ip + 16u, net_peer.ip);
    store_be16(ip + 10u, ip_checksum(ip, 20u));

    store_be16(udp + 0u, NET_PORT);
    store_be16(udp + 2u, net_peer.port);
    store_be16(udp + 4u, (u16)udp_len);
    store_be16(udp + 6u, 0u);

    net_store_packet_header(payload, NET_TYPE_ACK, seq, acked_type, status, 0u, 0u);
    eth_send_frame(net_tx_buffer, frame_len);
}

static void net_send_arp_reply(const u8 *request)
{
    const u8 *arp = request + 14u;
    u8 *reply = net_tx_buffer;
    u8 *out_arp = reply + 14u;

    zero_bytes(reply, 60u);
    copy_bytes(reply + 0u, request + 6u, 6u);
    copy_bytes(reply + 6u, net_local_mac, 6u);
    store_be16(reply + 12u, ETH_TYPE_ARP);

    store_be16(out_arp + 0u, 1u);
    store_be16(out_arp + 2u, ETH_TYPE_IP);
    out_arp[4] = 6u;
    out_arp[5] = 4u;
    store_be16(out_arp + 6u, 2u);
    copy_bytes(out_arp + 8u, net_local_mac, 6u);
    store_be32(out_arp + 14u, net_local_ip);
    copy_bytes(out_arp + 18u, arp + 8u, 6u);
    copy_bytes(out_arp + 24u, arp + 14u, 4u);
    eth_send_frame(reply, 42u);
    boot_uart_put('A');
}

static void net_handle_arp(const u8 *frame)
{
    const u8 *arp = frame + 14u;

    if (load_be16(arp + 0u) != 1u ||
        load_be16(arp + 2u) != ETH_TYPE_IP ||
        arp[4] != 6u ||
        arp[5] != 4u ||
        load_be16(arp + 6u) != 1u ||
        load_be32(arp + 24u) != net_local_ip) {
        return;
    }
    net_send_arp_reply(frame);
}

static int net_poll_packet(struct net_packet_header *packet, const u8 **payload_out)
{
    int frame_size = eth_receive_frame(net_rx_buffer, sizeof(net_rx_buffer));
    u16 eth_type;
    u8 *ip;
    u8 *udp;
    u8 *payload;
    u32 ihl;
    u32 total_len;
    u32 udp_len;
    u32 payload_len;
    u32 dst_ip;

    if (frame_size <= 0 || frame_size < 42) {
        return 0;
    }

    eth_type = load_be16(net_rx_buffer + 12u);
    if (eth_type == ETH_TYPE_ARP) {
        net_handle_arp(net_rx_buffer);
        return 0;
    }
    if (eth_type != ETH_TYPE_IP) {
        return 0;
    }

    ip = net_rx_buffer + 14u;
    if ((ip[0] >> 4) != 4u) {
        return 0;
    }
    ihl = (u32)(ip[0] & 0x0fu) * 4u;
    if (ihl < 20u) {
        return 0;
    }
    total_len = load_be16(ip + 2u);
    if (total_len < ihl + 8u + sizeof(struct net_packet_header) ||
        total_len + 14u > (u32)frame_size ||
        ip[9] != IP_PROTO_UDP) {
        return 0;
    }
    dst_ip = load_be32(ip + 16u);
    if (dst_ip != net_local_ip && dst_ip != 0xffffffffu) {
        return 0;
    }

    udp = ip + ihl;
    udp_len = load_be16(udp + 4u);
    if (udp_len < 8u + sizeof(struct net_packet_header) ||
        udp_len > total_len - ihl ||
        load_be16(udp + 2u) != NET_PORT) {
        return 0;
    }

    payload = udp + 8u;
    payload_len = udp_len - 8u;
    net_load_packet_header(packet, payload);
    if (packet->magic != NET_MAGIC ||
        packet->version != NET_VERSION ||
        packet->length > payload_len - sizeof(struct net_packet_header)) {
        return 0;
    }

    copy_bytes(net_peer.mac, net_rx_buffer + 6u, 6u);
    net_peer.ip = load_be32(ip + 12u);
    net_peer.port = load_be16(udp + 0u);
    boot_uart_put('F');
    payload += sizeof(struct net_packet_header);
    if (crc32_bytes(payload, packet->length) != packet->crc) {
        net_send_udp_status(packet->seq, packet->type, NET_STATUS_CRC);
        return 0;
    }

    *payload_out = payload;
    return 1;
}

static void net_load_boot_header(struct boot_header *header, const u8 *payload)
{
    u32 *words = (u32 *)header;
    u32 index;

    for (index = 0u; index < 9u; index++) {
        words[index] = load_le32(payload + index * 4u);
    }
}

int netboot_poll_header(struct boot_header *header)
{
    struct net_packet_header packet;
    const u8 *payload = 0;
    int error;

    if (!net_poll_packet(&packet, &payload)) {
        return 0;
    }
    if (packet.type != NET_TYPE_HEADER ||
        packet.length != sizeof(struct boot_header)) {
        net_send_udp_status(packet.seq, packet.type, NET_STATUS_BAD);
        return 0;
    }

    net_load_boot_header(header, payload);
    error = validate_header(header);
    if (error != 0) {
        net_send_udp_status(packet.seq, NET_TYPE_HEADER, (u32)error);
        return 0;
    }
    net_send_udp_status(packet.seq, NET_TYPE_HEADER, NET_STATUS_OK);
    boot_uart_put('H');
    return 1;
}

int netboot_receive_region(u32 address, u32 total_size, u32 stream)
{
    u32 written = 0u;

    while (written < total_size) {
        struct net_packet_header packet;
        const u8 *payload = 0;
        u32 index;

        if (!net_poll_packet(&packet, &payload)) {
            continue;
        }
        if (packet.type == NET_TYPE_HEADER) {
            net_send_udp_status(packet.seq, NET_TYPE_HEADER, NET_STATUS_OK);
            continue;
        }
        if (packet.type != NET_TYPE_DATA || packet.stream != stream) {
            if (packet.type == NET_TYPE_DATA &&
                packet.stream == NET_STREAM_IMAGE &&
                packet.offset + packet.length <= net_completed_image_size &&
                packet.offset + packet.length >= packet.offset) {
                net_send_udp_status(packet.seq, NET_TYPE_DATA, NET_STATUS_OK);
                continue;
            }
            if (packet.type == NET_TYPE_DATA &&
                packet.stream == NET_STREAM_DTB &&
                packet.offset + packet.length <= net_completed_dtb_size &&
                packet.offset + packet.length >= packet.offset) {
                net_send_udp_status(packet.seq, NET_TYPE_DATA, NET_STATUS_OK);
                continue;
            }
            net_send_udp_status(packet.seq, packet.type, NET_STATUS_BAD);
            continue;
        }
        if (packet.length == 0u ||
            packet.length > NET_CHUNK_SIZE ||
            packet.offset + packet.length > total_size ||
            packet.offset + packet.length < packet.offset) {
            net_send_udp_status(packet.seq, NET_TYPE_DATA, NET_STATUS_RANGE);
            return 8;
        }
        if (packet.offset < written &&
            packet.offset + packet.length <= written) {
            net_send_udp_status(packet.seq, NET_TYPE_DATA, NET_STATUS_OK);
            continue;
        }
        if (packet.offset != written) {
            net_send_udp_status(packet.seq, NET_TYPE_DATA, NET_STATUS_ORDER);
            continue;
        }

        for (index = 0u; index < packet.length; index++) {
            *(volatile u8 *)(address + written + index) = payload[index];
        }
        written += packet.length;
        net_send_udp_status(packet.seq, NET_TYPE_DATA, NET_STATUS_OK);
        boot_uart_put('C');
    }
    if (stream == NET_STREAM_IMAGE) {
        net_completed_image_size = total_size;
    } else if (stream == NET_STREAM_DTB) {
        net_completed_dtb_size = total_size;
    }
    return 0;
}

void netboot_send_boot_ack(void)
{
    net_send_udp_status(0u, NET_TYPE_BOOT, NET_STATUS_OK);
    boot_uart_put('B');
}
