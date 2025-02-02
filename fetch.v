`include "instrmem.v"
`include "adder.v"
`include "flopenr.v"
`include "mux6.v"
`include "branch_predictor.v"

module fetch(
    input clk,
    input reset,
    input stallf,
    input [1:0] pcsrcd, pcsrcd2,
    input [31:0] signextd, signextd2, pcd, pcbranchd, pcbranchd2,
    output [31:0] instrf, instrf2, pcplus4f, pcf,
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
        .pc(pcbranchd),              // Pass the branch address
        .branch_taken(pcsrcd[0]),    // Actual outcome of branch (taken or not)
        .instruction(instrf),        // Current instruction
        .predict(predict_taken)      // Predicted outcome (taken or not)
    );

    // FETCH - Cycle 1
    // Instruction Memory, Adder
    mux6 #(32) pcmux(pcplus4f, pcbranchd, signextd, signextd, signextd2, signextd2, muxselect, pcnext);
    flopenr #(32) pcreg(clk, reset, stallf, pcnext, pcf);
    adder pcadder(branchtoinstr, 32'h8, pcplus4f);
    instrmem instructmem(branchtoinstr, instrf, instrf2);

endmodule
