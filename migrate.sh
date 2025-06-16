#!/bin/bash

# 修复版脚本：解决重复实例化和条件编译问题
set -e

WORK_DIR=${CASE_PATH}
SRC_DIR="$WORK_DIR/gen-collateral"
DST_DIR="$WORK_DIR/modified_v"
echo "DST_DIR: $DST_DIR"

echo "=== 开始修改文件脚本 - 修复版 ==="

# 创建目标目录
if [ -d "$DST_DIR" ]; then
    rm -rf "$DST_DIR"
fi
mkdir -p "$DST_DIR"

echo "1. 处理 Rocket.sv - 添加调试追踪标记"
cp "$SRC_DIR/Rocket.sv" "$DST_DIR/Rocket.sv"

# 添加调试追踪标记
sed -i 's/^  wire             ctrl_killx = /  (* trace_net *) wire             ctrl_killx = /' "$DST_DIR/Rocket.sv"
sed -i 's/^  wire             dcache_kill_mem = /  (* trace_net *) wire             dcache_kill_mem = /' "$DST_DIR/Rocket.sv"
sed -i 's/^  wire             killm_common = /  (* trace_net *) wire             killm_common = /' "$DST_DIR/Rocket.sv"
sed -i 's/^  wire             wb_set_sboard = /  (* trace_net *) wire             wb_set_sboard = /' "$DST_DIR/Rocket.sv"
sed -i 's/^  wire             id_sboard_hazard = /  (* trace_net *) wire             id_sboard_hazard = /' "$DST_DIR/Rocket.sv"
sed -i 's/^  wire             ctrl_killm = /  (* trace_net *) wire             ctrl_killm = /' "$DST_DIR/Rocket.sv"

echo "2. 处理 VCU118FPGATestHarness.sv - 添加XEPIC宏定义和条件编译支持"
cp "$SRC_DIR/VCU118FPGATestHarness.sv" "$DST_DIR/VCU118FPGATestHarness.sv"

# 在第2行后添加XEPIC宏定义
sed -i '2a\
`define XEPIC_P2E\
`define XEPIC_XRAM_RTL\
' "$DST_DIR/VCU118FPGATestHarness.sv"

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
}' "$DST_DIR/VCU118FPGATestHarness.sv"

# 修改复位逻辑 - 添加条件编译
sed -i '/assign _WIRE = _resetIBUF_O | _fpga_power_on_power_on_reset;/ {
    i\
  `ifndef XEPIC_P2E\
        assign _WIRE = _resetIBUF_O | _fpga_power_on_power_on_reset;   // @[TestHarness.scala:100:25, :113:38, Xilinx.scala:104:21]\
  `else\
        assign _WIRE = reset | _fpga_power_on_power_on_reset;  // @[TestHarness.scala:100:25, :113:38, Xilinx.scala:104:21]\
  `endif
    d
}' "$DST_DIR/VCU118FPGATestHarness.sv"

# 删除所有原始的时钟、复位和PLL相关实例，避免重复
sed -i '/^  IBUFDS #(/,/^  );$/d' "$DST_DIR/VCU118FPGATestHarness.sv"
sed -i '/^  harnessSysPLL harnessSysPLL (/,/^  );$/d' "$DST_DIR/VCU118FPGATestHarness.sv"
sed -i '/^  IBUF resetIBUF (/,/^  );$/d' "$DST_DIR/VCU118FPGATestHarness.sv"
sed -i '/^  PowerOnResetFPGAOnly fpga_power_on (/,/^  );$/d' "$DST_DIR/VCU118FPGATestHarness.sv"

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
}' "$DST_DIR/VCU118FPGATestHarness.sv"

echo "3. 处理 XilinxVCU118MIGIsland.sv - 添加XEPIC宏定义、复位逻辑和XRAM接口扩展"
cp "$SRC_DIR/XilinxVCU118MIGIsland.sv" "$DST_DIR/XilinxVCU118MIGIsland.sv"

# 在第2行后添加XEPIC宏定义
sed -i '2a\
`define XEPIC_P2E\
`define XEPIC_XRAM_RTL' "$DST_DIR/XilinxVCU118MIGIsland.sv"

# 删除原来的_blackbox_c0_init_calib_complete声明行
sed -i '/^  wire        _blackbox_c0_init_calib_complete;.*XilinxVCU118MIG.scala/d' "$DST_DIR/XilinxVCU118MIGIsland.sv"

# 在_axi4asink_auto_out_r_ready行后添加复位逻辑
sed -i '/^  wire        _axi4asink_auto_out_r_ready;/a\
  wire        com_reset;\
  wire        _blackbox_c0_init_calib_complete;        // @[XilinxVCU118MIG.scala:51:26]\
  assign com_reset = reset | (~_blackbox_c0_init_calib_complete);' "$DST_DIR/XilinxVCU118MIGIsland.sv"

# 修改复位信号
sed -i 's/\.reset                          (reset),/.reset                          (com_reset),/' "$DST_DIR/XilinxVCU118MIGIsland.sv"


# 使用Python脚本正确添加XRAM接口扩展到正确位置
# 设置环境变量传递给Python
export TARGET_FILE="$DST_DIR/XilinxVCU118MIGIsland.sv"

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

echo ""
echo "=== 修改完成 ==="
echo "生成的文件："
ls -la "$DST_DIR"

echo ""
echo "文件行数统计："
wc -l "$DST_DIR"/*.sv

echo ""
echo "验证XEPIC宏定义："
grep -c "XEPIC_P2E" "$DST_DIR"/*.sv

echo ""
echo "验证trace_net属性："
grep -c "trace_net" "$DST_DIR"/Rocket.sv

echo ""
echo "4. 更新filelist文件"
if [ -f "./update_filelist.sh" ]; then
    echo "调用filelist更新脚本..."
    ./update_filelist.sh
    echo "Filelist更新完成"
else
    echo "警告: update_filelist.sh 未找到，请手动更新filelist"
fi

echo ""
echo "=== 脚本执行完成 ===" 