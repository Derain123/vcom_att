# 加速器平台开发手册

## 功能说明
本平台用于实现对流片架构代码的验证，主要功能包括：
1. 实现大型设计的验证
2. FPGA并行仿真验证
3. 处理器/加速器微架构debug

## 快速开始

### 1. 环境准备
```bash
source setup.csh
```

### 2. 编译流程

#### 2.1 获取原始RTL代码
```bash
# 从chipyard FPGA目录获取Verilog代码, 默认设的是RocketConfig
#需要修改的话，修改/home/rain/chipyard/fpga/src/main/scala/vcu118/Configs.scala文件
cd $CHIPYARD/fpga
make SUB_PROJECT=vcu118 CONFIG=RocketVCU118Config bitstream
#然后将生成的gen-collateral文件夹复制到工程目录下
```
> **⚠️ NOTE：** 此处如果出现板子类型找不到的报错不用理会，我们只需要verilog生成成功即可



#### 2.2 运行平台移植脚本
```bash
# 查看脚本帮助信息
./migrate.sh --help

# 基本移植（使用原始ROM）
./migrate.sh

# 使用特定ROM配置移植
./migrate.sh 1b5l    # 1大核5小核配置
./migrate.sh lc    # 小核配置
./migrate.sh 4l    # 4小核配置

# 移植并自动修正XEPIC代码位置
./migrate.sh --fix-position 1b5l

# 仅修正已有文件的XEPIC代码位置
./migrate.sh --fix-position
```
> **⚠️ NOTE：** --fix-position是必加的选项

此脚本会自动完成：
- TLROM文件替换（根据配置类型）
- Rocket.sv添加调试追踪标记
- VCU118FPGATestHarness.sv添加XEPIC条件编译支持
- XilinxVCU118MIGIsland.sv添加XRAM接口
- 自动位置修正（使用--fix-position参数时）

#### 2.3 验证移植结果
```bash
# 检查生成的RTL文件
ls -la modified_v/

# 验证XEPIC宏定义
grep -c "XEPIC_P2E" modified_v/*.sv

# 验证trace_net标记
grep -c "trace_net" modified_v/Rocket.sv

# 验证XRAM接口
grep -A 5 -B 5 "xram0_read" modified_v/XilinxVCU118MIGIsland.sv

# 检查更新的filelist
cat filelist_new.f | head -10
```

#### 2.4 编译设计
```bash
# 综合
make vsyn    # 生成VCU118FPGATestHarness.vm和area.log

# 编译
make vcom    # 运行vcom_compile.tcl脚本

# 布局布线
make pnr     # 在fpgaCompDir目录中执行
```
> **⚠️ NOTE：** make pnr无需进入目录，在工作目录make即可

### 3. 运行流程
```bash
# 修改.debug_info文件
vim .design_info    # 修改div:15

# 进入vdbg工具
vdbg    

# 运行tcl脚本
source debug_trigger.tcl     

# 后门写入测试程序
memory -write -fpga 0.A -channel 0 -file /home/tools/guochuang_backdoor_data/brno_c_22.hex 

# 继续运行
run -nowait 

```
> **⚠️ NOTE：** 自己的workload要求hex格式

## 脚本功能详解

### migrate.sh 脚本参数
```bash
# 显示帮助信息
./migrate.sh --help
./migrate.sh -h

# 显示版本信息  
./migrate.sh --version
./migrate.sh -v


# XEPIC位置修正
./migrate.sh --fix-position        # 仅修正位置
./migrate.sh --fix-position hc     # 完整流程+位置修正
```

### 脚本处理的文件
| 源文件 | 目标文件 | 处理内容 |
|--------|----------|----------|
| `tl_rom/TL_ROM_*.sv` | `modified_v/TLROM.sv` | ROM类型替换 |
| `gen-collateral/Rocket.sv` | `modified_v/Rocket.sv` | 添加trace_net标记 |
| `gen-collateral/VCU118FPGATestHarness.sv` | `modified_v/VCU118FPGATestHarness.sv` | 添加XEPIC条件编译 |
| `gen-collateral/XilinxVCU118MIGIsland.sv` | `modified_v/XilinxVCU118MIGIsland.sv` | 添加XRAM接口 |

### 执行步骤说明
1. **环境检查** - 验证bash/python版本、必需命令、CASE_PATH设置
2. **输出目录设置** - 创建/清理modified_v目录
3. **TLROM处理** - 根据参数复制对应ROM文件
4. **Rocket处理** - 为关键信号添加调试追踪标记
5. **TestHarness处理** - 添加XEPIC宏定义和条件编译
6. **MIGIsland处理** - 添加XRAM接口和复位逻辑
7. **位置修正** - 修正XEPIC代码在文件中的位置（可选）
8. **结果统计** - 验证处理结果并生成统计信息
9. **文件列表更新** - 调用update_filelist.sh更新编译列表

