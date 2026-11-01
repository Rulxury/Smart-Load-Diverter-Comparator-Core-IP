//==============================================================================
// Smart Load-Diverter Comparator - APB Slave Peripheral
//==============================================================================
// File       : smart_diverter_apb.v
// Description: Custom IP core that compares real-time sensor current against
//              an AI-injected threshold and drives a solid-state relay output.
//              Operates as an APB3/APB4 slave peripheral in an ARM-based SoC.
//
// Register Map:
//   Offset 0x00 - CTRL_REG      (R/W)  : Bit[0]=EN, Bit[1]=MODE
//   Offset 0x04 - STAT_REG      (RO)   : Bit[0]=relay status
//   Offset 0x08 - THRESHOLD_REG (R/W)  : 32-bit threshold from Edge-AI
//   Offset 0x0C - SENSOR_REG    (RO)   : 32-bit live sensor readback
//==============================================================================

module smart_diverter_apb (
    // ---- System Signals ----
    input  wire        PCLK,
    input  wire        PRESETn,

    // ---- APB Slave Interface ----
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY,

    // ---- Custom Hardware Signals ----
    input  wire [31:0] sensor_current_in,
    output wire        relay_out
);

    //==========================================================================
    // Internal Register Declarations
    //==========================================================================
    reg [31:0] ctrl_reg;       // Offset 0x00 - Control Register
    reg [31:0] threshold_reg;  // Offset 0x08 - AI Threshold Register

    // Wire aliases for readability
    wire       ctrl_en;        // CTRL_REG[0] - System Enable
    wire       ctrl_mode;      // CTRL_REG[1] - Mode Select (1=AI, 0=Manual)

    assign ctrl_en   = ctrl_reg[0];
    assign ctrl_mode = ctrl_reg[1];

    //==========================================================================
    // APB Ready Signal
    //==========================================================================
    // Zero wait-state slave: always ready
    assign PREADY = 1'b1;

    //==========================================================================
    // APB Write Logic (Sequential)
    //==========================================================================
    // Handles writes to CTRL_REG and THRESHOLD_REG on the access phase
    // of an APB write transaction (PSEL & PENABLE & PWRITE).
    //==========================================================================
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            ctrl_reg      <= 32'd0;
            threshold_reg <= 32'd0;
        end else begin
            if (PSEL && PENABLE && PWRITE) begin
                case (PADDR[3:0])
                    4'h0: ctrl_reg      <= PWDATA;  // Write to CTRL_REG
                    4'h8: threshold_reg <= PWDATA;  // Write to THRESHOLD_REG
                    // Writes to STAT_REG (0x04) and SENSOR_REG (0x0C) are
                    // ignored since they are read-only registers.
                    default: ; // No operation
                endcase
            end
        end
    end

    //==========================================================================
    // APB Read Logic (Combinational)
    //==========================================================================
    // Fills PRDATA based on the address offset. Uses a fully-specified case
    // with a default branch to avoid inferred latches.
    //==========================================================================
    always @(*) begin
        case (PADDR[3:0])
            4'h0:    PRDATA = ctrl_reg;             // CTRL_REG
            4'h4:    PRDATA = {31'd0, relay_out};   // STAT_REG (bit[0] = relay status)
            4'h8:    PRDATA = threshold_reg;        // THRESHOLD_REG
            4'hC:    PRDATA = sensor_current_in;    // SENSOR_REG (live sensor value)
            default: PRDATA = 32'd0;                // Unmapped addresses read as zero
        endcase
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
    assign relay_out = (ctrl_en) && (sensor_current_in > threshold_reg);

endmodule
