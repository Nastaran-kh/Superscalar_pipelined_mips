
module branch_predictor #(
    parameter PREDICTOR_MODE = 0,   // 0: Always Taken
                                    // 1: Always Not Taken
                                    // 2: GAs
                                    // 3: Gshare
                                    // 4: Gshare + Bimodal (Hybrid)
    parameter GBHR_SIZE      = 7,   // اندازه‌ی رجیستر تاریخچه‌ی جهانی
    parameter BHT_SIZE       = 512  // اندازه‌ی جدول تاریخچه (بایت یا Entry)
)(
    input               clk,
    input               rst,

    // ورودی‌های لازم برای Prediction
    input      [31:0]   pc_in,         // PC کنونی که می‌خواهیم درباره‌ی آن Prediction داشته باشیم
    output reg          predict_taken, // نتیجه‌ی پیش‌بینی (Taken/Not Taken)

    // ورودی/خروجی‌های لازم برای Update
    // وقتی شاخه واقعاً resolve شد (در EX یا MEM یا WB)، اطلاعات زیر برای آپدیت فرستاده شوند:
    input               update_en,     // سیگنال اعتبار برای آپدیت
    input      [31:0]   update_pc,     // PC مربوط به شاخه‌ای که resolve شد
    input               actual_taken   // نتیجه‌ی واقعی شاخه (1: Taken, 0: Not Taken)
);

    //========================================================================
    //  بخش 1: سیگنال‌ها و حافظه‌های لازم
    //========================================================================

    // رجیستر تاریخچه‌ی جهانی (GBHR)
    reg [GBHR_SIZE-1:0] gbhr_reg;

    // برای GAs و Gshare نیاز به جدول‌های پیش‌بینی داریم (BHT: Branch History Table)
    // هر خانه 2 بیت است (یک FSM اشباع شونده‌ی 4 حالته)
    // مقدار 00: strongly not taken
    //         01: weakly not taken
    //         10: weakly taken
    //         11: strongly taken
    // به صورت reg [1:0] bht_array [0 : BHT_SIZE-1] تعریف می‌کنیم.
    reg [1:0] bht_gas    [0 : BHT_SIZE-1];
    reg [1:0] bht_gshare [0 : BHT_SIZE-1];

    // برای هیبرید (Gshare + Bimodal)، علاوه بر bht_gshare، نیاز داریم به:
    //  - یک BHT ساده برای بای‌مودال (bht_bimodal)
    //  - یک جدول Counts به منظور انتخاب اینکه کدام پیش‌بینی (gshare یا bimodal) بهتر عمل می‌کند.
    reg [1:0] bht_bimodal [0 : BHT_SIZE-1];
    reg [1:0] chooser     [0 : BHT_SIZE-1];  // همان جدول Counts یا Meta-table (2 بیت)

    // اندیس نهایی برای دسترسی به جداول
    wire [GBHR_SIZE-1:0] gbhr_index;      // برای GAs
    wire [8:0]           pc_index_9bit;   // ممکن است از بیت‌های میانی یا پایینی PC استفاده کنیم
    wire [8:0]           gas_index;       // اندیس GAs
    wire [8:0]           gshare_index;    // اندیس Gshare
    wire [8:0]           bimodal_index;   // اندیس برای Bimodal

    //========================================================================
    //  بخش 2: تولید اندیس برای دسترسی به جداول
    //========================================================================

    // به عنوان یک مثال ساده، از بیت‌های 10:2 از PC برای ایندکس 9بیتی استفاده می‌کنیم
    // (این را با طراحی خودتان هماهنگ کنید)
    assign pc_index_9bit = pc_in[10:2];

    // 1) برای GAs:
    //    اندیس جدول = ترکیب PC_index + GBHR (بسته به طراحی می‌توان فقط از GBHR استفاده کرد
    //    یا از بیت‌های پایین PC استفاده کرد. در اینجا فقط از رجیستر جهانی استفاده می‌کنیم.)
    //    برای سادگی در این مثال، فرض می‌کنیم سایز جدول ما 512 است که می‌شود 9 بیت.
    //    اما GBHR_SIZE=7 داریم؛ پس اگر واقعاً بخواهیم کل ایندکس را از GBHR بگیریم،
    //    باید فقط 9 بیت را بسازیم. ما می‌توانیم 7 بیت از GBHR و 2 بیت از PC یا هر روش دلخواه.
    //    این فقط یک مثال است.
    assign gbhr_index = gbhr_reg; // 7 بیت هست؛ ما برای اینکه 9 بیت داشته باشیم 2 بیت اضافه از pc می‌گیریم:
    assign gas_index  = {pc_in[3:2], gbhr_index};  // شد 9 بیت (2 بیت از PC + 7 بیت از GBHR)

    // 2) برای Gshare:
    //    باید بالا یا میانه‌های PC_index را با gbhr_reg XOR کنیم.
    //    برای سادگی، همان pc_index_9bit را XOR می‌کنیم با gbhr_reg (در صورت تطابق سایز).
    //    اگر GBHR_SIZE=7 باشد، ما می‌توانیم 7 بیت پایین pc_index_9bit را XOR کنیم.
    wire [6:0] lower_pc_index = pc_index_9bit[6:0];
    wire [6:0] xored_index = lower_pc_index ^ gbhr_reg[6:0];  // 7 بیت XOR
    // حالا با دو بیت بالای pc_index_9bit یکجا می‌کنیم
    assign gshare_index = { pc_index_9bit[8:7], xored_index }; // 2 بیت بالا + 7 بیت XOR شده = 9 بیت

    // 3) برای Bimodal (همان استفاده ساده از pc_index_9bit):
    assign bimodal_index = pc_index_9bit;

    //========================================================================
    //  بخش 3: منطق پیش‌بینی (Predict) در هر کلاک - خروجی predict_taken
    //========================================================================
    wire [1:0] gas_counter_val;
    wire [1:0] gshare_counter_val;
    wire [1:0] bimodal_counter_val;
    wire [1:0] chooser_counter_val;

    // خواندن مقدار فعلی کانتر
    assign gas_counter_val     = bht_gas[gas_index];
    assign gshare_counter_val  = bht_gshare[gshare_index];
    assign bimodal_counter_val = bht_bimodal[bimodal_index];
    assign chooser_counter_val = chooser[gshare_index]; 
    // توجه: در برخی پیاده‌سازی‌ها index جدول chooser می‌تواند متفاوت باشد،
    // اما برای سادگی در اینجا همان اندیس gshare را استفاده کرده‌ایم.

    always @(*) begin
        case (PREDICTOR_MODE)
            //------------------------------------------------
            // 0) Always Taken
            //------------------------------------------------
            0: begin
                predict_taken = 1'b1;
            end

            //------------------------------------------------
            // 1) Always Not Taken
            //------------------------------------------------
            1: begin
                predict_taken = 1'b0;
            end

            //------------------------------------------------
            // 2) GAs
            //------------------------------------------------
            2: begin
                // اگر مقدار کانتر >= 2 بود یعنی taken
                // یعنی 2'b10 (2) یا 2'b11 (3)
                if (gas_counter_val >= 2)
                    predict_taken = 1'b1;
                else
                    predict_taken = 1'b0;
            end

            //------------------------------------------------
            // 3) Gshare
            //------------------------------------------------
            3: begin
                // اگر مقدار کانتر >= 2 بود یعنی taken
                if (gshare_counter_val >= 2)
                    predict_taken = 1'b1;
                else
                    predict_taken = 1'b0;
            end

            //------------------------------------------------
            // 4) Gshare + Bimodal (Hybrid)
            //------------------------------------------------
            4: begin
                // از جدول chooser_counter_val مشخص می‌کنیم کدام پیش‌بینی را قبول کنیم
                // اگر chooser >= 2 => gshare قوی‌تر است
                // در غیر این صورت => bimodal قوی‌تر است
                if (chooser_counter_val >= 2) begin
                    // استفاده از نتیجه gshare
                    predict_taken = (gshare_counter_val >= 2);
                end else begin
                    // استفاده از نتیجه bimodal
                    predict_taken = (bimodal_counter_val >= 2);
                end
            end

            //------------------------------------------------
            default: begin
                // به صورت پیش‌فرض always not taken
                predict_taken = 1'b0;
            end
        endcase
    end

    //========================================================================
    //  بخش 4: آپدیت رجیسترها و جداول در هر کلاک
    //========================================================================

    // برای تغییر حالت کانتر اشباع شونده:
    function [1:0] incr_counter;
        input [1:0] cnt;
        begin
            if(cnt != 2'b11)
                incr_counter = cnt + 1;
            else
                incr_counter = cnt; // اشباع شده
        end
    endfunction

    function [1:0] decr_counter;
        input [1:0] cnt;
        begin
            if(cnt != 2'b00)
                decr_counter = cnt - 1;
            else
                decr_counter = cnt; // اشباع شده
        end
    endfunction

    // با دریافت سیگنال update_en و actual_taken، باید:
    //  1) کانتر BHT مربوطه را آپدیت کنیم (بسته به نوع پریدیکتور)
    //  2) gbhr را آپدیت کنیم
    //  3) اگر هیبرید هست، جدول chooser را هم آپدیت کنیم

    // در اینجا فرض بر این است که آدرس شاخه (update_pc) همان pc_inِ آن سیکل نیست،
    // بلکه pc مربوط به شاخه‌ایست که حالا resolve شده.
    // پس باید اندیس مربوط به آن pc را محاسبه کنیم تا جدول صحیح را آپدیت کنیم.
    wire [8:0] update_pc_index_9bit = update_pc[10:2];
    wire [6:0] update_lower_pc      = update_pc_index_9bit[6:0];
    wire [6:0] update_xored_index   = update_lower_pc ^ gbhr_reg[6:0];
    wire [8:0] update_gshare_index  = {update_pc_index_9bit[8:7], update_xored_index};
    wire [8:0] update_bimodal_index = update_pc_index_9bit;
    wire [8:0] update_gas_index     = {update_pc[3:2], gbhr_reg};

    // رجیستر برای ذخیره‌ی last_gbhr جهت Update (اگر نیاز شد در طراحی شخصی)
    // در برخی طرح‌ها باید GBHR برای هر انشعاب جداگانه حفظ شود تا پس از resolve به درستی آپدیت کنیم.
    // برای سادگی اینجا همان gbhr_reg را استفاده می‌کنیم (ممکن است در طراحی شما نیاز به FIFO از gbhr داشته باشید).
    
    integer i;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            // پاکسازی تمام جدول‌ها
            gbhr_reg <= 0;
            for(i=0; i<BHT_SIZE; i=i+1) begin
                bht_gas[i]     <= 2'b01; // مقدار initial: weakly not taken
                bht_gshare[i]  <= 2'b01;
                bht_bimodal[i] <= 2'b01;
                chooser[i]     <= 2'b10; // فرضاً مقدار وسط => (2) یعنی اندکی تمایل به gshare
            end
        end else begin
            // ** آپدیت GBHR در هر شاخه resolve شده **
            // در بعضی طراحی‌ها ممکن است فقط وقتی آن شاخه مربوط به pc جاری است آپدیت کنیم.
            // ولی معمولاً gbhr با هر شاخه جدید، یک بیت شیفت می‌خورد. مثلاً:
            //   gbhr_reg = { gbhr_reg[GBHR_SIZE-2:0], actual_taken };
            // اینجا برای سادگی:
            if (update_en) begin
                gbhr_reg <= { gbhr_reg[GBHR_SIZE-2:0], actual_taken };
            end

            // آپدیت جداول
            if (update_en) begin
                case (PREDICTOR_MODE)
                    //--------------------------------
                    // 0) Always Taken
                    // 1) Always Not Taken
                    // هیچ جدولی نداریم که آپدیت کنیم
                    //--------------------------------
                    0, 1: begin
                        // کاری انجام نمی‌دهیم
                    end

                    //--------------------------------
                    // 2) GAs
                    //--------------------------------
                    2: begin
                        if (actual_taken)
                            bht_gas[update_gas_index] <= incr_counter(bht_gas[update_gas_index]);
                        else
                            bht_gas[update_gas_index] <= decr_counter(bht_gas[update_gas_index]);
                    end

                    //--------------------------------
                    // 3) Gshare
                    //--------------------------------
                    3: begin
                        if (actual_taken)
                            bht_gshare[update_gshare_index] <= incr_counter(bht_gshare[update_gshare_index]);
                        else
                            bht_gshare[update_gshare_index] <= decr_counter(bht_gshare[update_gshare_index]);
                    end

                    //--------------------------------
                    // 4) Hybrid (Gshare + Bimodal)
                    //--------------------------------
                    4: begin
                        // ابتدا نتیجه‌ی هر کدام از دو predictor را ببینیم (چه پیش‌بینی داده بودند):
                        // gshare_predict و bimodal_predict
                        // در عمل باید از همان اندیسی که هنگام اجرای دستور محاسبه کرده بودیم استفاده شود.
                        // در یک پیاده‌سازی دقیق، باید اندیس‌ها برای آن شاخه‌ی خاص نگه داشته شده باشد.
                        // در این مثال ساده، از update_... استفاده می‌کنیم.

                        // پیش‌بینی gshare
                        assign gshare_pred = (bht_gshare[update_gshare_index] >= 2);
                        // پیش‌بینی bimodal
                        assign bimodal_pred = (bht_bimodal[update_bimodal_index] >= 2);

                        // آپدیت chooser: اگر یکی درست پیش‌بینی کرد و دیگری اشتباه،
                        // وضعیت FSM مربوط به آن را به نفع پیش‌بینی‌کننده‌ی صحیح حرکت می‌دهیم.
                        // اگر هردو اشتباه یا هردو درست باشند، تغییری کم انجام شود یا اصلاً ندهیم.
                        if (gshare_pred == actual_taken && bimodal_pred != actual_taken) begin
                            // گشر درست بود، بایمودال اشتباه
                            chooser[update_gshare_index] <= incr_counter(chooser[update_gshare_index]);
                        end else if (gshare_pred != actual_taken && bimodal_pred == actual_taken) begin
                            // گشر اشتباه بود، بایمودال درست
                            chooser[update_gshare_index] <= decr_counter(chooser[update_gshare_index]);
                        end
                        // اگر هردو درست یا هردو اشتباه باشند، معمولاً تغییری نمی‌دهیم (یا یک آپدیت خیلی جزیی).

                        // آپدیت خودِ جداول gshare و bimodal
                        if (actual_taken) begin
                            bht_gshare[update_gshare_index]  <= incr_counter(bht_gshare[update_gshare_index]);
                            bht_bimodal[update_bimodal_index] <= incr_counter(bht_bimodal[update_bimodal_index]);
                        end else begin
                            bht_gshare[update_gshare_index]  <= decr_counter(bht_gshare[update_gshare_index]);
                            bht_bimodal[update_bimodal_index] <= decr_counter(bht_bimodal[update_bimodal_index]);
                        end
                    end

                    default: begin
                        // هیچ
                    end
                endcase
            end
        end
    end

endmodule