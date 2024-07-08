

`define ar_addr dev_tr_req_i.ar.addr
`define aw_addr dev_tr_req_i.aw.addr
`define ds_r_channel ds_resp_i.r

logic aw_or_ar_hsk;
assign aw_or_ar_hsk = (translation_req.ar_hsk || translation_req.aw_hsk);

logic ar_did_wider, aw_did_wider;
assign ar_did_wider = ((riscv_iommu.ddtp.iommu_mode.q == 2 && |dev_tr_req_i.ar.stream_id[23:6]) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |dev_tr_req_i.ar.stream_id[23:15])) && translation_req.ar_hsk;

assign aw_did_wider = ((riscv_iommu.ddtp.iommu_mode.q == 2 && |dev_tr_req_i.aw.stream_id[23:6]) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |dev_tr_req_i.aw.stream_id[23:15])) && translation_req.aw_hsk;

logic aw_seen_before;
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        aw_seen_before <= 0;
    else if(aw_seen_before && translation_req.aw_hsk)
        aw_seen_before <= 0;
    else if(dev_tr_req_i.aw_valid && !dev_tr_req_i.ar_valid)
        aw_seen_before <= 1;
end

logic [19:0] selected_pid;
assign selected_pid = aw_seen_before ? dev_tr_req_i.aw.substream_id : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.substream_id :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.substream_id : 0));

logic [23:0] selected_did;
assign selected_did = aw_seen_before ? dev_tr_req_i.aw.stream_id : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.stream_id :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.stream_id : 0));

logic priv_transac;
assign priv_transac = aw_seen_before ? dev_tr_req_i.aw.prot[0] : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.prot[0] :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.prot[0] : 0));

enum logic [1:0] {NONE, UNTRANSLATED_RX, UNTRANSLATED_R, UNTRANSLATED_W} trans_type;
assign trans_type = aw_seen_before ? UNTRANSLATED_W : (dev_tr_req_i.ar_valid ? (dev_tr_req_i.ar.prot[2] ? UNTRANSLATED_RX : UNTRANSLATED_R) : (dev_tr_req_i.aw_valid ? UNTRANSLATED_W : NONE));

logic selected_pv;
assign selected_pv = aw_seen_before ? dev_tr_req_i.aw.ss_id_valid : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.ss_id_valid :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.ss_id_valid : 0));

logic dde_rsrv_bits;
assign dde_rsrv_bits = (|`ds_r_channel.data[9:1] || |`ds_r_channel.data[63:54]);

logic last_beat_cdw;
assign last_beat_cdw = ds_resp_i.r.last && ds_resp_i.r_valid && ds_resp_i.r.id == 1;

//-----------------------------aux code CDW started--------------------------------------

logic [1:0] counter_dc, counter_non_leaf;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || riscv_iommu.trans_error)
        counter_non_leaf <= 0;
    else if(counter_non_leaf == 1 && ddtp.iommu_mode.q == 3 && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl) // ddtlevel 2
        counter_non_leaf <= 0;
    else if(counter_non_leaf == 2 && ddtp.iommu_mode.q == 4 && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl) // ddtlevel 3
        counter_non_leaf <= 0;
    else if(ddtp.iommu_mode.q > 2 && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw)
        counter_non_leaf <= counter_non_leaf + 1;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni )
        counter_dc <= 0;
    else if(aw_or_ar_hsk)
        counter_dc <= 0;
    else if(counter_dc == 3 && !aw_or_ar_hsk)
        counter_dc <= 3;
    else if((ddtp.iommu_mode.q == 2 || ((counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3) && !riscv_iommu.trans_error)) && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddtc_hit_q)
        counter_dc <= counter_dc + 1;

logic ddt_entry_accessed; // when this is high, ddte is accessed

assign ddt_entry_accessed = counter_dc == 0 && ((riscv_iommu.ddtp.iommu_mode.q == 4 && counter_non_leaf < 2) || (!selected_did[23:15] && riscv_iommu.ddtp.iommu_mode.q == 3 && !counter_non_leaf));

logic ready_to_capture_ddt_entry_invalid, ddt_entry_invalid_captured;
logic ready_to_capture_ddt_data_corruption, ddt_data_corruption_captured;
logic ready_to_capture_ddte_misconfig_rsrv_bits, ddte_misconfig_rsrv_captured;

assign ready_to_capture_ddt_entry_invalid        = (!pc_fsc_active && !pc_ta_active) && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && ddt_entry_accessed && !ds_resp_i.r.data[0] && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddt_entry_invalid_captured;

assign ready_to_capture_ddt_data_corruption      = !(pid_wider || ar_did_wider || aw_did_wider) && (!pc_fsc_active && !pc_ta_active) && !ddt_entry_invalid_captured && !ddte_misconfig_rsrv_captured && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddt_data_corruption_captured;
assign ready_to_capture_ddte_misconfig_rsrv_bits = !pdtc_miss_q && !pc_fsc_active && !pc_ta_active && !ddt_entry_invalid_captured && ds_resp_i.r.data[0] && !ddt_data_corruption_captured && ddt_entry_accessed && ds_resp_i.r.id == 1 && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && dde_rsrv_bits;

logic tc_pdtv, tc_pdtv_seen, tc_sxl, tc_sxl_seen ;
assign tc_pdtv = dc_tc_active && dc_tc_q.pdtv && !tc_pdtv_seen;
assign tc_sxl  = dc_tc_active && dc_tc_q.sxl && !tc_sxl_seen;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        ddt_entry_invalid_captured   <= 0;
        ddt_data_corruption_captured <= 0;
        tc_pdtv_seen                 <= 0;
        tc_sxl_seen                  <= 0;
    end
    else begin
        if(ds_resp_i.r.last && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1) begin
            ddt_entry_invalid_captured   <= 0;
            ddt_data_corruption_captured <= 0;
            tc_pdtv_seen                 <= 0;
            tc_sxl_seen                  <= 0;
        end
        else begin
            ddt_entry_invalid_captured    <= ddt_entry_invalid_captured || ready_to_capture_ddt_entry_invalid;
            ddt_data_corruption_captured  <= ddt_data_corruption_captured || ready_to_capture_ddt_data_corruption;
            tc_pdtv_seen                  <= tc_pdtv_seen || tc_pdtv;
            tc_sxl_seen                   <= tc_sxl_seen || tc_sxl;
        end
    end
end

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) 
        ddte_misconfig_rsrv_captured <= 0;
    else begin
        if(last_beat_cdw && data_strcuture.r_hsk_trnsl_compl &&  ((ready_to_capture_ddte_misconfig_rsrv_bits || ddte_misconfig_rsrv_captured) || (riscv_iommu.ddtp.iommu_mode.q == 4 && counter_non_leaf == 2) || (riscv_iommu.ddtp.iommu_mode.q == 3 && counter_non_leaf == 1)))
            ddte_misconfig_rsrv_captured <= 0;
        else
            ddte_misconfig_rsrv_captured <= ddte_misconfig_rsrv_captured || ready_to_capture_ddte_misconfig_rsrv_bits;
    end
end


logic dc_tc_active, dc_iohgatp_active, dc_ta_active, dc_fsc_active;

assign dc_tc_active      = !riscv_iommu.trans_error && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && !counter_dc && (riscv_iommu.ddtp.iommu_mode.q == 2 || (counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3)) ;

assign dc_iohgatp_active = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 1;

assign dc_ta_active      = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 2;

assign dc_fsc_active     = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 3 && !dc_ended_captured;

rv_iommu::tc_t      dc_tc_q;
rv_iommu::iohgatp_t dc_iohgatp_q;
rv_iommu::dc_ta_t   dc_ta_q;
rv_iommu::fsc_t     dc_fsc_q;

assign dc_tc_q      = dc_tc_active      ? ds_resp_i.r.data : 0;
assign dc_iohgatp_q = dc_iohgatp_active ? ds_resp_i.r.data : 0;
assign dc_ta_q      = dc_ta_active      ? ds_resp_i.r.data : 0;
assign dc_fsc_q     = dc_fsc_active     ? ds_resp_i.r.data : 0;

logic dc_tc_not_valid, dc_tc_not_valid_captured, ready_to_capture_data_corruption, dc_data_corruption_captured;
assign ready_to_capture_data_corruption = !pdtc_miss_q && !dc_ended_captured && (dc_tc_active || counter_dc != 0 ) && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && !dc_data_corruption_captured;
assign dc_tc_not_valid                  = dc_tc_active && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && !dc_tc_q.v && !dc_tc_not_valid_captured;

// Divided the different device context configuration checks
logic iohgatp_unsupported_mode, iohgatp_ppn_not_align, dc_rsrv_bits_high, tc_wrong_bits_high, iosatp_invalid;

assign dc_rsrv_bits_high        = (dc_tc_active && (|dc_tc_q.reserved_1 || |dc_tc_q.reserved_2)) || (dc_ta_active && (|dc_ta_q.reserved_1 || |dc_ta_q.reserved_2));
assign tc_wrong_bits_high       =  dc_tc_q.en_ats || dc_tc_q.en_pri || dc_tc_q.t2gpa || dc_tc_q.prpr || dc_tc_q.sade || dc_tc_q.gade || (dc_tc_active && ((riscv_iommu.fctl.be != dc_tc_q.sbe) || (riscv_iommu.fctl.gxl != dc_tc_q.sxl) || (!dc_tc_q.pdtv && dc_tc_q.dpe)));
assign iohgatp_unsupported_mode = riscv_iommu.fctl.gxl ? (dc_iohgatp_active && dc_iohgatp_q.mode != 0) : (dc_iohgatp_active && dc_iohgatp_q.mode != 0 && dc_iohgatp_q.mode != 8);
assign iohgatp_ppn_not_align    = dc_iohgatp_active && dc_iohgatp_q.mode != 0 && |dc_iohgatp_q.ppn[1:0];

assign iosatp_invalid           = !dc_tc_not_valid_captured && !dc_data_corruption_captured && !dc_misconfig_captured && dc_fsc_active && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && (|dc_fsc_q.reserved || (tc_pdtv_seen && (dc_fsc_q.mode inside {[4:15]})) || (!tc_pdtv_seen && (tc_sxl_seen ? dc_fsc_q.mode != 0 : !(!dc_fsc_q.mode || dc_fsc_q.mode == 8))));

logic ready_to_capture_dc_misconfig, dc_misconfig_captured, misconfig_checks;

assign misconfig_checks         = (iosatp_invalid && MSITrans != rv_iommu::MSI_DISABLED) || tc_wrong_bits_high || iohgatp_unsupported_mode || iohgatp_ppn_not_align || dc_rsrv_bits_high;

assign ready_to_capture_dc_misconfig = (!dc_pc_with_data_corruption_captured && !dc_pc_with_data_corruption) && !dc_tc_not_valid_captured && ((dc_tc_active && dc_tc_q.v) || counter_dc !=0) && ds_resp_i.r.resp == axi_pkg::RESP_OKAY &&  misconfig_checks;

logic ready_to_capture_pdtv_zero, pdtv_zero_captured; 
assign ready_to_capture_pdtv_zero    = !dc_tc_not_valid && (!dc_pc_with_data_corruption_captured && !dc_pc_with_data_corruption) && (!InclPC && dc_tc_q.pdtv) && dc_tc_active;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        dc_tc_not_valid_captured       <= 0;
        dc_data_corruption_captured    <= 0;
        dc_misconfig_captured          <= 0;
        pdtv_zero_captured             <= 0;
    end
    else begin
        if(counter_dc == 3 && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw) begin
            dc_tc_not_valid_captured       <= 0;
            dc_data_corruption_captured    <= 0;
            dc_misconfig_captured          <= 0;
            pdtv_zero_captured             <= 0;
        end
        else begin
            dc_tc_not_valid_captured       <= dc_tc_not_valid_captured || dc_tc_not_valid;
            dc_data_corruption_captured    <= dc_data_corruption_captured || ready_to_capture_data_corruption;
            dc_misconfig_captured          <= dc_misconfig_captured || ready_to_capture_dc_misconfig;
            pdtv_zero_captured             <= pdtv_zero_captured    || ready_to_capture_pdtv_zero;
        end
    end
end


//-----------------------------aux code CDW Ended----------------------------------------


//----------------------------- Assertion CDW Started----------------------------------------

assrt_1_ddt_entry_valid_for_level_1: // if ddte.v = 0, then cause must be DDT_ENTRY_INVALID
assert property (ddt_entry_invalid_captured && last_beat_cdw |=> $past(riscv_iommu.trans_error) || riscv_iommu.trans_error);

assrt_2_ddt_entry_valid_for_level_1: // if ddte.v = 0, then cause must be DDT_ENTRY_INVALID
assert property (ddt_entry_invalid_captured && last_beat_cdw |=> $past(riscv_iommu.cause_code) == rv_iommu::DDT_ENTRY_INVALID || riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID );

assrt_3_ddt_data_corruption: // if resp!=ok then cause must be ddt_data_corruption
assert property (ddt_data_corruption_captured && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::DDT_DATA_CORRUPTION);

assrt_4_ddt_misconfigured_non_leaf: // if reseerved bits of ddte are set high then cause must be ddt_entry_misconfigured 
assert property (ready_to_capture_ddte_misconfig_rsrv_bits && last_beat_cdw |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED);

assrt_5_did_length_wider: // if did length higher bits are set to 1 then cause must be TRANS_TYPE_DISALLOWED
assume property (ar_did_wider || aw_did_wider |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

assrt_6_ddtp_mode_off: // if mode is bare then cause must be ALL_INB_TRANSACTION_DISALLOWED
assume property (riscv_iommu.ddtp.iommu_mode.q == 0 && aw_or_ar_hsk |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::ALL_INB_TRANSACTIONS_DISALLOWED );

generate
for (genvar i = 0; i < riscv::PLEN; i++) begin
assrt_7_ddtp_mode_1_ar: // if mode is bare, then the input address is equal to the physical address
assume property (riscv_iommu.ddtp.iommu_mode.q == 1 && translation_req.ar_hsk |-> `ar_addr[i] == riscv_iommu.spaddr[i]);

