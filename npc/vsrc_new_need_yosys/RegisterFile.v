//--------------------------------------------------
// 文件：RegisterFile.v
//--------------------------------------------------
module GPR #(ADDR_WIDTH = 5,DATA_WIDTH = 32)
(
    input clk,//
    input rst,////
    input [DATA_WIDTH-1:0] wdata,//
    input [ADDR_WIDTH-1:0] waddr,//
    input wen,//
    input [ADDR_WIDTH-1:0] raddr1,//
    input [ADDR_WIDTH-1:0] raddr2,//
    output [DATA_WIDTH-1:0] rdata1,//
    output [DATA_WIDTH-1:0] rdata2,//
    output [DATA_WIDTH-1:0] a0,//
    input [ADDR_WIDTH-1:0] csr_addr,////
    input [DATA_WIDTH-1:0] csr_rs1_data,// 改：新名称csr_rs1_data，避免冲突
    input csrrw_en,////
    output reg [DATA_WIDTH-1:0] csr_rdata////
);

    //普通寄存器
    reg [DATA_WIDTH-1:0] rf [2**ADDR_WIDTH-1:0];

    always @(posedge clk) begin
        if (wen && (waddr != 0)) rf[waddr] <= wdata;
    end

    assign rdata1 = (raddr1 == 0) ? 0 : rf[raddr1];
    assign rdata2 = (raddr2 == 0) ? 0 : rf[raddr2];
    assign a0 = rf[10];



    //csr寄存器
    reg [31:0] mcycle;
    reg [31:0] mcycleh;
    reg [31:0] mvendorid;
    reg [31:0] marchid;

    wire [63:0] mcycle_total;
    assign mcycle_total = {mcycleh, mcycle};

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mcycle  <= 32'h00000000;
            mcycleh <= 32'h00000000;
            mvendorid <= 32'h79737978;
            marchid   <= 32'h017eb18f;
        end else begin
            if (csrrw_en && (csr_addr == 12'hb00)) begin
                mcycle <= csr_rs1_data;
            end else if (csrrw_en && (csr_addr == 12'hb80)) begin
                mcycleh <= csr_rs1_data;
            end else begin
                {mcycleh, mcycle} <= mcycle_total + 64'h1;
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


module ROM #(
  parameter ADDR_WIDTH = 8,  // 地址宽度
  parameter DATA_WIDTH = 32,  // 数据宽度
  parameter INIT_FILE  = ""  // 初始化文件路径，为空则不初始化
) (
  input  [ADDR_WIDTH-1:0] raddr,  // 读地址
  output reg [DATA_WIDTH-1:0] rdata  // 读出数据
);

  // 存储器数组
  reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

  // 从文件初始化ROM（如果提供了初始化文件）
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);  // 读取十六进制文件
    end
  end

  // 组合逻辑读取（无延迟）
  always @(*) begin
    rdata = mem[raddr];
  end

endmodule



module RAM #(
  parameter ADDR_WIDTH = 8,  // 地址宽度
  parameter DATA_WIDTH = 32,  // 数据宽度
  parameter INIT_FILE  = ""  // 初始化文件路径，为空则不初始化
) (
  input clk,                  // 时钟信号
  input [ADDR_WIDTH-1:0] raddr,  // 读地址
  input [ADDR_WIDTH-1:0] waddr,  // 写地址
  input [DATA_WIDTH-1:0] wdata,  // 写入数据
  input mem_wen,                  // 写使能信号（高有效）
  output reg [DATA_WIDTH-1:0] rdata  // 读出数据
);

  // 存储器数组
  reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

  // 从文件初始化RAM（如果提供了初始化文件）
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);  // 读取十六进制文件
    end
  end

  // 同步写操作（时钟上升沿）
  always @(posedge clk) begin
    if (mem_wen) begin
      mem[waddr] <= wdata;
    end
  end

  // 组合逻辑读操作（无延迟，也可改为同步读）
  always @(*) begin
    rdata = mem[raddr];
  end

endmodule
