// csr
module ysyx_25080207_csr(
    input clk,
    input rst,

    input is_csrrw,                 // 判断指令是不是 csrrw
    input is_csrrs,
    input [11:0] csr_addr,         // SR 地址 = inst[31:20]
    input [31:0] csr_wdata,        // 要写进CSR的数据
    output reg[31:0] csr_rdata    // 从CSR寄存器读到的数据
);
    //csr寄存器
    reg [31:0] mcycle;
    reg [31:0] mcycleh;

    wire [63:0] mcycle_total;
    assign mcycle_total = {mcycleh, mcycle};

    localparam [31:0] mvendorid = 32'h79737978;
    localparam [31:0] marchid   = 32'h017eb18f;

    always @(posedge clk) begin
        if (rst) begin
            mcycle  <= 32'h00000000;
            mcycleh <= 32'h00000000;
        end else begin
            {mcycleh, mcycle} <= mcycle_total + 64'h1;            
            if (is_csrrw) begin
                case (csr_addr)
                    12'hB00: mcycle  <= csr_wdata;
                    12'hB80: mcycleh <= csr_wdata;
                    12'hF11,12'hF12: ;
                    default: ;
                endcase
            end else if(is_csrrs && csr_wdata != 32'b0) begin
                case (csr_addr)
                    12'hB00: mcycle  <= mcycle | csr_wdata;
                    12'hB80: mcycleh <= mcycleh | csr_wdata;
                    12'hF11,12'hF12: ;
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        case (csr_addr)
            12'hb00: csr_rdata = mcycle;
            12'hb80: csr_rdata = mcycleh;
            12'hf11: csr_rdata = mvendorid;
            12'hf12: csr_rdata = marchid;
            default: csr_rdata = 32'h00000000;
        endcase
    end
endmodule


// gpr
module ysyx_25080207_GPR #(ADDR_WIDTH = 5,DATA_WIDTH = 32)
(
    input clk,
    input [DATA_WIDTH-1:0] wdata,
    input [ADDR_WIDTH-1:0] waddr,
    input wen,
    input pc_update_en,
    input [ADDR_WIDTH-1:0] raddr1,
    input [ADDR_WIDTH-1:0] raddr2,
    // output [DATA_WIDTH-1:0] a0,
    output [DATA_WIDTH-1:0] rdata1,
    output [DATA_WIDTH-1:0] rdata2
);
    //当pc更新时才写寄存器
    wire reg_wen;
    assign reg_wen = wen && pc_update_en;

    //普通寄存器
    reg [DATA_WIDTH-1:0] rf [2**ADDR_WIDTH-1:0];

    always @(posedge clk) begin
        if (reg_wen && (waddr != 0)) rf[waddr] <= wdata;
    end

    assign rdata1 = (raddr1 == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : rf[raddr1];
    assign rdata2 = (raddr2 == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : rf[raddr2];
    // assign a0 = rf[10];
endmodule


// exu
module ysyx_25080207_exu (
    input [31:0] rs1_data,
    input [31:0] rs2_data,
    input [31:0] imm,
    input [31:0] pc_reg,
    input [31:0] mem_rdata,
    input [31:0] csr_rdata,
    input [1:0]  mem_addr,
    input is_add,
    input is_addi,
    input is_lui,
    input is_lw,
    input is_lbu,
    input is_sw,
    input is_sb,
    input is_jalr,
    //input is_auipc,
    input is_csrrw,
    input is_csrrs,
    output [31:0] wdata,
    output [31:0] mem_wdata,
    output [31:0] jalr_pc_out,
    output [31:0] csr_wdata
);
    wire [31:0] wdata_add, wdata_addi, wdata_lui, wdata_lw, wdata_lbu, wdata_jalr;
   // wire [31:0] auipc;
    wire [31:0] mem_wdata_sw, mem_wdata_sb;

    assign wdata_add  = is_add  ? (rs1_data + rs2_data) : 32'd0;
    assign wdata_addi = is_addi ? (rs1_data + imm)      : 32'd0;
    assign wdata_lui  = is_lui  ? imm                   : 32'd0;
    assign wdata_lw   = is_lw   ? mem_rdata             : 32'd0;

    reg [7:0] lbu_byte;
    always @(*) begin
        case (mem_addr)
            2'b00: lbu_byte = mem_rdata[7:0];
            2'b01: lbu_byte = mem_rdata[15:8];
            2'b10: lbu_byte = mem_rdata[23:16];
            2'b11: lbu_byte = mem_rdata[31:24];
            default: lbu_byte = 8'd0;
        endcase
    end
    assign wdata_lbu    = is_lbu ? {24'b0, lbu_byte} : 32'd0;

    assign mem_wdata_sw = rs2_data;
    assign mem_wdata_sb = rs2_data & 32'h000000FF;

    assign wdata_jalr   = pc_reg + 4;
    assign jalr_pc_out  = is_jalr ? ((rs1_data + imm) & 32'hFFFFFFFE) : 32'b0;

    //assign wdata_auipc  = pc_reg + imm;

    assign csr_wdata  = (is_csrrw | is_csrrs) ? rs1_data : 32'b0;

    assign wdata =  is_add   ? wdata_add  :
                    is_addi  ? wdata_addi :
                    is_lui   ? wdata_lui  :
                    is_lw    ? wdata_lw   :
                    is_lbu   ? wdata_lbu  :
                    is_jalr  ? wdata_jalr :
                    //is_auipc ? wdata_auipc:
                    (is_csrrw | is_csrrs) ? csr_rdata  :
                    32'd0;

    assign mem_wdata =  is_sw ? mem_wdata_sw :
                        is_sb ? mem_wdata_sb :
                        32'd0;
endmodule


// idu
module ysyx_25080207_idu (
    input       [31:0]  inst,       // 输入的指令
    input       [31:0]  rs1_data,   // 寄存器rs1的数据（用于计算内存地址）
    input               inst_valid, // 确认是否译码
    // 寄存器读写控制
    output reg          wen,        // 寄存器写使能
    output reg  [4:0]   rs1_addr,   // rs1寄存器地址
    output reg  [4:0]   rs2_addr,   // rs2寄存器地址
    output reg  [4:0]   rd_addr,    // rd寄存器地址
    output reg  [11:0]  csr_addr,   // CSR寄存器地址
    // 立即数输出
    output reg  [31:0]  imm,        // 解码得到的立即数
    // 指令类型标志（控制后续执行阶段）
    output reg          is_add,     // ADD指令标志
    output reg          is_addi,    // ADDI指令标志
    output reg          is_lui,     // LUI指令标志
    output reg          is_lw,      // LW指令标志
    output reg          is_lbu,     // LBU指令标志
    output reg          is_sw,      // SW指令标志
    output reg          is_sb,      // SB指令标志
    output reg          is_jalr,    // JALR指令标志
    //output reg          is_auipc,   // AUIPC指令标志
    output reg          is_csrrw,   // CSRRW指令标志
    output reg          is_csrrs,
    // 内存访问控制
    output reg          mem_valid,  // 内存访问有效标志(在lsu要改为lsu_valid)
    output reg          mem_wen,    // 内存写使能（1为写，0为读）
    output reg  [31:0]  mem_addr,  // 内存操作地址
    output reg  [3:0]   mem_wmask,  // 内存写掩码（字节使能）
    // 异常相关标志
    //output reg          illegal_instruction // 非法指令标志
    output reg          is_ebreak          // EBreak指令标志
);  

    always @(*) begin
        wen = 0;
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        rd_addr = 5'd0;
        csr_addr = 12'd0;
        imm = 32'd0;
        {is_add, is_addi, is_lui, is_lw, is_lbu, is_sw, is_sb, is_jalr, is_csrrw, is_csrrs} = 10'b0;
        //is_auipc =0;
        mem_valid = 0;
        mem_wen = 0;
        mem_addr = 32'b0;
        mem_wmask = 4'b0000;
        is_ebreak = 0;
        // illegal_instruction = 0;

        casez (inst)
            //1. add
            32'b0000000_?????_?????_000_?????_01100_11: begin 
                wen = inst_valid;
                rs1_addr = inst[19:15];
                rs2_addr = inst[24:20];
                rd_addr = inst[11:7];
                is_add = 1;
            end

            //2. addi
            32'b???????_?????_?????_000_?????_00100_11: begin 
                wen = inst_valid;
                rs1_addr = inst[19:15];
                rd_addr = inst[11:7];
                imm = {{20{inst[31]}}, inst[31:20]};
                is_addi = 1;
            end
            
            //3. lui
            32'b???????_?????_?????_???_?????_01101_11: begin
                wen = inst_valid;
                rd_addr = inst[11:7];
                imm = {inst[31:12],12'b0};
                is_lui = 1;
            end

            //4. lw
            32'b???????_?????_?????_010_?????_00000_11: begin
                wen = inst_valid;
                mem_valid = inst_valid;
                mem_wmask = 4'hf;
                rs1_addr = inst[19:15];
                imm = {{20{inst[31]}}, inst[31:20]};
                mem_addr = rs1_data + imm;
                rd_addr = inst[11:7];
                is_lw = 1;
            end

            //5. lbu
            32'b???????_?????_?????_100_?????_00000_11: begin
                wen = inst_valid;
                mem_valid = inst_valid;
                rs1_addr = inst[19:15];
                imm = {{20{inst[31]}}, inst[31:20]};
                mem_addr = rs1_data + imm;
                rd_addr = inst[11:7];
                is_lbu = 1;
            end

            //6. sw
            32'b???????_?????_?????_010_?????_01000_11: begin
                mem_wen = inst_valid;
                mem_valid = inst_valid;
                rs1_addr = inst[19:15];
                rs2_addr = inst[24:20];
                imm = {{20{inst[31]}},inst[31:25],inst[11:7]};
                mem_addr = rs1_data + imm;
                mem_wmask = 4'b1111;
                is_sw = 1;
            end

            //7. sb
            32'b???????_?????_?????_000_?????_01000_11: begin
                mem_wen = inst_valid;
                mem_valid = inst_valid;
                rs1_addr = inst[19:15];
                rs2_addr = inst[24:20];
                imm = {{20{inst[31]}},inst[31:25],inst[11:7]};
                mem_addr = rs1_data + imm;
                mem_wmask = 1 << (mem_addr[1:0]);
                is_sb = 1;
            end

            //8. jalr
            32'b???????_?????_?????_000_?????_11001_11: begin 
                wen = inst_valid;
                rs1_addr = inst[19:15];
                rd_addr = inst[11:7];
                imm = {{20{inst[31]}}, inst[31:20]};
                is_jalr = 1;
            end

            // //9. auipc
            // 32'b???????_?????_?????_???_?????_00101_11: begin 
            //     wen = inst_valid;
            //     rd_addr = inst[11:7];
            //     imm = {inst[31:12], 12'b0};
            //     is_auipc = 1;
            // end

            //10. csrrw
            32'b???????_?????_?????_001_?????_11100_11: begin
                wen = inst_valid;
                csr_addr = inst[31:20];
                rd_addr = inst[11:7];
                rs1_addr = inst[19:15];
                is_csrrw = 1;
            end

            //11, csrrs
            32'b???????_?????_?????_010_?????_11100_11 :begin
                wen = inst_valid;               // 写使能：csrrs会将CSR旧值写入rd
                csr_addr = inst[31:20];         // CSR地址：inst[31:20]
                rd_addr = inst[11:7];           // 目标寄存器rd：inst[11:7]
                rs1_addr = inst[19:15];         // 源寄存器rs1（置位掩码）：inst[19:15]
                is_csrrs = 1;                   // csrrs指令标志（需在模块输出中新增该信号）
            end

            //ebreak
            32'b0000000_00001_00000_000_00000_11100_11: begin
                is_ebreak = 1;
            end
            
            default: begin
                is_ebreak = (inst == 0) ?  0 : 1;
                // 非法信号指示位
                // illegal_instruction = (inst == 0) ?  0 : 1;
            end
        endcase
    end
endmodule


// lsu
module ysyx_25080207_lsu (
    input               clk,            // 时钟信号（上升沿触发）
    input               rst,            // 复位信号（高有效）
    // 控制信号（来自IDU）
    input  reg          lsu_respValid,  // 仿存请求
    output reg          lsu_reqValid,   // 仿存成功

    input               lsu_valid,      // 访存有效标志(mem_valid)（1=需要访存）
    input               mem_wen,        // 写使能（1=store，0=load）
    input       [31:0]  mem_addr,       // 访存地址（读/写共用）
    input       [31:0]  mem_wdata,      // 待写入数据（store时有效）
    input       [3:0]   mem_wmask,      // 写掩码（每bit对应1字节，1=写入）
    // 输出信号（到EXU/WBU）
    output reg  [31:0]  mem_rdata,      // 读出的数据（load时有效）
    output reg          lsu_done,       // 访存完成标志（1=操作结束）

    output      [31:0]  lsu_addr,
    output              lsu_wen,
    output      [31:0]  lsu_wdata,
    output      [3:0]   lsu_wmask,

    input       [31:0]  lsu_rdata,
    input               pc_update_en
);
    assign lsu_wen    = mem_wen && lsu_reqValid;
    assign lsu_wmask  = mem_wmask;
    assign lsu_wdata  = mem_wdata;
    assign lsu_addr   = mem_addr;
    assign mem_rdata  = lsu_rdata;
    // 状态定义（基础2状态机）
    localparam IDLE  = 1'b0;  // 空闲状态：等待访存请求
    localparam WAIT  = 1'b1;  // 等待状态：处理访存并延迟1周期

    // 内部信号
    reg         state;               // 状态寄存器

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    //判断是不是读写指令
                    if (lsu_valid) begin
                        state     <= WAIT;
                        lsu_reqValid <= 1;
                    end
                end
                WAIT: begin
                    if (lsu_respValid) begin
                        state <= IDLE;
                    end
                    lsu_reqValid <= 0;
                end
            endcase
        end
    end

    always @(*) begin
        case (state)
            IDLE:begin
                if (lsu_valid) begin
                    // if (mem_wen) begin
                    //     lsu_done = 1;
                    // end else begin
                    //     lsu_done =0;
                    // end
                    lsu_done = 0;
                end else begin
                    lsu_done = 1;
                end
            end 
            WAIT:begin
                if (lsu_respValid) begin
                    lsu_done     = 1;
                end
            end
        endcase
    end
endmodule


//ifu
module ysyx_25080207_ifu (
    input               clk,            // 时钟信号（上升沿触发）
    input               rst,            // 复位信号（高有效）
    input       [31:0]  pc_reg,         // 当前PC值（来自WBU）
    input               pc_update_en,   // pc是否更新
    input  reg          ifu_respValid,  // 访问请求
    output reg          ifu_reqValid,   // 访问成功信号
    output reg  [31:0]  ifu_raddr,      // 输出到存储器的取指地址（SimpleBus信号）
    input       [31:0]  ifu_rdata,      // 从存储器接收的指令（SimpleBus信号）
    output reg          inst_valid,     // 指令有效标志（高有效，通知IDU）
    output reg  [31:0]  inst            // 输出到IDU的有效指令
);
    localparam IDLE = 1'b0;  // 空闲状态：发送取指地址
    localparam WAIT = 1'b1;  // 等待状态：等待存储器返回指令
    reg state;

    always @(posedge clk ) begin
        if (rst) begin
            state       <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    state       <= WAIT; 
                    ifu_reqValid <= 1;
                end
                WAIT: begin
                    if(pc_update_en) begin
                        state <= IDLE;
                    end
                    ifu_reqValid <= 0;
                end
            endcase
        end
    end

    always @(*) begin
        ifu_raddr = pc_reg; 
        case (state)
            IDLE:begin
                inst_valid = 0;
            end 
            WAIT:begin
                if (ifu_respValid) begin
                    inst    = ifu_rdata;
                    inst_valid = 1;
                end
            end
        endcase
    end
endmodule


// wbu
module ysyx_25080207_wbu #(pc_start = 32'h80000000)
(
    input             clk,
    input             rst,
    input             is_jalr,
    input      [31:0] jalr_pc_out,
    input             inst_valid,
    input             lsu_done,
    output reg [31:0] pc_reg,
    //试一试给pc_update_en给ifu
    output pc_update_en
);
    assign pc_update_en = inst_valid && lsu_done;
    wire [31:0]pc_dnpc;
    assign pc_dnpc = is_jalr ? jalr_pc_out : (pc_reg + 4);

    // 更新PC逻辑
    always @(posedge clk) begin
        if (rst) begin
            pc_reg <= pc_start;
        end else begin
            pc_reg <= pc_update_en ? pc_dnpc : pc_reg;  // 不满足则保持PC
        end
    end
endmodule


// 顶层模块：实例化所有子模块（放在最后）
module ysyx_25080207 (
    // 全局时钟与复位
    input         clock,          // 全局时钟信号
    input         reset,          // 全局复位信号（高有效）
    // IFU（指令取指单元）对外接口
    output        io_ifu_reqValid, // IFU发起取指请求的有效信号
    output [31:0] io_ifu_addr,    // IFU取指地址（32位）
    input         io_ifu_respValid, // 外部对IFU取指的响应有效
    input  [31:0] io_ifu_rdata,   // 外部返回给IFU的指令数据

    // LSU（加载存储单元）对外接口
    output        io_lsu_reqValid, // LSU发起访存请求的有效信号
    output [31:0] io_lsu_addr,    // LSU访存地址（32位）
    output [1:0]  io_lsu_size,    // LSU访存数据大小（00:字节, 01:半字, 10:字）
    output        io_lsu_wen,     // LSU写使能（1:写, 0:读）
    output [31:0] io_lsu_wdata,   // LSU写数据（32位）
    output [3:0]  io_lsu_wmask,   // LSU写掩码（4位对应4字节）
    input         io_lsu_respValid, // 外部对LSU访存的响应有效
    input  [31:0] io_lsu_rdata   // 外部返回给LSU的读数据
);
    
    // ---------------------- 内部信号定义 ----------------------
    // 全局时钟/复位内部别名（统一子模块命名）
    wire          clk;
    wire          rst;
    assign clk = clock;  // 外部clock映射到内部clk
    assign rst = reset;  // 外部reset映射到内部rst

    // IFU（取指单元）内部信号
    wire [31:0] ifu_raddr;        // IFU内部取指地址
    wire [31:0] ifu_rdata;        // IFU内部读取的指令数据
    wire        ifu_reqValid;     // IFU内部请求有效
    wire        ifu_respValid;    // IFU内部响应有效

    // LSU（加载存储单元）内部信号
    wire [31:0] lsu_addr;         // LSU内部访存地址
    wire        lsu_wen;          // LSU内部写使能
    wire [31:0] lsu_wdata;        // LSU内部写数据
    wire [3:0]  lsu_wmask;        // LSU内部写掩码
    wire [31:0] lsu_rdata;        // LSU内部读数据
    wire        lsu_reqValid;     // LSU内部请求有效
    wire        lsu_respValid;    // LSU内部响应有效

    // EXU（执行单元）内部信号
    wire [31:0] imm;               // 指令解码出的立即数
    wire [31:0] pc_reg;            // 当前PC寄存器的值
    wire [31:0] rs1_data, rs2_data; // 寄存器堆读出的源寄存器数据
    wire [31:0] mem_rdata;         // 内存读数据（传给EXU）
    wire [31:0] csr_rdata;         // CSR读数据（传给EXU）
    wire [31:0] wdata;             // 写回寄存器堆的数据
    wire [31:0] mem_wdata;         // 要写入内存的数据（来自EXU）
    wire [31:0] csr_wdata;         // 要写入CSR的数据（来自EXU）
    wire [31:0] jalr_pc_out;       // JALR指令计算的目标PC
    wire [31:0] mem_addr;          // 内存地址（来自EXU）

    // 控制信号（来自IDU指令解码）
    wire is_add, is_addi, is_lui, is_lw, is_lbu, is_sw, is_sb, is_jalr, is_csrrw, is_csrrs, is_ebreak;
    //wire is_auipc;
    wire inst_valid;               // 指令是否有效
    wire wen;                      // 寄存器堆写使能
    wire mem_valid;                // 内存操作是否有效
    wire mem_wen;                  // 内存写使能
    wire lsu_done;                 // LSU操作是否完成
    wire pc_update_en;             // PC更新使能
    wire [3:0] mem_wmask;

    // 寄存器地址信号（来自IDU）
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire [11:0] csr_addr;

    // LSU访存大小生成：根据指令类型决定io_lsu_size
    assign io_lsu_size = (is_lbu | is_sb) ? 2'b00 :  // 字节操作
                         (is_lw  | is_sw) ? 2'b10 : 2'b00; // 字操作

    wire [31:0] inst;

    // IFU对外接口映射
    assign io_ifu_reqValid = ifu_reqValid;
    assign io_ifu_addr     = ifu_raddr;
    assign ifu_respValid   = io_ifu_respValid;
    assign ifu_rdata       = io_ifu_rdata;

    // LSU对外接口映射
    assign io_lsu_reqValid = lsu_reqValid;
    assign io_lsu_addr     = lsu_addr;
    assign io_lsu_wen      = lsu_wen;
    assign io_lsu_wdata    = lsu_wdata << lsu_addr[1:0]*8;
    assign io_lsu_wmask    = lsu_wmask;
    assign lsu_respValid   = io_lsu_respValid;
    assign lsu_rdata       = io_lsu_rdata;

    // assign pc = pc_reg;            // PC输出与内部PC寄存器同步



`ifdef VERILATOR
    //DPI-C使用
    import "DPI-C" function void ebreak(input bit is_ebreak);  // 函数名直接用ebreak

    // 在时钟沿触发
    always @(posedge clk) begin
        if (!rst) begin  // 复位释放后才检测
            // 直接调用ebreak函数，传is_ebreak状态，当is_ebreak为1时，触发函数使得main里跳出主循环
            ebreak(is_ebreak);
        end
    end

`endif

    // ---------------------- 子模块实例化 ----------------------
    // IFU：指令取指单元
    ysyx_25080207_ifu u_ifu (
        .clk            (clk),
        .rst            (rst),
        .pc_reg         (pc_reg),
        .pc_update_en   (pc_update_en),
        .ifu_respValid  (ifu_respValid),
        .ifu_reqValid   (ifu_reqValid),
        .ifu_raddr      (ifu_raddr),
        .ifu_rdata      (ifu_rdata),
        .inst_valid     (inst_valid),
        .inst           (inst)
    );

    // WBU：写回与PC更新单元
    ysyx_25080207_wbu #(
        .pc_start(32'h30000000)  // PC起始地址参数化
    ) u_wbu (
        .clk            (clk),
        .rst            (rst),
        .is_jalr        (is_jalr),
        .jalr_pc_out    (jalr_pc_out),
        .inst_valid     (inst_valid),
        .lsu_done       (lsu_done),
        .pc_reg         (pc_reg),
        .pc_update_en   (pc_update_en)
    );


    // LSU：加载存储单元
    ysyx_25080207_lsu u_lsu (
        .clk            (clk),
        .rst            (rst),
        .lsu_respValid  (lsu_respValid),
        .lsu_reqValid   (lsu_reqValid),
        .lsu_valid      (mem_valid),
        .mem_wen        (mem_wen),
        .mem_addr       (mem_addr),
        .mem_wdata      (mem_wdata),
        .mem_wmask      (mem_wmask),
        .mem_rdata      (mem_rdata),
        .lsu_done       (lsu_done),
        .lsu_addr       (lsu_addr),
        .lsu_wen        (lsu_wen),
        .lsu_wdata      (lsu_wdata),
        .lsu_wmask      (lsu_wmask),
        .lsu_rdata      (lsu_rdata),
        .pc_update_en   (pc_update_en)
    );

    // EXU：执行单元
    ysyx_25080207_exu u_exu (
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .imm            (imm),
        .pc_reg         (pc_reg),
        .mem_rdata      (mem_rdata),
        .csr_rdata      (csr_rdata),
        .mem_addr       (mem_addr[1:0]),  // 内存地址低2位（字节对齐）
        .is_add         (is_add),
        .is_addi        (is_addi),
        .is_lui         (is_lui),
        .is_lw          (is_lw),
        .is_lbu         (is_lbu),
        .is_sw          (is_sw),
        .is_sb          (is_sb),
        .is_jalr        (is_jalr),
        // .is_auipc       (is_auipc),
        .is_csrrw       (is_csrrw),
        .is_csrrs       (is_csrrs),
        .wdata          (wdata),
        .mem_wdata      (mem_wdata),
        .jalr_pc_out    (jalr_pc_out),
        .csr_wdata      (csr_wdata)
    );

    // IDU：指令解码单元
    ysyx_25080207_idu u_idu (
        .inst               (inst),
        .inst_valid         (inst_valid),
        .rs1_data           (rs1_data),
        .wen                (wen),
        .rs1_addr           (rs1_addr),
        .rs2_addr           (rs2_addr),
        .rd_addr            (rd_addr),
        .csr_addr           (csr_addr),
        .imm                (imm),
        .is_add             (is_add),
        .is_addi            (is_addi),
        .is_lui             (is_lui),
        .is_lw              (is_lw),
        .is_lbu             (is_lbu),
        .is_sw              (is_sw),
        .is_sb              (is_sb),
        .is_jalr            (is_jalr),
        // .is_auipc           (is_auipc),
        .is_csrrw           (is_csrrw),
        .is_csrrs           (is_csrrs),
        .mem_valid          (mem_valid),
        .mem_wen            (mem_wen),
        .mem_addr           (mem_addr),
        .mem_wmask          (mem_wmask),
        // .illegal_instruction(illegal_instruction),   非法指令标志位
        .is_ebreak          (is_ebreak)
    );

    // GPR：通用寄存器堆
    ysyx_25080207_GPR #(
        .ADDR_WIDTH(5),   // 寄存器地址宽度（5位→32个寄存器）
        .DATA_WIDTH(32)   // 寄存器数据宽度（32位）
    ) gpr (
        .clk            (clk),
        .wdata          (wdata),
        .waddr          (rd_addr),
        .wen            (wen),
        .pc_update_en   (pc_update_en),
        .raddr1         (rs1_addr),
        .raddr2         (rs2_addr),
        // .a0             (a0),     引出a0判断是否成功执行程序
        .rdata1         (rs1_data),
        .rdata2         (rs2_data)
    );

    // CSR：控制状态寄存器
    ysyx_25080207_csr u_csr (
        .clk            (clk),
        .rst            (rst),
        .is_csrrw       (is_csrrw),
        .is_csrrs       (is_csrrs),
        .csr_addr       (csr_addr),
        .csr_wdata      (csr_wdata),
        .csr_rdata      (csr_rdata)
    );

endmodule
