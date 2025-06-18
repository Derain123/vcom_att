#!/bin/bash
#
# 脚本名称: migrate.sh
# 描述: FPGA设计迁移脚本 - 支持XEPIC加速器平台
#       将标准FPGA设计转换为支持XEPIC的设计，包括添加调试追踪、
#       条件编译支持、XRAM接口等功能
# 作者: SEU-ACAL
# 版本: v1.0.1
# 创建日期: 2025-06-17
# 最后修改: 2025-06-17
# 
# 功能说明:
#   1. 处理TLROM文件替换 (支持1b4l/1b5l/4l/lc四种ROM类型)
#   2. 为Rocket.sv添加调试追踪标记
#   3. 为VCU118FPGATestHarness.sv添加XEPIC条件编译支持
#   4. 为XilinxVCU118MIGIsland.sv添加XRAM接口
#   5. 向后兼容支持hc/mc选项 (映射到1b4l/4l)
#
# 依赖要求:
#   - bash >= 4.0
#   - python >= 2.7
#   - sed, grep等标准Unix工具
#
# 环境变量:
#   CASE_PATH: 项目根目录路径 (必需)
#
# 用法: 
#   ./migrate.sh [-h|--help] [1b4l|1b5l|4l|lc|hc|mc]
#
# 示例:
#   export CASE_PATH=/path/to/project
#   ./migrate.sh 1b4l  # 使用1大核4小核配置
#   ./migrate.sh 4l    # 使用4小核配置
#   ./migrate.sh       # 使用原始ROM
#
# 许可证: SEU-ACAL
#

# =============================================================================
# 全局设置和常量定义
# =============================================================================

# 严格模式设置
set -euo pipefail
IFS=$'\n\t'

# 脚本信息常量
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="1.0.1"
readonly AUTHOR="SEU-ACAL"

# 配置常量
readonly REQUIRED_BASH_VERSION="4.0"
readonly REQUIRED_PYTHON_VERSION="2.7"
readonly DEFAULT_ROM_TYPE="original"

# 全局变量
ROM_TYPE=""
FIX_POSITION=false
WORK_DIR=""
SRC_DIR=""
DST_DIR=""
ROM_SRC_DIR=""

# =============================================================================
# 工具函数
# =============================================================================

# 显示脚本版本信息
show_version() {
    cat << EOF
$SCRIPT_NAME version $VERSION
作者: $AUTHOR
描述: FPGA设计迁移脚本 - 支持XEPIC加速器平台

Copyright (c) 2025. All rights reserved.
EOF
}

# 显示帮助信息
show_help() {
    echo "$SCRIPT_NAME - FPGA设计迁移脚本"
    echo ""
    echo "描述:"
    echo "  将标准FPGA设计转换为支持XEPIC加速器平台的设计"
    echo ""
    echo "用法:"
    echo "  $SCRIPT_NAME [选项] [ROM类型]"
    echo ""
    echo "选项:"
echo "  -h, --help     显示此帮助信息"
echo "  -v, --version  显示版本信息"
echo "  --fix-position 修正XEPIC代码位置"
echo ""
echo "ROM类型:"
echo "  1b4l           使用1大核4小核配置 (TLROM_1b4l.sv)"
echo "  1b5l           使用1大核5小核配置 (TLROM_1b5l.sv)"
echo "  4l             使用4小核配置 (TLROM_4l.sv)"
echo "  lc             使用小核配置 (TLROM_lc.sv)"
echo ""
echo "向后兼容选项 (已弃用，建议使用上述具体选项):"
echo "  hc             使用异构核配置 (等同于1b4l)"
echo "  mc             使用多核配置 (等同于4l)"
echo "  (无参数)       使用原始TLROM.sv"
    echo ""
    echo "环境变量:"
echo "  CASE_PATH      项目根目录路径 (通过setup.csh设置)"
echo ""
echo "示例:"
echo "  source setup.csh           # 设置环境变量"
echo "  ./$SCRIPT_NAME 1b4l        # 使用1大核4小核配置"
echo "  ./$SCRIPT_NAME 4l          # 使用4小核配置"
echo "  ./$SCRIPT_NAME             # 使用原始ROM"
echo "  ./$SCRIPT_NAME --fix-position 1b4l  # 使用1大核4小核配置并修正XEPIC位置"
echo "  ./$SCRIPT_NAME --fix-position       # 仅修正XEPIC位置"
}

