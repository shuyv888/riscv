module top (
    // 时钟与复位信号
    input         clk,
    input         rst,

    // 指令相关输出（来自 IFU）
    output [31:0] inst,

    // 程序计数器（PC）输出
    output reg [31:0] pc,

    // 结果与状态输出
    output [31:0] a0,           // 通用寄存器 a0 的值（用于调试/外部交互）
    output        is_ebreak,    // 是否执行 ebreak 指令
    output        illegal_instruction  // 是否为非法指令
);

    // ---------------------- 内部信号定义 ----------------------
    // IFU（取指单元）相关信号
    wire [31:0] ifu_raddr;      // IFU 读取指令的地址
    wire [31:0] ifu_rdata;      // IFU 读取到的指令数据
    wire        ifu_reqValid;   // IFU 发起的请求是否有效
    wire        ifu_respValid;  // 对 IFU 请求的响应是否有效

    // LSU（加载存储单元）与 MEM（内存）交互信号
    wire [31:0] lsu_addr;       // LSU 访问内存的地址
    wire        lsu_wen;        // LSU 写使能（1=写，0=读）
    wire [31:0] lsu_wdata;      // LSU 要写入内存的数据
    wire [3:0]  lsu_wmask;      // LSU 写掩码（每一位对应 1 字节的写使能）
    wire [31:0] lsu_rdata;      // LSU 从内存读取的数据
    wire        lsu_reqValid;   // LSU → MEM：访存请求是否有效
    wire        lsu_respValid;  // MEM → LSU：访存响应是否有效

    // EXU（执行单元）相关信号
    wire [31:0] rs1_data, rs2_data; // 寄存器堆读出的源寄存器数据
    wire [31:0] imm;                // 指令解码出的立即数
    wire [31:0] pc_reg;             // 当前 PC 寄存器的值
    wire [31:0] mem_rdata;          // 内存读数据（传给 EXU）
    wire [31:0] csr_rdata;          // CSR 读数据（传给 EXU）
    wire [31:0] wdata;              // 要写回寄存器堆的数据
    wire [31:0] mem_wdata;          // 要写入内存的数据（来自 EXU）
    wire [31:0] jalr_pc_out;        // JALR 指令计算出的目标 PC
    wire [31:0] csr_wdata;          // 要写入 CSR 的数据（来自 EXU）
    wire [31:0] mem_addr;           // 内存地址（来自 EXU）

    // 控制信号（来自 IDU 指令解码）
    wire is_add, is_addi, is_lui, is_lw, is_lbu, is_sw, is_sb, is_jalr, is_auipc, is_csrrw;
    wire inst_valid;                // 指令是否有效
    wire wen;                       // 寄存器堆写使能
    wire mem_valid;                 // 内存操作是否有效
    wire mem_wen;                   // 内存写使能
    wire [3:0] mem_wmask;                 // 写掩码
    wire lsu_done;                  // LSU 操作是否完成
    wire pc_update_en;              // PC 更新使能

    // 寄存器地址信号（来自 IDU）
    wire [4:0] rs1_addr, rs2_addr, rd_addr;
    wire [11:0] csr_addr;

    assign pc = pc_reg;  // PC 输出与内部 PC 寄存器同步


    // ---------------------- 子模块实例化 ----------------------
    // IFU：取指单元
    ifu u_ifu (
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

    // WBU：写回与 PC 更新单元
    wbu #(
        .pc_start(32'h80000000)  // PC 起始地址参数化
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

    // MEM：内存单元
    mem u_mem (
        .clk            (clk),
        .ifu_respValid  (ifu_respValid),
        .ifu_reqValid   (ifu_reqValid),
        .ifu_raddr      (ifu_raddr),
        .ifu_rdata      (ifu_rdata),
        .lsu_respValid  (lsu_respValid),
        .lsu_reqValid   (lsu_reqValid),
        .lsu_addr       (lsu_addr),
        .lsu_wen        (lsu_wen),
        .lsu_wdata      (lsu_wdata),
        .lsu_wmask      (lsu_wmask),
        .lsu_rdata      (lsu_rdata)
    );

    // LSU：加载存储单元
    lsu u_lsu (
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
    exu u_exu (
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .imm            (imm),
        .pc_reg         (pc_reg),
        .mem_rdata      (mem_rdata),
        .csr_rdata      (csr_rdata),
        .mem_addr       (mem_addr[1:0]),  // 内存地址低 2 位（用于字节对齐）
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
        .wdata          (wdata),
        .mem_wdata      (mem_wdata),
        .jalr_pc_out    (jalr_pc_out),
        .csr_wdata      (csr_wdata)
    );

    // IDU：指令解码单元
    idu u_idu (
        .rst                (rst),
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
        .mem_valid          (mem_valid),
        .mem_wen            (mem_wen),
        .mem_addr           (mem_addr),
        .mem_wmask          (mem_wmask),
        .is_ebreak          (is_ebreak),
        .illegal_instruction(illegal_instruction)
    );

    // GPR：通用寄存器堆
    GPR #(
        .ADDR_WIDTH(5),   // 寄存器地址宽度（5 位对应 32 个寄存器）
        .DATA_WIDTH(32)   // 寄存器数据宽度（32 位）
    ) gpr (
        .clk            (clk),
        .wdata          (wdata),
        .waddr          (rd_addr),
        .wen            (wen),
        .pc_update_en   (pc_update_en),
        .raddr1         (rs1_addr),
        .raddr2         (rs2_addr),
        .rdata1         (rs1_data),
        .rdata2         (rs2_data),
        .a0             (a0)
    );

    // CSR：控制状态寄存器
    csr u_csr (
        .clk            (clk),
        .rst            (rst),
        .is_csrrw       (is_csrrw),
        .csr_addr       (csr_addr),
        .csr_wdata      (csr_wdata),
        .csr_rdata      (csr_rdata)
    );

endmodule
