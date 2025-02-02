// // External unified memory used by MIPS multicycle processor.
// module instrmem(a, rd,rd2);
//   input [31:0] a;
//   output [31:0] rd,rd2;
   
//   reg [31:0] RAM[63:0];

//   integer i;

//   initial begin
//     for (i=21; i<64; i=i+1)  // CHANGE START VALUE WHENEVER YOU CHANGE RAM VALUES
//       RAM[i] = 32'b0;
//     $readmemh("memfile.dat",RAM); // "memfile.dat" contains your instructions in hex
//   end

//   assign rd = {RAM[a[31:2]]}; // word aligned
//   assign rd2 ={RAM[a[31:2]+30'h1]};
// endmodule
module instrmem (
  input [31:0] addr,       // آدرس ورودی
  output reg [31:0] instr  // دستور خروجی
);

  reg [31:0] mem [0:63];   // حافظه 64 کلمه‌ای

  // خواندن داده از فایل در آغاز شبیه‌سازی
  initial begin
      // بررسی و خواندن داده‌ها از فایل
      $readmemh("memfile.dat", mem, 0, 63);  // خواندن از فایل و ذخیره در حافظه
  end

  // دسترسی به حافظه بر اساس آدرس ورودی
  always @(*) begin
      instr = mem[addr[7:2]];  // فرض می‌کنیم addr[7:2] ایندکس حافظه است
  end

endmodule