# 日志函数
log_info() {
    echo "[INFO] $1"
}

log_success() {
    echo "[成功] $1"
}

log_warning() {
    echo "[警告] $1"
}

log_error() {
    echo "[错误] $1" >&2
}

log_step() {
    echo "=== 步骤 $1: $2 ==="
}

# 错误处理函数
die() {
    log_error "$1"
    exit "${2:-1}"
}

# 清理函数
cleanup() {
    # 在这里添加需要清理的资源
    :
}

# 设置信号处理
trap cleanup EXIT
trap 'die "脚本被中断"' INT TERM

# =============================================================================
# 验证函数
# =============================================================================

# 检查bash版本
check_bash_version() {
    local current_version
    current_version=$(bash --version | head -n1 | grep -oP '\d+\.\d+' | head -1)
    
    if ! version_ge "$current_version" "$REQUIRED_BASH_VERSION"; then
        die "需要bash版本 >= $REQUIRED_BASH_VERSION，当前版本: $current_version"
    fi

}

# 检查Python版本
check_python_version() {
    if ! command -v python >/dev/null 2>&1; then
        die "未找到python命令，请安装Python >= $REQUIRED_PYTHON_VERSION"
    fi
    
    local python_version
    python_version=$(python --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
    
    if ! version_ge "$python_version" "$REQUIRED_PYTHON_VERSION"; then
        die "需要Python版本 >= $REQUIRED_PYTHON_VERSION，当前版本: $python_version"
    fi

}

# 版本比较函数
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -q "^$2$"
}

# 检查必需的命令
check_required_commands() {
    local required_commands=("sed" "grep" "cp" "mkdir" "rm" "wc")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        die "缺少必需的命令: ${missing_commands[*]}"
    fi

}

# =============================================================================
# 参数解析和验证
# =============================================================================

# 参数解析
parse_arguments() {
    ROM_TYPE=""
    FIX_POSITION=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --fix-position)
                FIX_POSITION=true
                shift
                ;;
            1b4l|1b5l|4l|lc)
                ROM_TYPE="$1"
                shift
                ;;
            hc)
                # 向后兼容：hc映射到1b4l
                ROM_TYPE="1b4l"
                log_warning "选项 'hc' 已弃用，自动映射到 '1b4l' (1大核4小核配置)"
                shift
                ;;
            mc)
                # 向后兼容：mc映射到4l
                ROM_TYPE="4l"
                log_warning "选项 'mc' 已弃用，自动映射到 '4l' (4小核配置)"
                shift
                ;;
            -*)
                die "未知选项: $1\n使用 '$SCRIPT_NAME --help' 查看帮助信息"
                ;;
            *)
                die "未知参数: $1\n使用 '$SCRIPT_NAME --help' 查看帮助信息"
                ;;
        esac
    done

}

# 环境检查
check_environment() {
    log_step "0" "环境检查"
    
    # 检查系统依赖
    check_bash_version
    check_python_version
    check_required_commands
    
    # 检查环境变量
    if [[ -z "${CASE_PATH:-}" ]]; then
        die "未设置CASE_PATH环境变量\n请在执行前运行: source setup.csh"
    fi
    
    if [[ ! -d "$CASE_PATH" ]]; then
        die "CASE_PATH目录不存在: $CASE_PATH"
    fi
    
    # 设置路径变量
    WORK_DIR="$CASE_PATH"
    SRC_DIR="$WORK_DIR/gen-collateral"
    DST_DIR="$WORK_DIR/modified_v"
    ROM_SRC_DIR="$SCRIPT_DIR/tl_rom"
    
    log_info "工作目录: $WORK_DIR"
    log_info "源文件目录: $SRC_DIR"
    log_info "输出目录: $DST_DIR"
    log_info "ROM源目录: $ROM_SRC_DIR"
    
    if [[ ! -d "$SRC_DIR" ]]; then
        die "源文件目录不存在: $SRC_DIR"
    fi
    
    log_success "环境检查通过"
}

