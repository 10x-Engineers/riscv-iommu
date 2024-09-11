#----------------------------------------
# JasperGold Version Info
# tool      : JasperGold 2019.06
# platform  : Linux 3.10.0-1160.118.1.el7.x86_64
# version   : 2019.06 FCS 64 bits
# build date: 2019.06.29 18:06:18 PDT
#----------------------------------------
# started Mon Sep 02 06:11:55 EDT 2024
# hostname  : localhost.localdomain
# pid       : 9504
# arguments : '-label' 'session_0' '-console' 'localhost.localdomain:32978' '-style' 'windows' '-data' 'AQAAADx/////AAAAAAAAA3oBAAAAEABMAE0AUgBFAE0ATwBWAEU=' '-proj' '/home/hayat/Desktop/riscv-iommu/formal/jgproject/sessionLogs/session_0' '-init' '-hidden' '/home/hayat/Desktop/riscv-iommu/formal/jgproject/.tmp/.initCmds.tcl' '/home/hayat/Desktop/riscv-iommu/formal/script/jg.tcl'
global env
clear -all

set lab_path          $env(FPV_PATH)
set design_top        $env(DUT_TOP)

analyze -sv09 -f $lab_path/script/files.f

analyze -sv09 $lab_path/bind/iommu_bind.sv \
                        $lab_path/sva/iommu_sva.sv                       

elaborate  -top $design_top -disable_auto_bbox -create_related_covers {precondition witness}

check_cov -init -type all -model all

clock clk_i
reset ~rst_ni

get_design_info

set_engine_mode auto

set_proofgrid_manager on

stopat  {dbg_if_ctl ddtp.iommu_mode.q fctl}

# stopat  {dbg_if_ctl ddtp.iommu_mode.q fctl flush_*}

set_visualize_preload_signal_list /home/hayat/Desktop/riscv-iommu/formal/waveform/tr_logic_wrapper.sig

set_visualize_show_default_signals off

prove -bg -all
