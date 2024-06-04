

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


logic [23:0] selected_did;
assign selected_did = aw_seen_before ? dev_tr_req_i.aw.stream_id : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.stream_id :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.stream_id : 0));


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
    else if(counter_dc == 3 && ddtp.iommu_mode.q >= 2 && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1) // ddtlevel 1
        counter_dc <= 0;
    else if((ddtp.iommu_mode.q == 2 || ((counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3) && !riscv_iommu.trans_error)) && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1)
        counter_dc <= counter_dc + 1;

logic ddt_entry_accessed; // when this is high, ddte is accessed

assign ddt_entry_accessed = ((riscv_iommu.ddtp.iommu_mode.q == 4 && counter_non_leaf < 2) || (!selected_did[23:15] && riscv_iommu.ddtp.iommu_mode.q == 3 && !counter_non_leaf));

logic ready_to_capture_ddt_entry_invalid, ddt_entry_invalid_captured;
logic ready_to_capture_ddt_data_corruption, ddt_data_corruption_captured;
logic ready_to_capture_ddte_misconfig_rsrv_bits, ddte_misconfig_rsrv_captured;

assign ready_to_capture_ddt_entry_invalid        = ds_resp_i.r.resp == axi_pkg::RESP_OKAY && ddt_entry_accessed && !ds_resp_i.r.data[0] && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddt_entry_invalid_captured;

assign ready_to_capture_ddt_data_corruption      = !ddt_entry_invalid_captured && !ddte_misconfig_rsrv_captured && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddt_data_corruption_captured;

assign ready_to_capture_ddte_misconfig_rsrv_bits = !ddt_entry_invalid_captured && ds_resp_i.r.data[0] && !ddt_data_corruption_captured && ddt_entry_accessed && ds_resp_i.r.id == 1 && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && dde_rsrv_bits;

logic tc_pdtv_low, tc_pdtv_low_seen, tc_sxl, tc_sxl_seen ;
assign tc_pdtv_low = dc_tc_active && !dc_tc_q.pdtv && !tc_pdtv_low_seen;
assign tc_sxl      = dc_tc_active && dc_tc_q.sxl && !tc_sxl_seen;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        ddt_entry_invalid_captured   <= 0;
        ddt_data_corruption_captured <= 0;
        tc_pdtv_low_seen             <= 0;
        tc_sxl_seen                  <= 0;
    end
    else begin
        if(ds_resp_i.r.last && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1) begin
            ddt_entry_invalid_captured   <= 0;
            ddt_data_corruption_captured <= 0;
            tc_pdtv_low_seen             <= 0;
            tc_sxl_seen                  <= 0;
        end
        else begin
            ddt_entry_invalid_captured    <= ddt_entry_invalid_captured || ready_to_capture_ddt_entry_invalid;
            ddt_data_corruption_captured  <= ddt_data_corruption_captured || ready_to_capture_ddt_data_corruption;
            tc_pdtv_low_seen              <= tc_pdtv_low_seen || tc_pdtv_low;
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

assign dc_fsc_active     = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 3;

rv_iommu::tc_t      dc_tc_q;
rv_iommu::iohgatp_t dc_iohgatp_q;
rv_iommu::dc_ta_t   dc_ta_q;
rv_iommu::fsc_t     dc_fsc_q;

assign dc_tc_q      = dc_tc_active      ? ds_resp_i.r.data : 0;
assign dc_iohgatp_q = dc_iohgatp_active ? ds_resp_i.r.data : 0;
assign dc_ta_q      = dc_ta_active      ? ds_resp_i.r.data : 0;
assign dc_fsc_q     = dc_fsc_active     ? ds_resp_i.r.data : 0;

logic dc_tc_not_valid, dc_tc_not_valid_captured, ready_to_capture_data_corruption, dc_data_corruption_captured;
assign ready_to_capture_data_corruption = (dc_tc_active || counter_dc != 0 ) && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && !dc_data_corruption_captured;
assign dc_tc_not_valid                  = dc_tc_active && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && !dc_tc_q.v && !dc_tc_not_valid_captured;

// Divided the different device context configuration checks
logic iohgatp_unsupported_mode, iohgatp_ppn_not_align, dc_rsrv_bits_high, tc_wrong_bits_high, iosatp_invalid;