# =============================================================================
# 核心功能函数
# =============================================================================

# 创建输出目录
setup_output_directory() {
    log_step "1" "设置输出目录"
    
    if [[ -d "$DST_DIR" ]]; then
        log_info "清理现有输出目录"
        rm -rf "$DST_DIR"
    fi
    
    mkdir -p "$DST_DIR"
    log_success "输出目录创建完成: $DST_DIR"
}

# 处理TLROM文件
process_tlrom() {
    log_step "2" "处理TLROM文件"
    
    if [[ -n "$ROM_TYPE" && "$ROM_TYPE" =~ ^(1b4l|1b5l|4l|lc)$ ]]; then
        local rom_file="TLROM_${ROM_TYPE}.sv"
        local rom_path="$ROM_SRC_DIR/$rom_file"
        
        if [[ -f "$rom_path" ]]; then
            log_info "使用自定义ROM: $rom_file"
            cp "$rom_path" "$DST_DIR/TLROM.sv"
            log_success "已将 $rom_file 复制为 TLROM.sv"
            
            # 显示ROM配置详细信息
            case "$ROM_TYPE" in
                1b4l)
                    log_info "ROM配置: 1大核4小核 (异构架构)"
                    ;;
                1b5l)
                    log_info "ROM配置: 1大核5小核 (异构架构)"
                    ;;
                4l)
                    log_info "ROM配置: 4小核 (多核架构)"
                    ;;
                lc)
                    log_info "ROM配置: 小核 (单核架构)"
                    ;;
            esac
        else
            log_warning "未找到ROM文件: $rom_path"
            log_info "回退到使用原始TLROM.sv"
            if [[ -f "$SRC_DIR/TLROM.sv" ]]; then
                cp "$SRC_DIR/TLROM.sv" "$DST_DIR/TLROM.sv"
                log_success "原始TLROM.sv复制完成"
            else
                die "原始TLROM.sv也不存在: $SRC_DIR/TLROM.sv"
            fi
        fi
    else
        log_info "使用原始TLROM.sv文件"
        if [[ -f "$SRC_DIR/TLROM.sv" ]]; then
            cp "$SRC_DIR/TLROM.sv" "$DST_DIR/TLROM.sv"
            log_success "原始TLROM.sv复制完成"
        else
            die "原始TLROM.sv不存在: $SRC_DIR/TLROM.sv"
        fi
    fi
}

# 处理Rocket.sv - 添加调试追踪标记
process_rocket() {
    log_step "3" "处理Rocket.sv - 添加调试追踪标记"
    
    local src_file="$SRC_DIR/Rocket.sv"
    local dst_file="$DST_DIR/Rocket.sv"
    
    if [[ ! -f "$src_file" ]]; then
        die "Rocket.sv文件不存在: $src_file"
    fi
    
    cp "$src_file" "$dst_file"
    
    # 添加调试追踪标记
    local trace_signals=("ctrl_killx" "dcache_kill_mem" "killm_common" "wb_set_sboard" "id_sboard_hazard" "ctrl_killm")
    
    for signal in "${trace_signals[@]}"; do
        sed -i "s/^  wire             ${signal} = /  (* trace_net *) wire             ${signal} = /" "$dst_file"

    done
    
    log_success "Rocket.sv处理完成，已添加 ${#trace_signals[@]} 个trace标记"
}

