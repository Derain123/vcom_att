#!/bin/bash

# 1. 检查备份文件是否存在，如果不存在则从当前文件创建
if [ ! -f gen-collateral/filelist.f.bak ]; then
    echo "备份文件不存在，从当前文件创建备份..."
    cp gen-collateral/filelist.f gen-collateral/filelist.f.bak
fi

# 2. 添加include路径
echo "+incdir+\${SRC_PATH}" > filelist_new.f
echo "+incdir+\${XRAM_PATH}" >> filelist_new.f

# 3. 定义xram相关文件名（不含路径）- 按照filelistall.f中的顺序
xram_files=(
xaxi4_slave_emb_lib.sv
xaxi4_slave_emb_wreq.sv
xaxi4_slave_emb_wresp.sv
xaxi4_slave_emb_rch.sv
xaxi4_slave_emb_rst.sv
xaxi4_slave_emb_rresp.sv
xaxi4_slave_emb_wmem.sv
xaxi4_slave_emb_rreq.sv
xaxi4_slave_emb_reg.sv
xaxi4_slave_emb_WDT.sv
xaxi4_slave_emb_exc.sv
xaxi4_slave_emb_rmem.sv
xaxi4_slave_emb.sv
xaxi4_slave_emb_core.sv
xaxi4_slave_emb_mem.sv
xaxi4_slave_emb_wch.sv
xaxi4_xram_adapter.sv
xaxi4_xram_rlatency_mon.sv
xaxi4_xram_mon.sv
)

# 4. 定义需要使用MODIFIED_PATH路径的特殊文件
modified_path_files=(
XilinxVCU118MIGIsland.sv
Rocket.sv
VCU118FPGATestHarness.sv
)

# 5. 处理主文件内容 - 先收集所有非XRAM文件
while read -r line; do
  # 跳过空行和include行
  [[ -z "$line" || "$line" =~ ^\+incdir ]] && continue
  
  # 提取纯文件名，移除所有可能的路径前缀
  clean_line="$line"
  
  # 如果行已经包含路径变量，直接提取文件名部分
  if [[ "$clean_line" =~ ^\$\{.*\}/ ]]; then
    # 提取路径变量后面的文件名
    clean_line="${clean_line##*/}"
  else
    # 移除其他可能的路径前缀
    clean_line="${clean_line#./}"
    clean_line="${clean_line##*/}"
  fi
  
  # 移除可能的后缀垃圾
  clean_line="${clean_line%/\}/\}/P2_Emu/wrapper/\}}"
  clean_line="${clean_line%/\}}"
  
  # 跳过xepic_golden_ip.sv、xram_bbox_wrapper.v和TestDriver.v，稍后单独处理或排除
  [[ "$clean_line" == "xepic_golden_ip.sv" || "$clean_line" == "xram_bbox_wrapper.v" || "$clean_line" == "TestDriver.v" ]] && continue
  
  # 判断是否是xram相关文件
  is_xram=0
  for xf in "${xram_files[@]}"; do
    [[ "$clean_line" == "$xf" ]] && is_xram=1 && break
  done
  
  # 判断是否是需要使用MODIFIED_PATH的文件
  is_modified=0
  for mf in "${modified_path_files[@]}"; do
    [[ "$clean_line" == "$mf" ]] && is_modified=1 && break
  done
  
  # 只添加非XRAM文件，XRAM文件按照指定顺序稍后添加
  if [[ $is_xram -eq 0 ]]; then
    if [[ $is_modified -eq 1 ]]; then
      echo "\${MODIFIED_PATH}/$clean_line" >> filelist_new.f
    else
      echo "\${SRC_PATH}/$clean_line" >> filelist_new.f
    fi
  fi
done < gen-collateral/filelist.f.bak

# 5. 按照指定顺序添加XRAM相关文件
for xf in "${xram_files[@]}"; do
  echo "\${XRAM_PATH}/$xf" >> filelist_new.f
done

# 6. 最后添加xepic_golden_ip.sv（重要：必须在其他XRAM文件之后）
echo "\${XRAM_PATH}/xepic_golden_ip.sv" >> filelist_new.f

# 7. 最后添加xram_bbox_wrapper.v
echo "\${XRAM_HOME}/P2_Emu/wrapper/xram_bbox_wrapper.v" >> filelist_new.f

# 8. 自动比对gen-collateral文件夹，添加缺少的文件
echo ""
echo "开始比对gen-collateral文件夹..."

# 获取gen-collateral中所有.sv和.v文件的基本文件名
find gen-collateral -name "*.sv" -o -name "*.v" | sed 's|gen-collateral/||' | sort > /tmp/gen_collateral_files.txt

# 获取当前filelist_new.f中所有文件的基本文件名
grep -o '[^/]*\.sv$\|[^/]*\.v$' filelist_new.f | sort | uniq > /tmp/filelist_current_files.txt

# 找出gen-collateral中有但filelist中没有的文件
missing_files=$(comm -23 /tmp/gen_collateral_files.txt /tmp/filelist_current_files.txt)

if [[ -n "$missing_files" ]]; then
    echo ""
    echo "# 自动添加的缺少文件" >> filelist_new.f
    echo "发现缺少的文件，正在添加..."
    
    while IFS= read -r missing_file; do
        if [[ -n "$missing_file" ]]; then
            echo "添加文件: $missing_file"
            
            # 判断是否是需要使用MODIFIED_PATH的文件
            is_modified_missing=0
            for mf in "${modified_path_files[@]}"; do
                [[ "$missing_file" == "$mf" ]] && is_modified_missing=1 && break
            done
            
            # 根据文件类型选择正确的路径变量
            if [[ $is_modified_missing -eq 1 ]]; then
                echo "\${MODIFIED_PATH}/$missing_file" >> filelist_new.f
            else
                echo "\${SRC_PATH}/$missing_file" >> filelist_new.f
            fi
        fi
    done <<< "$missing_files"
    
    echo "已添加 $(echo "$missing_files" | wc -l) 个缺少的文件"
else
    echo "未发现缺少的文件，所有gen-collateral中的文件都已包含"
fi

# 清理临时文件
rm -f /tmp/gen_collateral_files.txt /tmp/filelist_current_files.txt

# 清理不需要的文件条目（如果存在的话）
echo ""
echo "清理不需要的文件条目..."
excluded_files=("TestDriver.v")

for excluded_file in "${excluded_files[@]}"; do
    if grep -q "${excluded_file}" filelist_new.f; then
        echo "删除条目: ${excluded_file}"
        sed -i "/\/${excluded_file}$/d" filelist_new.f
    fi
done

echo ""
echo "处理完成，新文件生成为 filelist_new.f"
echo "原始备份文件为 gen-collateral/filelist.f.bak" 