assign dc_rsrv_bits_high        = (dc_tc_active && (|dc_tc_q.reserved_1 || |dc_tc_q.reserved_2)) || (dc_ta_active && (|dc_ta_q.reserved_1 || |dc_ta_q.reserved_2));
assign tc_wrong_bits_high       =  dc_tc_q.en_ats || dc_tc_q.en_pri || dc_tc_q.t2gpa || dc_tc_q.prpr || dc_tc_q.sade || dc_tc_q.gade || (dc_tc_active && ((riscv_iommu.fctl.be != dc_tc_q.sbe) || (riscv_iommu.fctl.gxl != dc_tc_q.sxl) || (!dc_tc_q.pdtv && dc_tc_q.dpe)));
assign iohgatp_unsupported_mode = riscv_iommu.fctl.gxl ? (dc_iohgatp_active && dc_iohgatp_q.mode != 0) : (dc_iohgatp_active && dc_iohgatp_q.mode != 0 && dc_iohgatp_q.mode != 8);
assign iohgatp_ppn_not_align    = dc_iohgatp_active && dc_iohgatp_q.mode != 0 && |dc_iohgatp_q.ppn[1:0];

assign iosatp_invalid           = !dc_tc_not_valid_captured && !dc_data_corruption_captured && !dc_misconfig_captured && ((dc_fsc_active && dc_fsc_q.reserved) || dc_fsc_active && ds_resp_i.r.resp == axi_pkg::RESP_OKAY &&  tc_pdtv_low_seen && (tc_sxl_seen ? dc_fsc_q.mode != 0 : !(!dc_fsc_q.mode || dc_fsc_q.mode == 8)));

logic ready_to_capture_dc_misconfig, dc_misconfig_captured, misconfig_checks_wo_pc;

assign misconfig_checks_wo_pc        = (iosatp_invalid && MSITrans != rv_iommu::MSI_DISABLED) || tc_wrong_bits_high || iohgatp_unsupported_mode || iohgatp_ppn_not_align || dc_rsrv_bits_high;

assign ready_to_capture_dc_misconfig = (!dc_with_data_corruption_captured && !dc_with_data_corruption) && !dc_tc_not_valid_captured && ((dc_tc_active && dc_tc_q.v) || counter_dc !=0) && ds_resp_i.r.resp == axi_pkg::RESP_OKAY &&  misconfig_checks_wo_pc;

logic ready_to_capture_pdtv_zero, pdtv_zero_captured; 
assign ready_to_capture_pdtv_zero    = !iosatp_invalid && !dc_misconfig_captured && !dc_tc_not_valid_captured && (!dc_with_data_corruption_captured && !dc_with_data_corruption) && (!InclPC && dc_tc_q.pdtv) && dc_tc_active;

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
assert property (ddt_entry_invalid_captured && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID );

assert_2_ddt_data_corruption: // if resp!=ok then cause must be ddt_data_corruption
assert property (ddt_data_corruption_captured && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::DDT_DATA_CORRUPTION);

assrt_3_ddt_misconfigured_non_leaf: // if reseerved bits of ddte are set high then cause must be ddt_entry_misconfigured 
assert property (ready_to_capture_ddte_misconfig_rsrv_bits && last_beat_cdw |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED);

assrt_4_did_length_wider: // if did length higher bits are set to 1 then cause must be TRANS_TYPE_DISALLOWED
assume property (ar_did_wider || aw_did_wider |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

assrt_5_ddtp_mode_off: // if mode is bare then cause must be ALL_INB_TRANSACTION_DISALLOWED
assume property (riscv_iommu.ddtp.iommu_mode.q == 0 && aw_or_ar_hsk |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::ALL_INB_TRANSACTIONS_DISALLOWED );

generate
for (genvar i = 0; i < riscv::PLEN; i++) begin
assrt_6_ddtp_mode_1_ar: // if mode is bare, then the input address is equal to the physical address
assume property (riscv_iommu.ddtp.iommu_mode.q == 1 && translation_req.ar_hsk |-> `ar_addr[i] == riscv_iommu.spaddr[i]);

assrt_7_ddtp_mode_1_aw: // if mode is bare, then the input address is equal to the physical address
assume property (riscv_iommu.ddtp.iommu_mode.q == 1 && translation_req.aw_hsk |-> `aw_addr[i] == riscv_iommu.spaddr[i]);
end
endgenerate

assrt_8_ddt_data_corruption: // 
assert property (data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.resp != axi_pkg::RESP_OKAY |=> riscv_iommu.cause_code == rv_iommu::DDT_DATA_CORRUPTION); 

// assrt_ddt_level1 is failing
assrt_9_ddt_level1_addr: // on read address
assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 2 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.addr ==  (riscv_iommu.ddtp.ppn + (selected_did[6:0] * 8)));

