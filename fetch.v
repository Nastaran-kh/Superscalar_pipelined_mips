// module fetch(clk, reset, stallf, pcsrcd, pcsrcd2, pcbranchd,pcbranchd2, signextd, signextd2, instrf, instrf2, pcplus4f, pcf, pcd, clrbp);
  
//   input  clk, reset, stallf;
//   input  [1:0] pcsrcd, pcsrcd2;
//   input  [31:0] signextd, signextd2, pcd, pcbranchd,pcbranchd2; 
//   output [31:0] instrf, pcplus4f, pcf, instrf2;
//   output clrbp;

//   // Internal signals of fetch module
//   wire [31:0] pcnext, branchtoinstr;

//   wire [2:0] muxselect;
//   assign muxselect = {pcsrcd2[1], pcsrcd};

//   // FETCH - Cycle 1
//   // Instr Mem, Adder
//   mux6  	  #(32) pcmux(pcplus4f, pcbranchd, signextd, signextd, signextd2, signextd2, muxselect, pcnext);
//   flopenr         #(32) pcreg(clk, reset, stallf, pcnext, pcf);
//   globalbranchpredictor branchpredictor(clk, pcsrcd,pcsrcd2, pcd, pcbranchd, pcbranchd2,{pcf,pcf+32'h4}, branchtoinstr, clrbp);
//   adder   	        pcadder(branchtoinstr, 32'h8, pcplus4f);
//   instrmem              instructmem(branchtoinstr, instrf,instrf2);

// endmodule

`include "instrmem.v"
`include "adder.v"
`include "flopenr.v"
`include "mux6.v"
`include "branch_predictor.v"
module fetch(clk, reset, stallf, pcsrcd, pcsrcd2, pcbranchd, pcbranchd2, signextd, signextd2, instrf, instrf2, pcplus4f, pcf, pcd, clrbp);
  
input  clk, reset, stallf;
input  [1:0] pcsrcd, pcsrcd2;
input  [31:0] signextd, signextd2, pcd, pcbranchd, pcbranchd2; 
output [31:0] instrf, pcplus4f, pcf, instrf2;
output clrbp;

// Internal signals of fetch module
wire [31:0] pcnext, branchtoinstr;
wire predict_taken;

wire [2:0] muxselect;
assign muxselect = {pcsrcd2[1], pcsrcd};

// Branch Predictor Integration
branch_predictor #(
    .PREDICTOR_MODE(4),  // Gshare + Bimodal
    .GBHR_SIZE(7),
    .BHT_SIZE(512)
) bp (
    .clk(clk),
    .rst(reset),
    .pc_in(pcf),
    .predict_taken(predict_taken),
    .update_en(clrbp),
    .update_pc(pcbranchd),
    .actual_taken(pcsrcd[0])
);

// FETCH - Cycle 1
// Instr Mem, Adder
mux6  	  #(32) pcmux(pcplus4f, pcbranchd, signextd, signextd, signextd2, signextd2, muxselect, pcnext);
flopenr         #(32) pcreg(clk, reset, stallf, pcnext, pcf);
adder   	        pcadder(branchtoinstr, 32'h8, pcplus4f);
instrmem              instructmem(branchtoinstr, instrf, instrf2);

endmodule
