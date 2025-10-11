module top (
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
    input  [31:0] io_lsu_rdata,   // 外部返回给LSU的读数据

    // // 结果与状态输出
    // output [31:0] inst,
    // output reg [31:0] pc,         // 程序计数器输出
    // output [31:0] a0,             // 通用寄存器a0的值（调试/交互用）
    // output        is_ebreak,      // 是否执行ebreak指令
    // output        illegal_instruction // 是否为非法指令
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
    wire is_add, is_addi, is_lui, is_lw, is_lbu, is_sw, is_sb, is_jalr, is_auipc, is_csrrw, is_csrrs, is_ebreak;
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
                        //  (is_lh  | is_sh) ? 2'b01 :  // 半字操作（若有is_lh/is_sh需补充，这里假设用户代码中通过is_lw/is_sw等隐含）
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

    import "DPI-C" function void ebreak(input bit is_ebreak);  // 函数名直接用ebreak

    // 在时钟沿触发（假设已通过IDU拿到is_ebreak信号）
    always @(posedge clk) begin
        if (!rst) begin  // 复位释放后才检测
            ebreak(is_ebreak);  // 直接调用ebreak函数，传is_ebreak状态
        end
    end
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

    // // MEM：内存控制单元（内部衔接IFU和LSU）
    // ysyx_25080207_mem u_mem (
    //     .clk            (clk),
    //     .ifu_respValid  (ifu_respValid),
    //     .ifu_reqValid   (ifu_reqValid),
    //     .ifu_raddr      (ifu_raddr),
    //     .ifu_rdata      (ifu_rdata),
    //     .lsu_respValid  (lsu_respValid),
    //     .lsu_reqValid   (lsu_reqValid),
    //     .lsu_addr       (lsu_addr),
    //     .lsu_wen        (lsu_wen),
    //     .lsu_wdata      (lsu_wdata),
    //     .lsu_wmask      (lsu_wmask),
    //     .lsu_rdata      (lsu_rdata)
    // );

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
        .is_auipc       (is_auipc),
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
        .is_auipc           (is_auipc),
        .is_csrrw           (is_csrrw),
        .is_csrrs           (is_csrrs),
        .mem_valid          (mem_valid),
        .mem_wen            (mem_wen),
        .mem_addr           (mem_addr),
        .mem_wmask          (mem_wmask),
        // .illegal_instruction(illegal_instruction),
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
        // .a0             (a0),
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
