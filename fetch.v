`include "instrmem.v"
`include "adder.v"
`include "flopenr.v"
`include "mux6.v"
`include "branch_predictor.v"
module fetch(
    input clk,
    input reset,
    input stallf,
    input [1:0] pcsrcd,
    input [1:0] pcsrcd2,
    input [31:0] signextd,
    input [31:0] signextd2,
    input [31:0] pcd,
    input [31:0] pcbranchd,
    input [31:0] pcbranchd2,
    output [31:0] instrf,
    output [31:0] pcplus4f,
    output [31:0] pcf,
    output [31:0] instrf2,
    output clrbp
);
  
    // Internal signals of fetch module
    wire [31:0] pcnext, branchtoinstr;
    wire predict_taken;

    wire [2:0] muxselect;
    assign muxselect = {pcsrcd2[1], pcsrcd};

    // Branch Predictor Integration
    branch_predictor bp (
        .clk(clk),
        .reset(reset),
        .pc(pcf),        // ورودی صحیح
        .branch_taken(predict_taken),  // شاخه واقعی گرفته شده
        .instruction(instrf), // ورودی دستور
        .predict(predict_taken) // پیش‌بینی شده
    );

    // FETCH - Cycle 1
    // Instr Mem, Adder
    mux6 #(32) pcmux(
        .d0(pcplus4f), 
        .d1(pcbranchd), 
        .d2(signextd), 
        .d3(signextd), 
        .d4(signextd2), 
        .d5(signextd2), 
        .s(muxselect), 
        .y(pcnext)
    );

    flopenr #(32) pcreg(
        .clk(clk), 
        .reset(reset), 
        .en(~stallf), 
        .d(pcnext), 
        .q(pcf)
    );

    adder pcadder(
        .a(branchtoinstr), 
        .b(32'h8), 
        .cout(pcplus4f)
    );

    instrmem instructmem(
        .addr(branchtoinstr), 
        .instr(instrf) // خروجی صحیح
    );

endmodule
