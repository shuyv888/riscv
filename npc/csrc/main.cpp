// 1. 头文件：Vtop.h → VysyxSoCFull.h（Verilator 顶层模块头文件命名规则）
#include "VysyxSoCFull.h"
#include <verilated.h>       // Verilator仿真头文件（如果用Verilator工具）
#include <verilated_vcd_c.h>  // 波形跟踪头文件
#include <string.h>
#include <sys/stat.h>
//用于文件读取的头文件
#include <fstream>

#include "common.h"

//新pmem初始化（逻辑不变，名称不变）
volatile bool is_ebreak = false;
volatile int a=0;

const uint32_t MEM_SIZE = 0x10000000; // 单位：32位字（指令/数据按字存储）
#define FLASH_BASE    0x00000000  // 系统中Flash的物理基地址
#define FLASH_SIZE    0x1000000   // 本地Flash数组大小（16MB，可按需调整）
static uint8_t flash[FLASH_SIZE] = {0};  // 本地Flash数组（16MB）

vector<uint32_t> pmem(MEM_SIZE, 0);
vector<uint32_t> pmem_rom(MEM_SIZE, 0);
vector<uint32_t> pmem_mmio(MEM_SIZE, 0);



//加载hex（逻辑不变，名称不变）
void load_hex_to_rom(const std::string& filename) {
  std::ifstream file(filename);
  if (!file.is_open()) {
    fprintf(stderr, "错误: 无法打开HEX文件 %s\n", filename.c_str());
    exit(1);
  }

  std::string line;
  while (std::getline(file, line)) {
    // 跳过空行或注释行
    if (line.empty() || line[0] == '#' || line.find(':') == std::string::npos) {
      continue;
    }

    // 分割地址和数据（例如 "00000: 00000413 00051137 ..."）
    size_t colon_pos = line.find(':');
    std::string addr_str = line.substr(0, colon_pos);  // 地址部分（如"00000"）
    std::string data_str = line.substr(colon_pos + 1); // 数据部分（如"00000413 00051137..."）

    // 转换字地址（十六进制 -> 整数）
    uint32_t word_addr = stoul(addr_str, nullptr, 16);

    // 逐个解析数据部分的指令字（空格分隔）
    uint32_t offset = 0;  // 行内偏移（0,1,2...）
    size_t pos = 0;
    while (pos < data_str.size()) {
      // 跳过空格
      while (pos < data_str.size() && data_str[pos] == ' ') pos++;
      if (pos + 8 > data_str.size()) break;  // 不足8个字符则退出

      // 提取8个字符作为一个指令字（如"00000413"）
      std::string word_str = data_str.substr(pos, 8);
      pos += 8;

      // 转换为32位整数并存储
      uint32_t inst = stoul(word_str, nullptr, 16);
      uint32_t final_addr = word_addr + offset;
      if (final_addr < MEM_SIZE) {  // 检查地址是否越界
        pmem_rom[final_addr] = inst;
      }

      offset++;
    }
  }

  file.close();
  printf("成功：从 %s 加载程序到pmem_rom\n", filename.c_str());
}


// //手动pmem初始化（注释保留，逻辑不变）
// const uint32_t MEM_SIZE = 0x100000;
// uint32_t pmem[MEM_SIZE] = {0};  // 初始化全为 0，避免未定义值

// uint32_t pmem_rom[] = {
//   0x00100073
// };
//加载bin（逻辑不变，名称不变）
void load_bin_to_rom(const char* bin_path) {
    FILE* fp = fopen(bin_path, "rb");
    if (!fp) {
        fprintf(stderr, "ERROR: 无法打开BIN文件 %s\n", bin_path);
        exit(1);
    }
    // 读取BIN文件到pmem_rom（按字节读取，保持原始字节流）
    size_t bytes_read = fread(
        pmem_rom.data(),  // 目标：pmem_rom的字节数组
        1,                // 每次读1字节
        MEM_SIZE,         // 最大读取量
        fp
    );
    fclose(fp);

    printf("BIN加载到pmem_rom完成：读取%ld字节（0x%08x ~ 0x%08lx）\n\n",
           bytes_read, PMEM_BASE, PMEM_BASE + bytes_read - 1);
}

