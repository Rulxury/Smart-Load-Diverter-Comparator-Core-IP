//==============================================================================
// Smart Load-Diverter Comparator - AXI4-Lite Slave Peripheral
//==============================================================================
// File       : smart_diverter_axi.v
// Description: Custom IP core that compares real-time sensor current against
//              an AI-injected threshold and drives a solid-state relay output.
//              Uses AXI4-Lite slave interface for native Vivado/Zynq integration.
//
// Register Map (identical functionality to APB version):
//   Offset 0x00 - CTRL_REG      (R/W)  : Bit[0]=EN, Bit[1]=MODE
//   Offset 0x04 - STAT_REG      (RO)   : Bit[0]=relay status
//   Offset 0x08 - THRESHOLD_REG (R/W)  : 32-bit threshold from Edge-AI
//   Offset 0x0C - SENSOR_REG    (RO)   : 32-bit live sensor readback
//
// AXI4-Lite Compliance:
//   - All write responses are OKAY (2'b00)
//   - All read responses are OKAY (2'b00)
//   - No wait states (single-cycle response)
//   - Write strobes (WSTRB) supported for byte-level access
//==============================================================================

module smart_diverter_axi #(
    // AXI4-Lite Parameters (Vivado auto-detects these)
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4
)(
    // ---- AXI4-Lite Slave Interface ----
    input  wire                                S_AXI_ACLK,
    input  wire                                S_AXI_ARESETN,

    // Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_AWADDR,
    input  wire [2:0]                          S_AXI_AWPROT,
    input  wire                                S_AXI_AWVALID,
    output wire                                S_AXI_AWREADY,

    // Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]   S_AXI_WSTRB,
    input  wire                                S_AXI_WVALID,
    output wire                                S_AXI_WREADY,

    // Write Response Channel
    output wire [1:0]                          S_AXI_BRESP,
    output wire                                S_AXI_BVALID,
    input  wire                                S_AXI_BREADY,

    // Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]       S_AXI_ARADDR,
    input  wire [2:0]                          S_AXI_ARPROT,
    input  wire                                S_AXI_ARVALID,
    output wire                                S_AXI_ARREADY,

    // Read Data Channel
    output wire [C_S_AXI_DATA_WIDTH-1:0]       S_AXI_RDATA,
    output wire [1:0]                          S_AXI_RRESP,
    output wire                                S_AXI_RVALID,
    input  wire                                S_AXI_RREADY,

    // ---- Custom Hardware Signals ----
    input  wire [31:0]                         sensor_current_in,
    output wire                                relay_out
);

    //==========================================================================
    // Local Parameters
    //==========================================================================
    localparam ADDR_LSB        = 2;  // 32-bit aligned: ignore 2 LSBs
    localparam OPT_ADDR_BITS   = 1;  // 2 bits needed for 4 registers (0-3)

    // Register address indices (after removing 2 LSBs)
    localparam CTRL_REG_ADDR      = 2'b00;  // Offset 0x00
    localparam STAT_REG_ADDR      = 2'b01;  // Offset 0x04
    localparam THRESHOLD_REG_ADDR = 2'b10;  // Offset 0x08
    localparam SENSOR_REG_ADDR    = 2'b11;  // Offset 0x0C

    //==========================================================================
    // Internal Registers
    //==========================================================================
    reg [31:0] ctrl_reg;       // Control Register
    reg [31:0] threshold_reg;  // AI Threshold Register

    //==========================================================================
    // AXI4-Lite Handshake Registers
    //==========================================================================
    reg        axi_awready;
    reg        axi_wready;
    reg [1:0]  axi_bresp;
    reg        axi_bvalid;
    reg        axi_arready;
    reg [31:0] axi_rdata;
    reg [1:0]  axi_rresp;
    reg        axi_rvalid;

    // Latched addresses
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;

    // Write transaction tracking
    reg        aw_en;  // Write address handshake enable

    //==========================================================================
    // Output Assignments
    //==========================================================================
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    //==========================================================================
    // Write Address Channel (AWREADY)
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else if (S_AXI_BREADY && axi_bvalid) begin
                aw_en       <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Latch Write Address
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awaddr <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (~axi_awready && S_AXI_AWVALID && S_AXI_WVALID && aw_en)
                axi_awaddr <= S_AXI_AWADDR;
        end
    end

    //==========================================================================
    // Write Data Channel (WREADY)
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_wready <= 1'b0;
        end else begin
            if (~axi_wready && S_AXI_WVALID && S_AXI_AWVALID && aw_en)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;
        end
    end

    //==========================================================================
    // Register Write Logic (with byte-level write strobes)
    //==========================================================================
    wire       slv_reg_wen;
    wire [1:0] wr_addr_index;

    assign slv_reg_wen  = axi_wready && S_AXI_WVALID && axi_awready && S_AXI_AWVALID;
    assign wr_addr_index = axi_awaddr[ADDR_LSB+OPT_ADDR_BITS : ADDR_LSB];

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            ctrl_reg      <= 32'd0;
            threshold_reg <= 32'd0;
        end else begin
            if (slv_reg_wen) begin
                case (wr_addr_index)
                    CTRL_REG_ADDR: begin
                        // Byte 0
                        if (S_AXI_WSTRB[0])
                            ctrl_reg[7:0]   <= S_AXI_WDATA[7:0];
                        // Byte 1
                        if (S_AXI_WSTRB[1])
                            ctrl_reg[15:8]  <= S_AXI_WDATA[15:8];
                        // Byte 2
                        if (S_AXI_WSTRB[2])
                            ctrl_reg[23:16] <= S_AXI_WDATA[23:16];
                        // Byte 3
                        if (S_AXI_WSTRB[3])
                            ctrl_reg[31:24] <= S_AXI_WDATA[31:24];
                    end
                    THRESHOLD_REG_ADDR: begin
                        if (S_AXI_WSTRB[0])
                            threshold_reg[7:0]   <= S_AXI_WDATA[7:0];
                        if (S_AXI_WSTRB[1])
                            threshold_reg[15:8]  <= S_AXI_WDATA[15:8];
                        if (S_AXI_WSTRB[2])
                            threshold_reg[23:16] <= S_AXI_WDATA[23:16];
                        if (S_AXI_WSTRB[3])
                            threshold_reg[31:24] <= S_AXI_WDATA[31:24];
                    end
                    // STAT_REG (0x04) and SENSOR_REG (0x0C) are read-only
                    // Writes are silently ignored
                    default: ;
                endcase
            end
        end
    end

    //==========================================================================
    // Write Response Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (axi_awready && S_AXI_AWVALID && ~axi_bvalid && axi_wready && S_AXI_WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b00;  // OKAY response
            end else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Read Address Channel (ARREADY)
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        end else begin
            if (~axi_arready && S_AXI_ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= S_AXI_ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Read Data Channel (RVALID + RDATA)
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin
            if (axi_arready && S_AXI_ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= 2'b00;  // OKAY response
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Register Read Logic
    //==========================================================================
    wire [1:0] rd_addr_index;
    reg  [31:0] reg_data_out;

    assign rd_addr_index = axi_araddr[ADDR_LSB+OPT_ADDR_BITS : ADDR_LSB];

    always @(*) begin
        case (rd_addr_index)
            CTRL_REG_ADDR:      reg_data_out = ctrl_reg;
            STAT_REG_ADDR:      reg_data_out = {31'd0, relay_out};
            THRESHOLD_REG_ADDR: reg_data_out = threshold_reg;
            SENSOR_REG_ADDR:    reg_data_out = sensor_current_in;
            default:            reg_data_out = 32'd0;
        endcase
    end

    // Output RDATA on valid read transaction
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN)
            axi_rdata <= 32'd0;
        else if (axi_arready && S_AXI_ARVALID && ~axi_rvalid)
            axi_rdata <= reg_data_out;
    end

    //==========================================================================
    // Diverting Logic - Power Comparator (Combinational)
    //==========================================================================
    // relay_out = 1 (divert power) IF AND ONLY IF:
    //   1. System is enabled              (CTRL_REG[0] == 1)
    //   2. sensor_current_in > threshold  (current exceeds AI-set limit)
    //
    // When the system is disabled (EN=0), relay_out is forced to 0.
    //==========================================================================
    wire ctrl_en;
    assign ctrl_en  = ctrl_reg[0];
    assign relay_out = ctrl_en && (sensor_current_in > threshold_reg);

endmodule