# 处理VCU118FPGATestHarness.sv - 添加XEPIC支持
process_test_harness() {
    log_step "4" "处理VCU118FPGATestHarness.sv - 添加XEPIC支持"
    
    local src_file="$SRC_DIR/VCU118FPGATestHarness.sv"
    local dst_file="$DST_DIR/VCU118FPGATestHarness.sv"
    
    if [[ ! -f "$src_file" ]]; then
        die "VCU118FPGATestHarness.sv文件不存在: $src_file"
    fi
    
    cp "$src_file" "$dst_file"
    
    log_info "添加XEPIC宏定义"
    # 在第2行后添加XEPIC宏定义
    sed -i '2a\
`define XEPIC_P2E\
`define XEPIC_XRAM_RTL\
' "$dst_file"

    log_info "修改模块接口 - 添加条件编译"
    # 修改模块接口 - 添加条件编译
    sed -i '/^  input         sys_clock_p,/,/^                sys_clock_n,/ {
        /^  input         sys_clock_p,/ {
            i\
`ifndef XEPIC_P2E
            a\
                    sys_clock_n,\
`else\
  input                clock,\
  output        sdio_sel,\
`endif
            d
        }
        /^                sys_clock_n,/ d
    }' "$dst_file"

    log_info "修改复位逻辑"
    # 修改复位逻辑 - 添加条件编译
    sed -i '/assign _WIRE = _resetIBUF_O | _fpga_power_on_power_on_reset;/ {
        i\
  `ifndef XEPIC_P2E\
            assign _WIRE = _resetIBUF_O | _fpga_power_on_power_on_reset;   // @[TestHarness.scala:100:25, :113:38, Xilinx.scala:104:21]\
  `else\
            assign _WIRE = reset | _fpga_power_on_power_on_reset;  // @[TestHarness.scala:100:25, :113:38, Xilinx.scala:104:21]\
  `endif
        d
    }' "$dst_file"

    log_info "删除原始实例，避免重复"
    # 删除所有原始的时钟、复位和PLL相关实例，避免重复
    sed -i '/^  IBUFDS #(/,/^  );$/d' "$dst_file"
    sed -i '/^  harnessSysPLL harnessSysPLL (/,/^  );$/d' "$dst_file"
    sed -i '/^  IBUF resetIBUF (/,/^  );$/d' "$dst_file"
    sed -i '/^  PowerOnResetFPGAOnly fpga_power_on (/,/^  );$/d' "$dst_file"

    log_info "添加完整的条件编译块"
    # 在AnalogToUInt_1 a2b_4后添加完整的条件编译块
    sed -i '/AnalogToUInt_1 a2b_4 (/,/);/ {
        /);/ a\
\
`ifndef XEPIC_P2E\
  IBUFDS #(\
    .DIFF_TERM("FALSE"),\
    .IOSTANDARD("DEFAULT"),\
    .DQS_BIAS("FALSE"),\
    .CAPACITANCE("DONT_CARE"),\
    .IFD_DELAY_VALUE("AUTO"),\
    .IBUF_LOW_PWR("TRUE"),\
    .IBUF_DELAY_VALUE(0)\
  ) sys_clock_ibufds (	// @[ClockOverlay.scala:14:24]\
    .I  (sys_clock_p),\
    .IB (sys_clock_n),\
    .O  (_sys_clock_ibufds_O)\
  );\
\
  harnessSysPLL harnessSysPLL (	// @[XilinxShell.scala:84:55]\
    .clk_in1  (_sys_clock_ibufds_O),	// @[ClockOverlay.scala:14:24]\
    .reset    (_WIRE),	// @[TestHarness.scala:113:38]\
    .clk_out1 (_harnessSysPLL_clk_out1),\
    .locked   (_harnessSysPLL_locked)\
  );\
\
  IBUF resetIBUF (	// @[TestHarness.scala:100:25]\
    .I (reset),\
    .O (_resetIBUF_O)\
  );\
\
  PowerOnResetFPGAOnly fpga_power_on (	// @[Xilinx.scala:104:21]\
    .clock          (_sys_clock_ibufds_O),	// @[ClockOverlay.scala:14:24]\
    .power_on_reset (_fpga_power_on_power_on_reset)\
  );\
`else\
  assign _sys_clock_ibufds_O = clock;\
  assign _harnessSysPLL_clk_out1 = clock;\
  assign _harnessSysPLL_locked = 1;\
\
  PowerOnResetFPGAOnly fpga_power_on (	// @[Xilinx.scala:104:21]\
    .clock          (clock),	// @[ClockOverlay.scala:14:24]\
    .power_on_reset (_fpga_power_on_power_on_reset)\
  );\
