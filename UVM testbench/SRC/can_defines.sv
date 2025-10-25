// ================== Protocol (classic CAN only) ==================
`define CAN_ID_STD                 1'b0
`define CAN_ID_EXT                 1'b1

`define CAN_DATA_FRAME             2'b00
`define CAN_REMOTE_FRAME           2'b01
`define CAN_OVERLOAD_FRAME         2'b10
`define CAN_ERROR_FRAME            2'b11

`define CAN_STANDARD_ID_WIDTH      11
`define CAN_EXTENDED_ID_WIDTH      29
`define CAN_DLC_WIDTH              4
`define CAN_CRC_WIDTH              15
`define CAN_STUFF_LIMIT            5
`define CAN_INTERMISSION_BITS      3

// ================== Fixed register addresses =====================
`define CAN_MODE_REG               8'd0
`define CAN_COMMAND_REG            8'd1
`define CAN_STATUS_REG             8'd2
`define CAN_IRQ_REG                8'd3
`define CAN_BUS_TIMING_0           8'd6
`define CAN_BUS_TIMING_1           8'd7
`define CAN_CLOCK_DIVIDER          8'd31   // bit7 = extended_mode

// ================== BASIC mode addresses ========================
`define CAN_ACC_CODE0_BASIC        8'd4
`define CAN_ACC_MASK0_BASIC        8'd5
// TX data window (valid when ~reset_mode & transmit_buffer_status)
`define CAN_TX_DATA0_BASIC         8'd10   // bytes at 0x10..0x19 (idx 0..9)

// ================== EXTENDED mode addresses =====================
`define CAN_IRQ_EN_EXT             8'd4
`define CAN_ALC_EXT                8'd11   // Arbitration Lost Capture (RO)
`define CAN_ECC_EXT                8'd12   // Error Code Capture (RO)
`define CAN_ERR_WARN_LIM_EXT       8'd13
`define CAN_RX_ERR_CNT_EXT         8'd14
`define CAN_TX_ERR_CNT_EXT         8'd15
// Acceptance code/mask (in reset_mode)
`define CAN_ACC_CODE0_EXT          8'd16
`define CAN_ACC_CODE1_EXT          8'd17
`define CAN_ACC_CODE2_EXT          8'd18
`define CAN_ACC_CODE3_EXT          8'd19
`define CAN_ACC_MASK0_EXT          8'd20
`define CAN_ACC_MASK1_EXT          8'd21
`define CAN_ACC_MASK2_EXT          8'd22
`define CAN_ACC_MASK3_EXT          8'd23
// TX data window (valid when ~reset_mode & transmit_buffer_status)
`define CAN_TX_DATA0_EXT           8'd16   // bytes at 16..28 (idx 0..12)
`define CAN_RX_MSG_CNT_EXT         8'd29   // {1'b0, rx_message_counter}

// ================== MODE register bits (from RTL) ===============
`define CAN_MODE_RESET_BIT         0
`define CAN_MODE_RESET_M           (1 << `CAN_MODE_RESET_BIT)

// Extended-mode feature bits (only when extended_mode==1)
`define CAN_MODE_LISTEN_ONLY_BIT   1   // mode_ext[1]
`define CAN_MODE_SELF_TEST_BIT     2   // mode_ext[2]
`define CAN_MODE_ACC_FILTER_BIT    3   // mode_ext[3]
`define CAN_MODE_LISTEN_ONLY_M     (1 << `CAN_MODE_LISTEN_ONLY_BIT)
`define CAN_MODE_SELF_TEST_M       (1 << `CAN_MODE_SELF_TEST_BIT)
`define CAN_MODE_ACC_FILTER_M      (1 << `CAN_MODE_ACC_FILTER_BIT)

// BASIC-mode IRQ enables inside MODE (mode_basic[4:1])
`define CAN_MODE_IRQ_RX_EN_BIT     1
`define CAN_MODE_IRQ_TX_EN_BIT     2
`define CAN_MODE_IRQ_ERR_EN_BIT    3
`define CAN_MODE_IRQ_OVR_EN_BIT    4
`define CAN_MODE_IRQ_RX_EN_M       (1 << `CAN_MODE_IRQ_RX_EN_BIT)
`define CAN_MODE_IRQ_TX_EN_M       (1 << `CAN_MODE_IRQ_TX_EN_BIT)
`define CAN_MODE_IRQ_ERR_EN_M      (1 << `CAN_MODE_IRQ_ERR_EN_BIT)
`define CAN_MODE_IRQ_OVR_EN_M      (1 << `CAN_MODE_IRQ_OVR_EN_BIT)