assrt_10_ddt_level1_len: // on read address
assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 2 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.len == 3);

assrt_11_ddt_level2_len: // on read address
assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 3 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.len == 0);

assrt_12_ddt_level2_addr: // on read address
assert property ($rose(riscv_iommu.ddt_walk) && riscv_iommu.ddtp.iommu_mode.q == 3 && ds_req_o.ar.id == 1 |-> ds_req_o.ar_valid && ds_req_o.ar.addr ==  (riscv_iommu.ddtp.ppn + (selected_did[15:7] * 8)));

assrt_13_ddt_data_corruption:
assert property (dc_data_corruption_captured && last_beat_cdw |->  riscv_iommu.cause_code == rv_iommu::DDT_DATA_CORRUPTION);

assrt_14_dc_tc_not_valid:
assert property (dc_tc_not_valid_captured && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID);

assrt_15_dc_misconfig:
assert property (wo_data_corruption && dc_misconfig_captured && last_beat_cdw |=> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED);

assrt_16_dc_misconfig_wo_pc:
assert property (iosatp_invalid |=> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED );

logic not_ddte;
assign not_ddte = ddtp.iommu_mode.q == 2 || ((counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3));

assrt_17_dc_misconfig_wo_pc:
assert property (riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED && $past(not_ddte) |=> iosatp_invalid || ((dc_misconfig_captured || ready_to_capture_ddte_misconfig_rsrv_bits) && last_beat_cdw));

assrt_18_ddt_walk: // if data is not present, there will be ddt_walk
assert property ($rose(ddtc_miss_q) |=> riscv_iommu.ddt_walk);

assrt_19_ddt_walk: 
assert property (riscv_iommu.ddt_walk |-> $past(ddtc_miss_q));

assrt_20_ddt_walk_off: // if data is present, there will be no ddt_walk
assert property ($rose(ddtc_hit_q) |=> !riscv_iommu.ddt_walk);

assrt_21_pdtv_zero: // if did length higher bits are set to 1 then cause must be TRANS_TYPE_DISALLOWED
assert property (wo_data_corruption && pdtv_zero_captured && last_beat_cdw |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);
//----------------------------- Assertion CDW Ended----------------------------------------