`endif\
\
assign sdio_sel = 1'\''b0;
    }' "$dst_file"

    log_success "VCU118FPGATestHarness.sv处理完成"
}

# 处理XilinxVCU118MIGIsland.sv - 添加XRAM接口
process_mig_island() {
    log_step "5" "处理XilinxVCU118MIGIsland.sv - 添加XRAM接口"
    
    local src_file="$SRC_DIR/XilinxVCU118MIGIsland.sv"
    local dst_file="$DST_DIR/XilinxVCU118MIGIsland.sv"
    
    if [[ ! -f "$src_file" ]]; then
        die "XilinxVCU118MIGIsland.sv文件不存在: $src_file"
    fi
    
    cp "$src_file" "$dst_file"
    
    log_info "添加XEPIC宏定义"
    # 在第2行后添加XEPIC宏定义
    sed -i '2a\
`define XEPIC_P2E\
`define XEPIC_XRAM_RTL' "$dst_file"

    log_info "处理复位逻辑"
    # 删除原来的_blackbox_c0_init_calib_complete声明行
    sed -i '/^  wire        _blackbox_c0_init_calib_complete;.*XilinxVCU118MIG.scala/d' "$dst_file"

    # 在_axi4asink_auto_out_r_ready行后添加复位逻辑
    sed -i '/^  wire        _axi4asink_auto_out_r_ready;/a\
  wire        com_reset;\
  wire        _blackbox_c0_init_calib_complete;        // @[XilinxVCU118MIG.scala:51:26]\
  assign com_reset = reset | (~_blackbox_c0_init_calib_complete);' "$dst_file"

    # 修改复位信号
    sed -i 's/\.reset                          (reset),/.reset                          (com_reset),/' "$dst_file"

    log_info "使用Python脚本添加XRAM接口"
    add_xram_interface "$dst_file"
    
    log_success "XilinxVCU118MIGIsland.sv处理完成"
}

# 使用Python添加XRAM接口
add_xram_interface() {
    local target_file="$1"

    
    # 设置环境变量传递给Python
    export TARGET_FILE="$target_file"

    python << 'EOF'
# -*- coding: utf-8 -*-
import re
import os

filename = os.environ.get('TARGET_FILE')

with open(filename, 'r') as f:
    content = f.read()

# 找到axi4asink模块结束位置
axi4asink_end = content.find('  );', content.find('auto_out_r_ready'))
if axi4asink_end != -1:
    axi4asink_end += 4  # include '  );'
    
    # 在axi4asink结束后、vcu118mig开始前插入XEPIC代码
    xepic_code = '''

`ifdef XEPIC_P2E
        logic  [1:0]                      xram0_read;        
        logic  [127:0]                    xram0_read_addr;  
        logic  [1:0]                      xram0_read_data_ready; 
        logic  [1:0]                      xram0_write;       
        logic  [127:0]                    xram0_write_addr; 
        logic  [1151:0]                   xram0_write_data;    
        logic  [127:0]                    xram0_write_data_mask;
        
        logic  [1151:0]                   xram0_read_data;    
        logic  [1:0]                      xram0_read_data_valid;
        logic                             mmp_ddr4_calib_done;

         // slave0 slave-embeded, support burst control
         defparam u_axi_xram.AXI_MODE = 4;  // AXI Mode: 3 = AXI3, 4 = AXI4
         defparam u_axi_xram.AXI_ID_WIDTH   = 4;
         defparam u_axi_xram.AXI_DATA_WIDTH = 64;   // Data Width: 8,16,32,64,128,256,512,1024 
         defparam u_axi_xram.AXI_ADDR_WIDTH = 32;  // Addr Width: 32..64
         defparam u_axi_xram.AXI_USER_WIDTH = 0;  // 
         defparam u_axi_xram.MEM_SIZE = 64'h4_0000_0000;  // 2^34
 
         xaxi4_slave_emb u_axi_xram ( //or xaxi4_slave_emb_wrapper
            /*AUTOARG*/
            .aclk      (io_port_c0_sys_clk_i),
            .aresetn   (~io_port_sys_rst),
            // AXI write address channel
            .i_awvalid (_axi4asink_auto_out_aw_valid),
            .o_awready (_blackbox_c0_ddr4_s_axi_awready),
            .i_awid    (_axi4asink_auto_out_aw_bits_id),
            .i_awaddr  (_axi4asink_auto_out_aw_bits_addr[30:0]),
            .i_awlen   (_axi4asink_auto_out_aw_bits_len),     // in AXI3 .mode    (mode    ), [7:4] should be fixed to 0
            .i_awsize  (_axi4asink_auto_out_aw_bits_size),
            .i_awburst (_axi4asink_auto_out_aw_bits_burst),
            .i_awlock  (_axi4asink_auto_out_aw_bits_lock),
            .i_awcache (4'h3),
            .i_awprot  (_axi4asink_auto_out_aw_bits_prot),
            .i_awqos   (_axi4asink_auto_out_aw_bits_qos),
            .i_awregion(4'b0),
            // AXI write data channel
            .i_wvalid  (_axi4asink_auto_out_w_valid),
            .o_wready  (_blackbox_c0_ddr4_s_axi_wready),
            .i_wid     (0),
            .i_wdata   (_axi4asink_auto_out_w_bits_data),
            .i_wstrb   (_axi4asink_auto_out_w_bits_strb),
            .i_wlast   (_axi4asink_auto_out_w_bits_last),
            // AXI write response channel
            .o_bvalid  (_blackbox_c0_ddr4_s_axi_bvalid),
            .i_bready  (_axi4asink_auto_out_b_ready),
            .o_bid     (_blackbox_c0_ddr4_s_axi_bid),
            .o_bresp   (_blackbox_c0_ddr4_s_axi_bresp),

            // AXI read address channel
            .i_arvalid (_axi4asink_auto_out_ar_valid),
            .o_arready (_blackbox_c0_ddr4_s_axi_arready),
            .i_arid    (_axi4asink_auto_out_ar_bits_id),
            .i_araddr  (_axi4asink_auto_out_ar_bits_addr[30:0]),
            .i_arlen   (_axi4asink_auto_out_ar_bits_len),     // in AXI3 .mode    (mode    ), [7:4] should be fixed to 0
            .i_arsize  (_axi4asink_auto_out_ar_bits_size),
            .i_arburst (_axi4asink_auto_out_ar_bits_burst),
            .i_arlock  (_axi4asink_auto_out_ar_bits_lock),
            .i_arcache (4'h3),
            .i_arprot  (_axi4asink_auto_out_ar_bits_prot),
            .i_arqos   (_axi4asink_auto_out_ar_bits_qos),
            .i_arregion(4'b0),
            // AXI read response
            .o_rvalid  (_blackbox_c0_ddr4_s_axi_rvalid),
            .i_rready  (_axi4asink_auto_out_r_ready),
            .o_rid     (_blackbox_c0_ddr4_s_axi_rid),
            .o_rresp   (_blackbox_c0_ddr4_s_axi_rresp),
            .o_rdata   (_blackbox_c0_ddr4_s_axi_rdata),
            .o_rlast   (_blackbox_c0_ddr4_s_axi_rlast)
            );
    
        `ifdef XEPIC_XRAM_RTL
          xram_bbox_wrapper u_xram_bbox_wrapper (
              .uclk(io_port_c0_sys_clk_i),
              .xram0_read(xram0_read),
              .xram0_read_addr(xram0_read_addr),
              .xram0_read_data_ready(xram0_read_data_ready),
              .xram0_write(xram0_write),
              .xram0_write_addr(xram0_write_addr),
              .xram0_write_data(xram0_write_data),
              .xram0_write_data_mask(xram0_write_data_mask),
              .xram0_read_data(xram0_read_data),
              .xram0_read_data_valid(xram0_read_data_valid), 
              .mmp_ddr4_calib_done(_blackbox_c0_init_calib_complete)
          )/* synthesis syn_preserve=1 */;

          assign xram0_write[0]                  = u_axi_xram.write_xram;
          assign xram0_write_addr[0 +: 64]       = u_axi_xram.wr_addr_xram ;
          assign xram0_write_data[0 +: 576]      = u_axi_xram.wrdata_xram;
          assign xram0_write_data_mask[0 +: 64]  = u_axi_xram.wrdata_mask_xram;

          assign xram0_read[0]                   = 1'h0;
          assign xram0_read_addr[0 +: 64]        = 64'h0;
          assign xram0_read_data_ready[0]        = 1'h0;


          assign u_axi_xram.init_calib_complete = _blackbox_c0_init_calib_complete;

          assign xram0_write[1]                  = 1'h0;
          assign xram0_write_addr[64 +: 64]      = 64'h0;
          assign xram0_write_data[576 +: 576]    = 576'h0;
          assign xram0_write_data_mask[64 +: 64] = 64'h0;

          assign xram0_read[1]                   = u_axi_xram.read_xram;        
          assign xram0_read_addr[64 +: 64]       = u_axi_xram.rd_addr_xram;     
          assign xram0_read_data_ready[1]        = u_axi_xram.rddata_ready_xram;
          assign u_axi_xram.rddata_xram        = xram0_read_data[576 +: 576];
          assign u_axi_xram.rddata_valid_xram  = xram0_read_data_valid[1];
        `endif
        assign io_port_c0_ddr4_ui_clk = io_port_c0_sys_clk_i;
        assign io_port_c0_ddr4_ui_clk_sync_rst = 1'b0;

`else'''
    
    # 插入XEPIC代码
    content = content[:axi4asink_end] + xepic_code + content[axi4asink_end:]
    
    # 找到vcu118mig模块的结束位置并插入endif
    vcu118mig_start = content.find('vcu118mig blackbox')
    if vcu118mig_start != -1:
        # 从vcu118mig开始位置向后找到对应的模块结束位置
        vcu118mig_end = content.find('  );', vcu118mig_start)
        if vcu118mig_end != -1:
            vcu118mig_end += 4  # include '  );'
            # 在vcu118mig模块结束后插入endif
            endif_code = '\n`endif'
            content = content[:vcu118mig_end] + endif_code + content[vcu118mig_end:]

# 写回文件
with open(filename, 'w') as f:
    f.write(content)
EOF


}

# 修正XEPIC代码位置
fix_xepic_position() {
    log_step "6" "修正XEPIC代码位置"
    
    local fix_script="$SCRIPT_DIR/fix_position.py"
    local target_file="$DST_DIR/XilinxVCU118MIGIsland.sv"
    
    # 检查Python脚本是否存在
    if [[ ! -f "$fix_script" ]]; then
        log_error "修正脚本不存在: $fix_script"
        return 1
    fi
    
    # 检查目标文件是否存在
    if [[ ! -f "$target_file" ]]; then
        log_error "目标文件不存在: $target_file"
        return 1
    fi
    
    log_info "运行XEPIC位置修正脚本..."
    log_info "脚本路径: $fix_script"
    log_info "目标文件: $target_file"
    
    # 运行Python脚本
    if python "$fix_script" "$target_file"; then
        log_success "XEPIC代码位置修正完成"
        return 0
    else
        log_error "XEPIC代码位置修正失败"
        return 1
    fi
}

# 生成结果统计
generate_summary() {
    if [[ "$FIX_POSITION" == "true" ]]; then
        log_step "7" "生成结果统计"
    else
        log_step "6" "生成结果统计"
    fi
    
    echo ""
    log_info "生成的文件列表:"
    ls -la "$DST_DIR"

    echo ""
    log_info "文件行数统计:"
    wc -l "$DST_DIR"/*.sv

    echo ""
    log_info "TLROM文件验证:"
    if [[ -n "$ROM_TYPE" && "$ROM_TYPE" =~ ^(1b4l|1b5l|4l|lc)$ ]]; then
        case "$ROM_TYPE" in
            1b4l)
                echo "  ROM类型: $ROM_TYPE - 1大核4小核配置 (来源: TLROM_${ROM_TYPE}.sv)"
                ;;
            1b5l)
                echo "  ROM类型: $ROM_TYPE - 1大核5小核配置 (来源: TLROM_${ROM_TYPE}.sv)"
                ;;
            4l)
                echo "  ROM类型: $ROM_TYPE - 4小核配置 (来源: TLROM_${ROM_TYPE}.sv)"
                ;;
            lc)
                echo "  ROM类型: $ROM_TYPE - 小核配置 (来源: TLROM_${ROM_TYPE}.sv)"
                ;;
        esac
    else
        echo "  ROM类型: 原始 (来源: 原始TLROM.sv)"
    fi
    echo "  TLROM行数: $(wc -l < "$DST_DIR/TLROM.sv")"

    echo ""
    log_info "XEPIC宏定义验证:"
    local xepic_count
    xepic_count=$(grep -c "XEPIC_P2E" "$DST_DIR"/*.sv | grep -v ":0" | wc -l || echo "0")
    if [[ "$xepic_count" -gt 0 ]]; then
        grep -c "XEPIC_P2E" "$DST_DIR"/*.sv | grep -v ":0"
    else
        echo "  未找到XEPIC_P2E宏定义"
    fi

    echo ""
    log_info "trace_net属性验证:"
    local trace_count
    trace_count=$(grep -c "trace_net" "$DST_DIR/Rocket.sv" 2>/dev/null || echo "0")
    echo "  Rocket.sv中的trace_net数量: $trace_count"
    
    echo ""
    log_info "处理统计:"
    echo "  - 总处理文件数: $(find "$DST_DIR" -name "*.sv" | wc -l)"
    echo "  - 总代码行数: $(cat "$DST_DIR"/*.sv | wc -l)"
    echo "  - 输出目录大小: $(du -sh "$DST_DIR" | cut -f1)"
}

# 更新文件列表
update_filelist() {
    if [[ "$FIX_POSITION" == "true" ]]; then
        log_step "8" "更新文件列表"
    else
        log_step "7" "更新文件列表"
    fi
    
    local filelist_script="./update_filelist.sh"
    
    if [[ -f "$filelist_script" ]]; then
        log_info "调用filelist更新脚本..."
        if bash "$filelist_script"; then
            log_success "Filelist更新完成"
        else
            log_warning "Filelist更新脚本执行失败，请检查脚本"
        fi
    else
        log_warning "update_filelist.sh 未找到，请手动更新filelist"
        log_info "您可以手动运行: bash update_filelist.sh"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

# 显示脚本横幅
show_banner() {
    echo "================================================================================"
    echo "                   FPGA设计迁移脚本 - XEPIC支持版本"
    echo "                             版本 $VERSION"
    echo "================================================================================"
}

# 仅运行位置修正功能
run_fix_position_only() {
    # 检查环境变量
    if [[ -z "${CASE_PATH:-}" ]]; then
        die "未设置CASE_PATH环境变量\n请在执行前运行: source setup.csh"
    fi
    
    if [[ ! -d "$CASE_PATH" ]]; then
        die "CASE_PATH目录不存在: $CASE_PATH"
    fi
    
    # 设置路径变量
    WORK_DIR="$CASE_PATH"
    DST_DIR="$WORK_DIR/modified_v"
    
    log_info "工作目录: $WORK_DIR"
    log_info "输出目录: $DST_DIR"
    
    # 检查输出目录是否存在
    if [[ ! -d "$DST_DIR" ]]; then
        die "输出目录不存在: $DST_DIR\n请先运行完整的迁移流程"
    fi
    
    # 运行位置修正
    fix_xepic_position
    
    echo ""
    log_success "=== 位置修正完成 ==="
    log_info "已修正文件: $DST_DIR/XilinxVCU118MIGIsland.sv"
}

# 主函数
main() {
    # 显示横幅
    show_banner
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 如果只指定了--fix-position参数，只运行位置修正
    if [[ "$FIX_POSITION" == "true" && -z "$ROM_TYPE" ]]; then
        run_fix_position_only
        return
    fi
    
    # 执行完整迁移步骤
    check_environment
    setup_output_directory
    process_tlrom
    process_rocket
    process_test_harness
    process_mig_island
    
    # 如果指定了--fix-position参数，运行位置修正
    if [[ "$FIX_POSITION" == "true" ]]; then
        fix_xepic_position
    fi
    
    generate_summary
    update_filelist
    
    echo ""
    log_success "=== 脚本执行完成 ==="
    log_info "输出文件位于: $DST_DIR"
    log_info "如有问题，请检查上述日志信息"
    

}

# =============================================================================
# 脚本入口点
# =============================================================================

# 当脚本被直接执行时运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 