// ================== COMMAND register bits (from RTL) ============
`define CAN_CMD_TXREQ_BIT          0
`define CAN_CMD_ABORT_BIT          1
`define CAN_CMD_REL_RX_BIT         2
`define CAN_CMD_CLR_OVR_BIT        3
`define CAN_CMD_SELF_RX_BIT        4
`define CAN_CMD_TXREQ_M            (1 << `CAN_CMD_TXREQ_BIT)
`define CAN_CMD_ABORT_M            (1 << `CAN_CMD_ABORT_BIT)
`define CAN_CMD_REL_RX_M           (1 << `CAN_CMD_REL_RX_BIT)
`define CAN_CMD_CLR_OVR_M          (1 << `CAN_CMD_CLR_OVR_BIT)
`define CAN_CMD_SELF_RX_M          (1 << `CAN_CMD_SELF_RX_BIT)
// Overload request not supported in this RTL (wired 0)

// ================== STATUS register bits (from RTL) =============
`define CAN_ST_BUS_OFF_BIT         7
`define CAN_ST_ERR_STAT_BIT        6
`define CAN_ST_TX_ACTIVE_BIT       5    // 'transmit_status'
`define CAN_ST_RX_ACTIVE_BIT       4    // 'receive_status'
`define CAN_ST_TX_COMPLETE_BIT     3
`define CAN_ST_TX_BUF_FREE_BIT     2    // 1 => buffer available
`define CAN_ST_OVERRUN_BIT         1
`define CAN_ST_RX_RDY_BIT          0

`define CAN_ST_BUS_OFF_M           (1 << `CAN_ST_BUS_OFF_BIT)
`define CAN_ST_ERR_STAT_M          (1 << `CAN_ST_ERR_STAT_BIT)
`define CAN_ST_TX_ACTIVE_M         (1 << `CAN_ST_TX_ACTIVE_BIT)
`define CAN_ST_RX_ACTIVE_M         (1 << `CAN_ST_RX_ACTIVE_BIT)
`define CAN_ST_TX_COMPLETE_M       (1 << `CAN_ST_TX_COMPLETE_BIT)
`define CAN_ST_TX_BUF_FREE_M       (1 << `CAN_ST_TX_BUF_FREE_BIT)
`define CAN_ST_OVERRUN_M           (1 << `CAN_ST_OVERRUN_BIT)
`define CAN_ST_RX_RDY_M            (1 << `CAN_ST_RX_RDY_BIT)

// ================== IRQ enable (Extended mode) ==================
`define CAN_IRQ_EN_BUS_ERR_BIT     7
`define CAN_IRQ_EN_ARB_LOST_BIT    6
`define CAN_IRQ_EN_ERR_PASS_BIT    5
`define CAN_IRQ_EN_DATA_OVR_BIT    3
`define CAN_IRQ_EN_ERR_WARN_BIT    2
`define CAN_IRQ_EN_TX_BIT          1
`define CAN_IRQ_EN_RX_BIT          0

`define CAN_IRQ_EN_BUS_ERR_M       (1 << `CAN_IRQ_EN_BUS_ERR_BIT)
`define CAN_IRQ_EN_ARB_LOST_M      (1 << `CAN_IRQ_EN_ARB_LOST_BIT)
`define CAN_IRQ_EN_ERR_PASS_M      (1 << `CAN_IRQ_EN_ERR_PASS_BIT)
`define CAN_IRQ_EN_DATA_OVR_M      (1 << `CAN_IRQ_EN_DATA_OVR_BIT)
`define CAN_IRQ_EN_ERR_WARN_M      (1 << `CAN_IRQ_EN_ERR_WARN_BIT)
`define CAN_IRQ_EN_TX_M            (1 << `CAN_IRQ_EN_TX_BIT)
`define CAN_IRQ_EN_RX_M            (1 << `CAN_IRQ_EN_RX_BIT)

// ================== Bus timing fields ===========================
`define CAN_BTR0_BRP_LO            0   // [5:0]
`define CAN_BTR0_BRP_HI            5
`define CAN_BTR0_SJW_LO            6   // [7:6]
`define CAN_BTR0_SJW_HI            7

`define CAN_BTR1_TSEG1_LO          0   // [3:0]
`define CAN_BTR1_TSEG1_HI          3
`define CAN_BTR1_TSEG2_LO          4   // [6:4]
`define CAN_BTR1_TSEG2_HI          6
`define CAN_BTR1_TRIPLE_SAMP_BIT   7
`define CAN_BTR1_TRIPLE_SAMP_M     (1 << `CAN_BTR1_TRIPLE_SAMP_BIT)

// Helpers to pack timing bytes (use in sequences)
`define CAN_PACK_BTR0(brp,sjw) \
  ( byte'(((sjw & 2'h3) << `CAN_BTR0_SJW_LO) | ((brp & 6'h3F) << `CAN_BTR0_BRP_LO)) )

`define CAN_PACK_BTR1(tseg1,tseg2,ts) \
  ( byte'(((ts & 1) << `CAN_BTR1_TRIPLE_SAMP_BIT) | ((tseg2 & 3'h7) << `CAN_BTR1_TSEG2_LO) | ((tseg1 & 4'hF) << `CAN_BTR1_TSEG1_LO)) )

// ================== Clock divider register ======================
`define CAN_CLKDIV_EXTENDED_BIT     7   // extended_mode
`define CAN_CLKDIV_CLOCK_OFF_BIT    3
`define CAN_CLKDIV_CODE_LO          0   // [2:0]
`define CAN_CLKDIV_CODE_HI          2
`define CAN_CLKDIV_EXTENDED_M       (1 << `CAN_CLKDIV_EXTENDED_BIT)
`define CAN_CLKDIV_CLOCK_OFF_M      (1 << `CAN_CLKDIV_CLOCK_OFF_BIT)

// ================== Address helpers =============================
`define CAN_TX_ADDR_BASIC(i)       (8'( `CAN_TX_DATA0_BASIC + (i) ))   // valid i: 0..9
`define CAN_TX_ADDR_EXT(i)         (8'( `CAN_TX_DATA0_EXT   + (i) ))   // valid i: 0..12

// ================== Misc / UVM IDs ==============================
`define MAX_CAN_NODES              4
`define DEFAULT_BIT_TIME_NS        100
`define MAX_DATA_BYTES             8

`define CAN_DRV_ID                 "CAN_DRV"
`define CAN_MON_ID                 "CAN_MON"
`define REG_DRV_ID                 "REG_DRV"
`define REG_MON_ID                 "REG_MON"
