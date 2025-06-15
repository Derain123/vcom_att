#!/bin/csh -f

    setenv HPE_HOME /home/tools/HPE_24_12_00_d103
    setenv VCOM_HOME $HPE_HOME
    setenv VDBG_HOME $HPE_HOME
    setenv VSYN_HOME $HPE_HOME
    setenv VVAC_HOME $HPE_HOME
    setenv XRAM_HOME $HPE_HOME/public/xram
    setenv DBGIP_HOME $HPE_HOME/share/pnr/dbg_ip
    setenv VIVADO_PATH /home/tools/vivado/Vivado/2022.2
    setenv PATH $VIVADO_PATH/bin:$PATH
    setenv PATH $VIVADO_PATH/gnu/microblaze/lin/bin:$PATH
    source /home/tools/HPE_24_12_00_d103/setup.csh
    setenv PATH $HPE_HOME/bin:$PATH
    setenv PATH $HPE_HOME/tools/xwave/bin:$PATH
    setenv RLM_LICENSE 5053@192.168.99.15
    setenv LM_LICENSE_FILE /home/tools/vivado/license.lic

    # 自动获取当前脚本所在目录和名称
    set script_dir = `dirname $0`
    set script_dir = `cd $script_dir && pwd`
    set script_name = `basename $script_dir`

    setenv CASE_NAME $script_name
    setenv CASE_PATH $script_dir
    setenv SRC_PATH $CASE_PATH/gen-collateral
    setenv MODIFIED_PATH $CASE_PATH/modified_v
    setenv XRAM_PATH $CASE_PATH/xaxi4_slave_emb
    setenv XAXI_RTL_HOME /home/youdean