void load_flash_from_bin(const char* bin_path) {
    FILE* fp = fopen(bin_path, "rb");
    if (!fp) {
        fprintf(stderr, "ERROR: 无法打开Flash BIN文件 %s\n", bin_path);
        exit(1);
    }
    
    // 读取bin文件内容到Flash数组（最多读取FLASH_SIZE字节）
    size_t bytes_read = fread(
        flash,          // 目标：Flash数组
        1,              // 每次读1字节
        FLASH_SIZE,     // 最大读取量
        fp
    );
    fclose(fp);
    
    printf("Flash加载完成：读取%ld字节（0x000000000 ~ 0x%08lx）\n",
           bytes_read, (unsigned long)(bytes_read - 1));
}


// 仿照 load_hex_to_rom 实现：将 HEX 文件加载到 Flash 数组（uint8_t flash[FLASH_SIZE]）
// 支持格式：开头 v3.0 标识行 + 地址: 32位数据 32位数据...（如 "00000: 80000237 123452b7..."）
void load_flash_from_hex(const std::string& filename) {
    // 打开 HEX 文件（与 load_hex_to_rom 逻辑一致）
    std::ifstream file(filename);
    if (!file.is_open()) {
        fprintf(stderr, "错误: 无法打开HEX文件 %s\n", filename.c_str());
        exit(1);
    }

    std::string line;
    uint32_t total_bytes = 0;  // 可选：统计总加载字节数，方便调试
    while (std::getline(file, line)) {
        // 跳过空行、注释行（#开头）、无冒号行（如开头的 "v3.0 hex words addressed"）
        if (line.empty() || line[0] == '#' || line.find(':') == std::string::npos) {
            continue;
        }

        // 分割地址和数据（完全复用 load_hex_to_rom 的分割逻辑）
        size_t colon_pos = line.find(':');
        std::string addr_str = line.substr(0, colon_pos);  // 地址部分（如 "00000"）
        std::string data_str = line.substr(colon_pos + 1); // 数据部分（如 "80000237 123452b7..."）

        // 转换字地址（十六进制 → 整数，与 load_hex_to_rom 一致）
        // 注意：这里的地址是「32位数据的字地址」，后续需转为 Flash 的字节地址
        uint32_t word_addr = stoul(addr_str, nullptr, 16);

        // 逐个解析数据部分的 32位指令字（空格分隔，复用解析逻辑）
        uint32_t offset = 0;  // 行内字偏移（0,1,2...，每个偏移对应1个32位数据）
        size_t pos = 0;
        while (pos < data_str.size()) {
            // 跳过空格（与 load_hex_to_rom 一致）
            while (pos < data_str.size() && data_str[pos] == ' ') pos++;
            // 不足8个字符（1个32位数据的十六进制长度）则退出
            if (pos + 8 > data_str.size()) break;

            // 提取8个字符作为1个32位数据（如 "80000237"）
            std::string word_str = data_str.substr(pos, 8);
            pos += 8;

            // 转换为32位整数（与 load_hex_to_rom 一致）
            uint32_t data_32 = stoul(word_str, nullptr, 16);

            // ---------------------- 核心修改：适配 Flash 字节存储 ----------------------
            // 1. 计算 Flash 的字节地址：字地址 × 4（1个32位数据占4字节）
            uint32_t flash_byte_addr = (word_addr + offset) * 4;
            // 2. 检查 Flash 地址是否越界（Flash 是 uint8_t 数组，最大地址 FLASH_SIZE - 1）
            if (flash_byte_addr + 3 >= FLASH_SIZE) {  // +3 是因为要写4个字节（addr~addr+3）
                fprintf(stderr, "错误: Flash 地址越界！字地址 0x%08x 对应字节地址 0x%08x（最大字节地址 0x%08x）\n",
                        (word_addr + offset), flash_byte_addr, FLASH_SIZE - 1);
                file.close();
                exit(1);
            }
            // 3. 小端模式写入 Flash（32位数据拆分为4字节，与 RISC-V 字节序一致）
            flash[flash_byte_addr + 0] = (data_32 >> 0)  & 0xFF;  // 最低8位（第1字节）
            flash[flash_byte_addr + 1] = (data_32 >> 8)  & 0xFF;  // 次低8位（第2字节）
            flash[flash_byte_addr + 2] = (data_32 >> 16) & 0xFF;  // 次高8位（第3字节）
            flash[flash_byte_addr + 3] = (data_32 >> 24) & 0xFF;  // 最高8位（第4字节）

            offset++;
            total_bytes += 4;  // 每解析1个32位数据，Flash 写入4字节
        }
    }

    // 关闭文件并打印结果（与 load_hex_to_rom 风格一致）
    file.close();
    printf("成功：从 %s 加载程序到 Flash，共加载 %d 字节（%d 个32位数据）\n",
           filename.c_str(), total_bytes, total_bytes / 4);
}


