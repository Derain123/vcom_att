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

#### 2.2 运行平台移植脚本
```bash
# 运行主要的平台移植脚本
./migrate.sh
```
此脚本会自动完成：
- RTL文件的修改和适配
- VCU118平台配置的添加
- 调试接口的集成
- 时钟和复位逻辑的调整


#### 2.3 修正代码位置（如需要）
```bash
# 如果出现位置错误，运行位置修正脚本
python fix_position.py modified_v/XilinxVCU118MIGIsland.sv
```

#### 2.4 验证移植结果
```bash
# 检查生成的RTL文件
ls -la modified_v/

# 检查更新的filelist
cat filelist_new.f | head -10

# 验证关键功能是否正确添加
grep -c "VCU118" modified_v/*.sv
```

#### 2.5 编译设计
```bash
# 综合
make vsyn    # 生成VCU118FPGATestHarness.vm和area.log

# 编译
make vcom    # 运行vcom_compile.tcl脚本

# 布局布线
make pnr     # 在fpgaCompDir目录中执行

```

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

### 3. 加入可写/刻度信号
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

## 输出文件
- `rtl/` - RTL源代码目录
- `filelist.f` - 文件列表
- `VCU118FPGATestHarness.vm` - 综合结果
- `area.log` - 面积报告
- `vsyn.log` - 综合日志
- `vcom_compile.log` - 编译日志
- `fpgaCompDir/` - 布局布线结果目录
- `waveform.vcd` - 波形文件

## 故障排除

### 常见问题
1. 综合失败
   - 检查RTL代码语法
   - 确认约束文件正确性
   - 查看综合日志

2. 仿真异常
   - 检查测试程序
   - 确认信号连接
   - 查看仿真日志

3. 时序违例
   - 检查时钟约束
   - 优化关键路径
   - 查看时序报告

4. Filelist错误
   - 检查文件路径是否正确
   - 确认文件是否存在
   - 验证文件顺序是否合理

---