## 常见功能介绍

### 1. 切换使用的FPGA
```bash
# 修改硬件配置文件
vim hw-config.hdf

# 修改IP地址的最后两位，可选择：
# 192.168.100.10
# 192.168.100.11  
# 192.168.100.12
# 192.168.100.13
# 192.168.100.14

# 示例：切换到FPGA板卡11
# BOARD += {"index": 0, "type": "FOUR_CHIP_BOARD", "SN": "RRD00000026AFE0", "CLK": 0, "IP": "192.168.100.11"}

```

### 2. FPGA联调方法
- 采用hw-config_union.hdf
- 在compile脚本选择每个board采用的资源百分比
- 一个双board联调的案例如下(修改vcom_compile.tcl脚本)

```tcl

 emulator_spec -add "file hw-config_union.hdf"

 emulator_util -add {default 0}
 emulator_util -add {0.A 60}
 emulator_util -add {0.B 60}
 emulator_util -add {0.C 60}
 emulator_util -add {0.D 60}
 emulator_util -add {1.A 60}
 emulator_util -add {1.B 60}
 emulator_util -add {1.C 60}
 emulator_util -add {1.D 60}

```

### 3. 加入可写/可读信号
```tcl
# 在vcom_compile脚本中加入
 write_net -add {reset}
 write_net -add {_WIRE}
 write_net -add {_fpga_power_on_power_on_reset}
 write_net -add {_harnessBinderReset_catcher_io_sync_reset}
 read_net -add  {VCU118FPGATestHarness.mig.island.mmp_ddr4_calib_done}
```

### 4. 后门输入测试程序
```tcl
# 在debug_trigger.tcl脚本加入
memory -write -fpga 0.A -channel 0 -file /home/tools/guochuang_backdoor_data/brno_c_22.hex

# 然后等待30s左右后运行
run -nowait

```

### 5. 波形生成与查看（修改run脚本）
```bash
# 生成波形文件
for {set i 0} {$i < 3} {incr i} {
tracedb -open wave_mb$i -xedb -overwrite;
trace_signals -add *;
run 800000 rclk;
tracedb -upload;
}

# 使用xWave查看波形
xwave -wdb wave_mb0.xvcf
```
> **⚠️ NOTE：** 修改debug_trigger.tcl

## 输出文件

### 脚本生成文件
- `modified_v/` - 修改后的RTL文件目录
  - `TLROM.sv` - ROM文件（根据配置替换）
  - `Rocket.sv` - 添加了trace标记的Rocket核心
  - `VCU118FPGATestHarness.sv` - 添加了XEPIC支持的测试平台
  - `XilinxVCU118MIGIsland.sv` - 添加了XRAM接口的内存岛
- `filelist_new.f` - 更新后的文件列表

### 编译生成文件
- `VCU118FPGATestHarness.vm` - 综合结果
- `area.log` - 面积报告
- `vsyn.log` - 综合日志
- `vcom_compile.log` - 编译日志
- `fpgaCompDir/` - 布局布线结果目录
- `waveform.vcd` - 波形文件

## 故障排除

### 脚本相关问题
1. **CASE_PATH未设置**
   ```bash
   [错误] 未设置CASE_PATH环境变量
   请在执行前运行: source setup.csh
   ```
   解决方法：运行 `source setup.csh` 设置环境变量

2. **源文件目录不存在**
   ```bash
   [错误] 源文件目录不存在: /path/to/gen-collateral
   ```
   解决方法：确认已从chipyard生成gen-collateral目录

3. **Python脚本不存在**
   ```bash
   [错误] 修正脚本不存在: /path/to/fix_position.py
   ```
   解决方法：确认fix_position.py文件在脚本同一目录下

4. **目标文件不存在（--fix-position）**
   ```bash
   [错误] 目标文件不存在: /path/to/modified_v/XilinxVCU118MIGIsland.sv
   ```
   解决方法：先运行完整迁移流程，再使用--fix-position

5. **ROM文件不存在**
   ```bash
   [警告] 未找到ROM文件: /path/to/tl_rom/TL_ROM_hc.sv
   [INFO] 回退到使用原始TLROM.sv
   ```
   解决方法：确认tl_rom目录下有对应的ROM文件

### 系统相关问题
1. **综合失败**
   - 检查RTL代码语法
   - 确认约束文件正确性
   - 查看综合日志

2. **仿真异常**
   - 检查测试程序
   - 确认信号连接
   - 查看仿真日志

3. **时序违例**
   - 检查时钟约束
   - 优化关键路径
   - 查看时序报告

4. **Filelist错误**
   - 检查文件路径是否正确
   - 确认文件是否存在
   - 验证文件顺序是否合理

---