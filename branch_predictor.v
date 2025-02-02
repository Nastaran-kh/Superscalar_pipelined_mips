module branch_predictor (
    input clk,
    input reset,
    input [31:0] pc,          // Program counter
    input branch_taken,       // آیا شاخه واقعی گرفته شده است؟
    input [31:0] instruction, // دستور فعلی
    output reg predict        // پیش‌بینی شده: آیا شاخه گرفته شده است؟
);

    // جداول و متغیرها
    reg [1:0] gshare_bht [0:511];  // جدول پیش‌بینی Gshare (512 ورودی)
    reg [1:0] bimodal_bht [0:511]; // جدول پیش‌بینی Bimodal (512 ورودی)
    reg [1:0] counts [0:511];      // جدول Counts (حاوی FSM برای انتخاب بهترین پیش‌بین)
    reg [6:0] gbhr;                // Global Branch History Register (7 بیت)
    reg always_true_mode, always_false_mode;  // تنظیمات برای پیش‌بینی همیشه درست یا همیشه غلط
    reg [1:0] prediction_mode; // حالت پیش‌بینی (گshare، bimodal، همیشه درست، همیشه غلط)

    wire [8:0] gshare_index;   // ایندکس برای Gshare
    wire [8:0] bimodal_index;  // ایندکس برای Bimodal

    // ایندکس برای Gshare
    assign gshare_index = {pc[8:0], gbhr[6:0]}; // XOR کردن PC و GBHR برای Gshare

    // ایندکس برای Bimodal (پایه روی 9 بیت)
    assign bimodal_index = pc[8:0];

    // پیش‌بینی Gshare
    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            gbhr <= 7'b0000000;
        end else begin
            if (branch_taken)
                gbhr <= {gbhr[5:0], 1'b1};  // اگر شاخه گرفته شده باشد
            else
                gbhr <= {gbhr[5:0], 1'b0};  // اگر شاخه گرفته نشده باشد
        end
    end

    // پیش‌بینی Gshare
    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            predict <= 0;
        end else begin
            case (prediction_mode)
                2'b00: begin  // Gshare prediction
                    predict <= (gshare_bht[gshare_index] >= 2'b10);
                end
                2'b01: begin  // Bimodal prediction
                    predict <= (bimodal_bht[bimodal_index] >= 2'b10);
                end
                2'b10: begin  // Always True
                    predict <= 1;
                end
                2'b11: begin  // Always False
                    predict <= 0;
                end
            endcase
        end
    end
    integer i;
    // به‌روزرسانی جداول پیش‌بینی Gshare و Bimodal
    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            // همه جداول به حالت اولیه
            
            for (i = 0; i < 512; i = i + 1) begin
                gshare_bht[i] <= 2'b01;  // پیش‌بینی ضعیف
                bimodal_bht[i] <= 2'b01; // پیش‌بینی ضعیف
                counts[i] <= 2'b00;      // حالت اولیه برای FSM Counts
            end
        end else begin
            // به‌روزرسانی جداول پیش‌بینی Gshare و Bimodal
            if (branch_taken) begin
                if (gshare_bht[gshare_index] < 2'b11)
                    gshare_bht[gshare_index] <= gshare_bht[gshare_index] + 1;  // افزایش پیش‌بینی Gshare
                if (bimodal_bht[bimodal_index] < 2'b11)
                    bimodal_bht[bimodal_index] <= bimodal_bht[bimodal_index] + 1;  // افزایش پیش‌بینی Bimodal
            end else begin
                if (gshare_bht[gshare_index] > 2'b00)
                    gshare_bht[gshare_index] <= gshare_bht[gshare_index] - 1;  // کاهش پیش‌بینی Gshare
                if (bimodal_bht[bimodal_index] > 2'b00)
                    bimodal_bht[bimodal_index] <= bimodal_bht[bimodal_index] - 1;  // کاهش پیش‌بینی Bimodal
            end

            // به‌روزرسانی Counts FSM (این کار پیش‌بینی بهتر را انتخاب می‌کند)
            if (counts[gshare_index] == 2'b00 || counts[gshare_index] == 2'b01) begin
                counts[gshare_index] <= counts[gshare_index] + 1;  // گام به گام به سمت بهتر شدن
            end else if (counts[gshare_index] == 2'b10 || counts[gshare_index] == 2'b11) begin
                counts[gshare_index] <= counts[gshare_index] - 1;  // گام به گام به سمت بدتر شدن
            end
        end
    end

    // تنظیمات حالت پیش‌بینی برای پنج نوع پیش‌بینی
    always @ (posedge clk or posedge reset) begin
        if (reset) begin
            prediction_mode <= 2'b00;  // پیش‌فرض: Gshare
        end else begin
            // اینجا می‌توانید مد پیش‌بینی را بر اساس شرایط خاص یا سیگنال‌ها تغییر دهید
            // مثلا: انتخاب پیش‌بینی گshare یا bimodal بر اساس نیاز
        end
    end

endmodule