extern "C"{

  void ebreak(uint8_t flag) {
    if (flag == 1) {  // 当Verilog传来1时，标记检测到ebreak
        is_ebreak = true;
    }
  }

  void flash_read(int32_t addr, int32_t *data) {
    if (addr < FLASH_BASE || addr > (FLASH_BASE + FLASH_SIZE - 1)) {
        fprintf(stderr, "ERROR: Flash物理地址越界！\n");
        fprintf(stderr, "  访问地址：0x%08x | 合法范围：0x%08x ~ 0x%08x\n",
                addr, FLASH_BASE, FLASH_BASE + FLASH_SIZE - 1);
        assert(0);
    }

    // ② 第二步：地址映射（物理地址 → 本地数组索引）
    // 减去物理基地址，得到本地Flash数组的偏移量（如0x30000000 → 0x0，0x30000004 → 0x4）
    uint32_t local_addr = addr - FLASH_BASE;

    // ③ 第三步：检查本地数组索引是否越界（原有逻辑，确保安全）
    if (local_addr + 3 >= FLASH_SIZE) {  // 读32位需4个连续字节
        fprintf(stderr, "ERROR: Flash本地数组越界！\n");
        fprintf(stderr, "  本地索引：0x%08x | 数组最大索引：0x%08x\n",
                local_addr, FLASH_SIZE - 1);
        assert(0);
    }

    // ④ 第四步：检查数据指针（原有逻辑）
    if (data == nullptr) {
        fprintf(stderr, "ERROR: flash_read的data指针为空！\n");
        assert(0);
    }

   // printf("addr: %08x , data_before: %08x\n",addr,flash[local_addr]);
    uint32_t flash_data = (flash[local_addr]      ) |
                         (flash[local_addr + 1] << 8) |
                         (flash[local_addr + 2] << 16) |
                         (flash[local_addr + 3] << 24);
    
   // printf("addr: %08x , data: %08x\n",addr,flash_data);
    
    
    *data = static_cast<int32_t>(flash_data);
  }
}