assrt_8_ddtp_mode_1_aw: // if mode is bare, then the input address is equal to the physical address
assume property (riscv_iommu.ddtp.iommu_mode.q == 1 && translation_req.aw_hsk |-> `aw_addr[i] == riscv_iommu.spaddr[i]);
end
endgenerate


// need to set last 5 bit to 0 as wihotut base dc is 128 bit wide
    // assrt_ddt_level1 is failing
    // assrt_9_ddt_level1_addr: // on read address
    // assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 2 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.addr ==  (riscv_iommu.ddtp.ppn + (selected_did[6:0] * 8)));

    // assrt_10_ddt_level1_len: // on read address
    // assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 2 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.len == 3);

    // assrt_11_ddt_level2_len: // on read address
    // assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 3 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.len == 0);

    // assrt_12_ddt_level2_addr: // on read address
    // assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 3 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.addr ==  (riscv_iommu.ddtp.ppn + (selected_did[15:7] * 8)));

assrt_9_ddt_data_corruption:
assert property (dc_data_corruption_captured && last_beat_cdw |->  riscv_iommu.cause_code == rv_iommu::DDT_DATA_CORRUPTION);

assrt_10_dc_tc_not_valid:
assert property (wo_data_corruption && dc_tc_not_valid_captured && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID);

assrt_11_dc_misconfig:
assert property (wo_data_corruption && dc_misconfig_captured && last_beat_cdw |=> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED);

assrt_12_dc_misconfig_pc:
assert property (iosatp_invalid |=> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED );

assrt_13_2_dc_misconfig_pc:
assert property (iosatp_invalid |=> riscv_iommu.trans_error);

logic not_ddte;
assign not_ddte = ddtp.iommu_mode.q == 2 || ((counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3));

assrt_14_dc_misconfig_wo_pc:
assert property (riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED && $past(not_ddte) |=> iosatp_invalid || ((dc_misconfig_captured || ready_to_capture_ddte_misconfig_rsrv_bits) && last_beat_cdw));

assrt_15_ddt_walk: // if data is not present, there will be ddt_walk
assert property ($rose(ddtc_miss_q) |=> riscv_iommu.ddt_walk);

assrt_16_ddt_walk: 
assert property (riscv_iommu.ddt_walk |-> $past(ddtc_miss_q));

assrt_17_ddt_walk_off: // if data is present, there will be no ddt_walk
assert property ($rose(ddtc_hit_q) |=> !riscv_iommu.ddt_walk);

logic wo_data_corruption;
assign wo_data_corruption = !dc_pc_with_data_corruption_captured && !dc_pc_with_data_corruption;

assrt_18_pdtv_zero: // if did length higher bits are set to 1 then cause must be TRANS_TYPE_DISALLOWED
assert property (wo_data_corruption && pdtv_zero_captured && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

assrt_19_error_and_valid_both_high:
assert property (!(riscv_iommu.trans_error && riscv_iommu.trans_valid));

assrt_20_type_disallow_error:
assert property (ready_to_capt_valid_type_disalow && last_beat_cdw |-> riscv_iommu.trans_error);

assrt_21_type_disallow_error:
assert property (ready_to_capt_valid_type_disalow && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

// assrt_26_type_disallow_error:
// assert property (ready_to_capt_trans_type_disallow && last_beat_cdw |-> riscv_iommu.trans_error);

// assrt_27_type_disallow_cause_code:
// assert property (ready_to_capt_trans_type_disallow && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);
//----------------------------- Assertion CDW Ended----------------------------------------


//-----------------------------Cover CDW Started---------------------------------------------

cov_1_checking_dc:
cover property (counter_dc == 2 && riscv_iommu.ddtp.iommu_mode.q == 4);

cov_2_cause_code_define:
cover property (riscv_iommu.cause_code == 263 && riscv_iommu.i_rv_iommu_translation_wrapper.wrap_cause_code == 260);

cov_3_dc_valid:
cover property (dc_tc_not_valid_captured && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID);

cov_4_dc_misconfig:
cover property (dc_misconfig_captured && last_beat_cdw);

cov_5_error:
cover property (riscv_iommu.trans_error && riscv_iommu.cause_code != 260 ##[1:$] !dc_loaded_with_error && correct_did && riscv_iommu.cause_code == 260 );

cov_6_checking_cache:
cover property ($rose(ddtc_hit_q) ##[0:$] $rose(ddtc_miss_q));

cov_7_update_not_existing:
cover property (($rose(ddtc_miss_q) ##5 !ddtc_miss_q)[*8]);

cov_8_seq_det_4:
cover property (ddtc_seq_detector[4] == 1);

cov_9_seq_det_7:
cover property (ddtc_seq_detector[7] == 1);

// cover_10_unique:
// cover property ($onehot0(ddtc_hit_n));

cover_11_ptw_checker:
cover property (ds_resp_i.r.id == 0 && ds_resp_i.r_valid);

cover_12_error_and_valid_both_high:
cover property (counter_dc != 0 && translation_compl.ar_hsk_trnsl_compl && riscv_iommu.trans_valid);

cover_13_unique_case:
cover property (i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.wrap_error && i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.ptw_error);
//-----------------------------Cover CDW Ended---------------------------------------------



//............................DDTC Cache Started-------------------------------------------------

rv_iommu::dc_base_t dc_q;

always @(posedge clk_i or negedge rst_ni)
        if(!rst_ni)
            dc_q <= 0;

        else if(dc_tc_active)
            dc_q.tc <= dc_tc_q;

        else if(dc_iohgatp_active)
            dc_q.iohgatp <= dc_iohgatp_q;

        else if(dc_ta_active)
            dc_q.ta <= dc_ta_q;

        else if(dc_fsc_active)
            dc_q.fsc <= dc_fsc_q;
        
        else
            dc_q <= dc_q;

logic [$clog2(DDTC_ENTRIES) : 0] ddtc_seq_detector [DDTC_ENTRIES - 1 : 0];

logic [DDTC_ENTRIES - 1 : 0] ddtc_hit_n, ddtc_miss_n;
logic ddtc_hit_q, ddtc_miss_q;

logic dc_loaded_with_error, dc_loaded_with_error_captured;
logic dc_pc_with_data_corruption, dc_pc_with_data_corruption_captured;

assign dc_loaded_with_error = (ar_did_wider || aw_did_wider) || pdtv_zero_captured || iosatp_invalid || ready_to_capture_ddte_misconfig_rsrv_bits || ready_to_capture_ddt_entry_invalid || ready_to_capture_ddt_data_corruption || dc_tc_not_valid_captured || dc_data_corruption_captured || dc_misconfig_captured;
assign dc_pc_with_data_corruption = ds_resp_i.r.id == 1 && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && ds_resp_i.r_valid;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        dc_loaded_with_error_captured         <= 0;
        dc_pc_with_data_corruption_captured   <= 0;
    end
        
    else if(translation_req.ar_hsk || translation_req.aw_hsk) begin
        dc_loaded_with_error_captured         <= 0;
        dc_pc_with_data_corruption_captured   <= 0;
    end
        
    else begin
        dc_loaded_with_error_captured         <= dc_loaded_with_error_captured || dc_loaded_with_error;
        dc_pc_with_data_corruption_captured   <= dc_pc_with_data_corruption_captured || dc_pc_with_data_corruption;
    end
end

logic correct_did;
assign correct_did = (dev_tr_req_i.ar_valid || dev_tr_req_i.aw_valid) && (riscv_iommu.ddtp.iommu_mode.q == 4 ||(riscv_iommu.ddtp.iommu_mode.q == 2 && |selected_did[23:6] == 0) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |selected_did[23:15] == 0));

generate
for (genvar i  = 0; i < DDTC_ENTRIES; i++ ) begin
assign ddtc_hit_n[i]  = correct_did && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && ddtc_entry_valid[i] && selected_did == ddtc_entry[i] && !ddtc_miss_q;
assign ddtc_miss_n[i] = correct_did && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && (selected_did != ddtc_entry[i] || !ddtc_entry_valid[i]);
end
endgenerate


always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        ddtc_hit_q  <= 0;
        ddtc_miss_q <= 0;
    end

    else begin
        if(translation_req.aw_hsk || translation_req.ar_hsk) begin
        ddtc_hit_q  <= 0;
        ddtc_miss_q <= 0;
        end
        else begin
        ddtc_hit_q  <= ddtc_hit_q  || (ddtc_hit_n != 0);
        ddtc_miss_q <= ddtc_miss_q || ddtc_miss_n == 8'hff;
        end
    end
end

logic [23:0] ddtc_entry [DDTC_ENTRIES - 1 : 0];
logic ddtc_entry_valid [DDTC_ENTRIES - 1 : 0];
logic ddtc_pdtv [DDTC_ENTRIES - 1 : 0];
logic [3:0] ddtc_fsc_mode [DDTC_ENTRIES - 1 : 0];
logic ddtc_dpe [DDTC_ENTRIES - 1 : 0];

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            ddtc_entry[i]         <= 0;
            ddtc_entry_valid[i]   <= 0;
            ddtc_seq_detector[i]  <= 0;  
            ddtc_pdtv[i]          <= 0; 
            ddtc_fsc_mode[i]      <= 0;
            ddtc_dpe[i]           <= 0;
        end
    else if(ddtc_miss_q && !dc_loaded_with_error_captured && (translation_req.aw_hsk || translation_req.ar_hsk)) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            if((ddtc_seq_detector[i] == 0 || ddtc_seq_detector[i] == DDTC_ENTRIES)) begin
                
                ddtc_seq_detector[i]  <= 1;
                ddtc_entry[i]         <= selected_did;
                ddtc_entry_valid[i]   <= 1'b1;
                ddtc_pdtv[i]          <= dc_q.tc.pdtv;
                ddtc_fsc_mode[i]      <= dc_q.fsc.mode;
                ddtc_dpe[i]           <= dc_q.tc.dpe;

                for (int j = 0; j < DDTC_ENTRIES; j++ )
                    if(!(ddtc_seq_detector[j] == 0 || ddtc_seq_detector[j] == DDTC_ENTRIES))
                        ddtc_seq_detector[j] <= ddtc_seq_detector[j] + 1;
                
                break;
            end
        end
    end

    else if($rose(ddtc_hit_q)) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            if(ddtc_hit_n[i] == 1 && ddtc_seq_detector[i] != 1) begin
                
                for (int j = 0; j < DDTC_ENTRIES; j++ ) begin
                    if(ddtc_hit_n[j])
                        ddtc_seq_detector[j] <= 1;
                    else if((ddtc_seq_detector[i] == DDTC_ENTRIES) && ddtc_seq_detector[j] != 0)
                        ddtc_seq_detector[j] <= ddtc_seq_detector[j] - 1;
                    else if(ddtc_seq_detector[j] != 0)
                        ddtc_seq_detector[j] <= ddtc_seq_detector[j] + 1;
                end
                break;
            end
        end
    end
end

// ............................DDTC Cache Ended-------------------------------------------------


//............................PDTC Cache Started-------------------------------------------------

logic [$clog2(PDTC_ENTRIES) : 0] pdtc_seq_detector [PDTC_ENTRIES - 1 : 0];

logic [PDTC_ENTRIES - 1 : 0] pdtc_hit_n, pdtc_miss_n;
logic pdtc_hit_q, pdtc_miss_q;

logic correct_pid;
assign correct_pid = (dev_tr_req_i.ar_valid || dev_tr_req_i.aw_valid) && !pid_wider;

generate
for (genvar i  = 0; i < PDTC_ENTRIES; i++ ) begin
assign pdtc_hit_n[i]  = (correct_pid || ((ddtc_miss_q && dc_q.tc.dpe) || (ddtc_hit_q && ddtc_dpe[i]))) && correct_did && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && pdtc_entry_valid[i] && selected_did == pdtc_did[i] && selected_pid == pdtc_pid[i] && !pdtc_miss_q;
assign pdtc_miss_n[i] = (ddtc_hit_q) || (ddtc_miss_q && !riscv_iommu.ddt_walk && dc_ended_captured) && !dc_loaded_with_error_captured && !((!selected_pv && !dc_q.tc.dpe) || !dc_q.tc.pdtv || !dc_q.fsc.mode) && (correct_pid || ((ddtc_miss_q && !selected_pv && dc_q.tc.dpe && !dc_q.tc.pdtv) || (ddtc_hit_q && ddtc_dpe[i]))) && correct_did && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && (selected_did != pdtc_did[i] || selected_pid != pdtc_pid[i] || !pdtc_entry_valid[i]);
end
endgenerate

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        pdtc_hit_q  <= 0;
        pdtc_miss_q <= 0;
    end

    else begin
        if(translation_req.aw_hsk || translation_req.ar_hsk) begin
        pdtc_hit_q  <= 0;
        pdtc_miss_q <= 0;
        end
        else begin
        pdtc_hit_q  <= pdtc_hit_q  || pdtc_hit_n != 0;
        pdtc_miss_q <= pdtc_miss_q || pdtc_miss_n == 8'hff;
        end
    end
end

logic [19:0] pdtc_pid [PDTC_ENTRIES - 1 : 0];
logic [23:0] pdtc_did [DDTC_ENTRIES - 1 : 0];
logic pdtc_sum [DDTC_ENTRIES -1 : 0];
logic [3:0] pdtc_fsc_mode [DDTC_ENTRIES -1 : 0];

logic pdtc_entry_valid [PDTC_ENTRIES - 1 : 0];

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        for (int i = 0; i < PDTC_ENTRIES; i++ ) begin
            pdtc_pid[i]           <= 0;
            pdtc_did[i]           <= 0;
            pdtc_entry_valid[i]   <= 0;
            pdtc_seq_detector[i]  <= 0;
            pdtc_sum[i]           <= 0;
            pdtc_fsc_mode[i]      <= 0;
        end 

    else if(pdtc_miss_q && counter_pc == 1 && !pc_loaded_with_error_captured && (translation_req.aw_hsk || translation_req.ar_hsk)) begin

        for (int i = 0; i < PDTC_ENTRIES; i++ ) begin
            if((pdtc_seq_detector[i] == 0 || pdtc_seq_detector[i] == PDTC_ENTRIES)) begin
                
                pdtc_seq_detector[i]  <= 1;
                pdtc_did[i]           <= selected_did;
                pdtc_pid[i]           <= selected_pid;
                pdtc_sum[i]           <= pc_q.ta.sum;
                pdtc_fsc_mode[i]      <= pc_q.fsc.mode;
                pdtc_entry_valid[i]   <= 1'b1;

                for (int j = 0; j < PDTC_ENTRIES; j++ )
                    if(!(pdtc_seq_detector[j] == 0 || pdtc_seq_detector[j] == PDTC_ENTRIES))
                        pdtc_seq_detector[j] <= pdtc_seq_detector[j] + 1;
                
                break;
            end
        end
    end

    else if($rose(pdtc_hit_q)) begin

        for (int i = 0; i < PDTC_ENTRIES; i++ ) begin
            if(pdtc_hit_n[i] == 1 && pdtc_seq_detector[i] != 1) begin
                
                for (int j = 0; j < PDTC_ENTRIES; j++ ) begin
                    if(pdtc_hit_n[j])
                        pdtc_seq_detector[j] <= 1;
                    else if((pdtc_seq_detector[i] == PDTC_ENTRIES) && pdtc_seq_detector[j] != 0)
                        pdtc_seq_detector[j] <= pdtc_seq_detector[j] - 1;
                    else if(pdtc_seq_detector[j] != 0)
                        pdtc_seq_detector[j] <= pdtc_seq_detector[j] + 1;
                end
                break;
            end
        end
    end
end

// logic must_pdt_walk;
// assign must_pdt_walk = pdtc_miss_q && ();

assrt_22_pdt_walk: // if data is not present, there will be pdt_walk
assert property ($rose(pdtc_miss_q) |-> riscv_iommu.pdt_walk);

assrt_23_pdt_walk: 
assert property (riscv_iommu.pdt_walk |-> (pdtc_miss_q));

assrt_24_pdt_walk_off: // if data is present, there will be no pdt_walk
assert property ($rose(pdtc_hit_q) |=> !riscv_iommu.pdt_walk);
// ............................PDTC Cache Ended-------------------------------------------------


// ----------------------------Process to tranlsate an IOVA checks started----------------------

// logic trans_type_disallow_bare;
// Translated (!b3 && b2) and  PCIe (b3)
// assign ready_to_capt_trans_type_disallow = riscv_iommu.ddtp.iommu_mode.q == 1 && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && (trans_type[3] || (trans_type[3:2] == 2'b01)); 

logic ready_to_capt_valid_type_disalow, valid_pv_pdtv_zero_captured;
assign ready_to_capt_valid_type_disalow = !dc_loaded_with_error && !dc_loaded_with_error_captured && wo_data_corruption && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && (pid_wider || (selected_pv && ((ddtc_miss_q && dc_ended_captured && (!dc_q.tc.pdtv)) || (ddtc_hit_q && !ddtc_pdtv[hit_index]))));

logic pid_wider_when_cache_miss, pid_wider_when_cache_hit;
assign pid_wider_when_cache_miss = ddtc_miss_q && dc_ended_captured && dc_q.tc.pdtv && ((dc_q.fsc.mode == 1 && |selected_pid[19:8]) || ((dc_q.fsc.mode == 2 && |selected_pid[19:17])));
assign pid_wider_when_cache_hit = ddtc_hit_q && ddtc_pdtv[hit_index] && ((ddtc_fsc_mode[hit_index] == 1 && |selected_pid[19:8])  || (ddtc_fsc_mode[hit_index] == 2 && |selected_pid[19:17]));

logic pid_wider;
assign pid_wider = selected_pv && (pid_wider_when_cache_miss || pid_wider_when_cache_hit);

logic [$clog2(DDTC_ENTRIES) : 0] hit_index;
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        hit_index <= 0;
    else begin
        for (int i  = 0; i < DDTC_ENTRIES; i++ )
            if(ddtc_hit_n[i] == 1) begin
               hit_index <= i;
               break;
            end
    end
end

//----------------------------Process to tranlsate an IOVA checks Ended----------------------



//----------------------------Process directory checks started--------------------------------

rv_iommu::pc_t pc_q;
always @(posedge clk_i or negedge rst_ni)
        if(!rst_ni)
            pc_q <= 0;

        else if(pc_ta_active)
            pc_q.ta <= pc_ta_q;

        else if(pc_fsc_active)
            pc_q.fsc <= pc_fsc_q;
        
        else
            pc_q <= pc_q;

logic ready_to_capt_dc_ended, dc_ended_captured;
assign ready_to_capt_dc_ended = (counter_dc == 3) && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw && !dc_ended_captured;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni)
        dc_ended_captured <= 0;
    else if(aw_or_ar_hsk)
        dc_ended_captured <= 0;
    else
        dc_ended_captured <= dc_ended_captured || ready_to_capt_dc_ended;


logic [1:0] counter_non_leaf_pc;
logic counter_pc;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni)
        counter_non_leaf_pc <= 0;

    else if(counter_non_leaf_pc == 1 && ((dc_q.fsc.mode == 2 && ddtc_miss_q) || (ddtc_fsc_mode[hit_index] == 2 && ddtc_hit_q)) && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl) // ddtlevel 2
        counter_non_leaf_pc <= 0;
    
    else if(counter_non_leaf_pc == 2 && ((dc_q.fsc.mode == 3 && ddtc_miss_q) || (ddtc_fsc_mode[hit_index] == 3 && ddtc_hit_q)) && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl) // ddtlevel 3
        counter_non_leaf_pc <= 0;
    
    else if(((ddtc_fsc_mode[hit_index] > 1 && ddtc_hit_q) || (dc_ended_captured && dc_q.fsc.mode > 1)) && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw)
        counter_non_leaf_pc <= counter_non_leaf_pc + 1;

logic dc_miss, dc_hit;
assign dc_miss = ddtc_miss_q && (dc_q.fsc.mode == 1 || ((counter_non_leaf_pc == 2 && dc_q.fsc.mode == 3) || (counter_non_leaf_pc == 1 && dc_q.fsc.mode == 2)));
assign dc_hit  = (ddtc_pdtv[hit_index] || ddtc_dpe[hit_index]) && ddtc_hit_q  && (ddtc_fsc_mode[hit_index] == 1 || ((counter_non_leaf_pc == 2 && ddtc_fsc_mode[hit_index] == 3) || (counter_non_leaf_pc == 1 && ddtc_fsc_mode[hit_index] == 2)));

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni)
        counter_pc <= 0;
    else if(aw_or_ar_hsk)
        counter_pc <= 0;
    else if(counter_pc == 1 && !aw_or_ar_hsk)
        counter_pc <= 1;
    else if((dc_ended_captured || (ddtc_hit_q && ddtc_pdtv[hit_index])) && (dc_hit || dc_miss) && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1)
        counter_pc <= 1;

logic pc_ta_active, pc_fsc_active;

assign pc_ta_active  = (counter_pc == 0 && (dc_hit || (dc_ended_captured && dc_miss))) && ds_resp_i.r.id == 1 && ds_resp_i.r_valid;
assign pc_fsc_active = counter_pc == 1 && ds_resp_i.r.id == 1 && ds_resp_i.r_valid;

rv_iommu::pc_ta_t pc_ta_q;
rv_iommu::fsc_t   pc_fsc_q;

assign pc_ta_q  = pc_ta_active  ? ds_resp_i.r.data : 0;
assign pc_fsc_q = pc_fsc_active ? ds_resp_i.r.data : 0;

logic ready_to_capt_pc_not_valid, pc_not_valid_captured;
assign ready_to_capt_pc_not_valid = pc_ta_active && !pc_ta_q.v && !pc_not_valid_captured;

logic ready_to_capt_pc_misconfig, pc_misconfig_captured;
assign ready_to_capt_pc_misconfig = !pid_wider && !ready_to_capt_pc_not_valid && !pc_not_valid_captured && ((pc_ta_active && (|pc_ta_q.reserved_1 || |pc_ta_q.reserved_2)) || (pc_fsc_active && (!(pc_fsc_q.mode == 0 || pc_fsc_q.mode == 8) || |pc_fsc_q.reserved))) && !pc_misconfig_captured;

logic ready_to_capt_pdte_not_valid, pdte_not_valid_captured;
assign ready_to_capt_pdte_not_valid = !ds_resp_i.r.data[0] && pdte_accessed;

logic ready_to_capt_pdte_misconfig, pdte_misconfig_captured;
assign ready_to_capt_pdte_misconfig = pdte_accessed && !ready_to_capt_pdte_not_valid && (|ds_resp_i.r.data[9:1] || |ds_resp_i.r.data[63:54]);

logic pdte_accessed; // when this is high, pdte is accessed
assign pdte_accessed = dc_ended_captured && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !dc_loaded_with_error && counter_pc == 0 && ((dc_q.fsc.mode == 3 && counter_non_leaf_pc < 2) || (!selected_pid[19:17] && dc_q.fsc.mode == 2 && !counter_non_leaf_pc));

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni) begin
        pdte_misconfig_captured   <= 0;
        pdte_not_valid_captured   <= 0;
    end
    else if(ds_resp_i.r.last && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1) begin
        pdte_misconfig_captured   <= 0;        
        pdte_not_valid_captured   <= 0;  
    end
    else begin
        pdte_misconfig_captured    <= pdte_misconfig_captured || ready_to_capt_pdte_misconfig;
        pdte_not_valid_captured    <= pdte_not_valid_captured || ready_to_capt_pdte_not_valid;
    end

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni) begin
        pc_not_valid_captured <= 0;
        pc_misconfig_captured <= 0;
    end
    else if(aw_or_ar_hsk) begin
        pc_not_valid_captured <= 0;
        pc_misconfig_captured <= 0;        
    end
    else begin
        pc_not_valid_captured <= pc_not_valid_captured || ready_to_capt_pc_not_valid;
        pc_misconfig_captured <= pc_misconfig_captured || ready_to_capt_pc_misconfig;
    end


logic pc_loaded_with_error, pc_loaded_with_error_captured;
assign pc_loaded_with_error = ready_to_capt_pdte_not_valid || ready_to_capt_pdte_misconfig || ready_to_capt_pc_not_valid || ready_to_capt_pc_misconfig;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni)
        pc_loaded_with_error_captured   <= 0;
        
    else if(translation_req.ar_hsk || translation_req.aw_hsk) 
        pc_loaded_with_error_captured   <= 0;
        
    else 
        pc_loaded_with_error_captured   <= pc_loaded_with_error_captured || pc_loaded_with_error;

assrt_25_pdte_not_valid:
assert property (ready_to_capt_pdte_not_valid |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_INVALID);

assrt_26_pdte_misconfig:
assert property (ready_to_capt_pdte_misconfig |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_MISCONFIGURED);

assrt_27_pc_not_valid:
assert property (pc_not_valid_captured && wo_data_corruption && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_INVALID);

assrt_28_pc_misconfig:
assert property (pc_misconfig_captured && wo_data_corruption && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_MISCONFIGURED);

//----------------------------Process directory checks Ended--------------------------------


//----------------------------PTW Checks Started-----------------------------------------------
logic pte_active;
assign pte_active = (ds_resp_i.r.id == 0 && ds_resp_i.r_valid);

riscv::pte_t pte;
assign pte = pte_active ? ds_resp_i.r.data : 0;

logic ready_to_capt_pf_excep, pf_excep_captured;
assign ready_to_capt_pf_excep = !ready_to_capt_data_corrup_ptw && pte_active && (!pte.v || (!pte.r && pte.w) || |pte.reserved);

logic ready_to_capt_accessed_low, accessed_low_captured;
assign ready_to_capt_accessed_low = !ready_to_capt_misaligned_super_page && pte_active && (pte.r || pte.x) && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && !pte.a && !accessed_low_captured;

logic ready_to_capt_dirty_low, dirty_low_captured;
assign ready_to_capt_dirty_low = !ready_to_capt_misaligned_super_page && pte_active && (pte.r || pte.x) && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && pte.a && !pte.d && aw_seen_before && !dirty_low_captured;

logic ready_to_capt_data_corrup_ptw, ptw_data_corrup_captured;
assign ready_to_capt_data_corrup_ptw = pte_active && ds_resp_i.r.id == 0 && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && ds_resp_i.r_valid;

logic ready_to_capt_misaligned_super_page;
assign ready_to_capt_misaligned_super_page = (!ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && (pte.r || pte.x)) && (current_level == 2 ? |pte[27 : 10] : (current_level == 1 ? |pte[18 : 10] : 0));

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        ptw_data_corrup_captured    <= 0;
        pf_excep_captured           <= 0;
        accessed_low_captured       <= 0;
        dirty_low_captured          <= 0;
    end
    else if(aw_or_ar_hsk) begin
        pf_excep_captured           <= 0;
        ptw_data_corrup_captured    <= 0;
        accessed_low_captured       <= 0;
        dirty_low_captured          <= 0;
    end
    else begin
        pf_excep_captured           <= pf_excep_captured || ready_to_capt_pf_excep;
        ptw_data_corrup_captured    <= ptw_data_corrup_captured || ready_to_capt_data_corrup_ptw;
        accessed_low_captured       <= ready_to_capt_accessed_low || accessed_low_captured;
        dirty_low_captured          <= dirty_low_captured || ready_to_capt_dirty_low;
    end
end

logic [2:0] counter_PTE;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        counter_PTE <= 0;
    else if(aw_or_ar_hsk)
        counter_PTE <= 0;
    else if(!ready_to_capt_data_corrup_ptw && !ready_to_capt_pf_excep && pte_active && (pte.r || pte.x))
        counter_PTE <= counter_PTE + 1;
    // else if(pte_active && ds_req_o.r_ready && !ready_to_capt_data_corrup_ptw && !ready_to_capt_pf_excep)
    //     counter_PTE <= counter_PTE + 1;
end

int current_level;
logic decr_crnt_lvl;
assign decr_crnt_lvl = pte_active && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && !pte.r && !pte.x && data_strcuture.r_hsk_trnsl_compl;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        current_level <= 2;
    else if(aw_or_ar_hsk)
        current_level <= 2;
    else
        current_level <= current_level - decr_crnt_lvl;
end


logic pdtv_enable, pdtc_stage_1_enable, stage1_enable;

assign pdtv_enable = (ddtc_miss_q && dc_q.tc.pdtv) || (ddtc_hit_q && ddtc_pdtv[hit_index]);

assign pdtc_stage_1_enable = pdtv_enable && ((pdtc_miss_q && pc_q.fsc.mode != 0) || (pdtc_hit_q && pdtc_fsc_mode[hit_index] != 0));

assign stage1_enable = pdtc_stage_1_enable || (!pdtv_enable && ((ddtc_hit_q && ddtc_fsc_mode[hit_index] != 0) || (ddtc_miss_q && dc_q.fsc.mode != 0)));

logic user_mode_trans, store_nd_wo_w_permis, x_1_sum_0;
assign user_mode_trans      = !priv_transac && !pte.u && stage1_enable;
assign store_nd_wo_w_permis = stage1_enable && pte_active && !pte.w && trans_type == UNTRANSLATED_W;
assign rx_nd_wo_x_permis    = stage1_enable && trans_type == UNTRANSLATED_RX && pte_active && !pte.x;

logic ta_sum_0;
assign ta_sum_0   = pdtc_miss_q ? !pc_q.ta.sum : (pdtc_hit_q && !pdtc_sum[hit_index]);
assign x_1_sum_0  = priv_transac && pte.u && (ta_sum_0 || pte.x);

logic ready_to_capt_s_and_u_mode_fault;
assign ready_to_capt_s_and_u_mode_fault = pte_active && (rx_nd_wo_x_permis || store_nd_wo_w_permis || user_mode_trans || x_1_sum_0);


logic ready_to_capt_super_page;
assign ready_to_capt_super_page = !ready_to_capt_s_and_u_mode_fault && pte_active && pte.r && !ready_to_capt_misaligned_super_page && !ready_to_capt_accessed_low && !ready_to_capt_dirty_low && current_level > 0 && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && (pte.r || pte.x);

//----------------------------PTW Checks Ended-----------------------------------------------


//----------------------------Assertions PTW Started-----------------------------------------

assrt_30_ptw_pg_fault_trans_error:
assert property ($rose(pf_excep_captured) |-> riscv_iommu.trans_error);

assrt_31_ptw_corrupt:
assert property ($rose(ptw_data_corrup_captured) |-> riscv_iommu.cause_code == rv_iommu::PT_DATA_CORRUPTION);

assrt_32_ptw_corrupt_trans_error:
assert property ($rose(ptw_data_corrup_captured) |-> riscv_iommu.trans_error);

assrt_33_ptw_accessed_bit:
assert property ($rose(accessed_low_captured) |-> riscv_iommu.trans_error);

assrt_34_ptw_accessed_bit:
assert property ($rose(accessed_low_captured) |-> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT || riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_35_ptw_dirty_bit:
assert property ($rose(dirty_low_captured) |-> riscv_iommu.trans_error);

assrt_36_ptw_dirty_bit:
assert property ($rose(dirty_low_captured) |-> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

assrt_37_level_less_than_0_error:
assert property (current_level < 0 && $changed(current_level) |-> riscv_iommu.trans_error);

assrt_38_level_less_than_0_cause_code:
assert property (current_level < 0 && aw_seen_before && $changed(current_level) |-> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

assrt_39_level_less_than_0_cause_code:
assert property (current_level < 0 && !aw_seen_before && $changed(current_level) |-> riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_40_misaligned_error:
assert property (ready_to_capt_misaligned_super_page |=> riscv_iommu.trans_error);

assrt_41_misaligned_cause_code:
assert property (ready_to_capt_misaligned_super_page && aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

assrt_42_misaligned_cause_code:
assert property (ready_to_capt_misaligned_super_page && !aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_43_data_corruption_error:
assert property (ready_to_capt_data_corrup_ptw |=> riscv_iommu.trans_error);

assrt_43_data_corruption_cause_code:
assert property (ready_to_capt_data_corrup_ptw |=> riscv_iommu.cause_code == rv_iommu::PT_DATA_CORRUPTION);

assrt_44_super_page_valid:
assert property (ready_to_capt_super_page |=> riscv_iommu.trans_valid);

assrt_45_super_page:
assert property (ready_to_capt_super_page |=> riscv_iommu.is_superpage);

assrt_46_sum_o_error:
assert property (ready_to_capt_s_and_u_mode_fault |=> riscv_iommu.trans_error);

assrt_47_sum_o_cause_code:
assert property (ready_to_capt_s_and_u_mode_fault && !aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_48_sum_o_cause_code:
assert property (ready_to_capt_s_and_u_mode_fault && aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::STORE_GUEST_PAGE_FAULT);
//----------------------------Assertions PTW Ended-----------------------------------------