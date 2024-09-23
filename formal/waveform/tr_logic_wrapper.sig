<?xml version="1.0" encoding="UTF-8"?>
<wavelist version="3">
  <insertion-point-position>9</insertion-point-position>
  <wave>
    <expr>clk_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>sva.ddtc_miss_q</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>sva.ddtc_hit_q</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.i_rv_iommu_ddtc.update_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>i_rv_iommu_translation_wrapper.flush_ddtc_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>i_rv_iommu_translation_wrapper.flush_dv_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>i_rv_iommu_translation_wrapper.flush_did_i</expr>
    <label/>
    <radix/>
  </wave>
  <spacer/>
  <wave>
    <expr>sva.pdtc_hit_q</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>sva.pdtc_miss_q</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>i_rv_iommu_translation_wrapper.gen_pc_support.i_rv_iommu_tw_sv39x4_pc.i_rv_iommu_pdtc.update_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>i_rv_iommu_translation_wrapper.flush_pdtc_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>i_rv_iommu_translation_wrapper.flush_pv_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>i_rv_iommu_translation_wrapper.flush_pid_i</expr>
    <label/>
    <radix/>
  </wave>
  <spacer/>
  <group collapsed="false">
    <expr/>
    <label>wrapper_logic</label>
    <wave collapsed="true">
      <expr>i_rv_iommu_translation_wrapper.iova_i</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.trans_valid_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.req_trans_i</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>i_rv_iommu_translation_wrapper.did_i</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.trans_error_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.report_fault_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>i_rv_iommu_translation_wrapper.cause_code_o</expr>
      <label/>
      <radix>dec</radix>
    </wave>
    <wave collapsed="true">
      <expr>i_rv_iommu_translation_wrapper.did_i</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.ddt_walk_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.iotlb_miss_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.pdt_walk_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.s1_ptw_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>i_rv_iommu_translation_wrapper.s2_ptw_o</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>i_rv_iommu_translation_wrapper.trans_type_i</expr>
      <label/>
      <radix>bin</radix>
    </wave>
  </group>
  <spacer/>
  <group collapsed="false">
    <expr/>
    <label>tr_aw_channel</label>
    <wave>
      <expr>sva.translation_req.aw_hsk</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.len</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.size</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.qos</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.cache</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.prot</expr>
      <label/>
      <radix/>
      <wave>
        <expr>sva.translation_req.dev_tr_req_i.aw_valid</expr>
        <label/>
        <radix/>
      </wave>
      <wave>
        <expr>sva.translation_req.dev_tr_resp_o.aw_ready</expr>
        <label/>
        <radix/>
        <wave>
          <expr>sva.translation_req.dev_tr_req_i.aw_valid</expr>
          <label/>
          <radix/>
        </wave>
        <wave>
          <expr>sva.translation_req.dev_tr_resp_o.aw_ready</expr>
          <label/>
          <radix/>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.burst</expr>
            <label/>
            <radix/>
          </wave>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.substream_id</expr>
            <label/>
            <radix/>
          </wave>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.id</expr>
            <label/>
            <radix/>
          </wave>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.region</expr>
            <label/>
            <radix/>
          </wave>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.atop</expr>
            <label/>
            <radix/>
          </wave>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.stream_id</expr>
            <label/>
            <radix/>
          </wave>
          <wave collapsed="true">
            <expr>sva.translation_req.dev_tr_req_i.aw.addr</expr>
            <label/>
            <radix/>
          </wave>
        </wave>
      </wave>
    </wave>
  </group>
  <spacer/>
  <group collapsed="false">
    <expr/>
    <label>tr_ar_channel</label>
    <wave>
      <expr>sva.translation_req.ar_hsk</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.addr</expr>
      <label/>
      <radix>hex</radix>
      <wave>
        <expr>sva.translation_req.dev_tr_req_i.ar_valid</expr>
        <label/>
        <radix/>
      </wave>
      <wave>
        <expr>sva.translation_req.dev_tr_resp_o.ar_ready</expr>
        <label/>
        <radix/>
        <wave>
          <expr>sva.translation_req.dev_tr_req_i.ar_valid</expr>
          <label/>
          <radix/>
        </wave>
        <wave>
          <expr>sva.translation_req.dev_tr_resp_o.ar_ready</expr>
          <label/>
          <radix/>
          <wave>
            <expr>sva.translation_req.dev_tr_req_i.ar_valid</expr>
            <label/>
            <radix/>
          </wave>
          <wave>
            <expr>sva.translation_req.dev_tr_resp_o.ar_ready</expr>
            <label/>
            <radix/>
            <wave>
              <expr>sva.translation_req.dev_tr_req_i.ar_valid</expr>
              <label/>
              <radix/>
            </wave>
            <wave>
              <expr>sva.translation_req.dev_tr_resp_o.ar_ready</expr>
              <label/>
              <radix/>
            </wave>
          </wave>
        </wave>
      </wave>
    </wave>
  </group>
  <spacer/>
  <group collapsed="false">
    <expr/>
    <label>ds_read_channel</label>
    <wave>
      <expr>sva.data_strcuture.r_hsk_trnsl_compl</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="false">
      <expr>sva.translation_req.dev_tr_req_i.ar.burst</expr>
      <label/>
      <radix/>
      <wave collapsed="true">
        <expr>sva.data_strcuture.axi_ds_tr_compl_i.r.data</expr>
        <label/>
        <radix/>
      </wave>
      <wave collapsed="true">
        <expr>sva.data_strcuture.axi_ds_tr_compl_i.r.resp</expr>
        <label/>
        <radix/>
      </wave>
      <wave>
        <expr>sva.data_strcuture.axi_ds_tr_compl_i.r.last</expr>
        <label/>
        <radix/>
      </wave>
      <wave>
        <expr>sva.data_strcuture.axi_ds_tr_compl_i.r.user</expr>
        <label/>
        <radix/>
      </wave>
      <wave collapsed="true">
        <expr>sva.data_strcuture.axi_ds_tr_compl_i.r.id</expr>
        <label/>
        <radix/>
      </wave>
      <wave>
        <expr>sva.data_strcuture.r_hsk_trnsl_compl</expr>
        <label/>
        <radix/>
        <wave collapsed="true">
          <expr>sva.dev_tr_req_i.ar.stream_id</expr>
          <label/>
          <radix/>
        </wave>
        <wave collapsed="true">
          <expr>sva.translation_req.dev_tr_req_i.ar.size</expr>
          <label/>
          <radix/>
        </wave>
        <wave collapsed="true">
          <expr>sva.translation_req.dev_tr_req_i.ar.id</expr>
          <label/>
          <radix/>
        </wave>
        <wave collapsed="true">
          <expr>sva.translation_req.dev_tr_req_i.ar.len</expr>
          <label/>
          <radix>dec</radix>
          <wave>
            <expr>sva.data_strcuture.axi_ds_tr_compl_i.r_valid</expr>
            <label/>
            <radix/>
          </wave>
          <wave>
            <expr>sva.data_strcuture.axi_ds_tr_compl_o.r_ready</expr>
            <label/>
            <radix/>
          </wave>
        </wave>
      </wave>
    </wave>
  </group>
  <spacer/>
  <group collapsed="false">
    <expr/>
    <label>ds_ar_channel</label>
    <wave>
      <expr>sva.data_strcuture.ar_hsk_trnsl_compl</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.id</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.addr</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.len</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.size</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.user</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.burst</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.lock</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.cache</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.prot</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.qos</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar.region</expr>
      <label/>
      <radix/>
      <wave collapsed="true">
        <expr>ds_resp_i.r.resp</expr>
        <label/>
        <radix/>
      </wave>
      <wave collapsed="true">
        <expr>sva.data_strcuture.read_counter</expr>
        <label/>
        <radix/>
      </wave>
      <wave collapsed="true">
        <expr>ds_resp_i.r.data</expr>
        <label/>
        <radix>hex</radix>
      </wave>
      <wave>
        <expr>sva.data_strcuture.axi_ds_tr_compl_i.r.last</expr>
        <label/>
        <radix/>
        <wave>
          <expr>sva.data_strcuture.axi_ds_tr_compl_i.ar_ready</expr>
          <label/>
          <radix/>
        </wave>
        <wave>
          <expr>sva.data_strcuture.axi_ds_tr_compl_o.ar_valid</expr>
          <label/>
          <radix/>
        </wave>
        <highlightlist>
          <!--Users can remove the highlightlist block if they want to load the signal save file into older version of JasperGold-->
          <highlight>
            <expr>sva.programming_interface_axi.prog_resp_o.r.last</expr>
            <color>builtin_red</color>
          </highlight>
        </highlightlist>
      </wave>
    </wave>
  </group>
</wavelist>