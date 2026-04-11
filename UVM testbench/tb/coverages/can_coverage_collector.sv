`ifndef CAN_COVERAGE_COLLECTOR_SV
`define CAN_COVERAGE_COLLECTOR_SV

`include "uvm_macros.svh"
import uvm_pkg::*;
import can_pkg::*;

// ============================================================
// CAN Functional Coverage Collector
// Subscribes to monitor analysis port and samples covergroups
// ============================================================

class can_coverage_collector extends uvm_subscriber #(can_transaction);
  `uvm_component_utils(can_coverage_collector)

  // ============================================================
  // CG1: Frame Type x Format Coverage
  // Samples ALL frame types including ERROR and OVERLOAD
  // ============================================================
  covergroup cg_frame_format;

    cp_fmt : coverpoint tr.can_fmt {
      bins std_frame = {`CAN_ID_STD};
      bins ext_frame = {`CAN_ID_EXT};
    }

    cp_ftype : coverpoint tr.f_type {
      bins data_frame     = {`CAN_DATA_FRAME};
      bins remote_frame   = {`CAN_REMOTE_FRAME};
      bins error_frame    = {`CAN_ERROR_FRAME};
      bins overload_frame = {`CAN_OVERLOAD_FRAME};
    }

    // Cross: format x frame type (DATA and REMOTE only — errors don't have format)
    cp_ftype_x_fmt : cross cp_fmt, cp_ftype {
      bins std_data    = binsof(cp_fmt.std_frame) && binsof(cp_ftype.data_frame);
      bins std_remote  = binsof(cp_fmt.std_frame) && binsof(cp_ftype.remote_frame);
      bins ext_data    = binsof(cp_fmt.ext_frame) && binsof(cp_ftype.data_frame);
      bins ext_remote  = binsof(cp_fmt.ext_frame) && binsof(cp_ftype.remote_frame);
      ignore_bins error_fmt    = binsof(cp_ftype.error_frame);
      ignore_bins overload_fmt = binsof(cp_ftype.overload_frame);
    }
  endgroup

  // ============================================================
  // CG2: DLC Coverage
  // All valid DLC values 0-8 in both STD and EXT formats
  // ============================================================
  covergroup cg_dlc;
    cp_dlc : coverpoint tr.dlc {
      bins dlc_0 = {0};
      bins dlc_1 = {1};
      bins dlc_2 = {2};
      bins dlc_3 = {3};
      bins dlc_4 = {4};
      bins dlc_5 = {5};
      bins dlc_6 = {6};
      bins dlc_7 = {7};
      bins dlc_8 = {8};
    }

    cp_fmt : coverpoint tr.can_fmt {
      bins std_frame = {`CAN_ID_STD};
      bins ext_frame = {`CAN_ID_EXT};
    }

    // Cross: DLC x format
    cp_dlc_x_fmt : cross cp_dlc, cp_fmt;
  endgroup

  // ============================================================
  // CG3: ID Boundary Coverage
  // Min/max IDs for both STD and EXT formats
  // ============================================================
  covergroup cg_id_boundary;

    cp_std_id : coverpoint tr.id[10:0] {
      option.auto_bin_max = 0;
      bins id_min  = {11'h000};
      bins id_max  = {11'h7FF};
      bins id_low  = {[11'h001:11'h0FF]};
      bins id_mid  = {[11'h100:11'h6FF]};
      bins id_high = {[11'h700:11'h7FE]};
    }

    cp_ext_id : coverpoint tr.id[28:11] {
      option.auto_bin_max = 0;
      bins id_min  = {18'h00000};
      bins id_max  = {18'h3FFFF};
      bins id_low  = {[18'h00001:18'h0FFFF]};
      bins id_high = {[18'h10000:18'h3FFFE]};
    }

    cp_fmt : coverpoint tr.can_fmt {
      bins std_frame = {`CAN_ID_STD};
      bins ext_frame = {`CAN_ID_EXT};
    }
  endgroup

  // ============================================================
  // CG4: Error Type Coverage
  // All error types injected and observed
  // ============================================================
  covergroup cg_error_type;

    cp_crc_err   : coverpoint tr.crc_error_seen   {
      bins crc_error   = {1};
      bins no_crc_err  = {0};
    }

    cp_form_err  : coverpoint tr.form_error_seen  {
      bins form_error  = {1};
      bins no_form_err = {0};
    }

    cp_stuff_err : coverpoint tr.stuff_error_seen {
      bins stuff_error  = {1};
      bins no_stuff_err = {0};
    }

    cp_ack : coverpoint tr.ack_seen {
      bins ack_present = {1};
      bins ack_missing = {0};
    }

    // Error combinations
    cp_err_combo : cross cp_crc_err, cp_form_err, cp_stuff_err {
      bins crc_only   = binsof(cp_crc_err.crc_error)   &&
                        binsof(cp_form_err.no_form_err) &&
                        binsof(cp_stuff_err.no_stuff_err);
      bins form_only  = binsof(cp_crc_err.no_crc_err)  &&
                        binsof(cp_form_err.form_error)  &&
                        binsof(cp_stuff_err.no_stuff_err);
      bins stuff_only = binsof(cp_crc_err.no_crc_err)  &&
                        binsof(cp_form_err.no_form_err) &&
                        binsof(cp_stuff_err.stuff_error);
      bins no_error   = binsof(cp_crc_err.no_crc_err)  &&
                        binsof(cp_form_err.no_form_err) &&
                        binsof(cp_stuff_err.no_stuff_err);
    }
  endgroup

  // ============================================================
  // CG5: Format x Error Cross Coverage
  // Errors tested in both STD and EXT frames
  // ============================================================
  covergroup cg_format_x_error;

    cp_fmt : coverpoint tr.can_fmt {
      bins std_frame = {`CAN_ID_STD};
      bins ext_frame = {`CAN_ID_EXT};
    }

    cp_any_error : coverpoint (tr.crc_error_seen |
                               tr.form_error_seen |
                               tr.stuff_error_seen) {
      bins error_present = {1};
      bins error_absent  = {0};
    }

    cp_fmt_x_err : cross cp_fmt, cp_any_error;
  endgroup

  // ============================================================
  // CG6: DLC x Error Cross Coverage
  // Errors tested across DLC ranges
  // ============================================================
  covergroup cg_dlc_x_error;

    cp_dlc : coverpoint tr.dlc {
      bins dlc_zero  = {0};
      bins dlc_short = {[1:3]};
      bins dlc_mid   = {[4:6]};
      bins dlc_max   = {[7:8]};
    }

    cp_any_error : coverpoint (tr.crc_error_seen |
                               tr.form_error_seen |
                               tr.stuff_error_seen) {
      bins error_present = {1};
      bins error_absent  = {0};
    }

    cp_dlc_x_err : cross cp_dlc, cp_any_error;
  endgroup

  // Transaction handle — updated in write()
  can_transaction tr;

  function new(string name="can_coverage_collector", uvm_component parent=null);
    super.new(name, parent);
    cg_frame_format   = new();
    cg_dlc            = new();
    cg_id_boundary    = new();
    cg_error_type     = new();
    cg_format_x_error = new();
    cg_dlc_x_error    = new();
  endfunction

  // Called by UVM analysis port on every observed transaction
  function void write(can_transaction t);
    tr = t;

    // Sample frame type and format for ALL frames including error/overload
    cg_frame_format.sample();

    // Sample remaining covergroups only for valid DATA/REMOTE frames
    if (tr.f_type == `CAN_DATA_FRAME || tr.f_type == `CAN_REMOTE_FRAME) begin
      cg_dlc.sample();
      cg_id_boundary.sample();
      cg_error_type.sample();
      cg_format_x_error.sample();
      cg_dlc_x_error.sample();
    end
  endfunction

  // Print coverage summary at end of simulation
  function void report_phase(uvm_phase phase);
    `uvm_info("COV",
      $sformatf("\n=== FUNCTIONAL COVERAGE SUMMARY ===\n  Frame Type/Format: %0.1f%%\n  DLC:               %0.1f%%\n  ID Boundary:       %0.1f%%\n  Error Type:        %0.1f%%\n  Format x Error:    %0.1f%%\n  DLC x Error:       %0.1f%%\n===================================",
        cg_frame_format.get_coverage(),
        cg_dlc.get_coverage(),
        cg_id_boundary.get_coverage(),
        cg_error_type.get_coverage(),
        cg_format_x_error.get_coverage(),
        cg_dlc_x_error.get_coverage()),
      UVM_LOW)
  endfunction

endclass

`endif // CAN_COVERAGE_COLLECTOR_SV