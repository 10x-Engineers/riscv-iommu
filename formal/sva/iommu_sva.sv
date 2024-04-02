module iommu_sva #(
    // Number of IOTLB entries
    parameter int unsigned  IOTLB_ENTRIES       = 4,
    // Number of DDTC entries
    parameter int unsigned  DDTC_ENTRIES        = 4,
    // Number of PDTC entries
    parameter int unsigned  PDTC_ENTRIES        = 4,
    // Number of MRIF cache entries (if supported)
    parameter int unsigned  MRIFC_ENTRIES       = 4,

    // Include process_id support
    parameter bit                   InclPC      = 0,
    // Include AXI4 address boundary check
    parameter bit                   InclBC      = 0,
    // Include debug register interface
    parameter bit                   InclDBG     = 0,
    
    // MSI translation support
    parameter rv_iommu::msi_trans_t MSITrans    = rv_iommu::MSI_DISABLED,
    // Interrupt Generation Support
    parameter rv_iommu::igs_t       IGS         = rv_iommu::WSI_ONLY,
    // Number of interrupt vectors supported
    parameter int unsigned      N_INT_VEC       = 16,
    // Number of Performance monitoring event counters (set to zero to disable HPM)
    parameter int unsigned      N_IOHPMCTR      = 0,     // max 31

    /// AXI Bus Addr width.
    parameter int   ADDR_WIDTH      = -1,
    /// AXI Bus data width.
    parameter int   DATA_WIDTH      = -1,
    /// AXI ID width
    parameter int   ID_WIDTH        = -1,
    /// AXI ID width
    parameter int   ID_SLV_WIDTH    = -1,
    /// AXI user width
    parameter int   USER_WIDTH      = 1,
    /// AXI AW Channel struct type
    parameter type aw_chan_t        = logic,
    /// AXI W Channel struct type
    parameter type w_chan_t         = logic,
    /// AXI B Channel struct type
    parameter type b_chan_t         = logic,
    /// AXI AR Channel struct type
    parameter type ar_chan_t        = logic,
    /// AXI R Channel struct type
    parameter type r_chan_t         = logic,
    /// AXI Full request struct type
    parameter type  axi_req_t       = logic,
    /// AXI Full response struct type
    parameter type  axi_rsp_t       = logic,
    /// AXI Full Slave request struct type
    parameter type  axi_req_slv_t   = logic,
    /// AXI Full Slave response struct type
    parameter type  axi_rsp_slv_t   = logic,
    /// AXI Full request struct type w/ DVM extension for SMMU
    parameter type  axi_req_iommu_t = logic,
    /// Regbus request struct type.
    parameter type  reg_req_t       = logic,
    /// Regbus response struct type.
    parameter type  reg_rsp_t       = logic
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Translation Request Interface (Slave)
    input  axi_req_iommu_t  dev_tr_req_i,
    input axi_rsp_t        dev_tr_resp_o,

    // Translation Completion Interface (Master)
    input  axi_rsp_t        dev_comp_resp_i,
    input axi_req_t        dev_comp_req_o,

    // Data Structures Interface (Master)
    input  axi_rsp_t        ds_resp_i,
    input axi_req_t        ds_req_o,

    // Programming Interface (Slave) (AXI4 + ATOP => Reg IF)
    input  axi_req_slv_t    prog_req_i,
    input axi_rsp_slv_t    prog_resp_o,

    input logic [(N_INT_VEC-1):0] wsi_wires_o
);










endmodule