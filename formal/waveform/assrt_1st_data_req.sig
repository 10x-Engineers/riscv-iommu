<?xml version="1.0" encoding="UTF-8"?>
<wavelist version="3">
  <insertion-point-position>12</insertion-point-position>
  <wave>
    <expr>clk_i</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>sva.rst_ni</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.read_counter</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.symbolic_id</expr>
    <label/>
    <radix>dec</radix>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.symbolic_addr</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.wdata_captured</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.rvalid_counter</expr>
    <label/>
    <radix/>
  </wave>
  <spacer/>
  <group collapsed="true">
    <expr/>
    <label>ar_hsk</label>
    <wave>
      <expr>sva.translation_req.ar_hsk</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.id</expr>
      <label/>
      <radix>dec</radix>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.addr</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.size</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.len</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.cache</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.region</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.ar.qos</expr>
      <label/>
      <radix/>
    </wave>
  </group>
  <spacer/>
  <group collapsed="true">
    <expr/>
    <label>r_hsk</label>
    <wave>
      <expr>sva.translation_req.r_hsk</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>sva.translation_req.dev_tr_req_i.r_ready</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>sva.translation_req.dev_tr_resp_o.r_valid</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.dev_tr_resp_o.r.id</expr>
      <label/>
      <radix>dec</radix>
    </wave>
    <wave collapsed="true">
      <expr>sva.dev_tr_resp_o.r.data</expr>
      <label/>
      <radix/>
    </wave>
  </group>
  <spacer/>
  <group collapsed="true">
    <expr/>
    <label>aw_hsk</label>
    <wave>
      <expr>sva.translation_req.aw_hsk</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.id</expr>
      <label/>
      <radix>dec</radix>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.addr</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.size</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.len</expr>
      <label/>
      <radix>dec</radix>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.cache</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>sva.translation_req.dev_tr_req_i.aw.lock</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.aw.prot</expr>
      <label/>
      <radix/>
    </wave>
  </group>
  <spacer/>
  <spacer/>
  <group collapsed="true">
    <expr/>
    <label>w_hsk</label>
    <wave>
      <expr>sva.translation_req.w_hsk</expr>
      <label/>
      <radix/>
    </wave>
    <wave collapsed="true">
      <expr>sva.translation_req.dev_tr_req_i.w.data</expr>
      <label/>
      <radix/>
    </wave>
  </group>
  <spacer/>
  <spacer/>
  <wave collapsed="true">
    <expr>sva.translation_req.capture_id</expr>
    <label/>
    <radix>dec</radix>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.capture_addr</expr>
    <label/>
    <radix/>
  </wave>
  <spacer/>
  <wave>
    <expr>sva.translation_req.b_hsk</expr>
    <label/>
    <radix/>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.dev_tr_resp_o.b.id</expr>
    <label/>
    <radix>dec</radix>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.resp_counter</expr>
    <label/>
    <radix>dec</radix>
  </wave>
  <highlightlist>
    <!--Users can remove the highlightlist block if they want to load the signal save file into older version of JasperGold-->
    <highlight>
      <expr>sva.programming_interface_axi.prog_resp_o.r.last</expr>
      <color>builtin_red</color>
    </highlight>
  </highlightlist>
</wavelist>