logic wo_data_corruption;
assign wo_data_corruption = !dc_with_data_corruption_captured && !dc_with_data_corruption;

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
cover property (riscv_iommu.trans_error && riscv_iommu.cause_code != 260 ##[1:$] !dc_loaded_wo_error && correct_did && riscv_iommu.cause_code == 260 );

cov_6_checking_cache:
cover property ($rose(ddtc_hit_q) ##[0:$] $rose(ddtc_miss_q));

cov_7_update_not_existing:
cover property (($rose(ddtc_miss_q) ##5 !ddtc_miss_q)[*8]);

cov_8_seq_det_4:
cover property (cache_seq_detector[4] == 1);

cov_9_seq_det_7:
cover property (cache_seq_detector[7] == 1);

cover_10_unique:
cover property ($onehot0(ddtc_hit_n));
//-----------------------------Cover CDW Ended---------------------------------------------

//............................DDTC Cache Started-------------------------------------------------

rv_iommu::dc_base_t dc_q;

always @(posedge clk_i or negedge rst_ni) begin
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
end


logic [$clog2(DDTC_ENTRIES) - 1 : 0] entry_no;
logic [$clog2(DDTC_ENTRIES) : 0] cache_seq_detector [DDTC_ENTRIES - 1 : 0];

logic [DDTC_ENTRIES - 1 : 0] ddtc_hit_n, ddtc_miss_n;
logic ddtc_hit_q, ddtc_miss_q;

logic dc_loaded_wo_error, dc_loaded_wo_error_captured;
logic dc_with_data_corruption, dc_with_data_corruption_captured;

assign dc_loaded_wo_error = iosatp_invalid || ready_to_capture_ddte_misconfig_rsrv_bits || ready_to_capture_ddt_entry_invalid || ready_to_capture_ddt_data_corruption || dc_tc_not_valid_captured || dc_data_corruption_captured || dc_misconfig_captured;
assign dc_with_data_corruption = ds_resp_i.r.id == 1 && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && ds_resp_i.r_valid;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        dc_loaded_wo_error_captured         <= 0;
        dc_with_data_corruption_captured    <= 0;
    end
        
    else if(translation_req.ar_hsk || translation_req.aw_hsk) begin
        dc_loaded_wo_error_captured         <= 0;
        dc_with_data_corruption_captured    <= 0;
    end
        
    else begin
        dc_loaded_wo_error_captured         <= dc_loaded_wo_error_captured || dc_loaded_wo_error;
        dc_with_data_corruption_captured    <= dc_with_data_corruption_captured || dc_with_data_corruption;
    end
        
end

logic correct_did;
assign correct_did = (dev_tr_req_i.ar_valid || dev_tr_req_i.aw_valid) && (riscv_iommu.ddtp.iommu_mode.q == 4 ||(riscv_iommu.ddtp.iommu_mode.q == 2 && |selected_did[23:6] == 0) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |selected_did[23:15] == 0));

generate
for (genvar i  = 0; i < DDTC_ENTRIES; i++ ) begin
assign ddtc_hit_n[i]  = correct_did && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && cache_entry_valid[i] && selected_did == cache_entry[i] && !ddtc_miss_q;
assign ddtc_miss_n[i] = correct_did && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && (selected_did != cache_entry[i] || !cache_entry_valid[i]);
end
endgenerate


always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        ddtc_hit_q     <= 0;
        ddtc_miss_q <= 0;
    end

    else begin
        if(translation_req.aw_hsk || translation_req.ar_hsk) begin
        ddtc_hit_q     <= 0;
        ddtc_miss_q <= 0;
        end
        else begin
        ddtc_hit_q     <= ddtc_hit_q     || (ddtc_hit_n != 0);
        ddtc_miss_q    <= ddtc_miss_q || ddtc_miss_n == 8'hff;
        end
    end
end

logic [23:0] cache_entry [DDTC_ENTRIES - 1 : 0];
logic cache_entry_valid [DDTC_ENTRIES - 1 : 0];

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            cache_entry[i]        <= 0;
            cache_entry_valid[i]  <= 0;
            cache_seq_detector[i] <= 0;   
        end

    else if(ddtc_miss_q && !dc_loaded_wo_error_captured && (translation_req.aw_hsk || translation_req.ar_hsk)) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            if((cache_seq_detector[i] == 0 || cache_seq_detector[i] == DDTC_ENTRIES)) begin
                
                cache_seq_detector[i] <= 1;
                cache_entry[i]        <= selected_did;
                cache_entry_valid[i]  <= 1'b1;

                for (int j = 0; j < DDTC_ENTRIES; j++ )
                    if(!(cache_seq_detector[j] == 0 || cache_seq_detector[j] == DDTC_ENTRIES))
                        cache_seq_detector[j] <= cache_seq_detector[j] + 1;
                
                break;
            end
        end
    end

    else if($rose(ddtc_hit_q)) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            if(ddtc_hit_n[i] == 1 && cache_seq_detector[i] != 1) begin
                
                for (int j = 0; j < DDTC_ENTRIES; j++ ) begin
                    if(ddtc_hit_n[j])
                        cache_seq_detector[j] <= 1;
                    else if((cache_seq_detector[i] == DDTC_ENTRIES) && cache_seq_detector[j] != 0)
                        cache_seq_detector[j] <= cache_seq_detector[j] - 1;
                    else if(cache_seq_detector[j] != 0)
                        cache_seq_detector[j] <= cache_seq_detector[j] + 1;
                end
                break;
            end
        end
    end
end

//............................DDTC Cache Ended-------------------------------------------------