int main(int argc, char**argv) {
//打开外部程序到pmem_rom（逻辑不变）

  if (argv[1] == NULL) {
        //char filename[] = "/home/shuyv/ysyx-workbench/ysyxSoC/ready-to-run/D-stage/new.bin";
        char filename[] = "/home/shuyv/ysyx-workbench/npc/some_hex/rtc.bin";
        //char filename[] = "/home/shuyv/ysyx-workbench/npc/some_hex/new.bin";
        //char filename[] = "/home/shuyv/ysyx-workbench/ysyxSoC/ready-to-run/D-stage/hello-minirv-ysyxsoc.bin";
        printf("未指定bin文件,使用默认程序 : %s\n",filename);
        //load_flash_from_bin("/home/shuyv/ysyx-workbench/npc/some_hex/new.bin");
        load_flash_from_bin(filename);
        //load_flash_from_hex("/home/shuyv/ysyx-workbench/npc/some_hex/my_hex_300.hex");
  } else {
        printf("使用命令行指定的bin文件:%s\n", argv[1]);
        load_flash_from_bin(argv[1]);         // 支持手动指定其他bin文件
  }



// 将测试指令复制到 pmem 起始位置（CPU 从 0x80000000 地址取指）（逻辑不变）
  memcpy(pmem.data(), pmem_rom.data(), pmem_rom.size() * sizeof(uint32_t));

  //memcpy(pmem, pmem_rom, sizeof(pmem_rom));


  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(true);  // 开启波形跟踪（逻辑不变）
  // 2. 模块实例：Vtop* top → VysyxSoCFull* soc（仅名称替换，类型对应顶层模块）
  VysyxSoCFull* soc = new VysyxSoCFull;
  //VerilatedVcdC* tfp = new VerilatedVcdC;  // 波形文件指针（名称不变）

  // 初始化波形文件（确保路径正确）（逻辑不变，仅波形文件名适配SoC）
  // 3. 波形跟踪绑定：top->trace → soc->trace（实例名同步替换）
  //soc->trace(tfp, 99);
  // 4. 波形文件名：wave_top.vcd → wave_soc.vcd（与Makefile的WAVE_FILE保持一致）
 // tfp->open("sim/wave_soc.vcd");

  //因为时间太短看不清楚变化，专门作了个时间变量（逻辑不变）
  vluint64_t time = 0;  // 时间变量，单位ps

  soc->reset = 1;  // 初始拉高rst
  for (int i = 0; i < 20; i++) {  // 循环RST_CYCLES个完整时钟周期
    // 1. clk低电平阶段
    soc->clock = 0;
    soc->eval();          // 评估信号
    //tfp->dump(time);      // 记录波形
    time += 10;           // 时间步长（与后续一致）

    // 2. clk高电平阶段
    soc->clock = 1;
    soc->eval();          // 评估信号
    //tfp->dump(time);      // 记录波形
    time += 10;           // 时间步长
  }
  // rst拉高结束，释放rst
  soc->reset = 0;

  uint64_t count = 0;
  while(1) {

    soc->clock = 0;
    soc->eval();
    //tfp->dump(time);
    time += 10;
    //soc->inst = pmem_read(soc->pc);（原注释保留，实例名同步）


    // if(soc->inst != 0){
    //printf("count=%" PRIu64 ": PC=0x%08x, inst=0x%08x\n", count, soc->pc, soc->inst);
    // }
    
    // if(count == 200000){
    //   printf("too many count!\n");
    //   break;
    // }
    // if(count % 40 == 0){
    //   printf("count=%" PRIu64 ": PC=0x%08x, inst=0x%08x\n", count, soc->pc, soc->inst);
    // }
    if (is_ebreak)
    {
      printf("system ebreak\n");
      break;
    }
    
    // if(soc->illegal_instruction == 1){
    //   break;
    // }


    soc->clock = 1;
    soc->eval(); 
    //tfp->dump(time);  // 记录上升沿状态
    time +=10;

    count++;
  }
  
  //关闭波形文件（确保内容写入磁盘）（逻辑不变）
  //tfp->dump(time);
  //tfp->close();
 // delete tfp;
  // 8. 内存释放：delete top → delete soc（实例名同步替换）
 // delete soc;

  printf("\ncount = %" PRIu64 "\n",count);
  // if(soc->is_ebreak == 1 && soc->illegal_instruction == 1){
  //   printf("Illegal instruction!, pc = 0x%08x, inst = 0x%08x\n",soc->pc,soc->inst);
  //   printf("BAD\n");
  // }else{
  //   if(soc->is_ebreak == 1 && soc->a0 == 0){
  //     printf("GOOD a0\n");
  //     printf("is_ebreak: %d, a0: %08x\n",soc->is_ebreak,soc->a0); 

  //   }else{
  //     printf("BAD a0\n");
  //     printf("is_ebreak: %d, a0: %08x\n",soc->is_ebreak,soc->a0);
  //   }
  // }

  print_halt(count);

  return 0;
}
