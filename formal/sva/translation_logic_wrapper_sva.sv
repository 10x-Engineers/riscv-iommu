`define ar_addr dev_tr_req_i.ar.addr
`define aw_addr dev_tr_req_i.aw.addr
`define ds_r_channel ds_resp_i.r


logic aw_or_ar_hsk, aw_or_ar_hsk_q, stage2_enable_q;
assign aw_or_ar_hsk = (translation_req.ar_hsk || translation_req.aw_hsk);

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni) begin
        aw_or_ar_hsk_q <= 0;
        stage2_enable_q  <= 0;
    end
    else begin
        aw_or_ar_hsk_q  <= aw_or_ar_hsk;
        stage2_enable_q <= stage2_enable;
    end

logic ar_did_wider, aw_did_wider;
assign ar_did_wider = ((riscv_iommu.ddtp.iommu_mode.q == 2 && |dev_tr_req_i.ar.stream_id[23:6]) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |dev_tr_req_i.ar.stream_id[23:15])) && translation_req.ar_hsk;

assign aw_did_wider = ((riscv_iommu.ddtp.iommu_mode.q == 2 && |dev_tr_req_i.aw.stream_id[23:6]) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |dev_tr_req_i.aw.stream_id[23:15])) && translation_req.aw_hsk;


// if aw and ar channel both valid are high at a same time then priority will be given to ar 
// but if aw valid asserted before ar valid then aw request will be sent to iommu
logic aw_seen_before;
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        aw_seen_before <= 0;
    else if(aw_seen_before && translation_req.aw_hsk)
        aw_seen_before <= 0;
    else if(dev_tr_req_i.aw_valid && !dev_tr_req_i.ar_valid)
        aw_seen_before <= 1;
end

logic [riscv::VLEN - 1 : 0] selected_addr;
assign selected_addr = aw_seen_before ? dev_tr_req_i.aw.addr : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.addr :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.addr : 0));


// dpe value individually from cache or from memory
logic dpe_indivi;
assign dpe_indivi = (ddtc_miss && dc_loaded_with_trans_ppn_q && dc_q.tc.dpe) || (ddtc_hit && symb_dc.tc.dpe);

// If DC.tc.DPE is 1 and no valid process_id is given by the device, default value of zero is used
logic pid_when_dpe_high;
assign pid_when_dpe_high = dpe_indivi && !(aw_seen_before ? dev_tr_req_i.aw.ss_id_valid : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.ss_id_valid :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.ss_id_valid : 0)));

logic [19:0] selected_pid;
assign selected_pid = pid_when_dpe_high ? '0 : aw_seen_before ? dev_tr_req_i.aw.substream_id : (dev_tr_req_i.ar_valid ? dev_tr_req_i.ar.substream_id :(dev_tr_req_i.aw_valid ? dev_tr_req_i.aw.substream_id : 0));

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
logic reset_cntr_non_leaf, freeze_cntr_non_leaf, incr_cnt;

assign reset_cntr_non_leaf  = ((counter_non_leaf == 1 && ddtp.iommu_mode.q == 3) || (counter_non_leaf == 2 && ddtp.iommu_mode.q == 4)) && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl;
assign freeze_cntr_non_leaf = (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3) || (counter_non_leaf == 2 && ddtp.iommu_mode.q == 4);
assign incr_cnt = ddtp.iommu_mode.q > 2 && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk || reset_cntr_non_leaf)
        counter_non_leaf <= 0;
    else if(freeze_cntr_non_leaf)
        counter_non_leaf <= counter_non_leaf;
    else if(incr_cnt)
        counter_non_leaf <= counter_non_leaf + 1;

/* 
counter_dc = 0 ----. dc.tc
counter_dc = 1 ----. dc.iohgatp
counter_dc = 2 ----. dc.ta
counter_dc = 3 ----. dc.fsc
This implementation is for base-format where the DC is 32 bytes.
*/
always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk)
        counter_dc <= 0;
    else if(counter_dc == 3)
        counter_dc <= 3;
    else if((ddtp.iommu_mode.q == 2 || ((counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3))) && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddtc_hit)
        counter_dc <= counter_dc + 1;

logic ddt_entry_accessed; // when this is high, ddte is accessed

assign ddt_entry_accessed = ds_resp_i.r.resp == axi_pkg::RESP_OKAY && counter_dc == 0 && ((riscv_iommu.ddtp.iommu_mode.q == 4 && counter_non_leaf < 2) || (!selected_did[23:15] && riscv_iommu.ddtp.iommu_mode.q == 3 && !counter_non_leaf)) && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 ;

logic ready_to_capture_ddt_entry_invalid, ddt_entry_invalid_captured;
logic ready_to_capture_ddt_data_corruption, ddt_data_corruption_captured;
logic ready_to_capture_ddte_misconfig_rsrv_bits, ddte_misconfig_rsrv_captured;

assign ready_to_capture_ddt_entry_invalid        = ddt_entry_accessed && !ds_resp_i.r.data[0] && !ddt_entry_invalid_captured;
assign ready_to_capture_ddt_data_corruption      = !(pid_wider || ar_did_wider || aw_did_wider) && !ddt_entry_invalid_captured && !ddte_misconfig_rsrv_captured && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !ddt_data_corruption_captured;
assign ready_to_capture_ddte_misconfig_rsrv_bits = !ddt_entry_invalid_captured && ds_resp_i.r.data[0] && !ddt_data_corruption_captured && ddt_entry_accessed && dde_rsrv_bits;

logic tc_pdtv, tc_pdtv_seen, tc_sxl, tc_sxl_seen ;
assign tc_pdtv = dc_tc_active && dc_tc_n.pdtv && !tc_pdtv_seen;
assign tc_sxl  = dc_tc_active && dc_tc_n.sxl && !tc_sxl_seen;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk) begin
        ddt_entry_invalid_captured   <= 0;
        ddt_data_corruption_captured <= 0;
        tc_pdtv_seen                 <= 0;
        tc_sxl_seen                  <= 0;
    end
    else begin
        ddt_entry_invalid_captured    <= ddt_entry_invalid_captured   || ready_to_capture_ddt_entry_invalid;
        ddt_data_corruption_captured  <= ddt_data_corruption_captured || ready_to_capture_ddt_data_corruption;
        tc_pdtv_seen                  <= tc_pdtv_seen || tc_pdtv;
        tc_sxl_seen                   <= tc_sxl_seen  || tc_sxl;
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


// this tell us that which part of device context is currently loading from memory
logic dc_tc_active, dc_iohgatp_active, dc_ta_active, dc_fsc_active;
assign dc_tc_active      = !ddtc_hit && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 0 && (riscv_iommu.ddtp.iommu_mode.q == 2 || (counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3)) ;
assign dc_iohgatp_active = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 1;
assign dc_ta_active      = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 2;
assign dc_fsc_active     = ds_resp_i.r.id == 1 && ds_resp_i.r_valid && counter_dc == 3 && !dc_loaded_wo_trans_ppn_q;

rv_iommu::tc_t      dc_tc_n;
rv_iommu::iohgatp_t dc_iohgatp_n;
rv_iommu::dc_ta_t   dc_ta_n;
rv_iommu::fsc_t     dc_fsc_n;

assign dc_tc_n      = dc_tc_active      ? ds_resp_i.r.data : 0;
assign dc_iohgatp_n = dc_iohgatp_active ? ds_resp_i.r.data : 0;
assign dc_ta_n      = dc_ta_active      ? ds_resp_i.r.data : 0;
assign dc_fsc_n     = dc_fsc_active     ? ds_resp_i.r.data : 0;

logic dc_tc_not_valid, dc_tc_not_valid_captured_q, ready_to_capture_data_corruption, dc_data_corruption_captured_q;
assign ready_to_capture_data_corruption = !pdtc_miss_q && !dc_loaded_with_trans_ppn_q && (dc_tc_active || counter_dc != 0 ) && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && !dc_data_corruption_captured_q;
assign dc_tc_not_valid                  = dc_tc_active && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && !dc_tc_n.v && !dc_tc_not_valid_captured_q;

// Divided the different device context configuration checks
logic iohgatp_unsupported_mode, iohgatp_ppn_not_align, dc_rsrv_bits_high, tc_wrong_bits_high, iosatp_invalid;

assign dc_rsrv_bits_high        = (dc_tc_active && (|dc_tc_n.reserved_1 || |dc_tc_n.reserved_2)) || (dc_ta_active && (|dc_ta_n.reserved_1 || |dc_ta_n.reserved_2));
assign tc_wrong_bits_high       =  dc_tc_n.en_ats || dc_tc_n.en_pri || dc_tc_n.t2gpa || dc_tc_n.prpr || dc_tc_n.sade || dc_tc_n.gade || (dc_tc_active && ((riscv_iommu.fctl.be != dc_tc_n.sbe) || (riscv_iommu.fctl.gxl != dc_tc_n.sxl) || (!dc_tc_n.pdtv && dc_tc_n.dpe)));
assign iohgatp_unsupported_mode = riscv_iommu.fctl.gxl ? (dc_iohgatp_active && dc_iohgatp_n.mode != 0) : (dc_iohgatp_active && dc_iohgatp_n.mode != 0 && dc_iohgatp_n.mode != 8);
assign iohgatp_ppn_not_align    = dc_iohgatp_active && dc_iohgatp_n.mode != 0 && |dc_iohgatp_n.ppn[1:0];

assign iosatp_invalid           = dc_fsc_active && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && (|dc_fsc_n.reserved || (tc_pdtv_seen && (dc_fsc_n.mode inside {[4:15]})) || (!tc_pdtv_seen && (tc_sxl_seen ? dc_fsc_n.mode != 0 : !(!dc_fsc_n.mode || dc_fsc_n.mode == 8)))) && !ready_to_capture_pdtv_zero && !dc_tc_not_valid_captured_q && !dc_data_corruption_captured_q && !dc_misconfig_captured_q;

logic ready_to_capture_dc_misconfig, dc_misconfig_captured_q, misconfig_checks;

assign misconfig_checks         = (iosatp_invalid && MSITrans != rv_iommu::MSI_DISABLED) || tc_wrong_bits_high || iohgatp_unsupported_mode || iohgatp_ppn_not_align || dc_rsrv_bits_high;

assign ready_to_capture_dc_misconfig = (!dc_pc_with_data_corruption_captured_q && !dc_pc_with_data_corruption) && !dc_tc_not_valid_captured_q && ((dc_tc_active && dc_tc_n.v) || counter_dc !=0) && ds_resp_i.r.resp == axi_pkg::RESP_OKAY &&  misconfig_checks;

logic ready_to_capture_pdtv_zero, pdtv_zero_captured_q; 
assign ready_to_capture_pdtv_zero    = !dc_tc_not_valid && (!dc_pc_with_data_corruption_captured_q && !dc_pc_with_data_corruption) && (!InclPC && dc_tc_n.pdtv) && dc_tc_active;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        dc_tc_not_valid_captured_q       <= 0;
        dc_data_corruption_captured_q    <= 0;
        dc_misconfig_captured_q          <= 0;
        pdtv_zero_captured_q             <= 0;
    end
    else begin
        if(counter_dc == 3 && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw) begin
            dc_tc_not_valid_captured_q       <= 0;
            dc_data_corruption_captured_q    <= 0;
            dc_misconfig_captured_q          <= 0;
            pdtv_zero_captured_q             <= 0;
        end
        else begin
            dc_tc_not_valid_captured_q       <= dc_tc_not_valid_captured_q || dc_tc_not_valid;
            dc_data_corruption_captured_q    <= dc_data_corruption_captured_q || ready_to_capture_data_corruption;
            dc_misconfig_captured_q          <= dc_misconfig_captured_q || ready_to_capture_dc_misconfig;
            pdtv_zero_captured_q             <= pdtv_zero_captured_q    || ready_to_capture_pdtv_zero;
        end
    end
end

logic correct_did;
assign correct_did = (dev_tr_req_i.ar_valid || dev_tr_req_i.aw_valid) && (riscv_iommu.ddtp.iommu_mode.q == 4 ||(riscv_iommu.ddtp.iommu_mode.q == 2 && |selected_did[23:6] == 0) || (riscv_iommu.ddtp.iommu_mode.q == 3 && |selected_did[23:15] == 0));

logic req_enable_q; // this will make the signal same like in trans_wrapper.req_trans_i
// assign req_enable_q = !aw_or_ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid);

logic flush_ddtc;
assign flush_ddtc = !riscv_iommu.flush_pv && ((riscv_iommu.flush_ddtc && !riscv_iommu.flush_dv) || (riscv_iommu.flush_ddtc && riscv_iommu.flush_dv && riscv_iommu.flush_did == selected_did));

logic dc_loaded_with_error, dc_loaded_with_error_q;
logic dc_pc_with_data_corruption, dc_pc_with_data_corruption_captured_q;

// didn't included ready_to_capt_valid_type_disalow because dc_loaded_with_error only make sure
// that dc can be store in cache but if ready_to_capt_valid_type_disalow is true, still we can store the dc in ddtc cache
assign dc_loaded_with_error = (ar_did_wider || aw_did_wider) || pdtv_zero_captured_q || iosatp_invalid || ready_to_capture_ddte_misconfig_rsrv_bits || ready_to_capture_ddt_entry_invalid || ready_to_capture_ddt_data_corruption || dc_tc_not_valid_captured_q || dc_data_corruption_captured_q || dc_misconfig_captured_q;
assign dc_pc_with_data_corruption = ds_resp_i.r.id == 1 && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && ds_resp_i.r_valid;
logic valid_type_disalow_captured_q, su_visor_not_allowed_captured_q;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni || aw_or_ar_hsk) begin
        dc_loaded_with_error_q                  <= 0;
        dc_pc_with_data_corruption_captured_q   <= 0;
        valid_type_disalow_captured_q           <= 0;
        pc_loaded_with_error_captured_q         <= 0;
        // su_visor_not_allowed_captured_q         <= 0;
        req_enable_q                            <= 0;
    end
        
    else begin
        dc_loaded_with_error_q                  <= dc_loaded_with_error_q || dc_loaded_with_error;
        dc_pc_with_data_corruption_captured_q   <= dc_pc_with_data_corruption_captured_q || dc_pc_with_data_corruption;
        valid_type_disalow_captured_q           <= valid_type_disalow_captured_q || ready_to_capt_valid_type_disalow;
        pc_loaded_with_error_captured_q         <= pc_loaded_with_error_captured_q || pc_loaded_with_error;
        // su_visor_not_allowed_captured_q         <= su_visor_not_allowed_captured_q || su_visor_not_allowed;
        req_enable_q                            <= !aw_or_ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid);
    end
end

rv_iommu::dc_base_t dc_q;
always @(posedge clk_i or negedge rst_ni)
        if(!rst_ni)
            dc_q <= 0;
        else if(dc_tc_active)
            dc_q.tc <= dc_tc_n;
        else if(dc_iohgatp_active)
            dc_q.iohgatp <= dc_iohgatp_n;
        else if(dc_ta_active)
            dc_q.ta <= dc_ta_n;
        else if(dc_fsc_active)
            dc_q.fsc <= dc_fsc_n;
        else
            dc_q <= dc_q;

//-----------------------------aux code CDW Ended----------------------------------------



//............................DDTC Cache Started-------------------------------------------------





// ............................DDTC Cache Ended-------------------------------------------------


//-----------------------------DDTC new method started--------------------------------------------------

rv_iommu::dc_base_t symb_dc;
logic [23:0] sym_did;

assmp_1_dc_stable:
assume property ($stable(symb_dc));

assmp_2_did_stable:
assume property ($stable(sym_did));

generate
    for (genvar i = 0; i < DDTC_ENTRIES ; i++)
        assmp3_only_symb_did_can_hit:
        assume property (ddtc_valid_q[i] && $rose(req_enable_q) && selected_did != sym_did |-> selected_did != ddtc_did_q[i]);
endgenerate

assmp_4_track_one_dc:
assume property (dc_loaded_with_trans_ppn_q && selected_did == sym_did && ddtc_miss |-> (symb_dc == dc_q));

typedef logic [$clog2(DDTC_ENTRIES) : 0] ddtc_seq [DDTC_ENTRIES - 1 : 0];
ddtc_seq ddtc_seq_detector_n;
ddtc_seq ddtc_seq_detector_q;

typedef logic [23:0] did_entry [DDTC_ENTRIES - 1 : 0];
did_entry ddtc_did_n;
did_entry ddtc_did_q;

typedef logic ddtc_valid [DDTC_ENTRIES - 1 : 0];
ddtc_valid ddtc_valid_n;
ddtc_valid ddtc_valid_q;


logic [DDTC_ENTRIES - 1 : 0] ddtc_hit_n, ddtc_miss_n;
logic ddtc_hit, ddtc_miss;

generate
for (genvar i  = 0; i < DDTC_ENTRIES; i++ ) begin
assign ddtc_hit_n[i]  = correct_did && req_enable_q && ddtc_valid_q[i] && selected_did == ddtc_did_q[i];
assign ddtc_miss_n[i] = correct_did && req_enable_q  && (selected_did != ddtc_did_q[i] || !ddtc_valid_q[i]);
end
endgenerate


always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk) begin
        ddtc_hit  <= 0;
        ddtc_miss <= 0;
    end
    else begin
        ddtc_hit  <= ddtc_hit  || ddtc_hit_n != 0;
        ddtc_miss <= ddtc_miss || (ddtc_miss_n == 'hff && !ddtc_hit);
    end

logic update_ddtc;
assign update_ddtc = dc_loaded_with_trans_ppn_q && aw_or_ar_hsk;

function automatic void update_dc(logic [23:0] selected_did, ref ddtc_seq ddtc_seq_detector_q, ddtc_seq_detector_n, ref did_entry ddtc_did_n, ref ddtc_valid ddtc_valid_n);
for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
    if((ddtc_seq_detector_q[i] == 0 || ddtc_seq_detector_q[i] == DDTC_ENTRIES)) begin
        ddtc_seq_detector_n[i]  = 1;
        ddtc_did_n[i]           = selected_did;
        ddtc_valid_n[i]         = 1'b1;
        for (int j = 0; j < DDTC_ENTRIES; j++ )
            if(!(ddtc_seq_detector_q[j] == 0 || ddtc_seq_detector_q[j] == DDTC_ENTRIES))
                ddtc_seq_detector_n[j] = ddtc_seq_detector_n[j] + 1;
        break;
    end
end
endfunction

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            ddtc_did_q[i]           <= 0;
            ddtc_valid_q[i]         <= 0;
            ddtc_seq_detector_q[i]  <= 0;  
        end
    end
    else
        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            ddtc_did_q[i]           <= ddtc_did_n[i];
            ddtc_valid_q[i]         <= ddtc_valid_n[i];
            ddtc_seq_detector_q[i]  <= ddtc_seq_detector_n[i];  
        end
end

always_comb begin

    for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
        ddtc_did_n[i]         = ddtc_did_q[i];
        ddtc_valid_n[i]       = ddtc_valid_q[i];
        ddtc_seq_detector_n[i]  = ddtc_seq_detector_q[i];  
    end
/* 
If DV is 0, then the inval_ddt invalidates all ddt and PDT entries for all devices
riscv_iommu.flush_pv ---->> This is used to difference between IODIR.INVAL_DDT and IODIR.INVAL_PDT
*/
    if(riscv_iommu.flush_ddtc && !riscv_iommu.flush_dv && !riscv_iommu.flush_pv) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            ddtc_seq_detector_n[i]  = 0;
            ddtc_did_n[i]           = 0;
            ddtc_valid_n[i]         = 0;
        end
    end

// If DV is 1, then the inval_ddt invalidates cached leaf-level all associated DDT entries
    else if(riscv_iommu.flush_ddtc && riscv_iommu.flush_dv && !riscv_iommu.flush_pv) begin
        
        if(update_ddtc)
            update_dc(selected_did, ddtc_seq_detector_q, ddtc_seq_detector_n, ddtc_did_n, ddtc_valid_n);

            for (int j = 0; j < DDTC_ENTRIES; j++)
                if(ddtc_did_q[j] == riscv_iommu.flush_did && ddtc_valid_q[j]) begin

                    for (int i = 0; i < DDTC_ENTRIES; i++ )
                        if(ddtc_seq_detector_q[j] > ddtc_seq_detector_q[i])
                            ddtc_seq_detector_n[i]  = ddtc_seq_detector_q[i] - 1;

                    ddtc_seq_detector_n[j]  = 0;
                    ddtc_did_n[j]           = 0;
                    ddtc_valid_n[j]         = 0;
                    break;
                end
    end

    else if(update_ddtc)
        update_dc(selected_did, ddtc_seq_detector_q, ddtc_seq_detector_n, ddtc_did_n, ddtc_valid_n);

    else if($rose(ddtc_hit)) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            if(ddtc_hit_n[i] == 1 && ddtc_seq_detector_q[i] != 1) begin
                
                for (int j = 0; j < DDTC_ENTRIES; j++ ) begin
                    if(ddtc_hit_n[j])
                        ddtc_seq_detector_n[j] = 1;
                    else if((ddtc_seq_detector_q[i] == DDTC_ENTRIES) && ddtc_seq_detector_q[j] != 0)
                        ddtc_seq_detector_n[j] = ddtc_seq_detector_q[j] - 1;
                    else if(ddtc_seq_detector_q[j] != 0)
                        ddtc_seq_detector_n[j] = ddtc_seq_detector_q[j] + 1;
                end
                break;
            end
        end
    end
end




//-----------------------------DDTC new method ended--------------------------------------------------


//............................PDTC Cache Started-------------------------------------------------

logic [$clog2(PDTC_ENTRIES) : 0] pdtc_seq_detector_n [PDTC_ENTRIES - 1 : 0];
logic [$clog2(PDTC_ENTRIES) : 0] pdtc_seq_detector_sorted [PDTC_ENTRIES - 1 : 0];
logic [$clog2(PDTC_ENTRIES) : 0] pdtc_sff, pdtc_saf, pdtc_temp, pdtc_consec_big; // small before flush, small after flush, consectuve big

always_comb begin
    // initialize with 0
    pdtc_sff        = 0;
    pdtc_saf        = 0;
    pdtc_consec_big = 0;
    pdtc_temp       = 0;

    for (int i = 0; i < PDTC_ENTRIES; i++) begin
        pdtc_seq_detector_n[i] = 0;
        pdtc_seq_detector_sorted[i] = 0;
    end

    if(riscv_iommu.flush_ddtc && riscv_iommu.flush_dv && !riscv_iommu.flush_pv) begin
       
    //    pdtc_sff = pdtc_seq_detector[0];

        for (int i = 0; i < PDTC_ENTRIES; i++) begin
        
            pdtc_seq_detector_n[i] = pdtc_seq_detector[i];

        // Step 1: Flush wherever requires
            if(pdtc_did[i] == riscv_iommu.flush_did && pdtc_entry_valid[i]) begin
                pdtc_seq_detector_n[i] = 0;

                // Step 2: Take small from flush(sff)
                if(pdtc_sff == 0)
                    pdtc_sff = pdtc_seq_detector[i];
                else if(pdtc_seq_detector[i] < pdtc_sff)
                    pdtc_sff = pdtc_seq_detector[i];
            end

        // Step 3: Sort the sequences after flush
            pdtc_seq_detector_sorted[i] = pdtc_seq_detector_n[i];
        end

        for (int i = 0; i < PDTC_ENTRIES; i++)
            for (int j = 0; j < PDTC_ENTRIES; j++) begin
                 if(pdtc_seq_detector_sorted[i] < pdtc_seq_detector_sorted[j]) begin
                    pdtc_temp = pdtc_seq_detector_sorted[i];
                    pdtc_seq_detector_sorted[i] = pdtc_seq_detector_sorted[j];
                    pdtc_seq_detector_sorted[j] = pdtc_temp;
                end
            end

        // Step 4: Take small after flush(saf)
        // pdtc_saf = pdtc_seq_detector_sorted[0];
        for(int i = 0; i < PDTC_ENTRIES; i++)
          if(pdtc_saf == 0)
            pdtc_saf = pdtc_seq_detector_sorted[i];
          else if(pdtc_seq_detector_sorted[i] < pdtc_saf)
            pdtc_saf = pdtc_seq_detector_sorted[i];

        // Step 5: Take consecutive_big
        pdtc_consec_big = pdtc_sff;
        for(int i = 0; i < PDTC_ENTRIES; i++)
            if(pdtc_seq_detector_sorted[i] == (pdtc_consec_big + 1))
                pdtc_consec_big = pdtc_seq_detector_sorted[i];
    end

    else if(riscv_iommu.flush_pdtc && riscv_iommu.flush_pv) begin
    //    pdtc_sff = pdtc_seq_detector[0];

        for (int i = 0; i < PDTC_ENTRIES; i++) begin
        
            pdtc_seq_detector_n[i] = pdtc_seq_detector[i];

        // Step 1: Flush wherever requires
            if(pdtc_did[i] == riscv_iommu.flush_did && pdtc_pid[i] == riscv_iommu.flush_pid && pdtc_entry_valid[i]) begin
                pdtc_seq_detector_n[i] = 0;

                // Step 2: Take small from flush(sff)
                if(pdtc_sff == 0)
                    pdtc_sff = pdtc_seq_detector[i];
                else if(pdtc_seq_detector[i] < pdtc_sff)
                    pdtc_sff = pdtc_seq_detector[i];
            end

        // Step 3: Sort the sequences after flush
            pdtc_seq_detector_sorted[i] = pdtc_seq_detector_n[i];
        end

        for (int i = 0; i < PDTC_ENTRIES; i++)
            for (int j = 0; j < PDTC_ENTRIES; j++) begin
                 if(pdtc_seq_detector_sorted[i] < pdtc_seq_detector_sorted[j]) begin
                    pdtc_temp = pdtc_seq_detector_sorted[i];
                    pdtc_seq_detector_sorted[i] = pdtc_seq_detector_sorted[j];
                    pdtc_seq_detector_sorted[j] = pdtc_temp;
                end
            end

        // Step 4: Take small after flush(saf)
        // pdtc_saf = pdtc_seq_detector_sorted[0];
        for(int i = 0; i < PDTC_ENTRIES; i++)
          if(pdtc_saf == 0)
            pdtc_saf = pdtc_seq_detector_sorted[i];
          else if(pdtc_seq_detector_sorted[i] < pdtc_saf)
            pdtc_saf = pdtc_seq_detector_sorted[i];

        // Step 5: Take consecutive_big
        pdtc_consec_big = pdtc_sff;
        for(int i = 0; i < PDTC_ENTRIES; i++)
            if(pdtc_seq_detector_sorted[i] == (pdtc_consec_big + 1))
                pdtc_consec_big = pdtc_seq_detector_sorted[i];
    end

end


logic [$clog2(PDTC_ENTRIES) : 0] pdtc_seq_detector [PDTC_ENTRIES - 1 : 0];

logic [PDTC_ENTRIES - 1 : 0] pdtc_hit_n, pdtc_miss_n;
logic pdtc_hit_q, pdtc_miss_q;

logic correct_pid;
assign correct_pid = (dev_tr_req_i.ar_valid || dev_tr_req_i.aw_valid) && !pid_wider;

logic [PDTC_ENTRIES - 1 : 0] match_pdtc;
logic ddtc_completed, dpe_high;
assign ddtc_completed = (ddtc_hit || (ddtc_miss && dc_loaded_with_trans_ppn_q)) && !dc_loaded_with_error_q;

/* When PDTV is 1, the DPE bit may set to 1 to enable the use of 0 as the default value of process_id for 
   translating requests without a valid process_id. */
assign dpe_high       = !selected_pv && ((ddtc_miss && dc_q.tc.pdtv && dc_q.tc.dpe) || (ddtc_hit && symb_dc.tc.pdtv && symb_dc.tc.dpe));

generate
for (genvar i  = 0; i < PDTC_ENTRIES; i++ ) begin
assign match_pdtc[i]  = pdtc_entry_valid[i] && selected_did == pdtc_did[i] && ((dpe_high && pdtc_pid[i] == 0) || selected_pid == pdtc_pid[i]);

assign pdtc_hit_n[i]  = (correct_pid || dpe_high) && correct_did && req_enable_q && match_pdtc[i] && !pdtc_miss_q;
assign pdtc_miss_n[i] = ddtc_completed && !((!selected_pv && !dc_q.tc.dpe) || !dc_q.tc.pdtv || !dc_q.fsc.mode) && (correct_pid || dpe_high) && correct_did && req_enable_q && !match_pdtc[i];
end
endgenerate

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk) begin
        pdtc_hit_q  <= 0;
        pdtc_miss_q <= 0;
    end
    else begin
        pdtc_hit_q  <= pdtc_hit_q  || pdtc_hit_n != 0;
        pdtc_miss_q <= pdtc_miss_q || pdtc_miss_n == 8'hff;
    end


logic [19:0] pdtc_pid [PDTC_ENTRIES - 1 : 0];
logic [23:0] pdtc_did [PDTC_ENTRIES - 1 : 0];
logic pdtc_sum [PDTC_ENTRIES - 1 : 0];
logic [3:0] pdtc_fsc_mode [PDTC_ENTRIES - 1 : 0];
logic pdtc_ens [PDTC_ENTRIES - 1 : 0];
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
            pdtc_ens[i]           <= 0;
        end 

// If DV is 0, then the inval_ddt invalidates all ddt and PDT entries for all devices
    else if(riscv_iommu.flush_ddtc && !riscv_iommu.flush_dv && !riscv_iommu.flush_pv) begin
        for (int i = 0; i < PDTC_ENTRIES; i++) begin
            pdtc_seq_detector[i]  <= 0;
            pdtc_did[i]           <= 0;
            pdtc_pid[i]           <= 0;
            pdtc_sum[i]           <= 0;
            pdtc_fsc_mode[i]      <= 0;
            pdtc_entry_valid[i]   <= 0;
            pdtc_ens[i]           <= 0;
        end
    end

// If DV is 1, then the inval_ddt invalidates cached leaf-level all associated PDT entries
    else if(riscv_iommu.flush_ddtc && riscv_iommu.flush_dv && !riscv_iommu.flush_pv) begin

        for(int i = 0; i < PDTC_ENTRIES; i++) begin
            
            if(pdtc_sff == 1) begin
                if(pdtc_seq_detector_n[i] <= pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - 1;
                else if(pdtc_seq_detector_n[i] > pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - pdtc_sff;
                else 
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i];
            end

            else if(pdtc_sff != 0) begin
                if(pdtc_seq_detector_n[i] <= pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - 1;
                else if(pdtc_seq_detector_n[i] > pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - pdtc_saf;
                else 
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i];
            end
        end

        for (int j = 0; j < PDTC_ENTRIES; j++)
            if(pdtc_did[j] == riscv_iommu.flush_did && pdtc_entry_valid[j]) begin
                pdtc_did[j]           <= 0;
                pdtc_pid[j]           <= 0;
                pdtc_sum[j]           <= 0;
                pdtc_fsc_mode[j]      <= 0;
                pdtc_entry_valid[j]   <= 0;
                pdtc_ens[j]           <= 0;
            end
    end

    else if(riscv_iommu.flush_pdtc && riscv_iommu.flush_pv) begin
        
        for(int i = 0; i < PDTC_ENTRIES; i++) begin
            if(pdtc_sff == 1) begin
                if(pdtc_seq_detector_n[i] <= pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - 1;
                else if(pdtc_seq_detector_n[i] > pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - pdtc_sff;
                else 
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i];
            end

            else if(pdtc_sff != 0) begin
                if(pdtc_seq_detector_n[i] <= pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - 1;
                else if(pdtc_seq_detector_n[i] > pdtc_consec_big && pdtc_seq_detector_n[i] > pdtc_sff)
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i] - pdtc_saf;
                else 
                    pdtc_seq_detector[i] <= pdtc_seq_detector_n[i];
            end
        end

        for (int j = 0; j < PDTC_ENTRIES; j++)
            if(pdtc_did[j] == riscv_iommu.flush_did && pdtc_pid[j] == riscv_iommu.flush_pid && pdtc_entry_valid[j]) begin
                pdtc_did[j]           <= 0;
                pdtc_pid[j]           <= 0;
                pdtc_sum[j]           <= 0;
                pdtc_fsc_mode[j]      <= 0;
                pdtc_entry_valid[j]   <= 0;
                pdtc_ens[j]           <= 0;
            end     
    end

    else if(pdtc_miss_q && counter_pc == 1 && wo_data_corruption && !pc_loaded_with_error_captured_q && (translation_req.aw_hsk || translation_req.ar_hsk)) begin

        for (int i = 0; i < PDTC_ENTRIES; i++ ) begin
            if((pdtc_seq_detector[i] == 0 || pdtc_seq_detector[i] == PDTC_ENTRIES)) begin
                
                pdtc_seq_detector[i]  <= 1;
                pdtc_did[i]           <= selected_did;
                pdtc_pid[i]           <= selected_pid;
                pdtc_sum[i]           <= pc_q.ta.sum;
                pdtc_fsc_mode[i]      <= pc_q.fsc.mode;
                pdtc_entry_valid[i]   <= 1'b1;
                pdtc_ens[i]           <= pc_q.ta.ens;

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

// ............................PDTC Cache Ended-------------------------------------------------

//............................IOTLB Started-------------------------------------------------
logic pte_1s_global;

always @(posedge clk_i or negedge rst_ni)
        if(!rst_ni || aw_or_ar_hsk)
            pte_1s_global <= 0;

        else if(trans_1s_in_progress && leaf_pte)
            pte_1s_global <= pte.g;
        
        else
            pte_1s_global <= pte_1s_global;


logic [$clog2(IOTLB_ENTRIES) : 0] IOTLB_seq_detector [IOTLB_ENTRIES - 1 : 0];

logic [IOTLB_ENTRIES - 1 : 0] IOTLB_hit_n, IOTLB_miss_n;
logic IOTLB_hit_q, IOTLB_miss_q;

// logic dc_loaded_with_error, dc_loaded_with_error_q;
// logic dc_pc_with_data_corruption, dc_pc_with_data_corruption_captured_q;

// assign dc_loaded_with_error = (ar_did_wider || aw_did_wider) || pdtv_zero_captured_q || iosatp_invalid || ready_to_capture_ddte_misconfig_rsrv_bits || ready_to_capture_ddt_entry_invalid || ready_to_capture_ddt_data_corruption || dc_tc_not_valid_captured_q || dc_data_corruption_captured_q || dc_misconfig_captured_q;
// assign dc_pc_with_data_corruption = ds_resp_i.r.id == 1 && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && ds_resp_i.r_valid;

// always @(posedge clk_i or negedge rst_ni) begin
//     if(!rst_ni) begin
//         dc_loaded_with_error_q         <= 0;
//         dc_pc_with_data_corruption_captured_q   <= 0;
//     end
        
//     else if(translation_req.ar_hsk || translation_req.aw_hsk) begin
//         dc_loaded_with_error_q         <= 0;
//         dc_pc_with_data_corruption_captured_q   <= 0;
//     end
        
//     else begin
//         dc_loaded_with_error_q         <= dc_loaded_with_error_q || dc_loaded_with_error;
//         dc_pc_with_data_corruption_captured_q   <= dc_pc_with_data_corruption_captured_q || dc_pc_with_data_corruption;
//     end
// end

logic [IOTLB_ENTRIES - 1 : 0] match_tlb_tag, match_stages, match_gscid, match_pscid, match_addrs_1s, match_addrs_2s;
logic [10:0] vpn2;
logic [8:0] vpn1, vpn0;

assign vpn2 = selected_addr[40:30];
assign vpn1 = selected_addr[29:21];
assign vpn0 = selected_addr[20:12];

logic pc_dc_loaded;
assign pc_dc_loaded = wo_data_corruption && !valid_type_disalow_captured_q && !su_visor_not_allowed_captured_q && !ready_to_capt_valid_type_disalow && (!pc_loaded_with_error_captured_q && (pc_loaded_q || pdtc_hit_q || !pdtv_enable || !InclPC)) && (!dc_loaded_with_error_q && (ddtc_hit || dc_loaded_with_trans_ppn_q));

generate
for (genvar i  = 0; i < IOTLB_ENTRIES; i++ ) begin
assign match_stages[i]   = stage1_enable == IOTLB_en_1s[i] && stage2_enable == IOTLB_en_2s[i];
assign match_gscid[i]    = (stage2_enable && IOTLB_gscid[i] == gscid) || !stage2_enable;
assign match_pscid[i]    = (stage1_enable && (IOTLB_pscid[i] == pscid || IOTLB_pte_global[i])) || !stage1_enable;
assign match_addrs_1s[i] = stage1_enable && (IOTLB_is_1G_1s[i] || (IOTLB_VPN[i][17:9] == vpn1 && (IOTLB_is_2m_1s[i] || IOTLB_VPN[i][8:0] == vpn0)));
assign match_addrs_2s[i] = !stage1_enable && stage2_enable && (IOTLB_is_1G_2s[i] || (IOTLB_VPN[i][17:9] == vpn1 && (IOTLB_is_2m_2s[i] || IOTLB_VPN[i][8:0] == vpn0)));

assign match_tlb_tag[i]  = (match_addrs_1s[i] || match_addrs_2s[i]) && IOTLB_VPN_valid[i] && (stage1_enable ? IOTLB_VPN[i][26:18] == vpn2[8:0] : IOTLB_VPN[i][28:18] == vpn2) && match_stages[i] && match_gscid[i] && match_pscid[i];

assign IOTLB_hit_n[i]   = pc_dc_loaded && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && match_tlb_tag[i];
assign IOTLB_miss_n[i]  = (stage1_enable || stage2_enable) && pc_dc_loaded && !translation_req.aw_hsk && !translation_req.ar_hsk && (dev_tr_req_i.aw_valid || dev_tr_req_i.ar_valid) && !match_tlb_tag[i];
end
endgenerate


always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        IOTLB_hit_q  <= 0;
        IOTLB_miss_q <= 0;
    end

    else begin
        if(translation_req.aw_hsk || translation_req.ar_hsk) begin
        IOTLB_hit_q  <= 0;
        IOTLB_miss_q <= 0;
        end
        else begin
        IOTLB_hit_q  <= IOTLB_hit_q  || (IOTLB_hit_n != 0);
        IOTLB_miss_q <= IOTLB_miss_q || IOTLB_miss_n == {IOTLB_ENTRIES{1'b1}};
        end
    end
end

logic [28:0] IOTLB_VPN [IOTLB_ENTRIES - 1 : 0];
logic IOTLB_VPN_valid [IOTLB_ENTRIES - 1 : 0];

logic IOTLB_en_1s [IOTLB_ENTRIES - 1 : 0];
logic IOTLB_en_2s [IOTLB_ENTRIES - 1 : 0];

logic IOTLB_is_2m_1s [IOTLB_ENTRIES - 1 : 0];
logic IOTLB_is_2m_2s [IOTLB_ENTRIES - 1 : 0];

logic IOTLB_is_1G_1s [IOTLB_ENTRIES - 1 : 0];
logic IOTLB_is_1G_2s [IOTLB_ENTRIES - 1 : 0];

logic IOTLB_is_msi [IOTLB_ENTRIES - 1 : 0];

logic [19:0] IOTLB_pscid [IOTLB_ENTRIES - 1 : 0];
logic [15:0] IOTLB_gscid [IOTLB_ENTRIES - 1 : 0];
logic IOTLB_pte_global   [IOTLB_ENTRIES - 1 : 0];

logic [15:0] gscid;
assign gscid = $rose(ddtc_hit) ? symb_dc.iohgatp.gscid : dc_q.iohgatp.gscid;

logic [19:0] pscid; 
assign pscid = $rose(ddtc_hit) ? symb_dc.ta.pscid : dc_q.ta.pscid;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        for (int i = 0; i < IOTLB_ENTRIES; i++ ) begin
            IOTLB_VPN[i]           <= 0;
            IOTLB_VPN_valid[i]     <= 0;
            IOTLB_seq_detector[i]  <= 0;  

            IOTLB_pscid[i]         <= 0; 
            IOTLB_gscid[i]         <= 0;

            IOTLB_pte_global[i]    <= 0;

            IOTLB_en_1s[i]         <= 0;
            IOTLB_en_2s[i]         <= 0;

            IOTLB_is_2m_2s[i]      <= 0;
            IOTLB_is_2m_1s[i]      <= 0;

            IOTLB_is_1G_1s[i]      <= 0;
            IOTLB_is_1G_2s[i]      <= 0;

            IOTLB_is_msi[i]        <= 0;

        end

    else if(IOTLB_miss_q && !with_error_pte && !with_error_pte_loaded && aw_or_ar_hsk) begin

        for (int i = 0; i < IOTLB_ENTRIES; i++ ) begin
            if((IOTLB_seq_detector[i] == 0 || IOTLB_seq_detector[i] == IOTLB_ENTRIES)) begin
                
                IOTLB_VPN_valid[i]     <= 1'b1;
                IOTLB_seq_detector[i]  <= 1;
                IOTLB_VPN[i]           <= selected_addr[40:12]; 
                IOTLB_pscid[i]         <= pscid;
                IOTLB_gscid[i]         <= gscid;
                
                IOTLB_pte_global[i]    <= pte_1s_global; 

                IOTLB_en_1s[i]         <= stage1_enable;
                IOTLB_en_2s[i]         <= stage2_enable;

                IOTLB_is_2m_1s[i]      <= first_s_2M;
                IOTLB_is_2m_2s[i]      <= second_s_2M;
                IOTLB_is_1G_1s[i]      <= first_s_1G;
                IOTLB_is_1G_2s[i]      <= second_s_1G;
                IOTLB_is_msi[i]        <= 0;            //tbd

                for (int j = 0; j < IOTLB_ENTRIES; j++ )
                    if(!(IOTLB_seq_detector[j] == 0 || IOTLB_seq_detector[j] == IOTLB_ENTRIES))
                        IOTLB_seq_detector[j] <= IOTLB_seq_detector[j] + 1;
                
                break;
            end
        end
    end

    else if($rose(IOTLB_hit_q)) begin

        for (int i = 0; i < DDTC_ENTRIES; i++ ) begin
            if(IOTLB_hit_n[i] == 1 && IOTLB_seq_detector[i] != 1) begin
                
                for (int j = 0; j < IOTLB_ENTRIES; j++ ) begin
                    if(IOTLB_hit_n[j])
                        IOTLB_seq_detector[j] <= 1;
                    else if((IOTLB_seq_detector[i] == IOTLB_ENTRIES) && IOTLB_seq_detector[j] != 0)
                        IOTLB_seq_detector[j] <= IOTLB_seq_detector[j] - 1;
                    else if(IOTLB_seq_detector[j] != 0)
                        IOTLB_seq_detector[j] <= IOTLB_seq_detector[j] + 1;
                end
                break;
            end
        end
    end
end

logic ready_to_capt_first_s_2M, ready_to_capt_first_s_1G, ready_to_capt_second_s_2M, ready_to_capt_second_s_1G;

assign ready_to_capt_first_s_2M  = trans_1s_in_progress && current_level == 1 && leaf_pte && !first_s_2M;
assign ready_to_capt_first_s_1G  = trans_1s_in_progress && current_level == 2 && leaf_pte && !first_s_1G;
assign ready_to_capt_second_s_2M = trans_2s_in_progress && current_level == 1 && leaf_pte && !second_s_2M;
assign ready_to_capt_second_s_1G = trans_2s_in_progress && current_level == 2 && leaf_pte && !second_s_1G;

logic first_s_2M, first_s_1G, second_s_2M, second_s_1G;
always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni || aw_or_ar_hsk) begin
        first_s_2M  <= 0;
        second_s_2M <= 0;
        first_s_1G  <= 0;
        second_s_1G <= 0;
    end
    else begin
        first_s_2M  <= first_s_2M  || ready_to_capt_first_s_2M;
        second_s_2M <= second_s_2M || ready_to_capt_second_s_2M;
        first_s_1G  <= first_s_1G  || ready_to_capt_first_s_1G;
        second_s_1G <= second_s_1G || ready_to_capt_second_s_1G;
    end
end

// ............................IOTLB Ended-------------------------------------------------

// ----------------------------Process to tranlsate an IOVA checks started----------------------

logic ready_to_capt_valid_type_disalow, valid_pv_pdtv_zero_captured;
assign ready_to_capt_valid_type_disalow = !dc_loaded_with_error && !dc_loaded_with_error_q && ((selected_pv && ddtc_hit && !symb_dc.tc.pdtv) || (wo_data_corruption && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && (pid_wider || (selected_pv && ((ddtc_miss && (dc_loaded_with_trans_ppn_q || ready_to_load_dc_wo_trans_ppn) && !dc_q.tc.pdtv))))));
logic su_visor_not_allowed;
// assign su_visor_not_allowed = !ready_to_capt_valid_type_disalow && !dc_loaded_with_error && !dc_loaded_with_error_q && ((pdtc_hit_q && priv_transac && !pdtc_ens[hit_index]) || (wo_data_corruption && ds_resp_i.r.id == 1 && ds_resp_i.r_valid && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && (pc_ta_active && !pc_ta_q.ens && priv_transac)));

logic pid_wider_when_cache_miss, pid_wider_when_cache_hit;
assign pid_wider_when_cache_miss = ddtc_miss && dc_loaded_with_trans_ppn_q && dc_q.tc.pdtv && ((dc_q.fsc.mode == 1 && |selected_pid[19:8]) || ((dc_q.fsc.mode == 2 && |selected_pid[19:17])));
assign pid_wider_when_cache_hit = ddtc_hit && symb_dc.tc.pdtv && ((symb_dc.fsc.mode == 1 && |selected_pid[19:8])  || (symb_dc.fsc.mode == 2 && |selected_pid[19:17]));

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

logic ready_to_load_dc_wo_trans_ppn, dc_loaded_wo_trans_ppn_q, ready_to_load_dc_with_trans_ppn, dc_loaded_with_trans_ppn_q, ready_to_laod_pc, pc_loaded_q;

assign ready_to_load_dc_wo_trans_ppn   = (counter_dc == 3) && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw && !dc_loaded_with_error && !dc_loaded_with_error_q && !dc_loaded_wo_trans_ppn_q;
assign ready_to_load_dc_with_trans_ppn = (ready_to_load_dc_wo_trans_ppn || dc_loaded_wo_trans_ppn_q) && (!stage2_enable || (dc_q.tc.pdtv ? ready_to_compl_pdtp_trans : 1)) && !dc_loaded_with_trans_ppn_q;

assign ready_to_laod_pc = pc_fsc_active && data_strcuture.r_hsk_trnsl_compl && !pc_loaded_q && !pc_loaded_with_error && !pc_loaded_with_error_captured_q;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk) begin
        dc_loaded_wo_trans_ppn_q   <= 0;
        dc_loaded_with_trans_ppn_q <= 0;
        pc_loaded_q <= 0;
    end
    else begin
        dc_loaded_wo_trans_ppn_q   <= dc_loaded_wo_trans_ppn_q   || ready_to_load_dc_wo_trans_ppn;
        dc_loaded_with_trans_ppn_q <= dc_loaded_with_trans_ppn_q || ready_to_load_dc_with_trans_ppn;
        pc_loaded_q                <= pc_loaded_q || ready_to_laod_pc;
    end

logic [1:0] counter_non_leaf_pc;
logic counter_pc;

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni)
        counter_non_leaf_pc <= 0;

    else if(counter_non_leaf_pc == 1 && ((dc_q.fsc.mode == 2 && ddtc_miss) || (symb_dc.fsc.mode == 2 && ddtc_hit)) && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl) // ddtlevel 2
        counter_non_leaf_pc <= 0;
    
    else if(counter_non_leaf_pc == 2 && ((dc_q.fsc.mode == 3 && ddtc_miss) || (symb_dc.fsc.mode == 3 && ddtc_hit)) && last_beat_cdw && data_strcuture.r_hsk_trnsl_compl) // ddtlevel 3
        counter_non_leaf_pc <= 0;
    
    else if(((symb_dc.fsc.mode > 1 && ddtc_hit) || (dc_loaded_with_trans_ppn_q && dc_q.fsc.mode > 1)) && data_strcuture.r_hsk_trnsl_compl && last_beat_cdw)
        counter_non_leaf_pc <= counter_non_leaf_pc + 1;

logic dc_miss_n, dc_hit_n, dc_miss_q, dc_hit_q;
assign dc_miss_n = ddtc_miss && (dc_q.fsc.mode == 1 || ((counter_non_leaf_pc == 2 && dc_q.fsc.mode == 3) || (counter_non_leaf_pc == 1 && dc_q.fsc.mode == 2)));
assign dc_hit_n  = (symb_dc.tc.pdtv || symb_dc.tc.dpe) && ddtc_hit  && (symb_dc.fsc.mode == 1 || ((counter_non_leaf_pc == 2 && symb_dc.fsc.mode == 3) || (counter_non_leaf_pc == 1 && symb_dc.fsc.mode == 2)));

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni || aw_or_ar_hsk) begin
        dc_miss_q <= 0;
        dc_hit_q  <= 0;
    end
    else begin
        dc_miss_q <= dc_miss_q || dc_miss_n;
        dc_hit_q  <= dc_hit_q  || dc_hit_n ;
    end
end

always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni)
        counter_pc <= 0;
    else if(aw_or_ar_hsk)
        counter_pc <= 0;
    else if(counter_pc == 1 && !aw_or_ar_hsk)
        counter_pc <= 1;
    else if((dc_loaded_with_trans_ppn_q || (ddtc_hit && symb_dc.tc.pdtv)) && (dc_hit_q || dc_miss_n) && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1)
        counter_pc <= 1;

logic pc_ta_active, pc_fsc_active;

assign pc_ta_active  = (counter_pc == 0 && (dc_hit_q || (dc_loaded_with_trans_ppn_q && dc_miss_n))) && ds_resp_i.r.id == 1 && ds_resp_i.r_valid;
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
assign pdte_accessed = dc_loaded_with_trans_ppn_q && ds_resp_i.r.resp == axi_pkg::RESP_OKAY && data_strcuture.r_hsk_trnsl_compl && ds_resp_i.r.id == 1 && !dc_loaded_with_error && counter_pc == 0 && ((dc_q.fsc.mode == 3 && counter_non_leaf_pc < 2) || (!selected_pid[19:17] && dc_q.fsc.mode == 2 && !counter_non_leaf_pc));

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


logic pc_loaded_with_error, pc_loaded_with_error_captured_q;
assign pc_loaded_with_error = ready_to_capt_pdte_not_valid || ready_to_capt_pdte_misconfig || ready_to_capt_pc_not_valid || ready_to_capt_pc_misconfig;




//----------------------------Process directory checks Ended--------------------------------


//----------------------------PTW Started-----------------------------------------------
logic pte_active;
assign pte_active = (ds_resp_i.r.id == 0 && ds_resp_i.r_valid);

logic [43:0] pte_1s_ppn, pte_2s_ppn;
always @(posedge clk_i or negedge rst_ni)
    if(!rst_ni || aw_or_ar_hsk) begin
        pte_1s_ppn <= 0;
        pte_2s_ppn <= 0;
    end
    else if(trans_1s_in_progress && leaf_pte)
        pte_1s_ppn <= pte.ppn;
    else if(trans_2s_in_progress && leaf_pte)
        pte_2s_ppn <= pte.ppn;

riscv::pte_t pte;
assign pte = pte_active ? ds_resp_i.r.data : 0;

logic ready_to_capt_pf_excep, pf_excep_captured;
assign ready_to_capt_pf_excep = !ready_to_capt_data_corrup_ptw && pte_active && (!pte.v || (!pte.r && pte.w) || |pte.reserved || (leaf_pte ? !pte.r: (pte.a || pte.d || pte.u)));

logic ready_to_capt_guest_pf_due_to_u_bit, guest_pf_captured_due_to_u_bit;
assign ready_to_capt_guest_pf_due_to_u_bit = !ready_to_capt_data_corrup_ptw && pte_active && (trans_2s_in_progress || trans_iosatp_in_progress || trans_pdtp_in_progress) && !pte.u && (pte.r || pte.x) && !guest_pf_captured_due_to_u_bit;

logic ready_to_capt_guest_pf_due_to_G_bit, guest_pf_captured_due_to_G_bit;
assign ready_to_capt_guest_pf_due_to_G_bit = !ready_to_capt_data_corrup_ptw && pte_active && (trans_2s_in_progress || trans_iosatp_in_progress || trans_pdtp_in_progress) && pte.g && !guest_pf_captured_due_to_G_bit;

logic ready_to_capt_accessed_low, accessed_low_captured;
assign ready_to_capt_accessed_low = !ready_to_capt_misaligned_super_page && pte_active && (pte.r || pte.x) && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && !pte.a && !accessed_low_captured;

logic ready_to_capt_dirty_low, dirty_low_captured;
assign ready_to_capt_dirty_low = !ready_to_capt_misaligned_super_page && pte_active && (pte.r || pte.x) && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && pte.a && !pte.d && aw_seen_before && !dirty_low_captured;

logic ready_to_capt_data_corrup_ptw, ptw_data_corrup_captured;
assign ready_to_capt_data_corrup_ptw = pte_active && ds_resp_i.r.id == 0 && ds_resp_i.r.resp != axi_pkg::RESP_OKAY && ds_resp_i.r_valid;

logic ready_to_capt_misaligned_super_page;
assign ready_to_capt_misaligned_super_page = (!ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && (pte.r || pte.x)) && (current_level == 2 ? |pte[27 : 10] : (current_level == 1 ? |pte[18 : 10] : 0));

logic guest_pf_63_41_high_39x4;
assign guest_pf_63_41_high_39x4 = (trans_1s_completed && $rose(trans_2s_in_progress || trans_pdtp_in_progress || trans_iosatp_in_progress) && |pte_1s_ppn[43:29]) || (!stage1_enable && stage2_enable && $rose(trans_2s_in_progress) && |selected_addr[63:41]);

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni) begin
        pf_excep_captured               <= 0;
        ptw_data_corrup_captured        <= 0;
        accessed_low_captured           <= 0;
        dirty_low_captured              <= 0;
        guest_pf_captured_due_to_u_bit  <= 0;
        guest_pf_captured_due_to_G_bit  <= 0;
    end
    else if(aw_or_ar_hsk) begin
        pf_excep_captured               <= 0;
        ptw_data_corrup_captured        <= 0;
        accessed_low_captured           <= 0;
        dirty_low_captured              <= 0;
        guest_pf_captured_due_to_u_bit  <= 0;
        guest_pf_captured_due_to_G_bit  <= 0;
    end
    else begin
        pf_excep_captured              <= pf_excep_captured                 || ready_to_capt_pf_excep;
        ptw_data_corrup_captured       <= ptw_data_corrup_captured          || ready_to_capt_data_corrup_ptw;
        accessed_low_captured          <= accessed_low_captured             || ready_to_capt_accessed_low;
        dirty_low_captured             <= dirty_low_captured                || ready_to_capt_dirty_low;
        guest_pf_captured_due_to_u_bit <= guest_pf_captured_due_to_u_bit    || ready_to_capt_guest_pf_due_to_u_bit;
        guest_pf_captured_due_to_G_bit <= guest_pf_captured_due_to_G_bit    || ready_to_capt_guest_pf_due_to_G_bit;
    end
end

logic with_error_pte, with_error_pte_loaded;
assign with_error_pte = ready_to_capt_s_and_u_mode_fault || guest_pf_63_41_high_39x4 || ready_to_capt_guest_pf_due_to_u_bit || ready_to_capt_guest_pf_due_to_G_bit || ready_to_capt_misaligned_super_page || ready_to_capt_dirty_low || ready_to_capt_accessed_low || ready_to_capt_data_corrup_ptw || ready_to_capt_pf_excep;

logic [2:0] counter_PTE;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        counter_PTE <= 0;
    else if(aw_or_ar_hsk)
        counter_PTE <= 0;
    else if(!with_error_pte && pte_active && (pte.r || pte.x))
        counter_PTE <= counter_PTE + 1;
end

int current_level;
logic decr_crnt_lvl;
assign decr_crnt_lvl = pte_active && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && !pte.r && !pte.x && data_strcuture.r_hsk_trnsl_compl;

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni)
        current_level <= 2;
    else if(aw_or_ar_hsk || (leaf_pte && (trans_iosatp_in_progress || trans_1s_in_progress || trans_2s_in_progress || trans_pdtp_in_progress)))
        current_level <= 2;
    else
        current_level <= current_level - decr_crnt_lvl;
end

logic pdtv_enable, pdtc_stage_1_enable, stage1_enable, stage2_enable;

assign pdtv_enable = (ddtc_miss && dc_q.tc.pdtv) || (ddtc_hit && symb_dc.tc.pdtv);

assign pdtc_stage_1_enable = pdtv_enable && ((pdtc_miss_q && pc_q.fsc.mode != 0) || (pdtc_hit_q && symb_dc.fsc.mode != 0));

assign stage1_enable = pdtc_stage_1_enable || (!pdtv_enable && ((ddtc_hit && symb_dc.fsc.mode != 0) || (ddtc_miss && dc_q.fsc.mode != 0)));

assign stage2_enable = (ddtc_miss && dc_q.iohgatp.mode != 'h0) || (ddtc_hit && symb_dc.iohgatp.mode != 'h0);

logic user_mode_trans, store_nd_wo_w_permis, x_1_sum_0;
assign user_mode_trans      = !priv_transac && !pte.u && (stage1_enable || stage2_enable);
assign store_nd_wo_w_permis = (stage1_enable || stage2_enable) && pte_active && !pte.w && trans_type == UNTRANSLATED_W;
assign rx_nd_wo_x_permis    = (stage1_enable || stage2_enable) && trans_type == UNTRANSLATED_RX && pte_active && !pte.x;

logic ta_sum_0;
// assign ta_sum_0   = pdtc_miss_q ? !pc_q.ta.sum : (pdtc_hit_q && !symb_dc.ta.sum);
// assign x_1_sum_0  = priv_transac && pte.u && (ta_sum_0 || pte.x);

logic ready_to_capt_s_and_u_mode_fault, s_and_u_mode_fault_captured;
assign ready_to_capt_s_and_u_mode_fault = !ready_to_capt_accessed_low && !ready_to_capt_dirty_low && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && !ready_to_capt_misaligned_super_page && (pte.r || pte.x) && pte_active && (rx_nd_wo_x_permis || store_nd_wo_w_permis || user_mode_trans || x_1_sum_0) && !s_and_u_mode_fault_captured;

// assign with_error_pte = guest_pf_63_41_high_39x4 || ready_to_capt_guest_pf_due_to_u_bit || ready_to_capt_guest_pf_due_to_G_bit || ready_to_capt_misaligned_super_page || ready_to_capt_dirty_low || ready_to_capt_accessed_low || ready_to_capt_data_corrup_ptw || ready_to_capt_pf_excep;

// at last will only include the !with_error_pte in place of too many variables. The reason for putting all variables individual is because of the 

logic ready_to_capt_super_page;
assign ready_to_capt_super_page = !ready_to_capt_guest_pf_due_to_G_bit || !ready_to_capt_s_and_u_mode_fault && !ready_to_capt_accessed_low && !ready_to_capt_dirty_low && !ready_to_capt_pf_excep && !ready_to_capt_data_corrup_ptw && !ready_to_capt_misaligned_super_page && pte_active && pte.r && current_level > 0 && (pte.r || pte.x);


logic implicit_access;
// will change later pdt_walk with pdt_miss_q...now using internal signal because there is bug in design and also will add condition later when msi is not disabled
assign implicit_access = (ddtc_hit && stage2_enable && symb_dc.tc.pdtv) || (ddtc_miss && stage2_enable && dc_q.tc.pdtv);

logic trans_iosatp_in_progress, iosatp_trans_completed;
assign trans_iosatp_in_progress  = (implicit_access ? counter_PTE == 1 : counter_PTE == 0) && stage1_enable && stage2_enable && pte_active && !iosatp_trans_completed;

logic trans_pdtp_in_progress, pdtp_translated, ready_to_compl_pdtp_trans;
assign trans_pdtp_in_progress = implicit_access && counter_PTE == 0 && pte_active && !pdtp_translated;
assign ready_to_compl_pdtp_trans = trans_pdtp_in_progress && leaf_pte && !with_error_pte && !with_error_pte_loaded;

logic with_second_stage;
assign with_second_stage = (!implicit_access && stage2_enable && iosatp_trans_completed) || (implicit_access && stage2_enable && pdtp_translated && iosatp_trans_completed) || !stage2_enable;

logic trans_1s_in_progress, trans_1s_completed, trans_2s_in_progress, trans_2s_completed;
assign trans_1s_in_progress = stage1_enable && with_second_stage && pte_active && !trans_1s_completed;

assign trans_2s_in_progress = stage2_enable && (stage1_enable ? (trans_1s_completed && (implicit_access ? (iosatp_trans_completed && pdtp_translated) : iosatp_trans_completed)) : ((implicit_access && pdtp_translated) || (!InclPC || !pdtv_enable ))) && pte_active && !trans_2s_completed;

logic ready_to_compl_trans_complete, trans_completed;
assign ready_to_compl_trans_complete = stage2_enable ? (trans_2s_in_progress && leaf_pte) : (stage1_enable && trans_1s_in_progress && leaf_pte) && !trans_completed;

logic leaf_pte;
assign leaf_pte = !ready_to_capt_data_corrup_ptw && (pte.r || pte.x);

always @(posedge clk_i or negedge rst_ni) begin
    if(!rst_ni || aw_or_ar_hsk) begin
        iosatp_trans_completed      <= 0;
        pdtp_translated             <= 0;
        trans_1s_completed          <= 0;
        trans_2s_completed          <= 0;
        with_error_pte_loaded       <= 0;
        trans_completed             <= 0;
        s_and_u_mode_fault_captured <= 0;
    end
    else begin       
        trans_1s_completed          <= trans_1s_completed            || (trans_1s_in_progress     && leaf_pte && !with_error_pte && !with_error_pte_loaded);
        pdtp_translated             <= pdtp_translated               || ready_to_compl_pdtp_trans;
        iosatp_trans_completed      <= iosatp_trans_completed        || (trans_iosatp_in_progress && leaf_pte && !with_error_pte && !with_error_pte_loaded);
        trans_2s_completed          <= trans_2s_completed            || (trans_2s_in_progress     && leaf_pte && !with_error_pte && !with_error_pte_loaded);
        trans_completed             <= ready_to_compl_trans_complete || trans_completed;
        with_error_pte_loaded       <= with_error_pte                || with_error_pte_loaded;
        s_and_u_mode_fault_captured <= s_and_u_mode_fault_captured   || ready_to_capt_s_and_u_mode_fault;
    end
end

// address calcultion
logic [55:0] physical_addrs;

always_comb begin
    physical_addrs = 0;

    if(stage1_enable && stage2_enable)
        case ({first_s_2M, first_s_1G, second_s_2M, second_s_1G})

            // 1-S: xx | 2-S: 4k:   {PPN[2], PPN[1],  PPN[0], OFF}
            4'bxx00: physical_addrs = {pte_2s_ppn, selected_addr[11:0]};

            // 1-S: 4k | 2-S: 1G:   {PPN[2], GPPN[1],  GPPN[0], OFF}
            4'b0001: physical_addrs = {pte_2s_ppn[43:18], pte_1s_ppn[17:0], selected_addr[11:0]};

            // 1-S: 4k | 2-S: 1M:   {PPN[2], PPN[1],  GPPN[0], OFF}
            4'b0010: physical_addrs = {pte_2s_ppn[43:9], pte_1s_ppn[8:0], selected_addr[11:0]};

            // 1-S: 1G | 2-S: 1G:    {PPN[2], VPN[1],  VPN[0],  OFF}
            4'b0101: physical_addrs = {pte_2s_ppn[43:18],selected_addr[29:0]};

            // 1-S: 1G | 2-S: 1G:    {PPN[2], GPPN[1], VPN[0],  OFF}
            4'b1001: physical_addrs = {pte_2s_ppn[43:18], pte_1s_ppn[17:9], selected_addr[20:0]};

            // 1-S: 2M | 2-S: 2M:   {PPN[2], PPN[1],  VPN[0],  OFF}
            // 1-S: 1G | 2-S: 2M:   {PPN[2], PPN[1],  VPN[0],  OFF}
            4'b0110, 4'b1010: physical_addrs = {pte_2s_ppn[43:9], selected_addr[20:0]};

            default:;
        endcase

    else if(stage1_enable && !stage2_enable)
        case ({first_s_2M, first_s_1G})
            
            // 1-S: 4k  | 2-S: disable : {PPN[2], PPN[1],  PPN[0], OFF}
            2'b00: physical_addrs = {pte_1s_ppn, selected_addr[11:0]};

            // 1-S: 1G  | 2-S: disable : {PPN[2], PPN[1],  VPN[0], OFF}
            2'b01: physical_addrs = {pte_1s_ppn[43:18], selected_addr[29:0]};

            // 1-S: 1M  | 2-S: disable : {PPN[2], PPN[1],  VPN[0], OFF}
            2'b10: physical_addrs = {pte_1s_ppn[43:9], selected_addr[20:0]};
            
            default:;
        endcase

    else if(!stage1_enable && stage2_enable)
        case ({second_s_2M, second_s_1G})
            
            // 1-S: disable  | 2-S: 4k : {PPN[2], PPN[1], PPN[0], OFF}
            2'b00: physical_addrs = {pte_2s_ppn, selected_addr[11:0]};

            // 1-S: disable  | 2-S: 1G : {PPN[2], VPN[1], VPN[0], OFF}
            2'b01: physical_addrs = {pte_2s_ppn[43:18], selected_addr[29:0]};

            // 1-S: disable  | 2-S: 1M : {PPN[2], PPN[1], VPN[0], OFF}
            2'b10: physical_addrs = {pte_2s_ppn[43:9], selected_addr[20:0]};

            default:;
        endcase

end

logic compare_addr;
assign compare_addr = !s_and_u_mode_fault_captured && trans_completed && (stage1_enable || stage2_enable) && !with_error_pte && !with_error_pte_loaded;

assrt_63_addr:
assert property (compare_addr |-> riscv_iommu.spaddr == physical_addrs);


//----------------------------PTW Ended-----------------------------------------------



//----------------------------- Assertion Started----------------------------------------

assrt_1_ddt_entry_invalid_error: // if ddte.v = 0, then cause must be DDT_ENTRY_INVALID
assert property (ddt_entry_invalid_captured && last_beat_cdw |=> $past(riscv_iommu.trans_error) || riscv_iommu.trans_error);

assrt_2_ddt_entry_invalid_cause_code: // if ddte.v = 0, then cause must be DDT_ENTRY_INVALID
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
assert property (dc_data_corruption_captured_q && last_beat_cdw |->  riscv_iommu.cause_code == rv_iommu::DDT_DATA_CORRUPTION);

assrt_10_dc_tc_not_valid:
assert property (wo_data_corruption && dc_tc_not_valid_captured_q && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID);

assrt_11_dc_misconfig:
assert property (wo_data_corruption && dc_misconfig_captured_q && last_beat_cdw |=> ($past(riscv_iommu.cause_code) == rv_iommu::DDT_ENTRY_MISCONFIGURED) || (riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED));

assrt_12_dc_misconfig_pc:
assert property (iosatp_invalid |=> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED );

assrt_13_2_dc_misconfig_pc:
assert property (iosatp_invalid |=> $past(riscv_iommu.trans_error) || riscv_iommu.trans_error);

logic not_ddte;
assign not_ddte = ddtp.iommu_mode.q == 2 || ((counter_non_leaf == 2 && ddtp.iommu_mode.q == 4) || (counter_non_leaf == 1 && ddtp.iommu_mode.q == 3));

assrt_14_dc_misconfig_wo_pc:
assert property (riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_MISCONFIGURED && $past(not_ddte) |=> iosatp_invalid || ((dc_misconfig_captured_q || ready_to_capture_ddte_misconfig_rsrv_bits) && last_beat_cdw));

assrt_15_ddt_walk: // if data is not present, there will be ddt_walk
assert property ($rose(ddtc_miss) |-> riscv_iommu.ddt_walk); 

assrt_16_ddt_walk: 
assert property (riscv_iommu.ddt_walk |-> ddtc_miss);

assrt_17_ddt_walk_off: // if data is present, there will be no ddt_walk
assert property ($rose(ddtc_hit) |=> !riscv_iommu.ddt_walk);

assrt_18_ddt_walk_off_wo_rose: // if data is present, there will be no ddt_walk
assert property (ddtc_hit |=> !riscv_iommu.ddt_walk);

logic wo_data_corruption;
assign wo_data_corruption = !dc_pc_with_data_corruption_captured_q && !dc_pc_with_data_corruption;

if(!InclPC)
assrt_18_pdtv_zero: // if did length higher bits are set to 1 then cause must be TRANS_TYPE_DISALLOWED
assert property (wo_data_corruption && pdtv_zero_captured_q && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

assrt_19_error_and_valid_both_high:
assert property (!(riscv_iommu.trans_error && riscv_iommu.trans_valid));

assrt_20_type_disallow_error:
assert property ($rose(ready_to_capt_valid_type_disalow) && last_beat_cdw |=> ##1 riscv_iommu.trans_error);

assrt_21_type_disallow_error:
assert property ($rose(ready_to_capt_valid_type_disalow) && last_beat_cdw |=> ##1 riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

assrt_22_pdt_walk: // if data is not present, there will be pdt_walk
assert property ($rose(pdtc_miss_q) |-> riscv_iommu.pdt_walk);

assrt_23_pdt_walk: 
assert property (riscv_iommu.pdt_walk |-> (pdtc_miss_q));

assrt_24_pdt_walk_off: // if data is present, there will be no pdt_walk
assert property ($rose(pdtc_hit_q) |=> !riscv_iommu.pdt_walk);

assrt_25_pdte_not_valid:
assert property (ready_to_capt_pdte_not_valid |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_INVALID);

assrt_26_pdte_misconfig:
assert property (ready_to_capt_pdte_misconfig |=> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_MISCONFIGURED);

assrt_27_pc_not_valid:
assert property (pc_not_valid_captured && wo_data_corruption && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_INVALID);

assrt_28_pc_misconfig:
assert property (pc_misconfig_captured && wo_data_corruption && last_beat_cdw |-> riscv_iommu.trans_error && riscv_iommu.cause_code == rv_iommu::PDT_ENTRY_MISCONFIGURED);

assrt_29_ptw_pg_fault_trans_error:
assert property ($rose(pf_excep_captured) |-> riscv_iommu.trans_error);

assrt_30_ptw_corrupt:
assert property ($rose(ptw_data_corrup_captured) |-> riscv_iommu.cause_code == rv_iommu::PT_DATA_CORRUPTION);

assrt_31_ptw_corrupt_trans_error:
assert property ($rose(ptw_data_corrup_captured) |-> riscv_iommu.trans_error);

assrt_32_ptw_accessed_bit: // proven
assume property ($rose(accessed_low_captured) |-> riscv_iommu.trans_error);

assrt_33_ptw_accessed_bit:
assert property ($rose(accessed_low_captured) |-> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT || riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_34_ptw_dirty_bit:
assert property ($rose(dirty_low_captured) |-> riscv_iommu.trans_error);

assrt_35_ptw_dirty_bit:
assert property ($rose(dirty_low_captured) |-> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

assrt_36_level_less_than_0_error:
assert property (current_level < 0 && $changed(current_level) |-> riscv_iommu.trans_error);

assrt_37_level_less_than_0_cause_code:
assert property (current_level < 0 && aw_seen_before && $changed(current_level) |-> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

assrt_38_level_less_than_0_cause_code:
assert property (current_level < 0 && !aw_seen_before && $changed(current_level) |-> riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_39_misaligned_error:
assert property (ready_to_capt_misaligned_super_page |=> riscv_iommu.trans_error);

assrt_40_misaligned_cause_code:
assert property (ready_to_capt_misaligned_super_page && aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

assrt_41_misaligned_cause_code:
assert property (ready_to_capt_misaligned_super_page && !aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_42_data_corruption_error: // proven 
assume property (ready_to_capt_data_corrup_ptw |=> riscv_iommu.trans_error);

assrt_43_data_corruption_cause_code:
assert property (ready_to_capt_data_corrup_ptw |=> riscv_iommu.cause_code == rv_iommu::PT_DATA_CORRUPTION);

assrt_44_super_page_valid:
assert property (ready_to_capt_super_page && ready_to_compl_trans_complete |=> riscv_iommu.trans_valid);

assrt_45_super_page:
assert property (ready_to_capt_super_page && ready_to_compl_trans_complete |=> riscv_iommu.is_superpage);

assrt_46_sum_o_error:
assert property (ready_to_capt_s_and_u_mode_fault |=> riscv_iommu.trans_error);

assrt_47_sum_o_cause_code:
assert property (ready_to_capt_s_and_u_mode_fault && !aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::LOAD_PAGE_FAULT);

assrt_48_sum_o_cause_code:
assert property (ready_to_capt_s_and_u_mode_fault && aw_seen_before |=> riscv_iommu.cause_code == rv_iommu::STORE_PAGE_FAULT);

// assrt_49_su_visor_error:
// assert property (su_visor_not_allowed && last_beat_cdw |-> riscv_iommu.trans_error);

// assrt_50_su_visor_cause_code:
// assert property (su_visor_not_allowed && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::TRANS_TYPE_DISALLOWED);

assrt_51_guest_pf_exception:
assert property ($rose(guest_pf_captured_due_to_u_bit) |-> riscv_iommu.trans_error);

assrt_52_guest_pf_exception_due_to_u_cause_code_1:
assert property ($rose(guest_pf_captured_due_to_u_bit) && aw_seen_before |-> riscv_iommu.cause_code == rv_iommu::STORE_GUEST_PAGE_FAULT);

assrt_53_guest_pf_exception_due_to_u_cause_code_2:
assert property ($rose(guest_pf_captured_due_to_u_bit) && !aw_seen_before |-> riscv_iommu.cause_code == rv_iommu::LOAD_GUEST_PAGE_FAULT);

assrt_54_guest_pf_exception_due_to_g_bit:
assert property ($rose(guest_pf_captured_due_to_G_bit) |-> riscv_iommu.trans_error);

assrt_55_guest_pf_exception_due_to_g_cause_code_1:
assert property ($rose(guest_pf_captured_due_to_G_bit) && aw_seen_before |-> riscv_iommu.cause_code == rv_iommu::STORE_GUEST_PAGE_FAULT);

assrt_56_guest_pf_exception_due_to_g_cause_code_2:
assert property ($rose(guest_pf_captured_due_to_G_bit) && !aw_seen_before |-> riscv_iommu.cause_code == rv_iommu::LOAD_GUEST_PAGE_FAULT);

assrt_57_ptw_walk: // if data is not present, there will be ptw
assert property ($rose(IOTLB_miss_q) |=> riscv_iommu.s1_ptw || riscv_iommu.s2_ptw);

assrt_58_iotlb_miss: // if data is not present, there will be iotlb miss
assert property ($rose(IOTLB_miss_q) |-> riscv_iommu.iotlb_miss);

assrt_59_iotlb_hit: // if data is not present, there will be no iotlb miss
assert property ($rose(IOTLB_hit_q) |-> !riscv_iommu.iotlb_miss);

assrt_60_ptw_walk: // if data is not present, there will be no page table walk
assert property ($rose(IOTLB_hit_q) |=> !(riscv_iommu.s1_ptw || riscv_iommu.s2_ptw));


assrt_61_high_63_41_error: // for sv39*4 63:41 must all be 0
assert property (guest_pf_63_41_high_39x4 |=> riscv_iommu.trans_error);

assrt_62_high_63_41_causecode: // for sv39*4 63:41 must all be 0
assert property (guest_pf_63_41_high_39x4 |=> aw_seen_before ? riscv_iommu.cause_code == rv_iommu::STORE_GUEST_PAGE_FAULT : riscv_iommu.cause_code == rv_iommu::LOAD_GUEST_PAGE_FAULT);

//----------------------------- Assertion Ended----------------------------------------


//-----------------------------Cover CDW Started---------------------------------------------

cov_1_checking_dc:
cover property (counter_dc == 2 && riscv_iommu.ddtp.iommu_mode.q == 4);

cov_2_cause_code_define:
cover property (riscv_iommu.cause_code == 263 && riscv_iommu.i_rv_iommu_translation_wrapper.wrap_cause_code == 260);

cov_3_dc_valid:
cover property (dc_tc_not_valid_captured_q && last_beat_cdw |-> riscv_iommu.cause_code == rv_iommu::DDT_ENTRY_INVALID);

cov_4_dc_misconfig:
cover property (dc_misconfig_captured_q && last_beat_cdw);

cov_5_error:
cover property (riscv_iommu.trans_error && riscv_iommu.cause_code != 260 ##[1:$] !dc_loaded_with_error && correct_did && riscv_iommu.cause_code == 260 );

cov_6_checking_cache:
cover property ($rose(ddtc_hit) ##[0:$] $rose(ddtc_miss));

cov_7_update_not_existing:
cover property (($rose(ddtc_miss) ##5 !ddtc_miss)[*8]);

cov_8_seq_det_4:
cover property (ddtc_seq_detector_n[4] == 1);

cov_9_seq_det_7:
cover property (ddtc_seq_detector_n[7] == 1);

// cover_10_unique:
// cover property ($onehot0(ddtc_hit_n));

cover_11_ptw_checker:
cover property (ds_resp_i.r.id == 0 && ds_resp_i.r_valid);

cover_12_error_and_valid_both_high:
cover property (counter_dc != 0 && translation_compl.ar_hsk_trnsl_compl && riscv_iommu.trans_valid);

cover_13_unique_case:
cover property (i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.wrap_error && i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.ptw_error);

cover_14_both_stages:
cover property (selected_pv && stage1_enable && stage2_enable && riscv_iommu.trans_valid);

cover_15_both_stages_wo_pc:
cover property (stage1_enable && stage2_enable && riscv_iommu.trans_valid);

cover_16_tlb_hit:
cover property (stage1_enable && stage2_enable && i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.i_rv_iommu_iotlb_sv39x4.lu_hit_o);

cover_17_pdtc_cache_seq_check:
cover property (pdtc_seq_detector[0] == 1 && pdtc_seq_detector[1] == 2 && riscv_iommu.flush_ddtc && riscv_iommu.flush_dv && !riscv_iommu.flush_pv |=> pdtc_seq_detector[1] == 1 && pdtc_entry_valid[1]);

cover_18_pdtc_cache_seq_check:
cover property (pdtc_seq_detector[0] == 1 && pdtc_seq_detector[1] == 2 && riscv_iommu.flush_ddtc && riscv_iommu.flush_dv && !riscv_iommu.flush_pv);
//-----------------------------Cover CDW Ended---------------------------------------------