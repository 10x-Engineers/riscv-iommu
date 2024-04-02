global env
clear -all

set lab_path          $env(FPV_PATH)
set design_top        $env(DUT_TOP)

analyze -sv09 -f $lab_path/script/files.f               

elaborate  -top $design_top -disable_auto_bbox -create_related_covers {precondition witness}

clock clk_i
reset ~rst_ni

get_design_info

set_engine_mode auto

set_proofgrid_manager on

prove -bg -all