//==============================================================================
// Testbench - Smart Load-Diverter Comparator (APB Slave)
//==============================================================================
// File       : tb_smart_diverter_apb.v
// Description: Validates the smart_diverter_apb IP through a sequence of
//              APB bus transactions simulating Hardware-Software Co-design
//              with an Edge-AI processor.
//
// Test Scenarios:
//   1. Reset & Initialization
//   2. APB Write: Inject AI threshold (5000) to THRESHOLD_REG
//   3. APB Write: Enable system via CTRL_REG
//   4. Sensor sweep: below threshold -> above threshold -> below again
//   5. APB Read: Verify all registers via bus reads
//   6. Disable system and verify relay forced off
//==============================================================================

`timescale 1ns / 1ps

module tb_smart_diverter_apb;

    //==========================================================================
    // Signal Declarations
    //==========================================================================
    reg         PCLK;
    reg         PRESETn;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [31:0] PADDR;
    reg  [31:0] PWDATA;
    wire [31:0] PRDATA;
    wire        PREADY;

    reg  [31:0] sensor_current_in;
    wire        relay_out;

    // Test tracking
    integer test_pass;
    integer test_fail;
    integer test_num;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    smart_diverter_apb uut (
        .PCLK             (PCLK),
        .PRESETn          (PRESETn),
        .PSEL             (PSEL),
        .PENABLE          (PENABLE),
        .PWRITE           (PWRITE),
        .PADDR            (PADDR),
        .PWDATA           (PWDATA),
        .PRDATA           (PRDATA),
        .PREADY           (PREADY),
        .sensor_current_in(sensor_current_in),
        .relay_out        (relay_out)
    );

    //==========================================================================
    // Clock Generation - 100 MHz (10 ns period)
    //==========================================================================
    initial PCLK = 1'b0;
    always #5 PCLK = ~PCLK;

    //==========================================================================
    // APB Write Task
    //==========================================================================
    // Performs a single APB write transaction (2-cycle: SETUP + ACCESS).
    //==========================================================================
    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            // SETUP phase
            @(posedge PCLK);
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b1;
            PADDR   <= addr;
            PWDATA  <= data;

            // ACCESS phase
            @(posedge PCLK);
            PENABLE <= 1'b1;

            // Wait for PREADY (always high in this design)
            @(posedge PCLK);
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PADDR   <= 32'd0;
            PWDATA  <= 32'd0;
        end
    endtask

    //==========================================================================
    // APB Read Task
    //==========================================================================
    // Performs a single APB read transaction (2-cycle: SETUP + ACCESS).
    // Returns the data read from the slave.
    //==========================================================================
    task apb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            // SETUP phase
            @(posedge PCLK);
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PADDR   <= addr;

            // ACCESS phase
            @(posedge PCLK);
            PENABLE <= 1'b1;

            // Sample PRDATA at the end of the access phase
            @(posedge PCLK);
            data = PRDATA;
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PADDR   <= 32'd0;
        end
    endtask

    //==========================================================================
    // Check / Assertion Helper
    //==========================================================================
    task check;
        input [255:0] test_name;  // Padded string for test description
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            test_num = test_num + 1;
            if (actual === expected) begin
                $display("[PASS] Test %0d: %0s | Expected=0x%08h, Got=0x%08h",
                         test_num, test_name, expected, actual);
                test_pass = test_pass + 1;
            end else begin
                $display("[FAIL] Test %0d: %0s | Expected=0x%08h, Got=0x%08h",
                         test_num, test_name, expected, actual);
                test_fail = test_fail + 1;
            end
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    reg [31:0] read_data;

    initial begin
        // Waveform dump for viewer
        $dumpfile("tb_smart_diverter_apb.vcd");
        $dumpvars(0, tb_smart_diverter_apb);

        // Initialize counters
        test_pass = 0;
        test_fail = 0;
        test_num  = 0;

        // Initialize APB signals
        PSEL              = 1'b0;
        PENABLE           = 1'b0;
        PWRITE            = 1'b0;
        PADDR             = 32'd0;
        PWDATA            = 32'd0;
        sensor_current_in = 32'd0;

        $display("==============================================================");
        $display("  Smart Load-Diverter Comparator - Testbench");
        $display("==============================================================");

        //----------------------------------------------------------------------
        // Scenario 1: Reset
        //----------------------------------------------------------------------
        $display("\n--- Scenario 1: Reset & Initialization ---");
        PRESETn = 1'b0;       // Assert reset
        repeat (4) @(posedge PCLK);
        PRESETn = 1'b1;       // De-assert reset
        @(posedge PCLK);

        // After reset, relay_out must be 0 (system disabled)
        check("relay_out after reset", {31'd0, relay_out}, 32'd0);

        // Read CTRL_REG -> should be 0
        apb_read(32'h00, read_data);
        check("CTRL_REG after reset", read_data, 32'd0);

        // Read THRESHOLD_REG -> should be 0
        apb_read(32'h08, read_data);
        check("THRESHOLD_REG after reset", read_data, 32'd0);

        //----------------------------------------------------------------------
        // Scenario 2: APB Write - Inject AI Threshold = 5000
        //----------------------------------------------------------------------
        $display("\n--- Scenario 2: Write AI Threshold (5000) ---");
        apb_write(32'h08, 32'd5000);

        // Readback verification
        apb_read(32'h08, read_data);
        check("THRESHOLD_REG readback", read_data, 32'd5000);

        //----------------------------------------------------------------------
        // Scenario 3: Enable System (CTRL_REG[0] = 1)
        //----------------------------------------------------------------------
        $display("\n--- Scenario 3: Enable System ---");
        apb_write(32'h00, 32'd1);   // EN=1, MODE=0

        // Readback verification
        apb_read(32'h00, read_data);
        check("CTRL_REG readback", read_data, 32'd1);

        // relay_out should still be 0 (sensor=0 < threshold=5000)
        #1; // Allow combinational logic to settle
        check("relay_out with sensor=0", {31'd0, relay_out}, 32'd0);

        //----------------------------------------------------------------------
        // Scenario 4a: Sensor below threshold (3000 < 5000)
        //----------------------------------------------------------------------
        $display("\n--- Scenario 4a: Sensor = 3000 (Below Threshold) ---");
        sensor_current_in = 32'd3000;
        #1; // Combinational settle time
        check("relay_out (sensor=3000 < thresh=5000)", {31'd0, relay_out}, 32'd0);

        // Read SENSOR_REG -> should reflect live sensor value
        apb_read(32'h0C, read_data);
        check("SENSOR_REG readback (3000)", read_data, 32'd3000);

        // Read STAT_REG -> relay status = 0
        apb_read(32'h04, read_data);
        check("STAT_REG (relay off)", read_data, 32'd0);

        //----------------------------------------------------------------------
        // Scenario 4b: Sensor above threshold (6000 > 5000) -> DIVERT!
        //----------------------------------------------------------------------
        $display("\n--- Scenario 4b: Sensor = 6000 (Above Threshold) -> DIVERT ---");
        sensor_current_in = 32'd6000;
        #1; // Combinational settle time
        check("relay_out (sensor=6000 > thresh=5000)", {31'd0, relay_out}, 32'd1);

        // Read SENSOR_REG -> should reflect 6000
        apb_read(32'h0C, read_data);
        check("SENSOR_REG readback (6000)", read_data, 32'd6000);

        // Read STAT_REG -> relay status = 1
        apb_read(32'h04, read_data);
        check("STAT_REG (relay on)", read_data, 32'd1);

        //----------------------------------------------------------------------
        // Scenario 4c: Sensor drops below threshold (2000 < 5000)
        //----------------------------------------------------------------------
        $display("\n--- Scenario 4c: Sensor = 2000 (Below Threshold) ---");
        sensor_current_in = 32'd2000;
        #1; // Combinational settle time
        check("relay_out (sensor=2000 < thresh=5000)", {31'd0, relay_out}, 32'd0);

        // Read SENSOR_REG -> should reflect 2000
        apb_read(32'h0C, read_data);
        check("SENSOR_REG readback (2000)", read_data, 32'd2000);

        // Read STAT_REG -> relay status = 0
        apb_read(32'h04, read_data);
        check("STAT_REG (relay off again)", read_data, 32'd0);

        //----------------------------------------------------------------------
        // Scenario 5: Boundary test (sensor == threshold exactly)
        //----------------------------------------------------------------------
        $display("\n--- Scenario 5: Sensor = 5000 (Equal to Threshold) ---");
        sensor_current_in = 32'd5000;
        #1;
        // Equal is NOT greater, so relay should remain OFF
        check("relay_out (sensor=5000 == thresh=5000)", {31'd0, relay_out}, 32'd0);

        //----------------------------------------------------------------------
        // Scenario 6: Disable system -> relay forced off
        //----------------------------------------------------------------------
        $display("\n--- Scenario 6: Disable System ---");
        sensor_current_in = 32'd9000;  // Sensor is way above threshold
        #1;
        check("relay_out before disable (sensor=9000)", {31'd0, relay_out}, 32'd1);

        apb_write(32'h00, 32'd0);     // Disable system (EN=0)
        #1;
        check("relay_out after disable", {31'd0, relay_out}, 32'd0);

        //----------------------------------------------------------------------
        // Scenario 7: Write to read-only register (should be ignored)
        //----------------------------------------------------------------------
        $display("\n--- Scenario 7: Write to Read-Only Registers ---");
        apb_write(32'h04, 32'hDEADBEEF);  // Write to STAT_REG (RO)
        apb_read(32'h04, read_data);
        check("STAT_REG unchanged after write", read_data, 32'd0);

        apb_write(32'h0C, 32'hCAFEBABE);  // Write to SENSOR_REG (RO)
        apb_read(32'h0C, read_data);
        check("SENSOR_REG unchanged after write", read_data, 32'd9000);

        //----------------------------------------------------------------------
        // Scenario 8: PREADY always high
        //----------------------------------------------------------------------
        $display("\n--- Scenario 8: PREADY Signal ---");
        check("PREADY always asserted", {31'd0, PREADY}, 32'd1);

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("\n==============================================================");
        $display("  TEST SUMMARY");
        $display("==============================================================");
        $display("  Total : %0d", test_pass + test_fail);
        $display("  PASSED: %0d", test_pass);
        $display("  FAILED: %0d", test_fail);
        $display("==============================================================");

        if (test_fail == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");

        $display("==============================================================\n");

        #100;
        $finish;
    end

endmodule
