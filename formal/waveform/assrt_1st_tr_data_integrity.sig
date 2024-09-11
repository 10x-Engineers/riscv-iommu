<?xml version="1.0" encoding="UTF-8"?>
<wavelist version="3">
  <insertion-point-position>3</insertion-point-position>
  <wave>
    <expr>clk_i</expr>
    <label/>
    <radix/>
  </wave>
  <spacer/>
  <wave collapsed="true">
    <expr>sva.translation_req.symbolic_id</expr>
    <label/>
    <radix>dec</radix>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.resp_counter</expr>
    <label/>
    <radix>dec</radix>
  </wave>
  <spacer/>
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
    <expr>sva.translation_req.dev_tr_req_i.aw.burst</expr>
    <label/>
    <radix/>
  </wave>
  <wave>
    <expr>sva.translation_req.aw_hsk</expr>
    <label/>
    <radix/>
  </wave>
  <spacer/>
  <wave>
    <expr>sva.translation_req.b_hsk</expr>
    <label/>
    <radix/>
    <wave>
      <expr>sva.translation_req.dev_tr_req_i.b_ready</expr>
      <label/>
      <radix/>
    </wave>
    <wave>
      <expr>sva.translation_req.dev_tr_resp_o.b_valid</expr>
      <label/>
      <radix/>
    </wave>
  </wave>
  <wave collapsed="true">
    <expr>sva.translation_req.dev_tr_resp_o.b.id</expr>
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
