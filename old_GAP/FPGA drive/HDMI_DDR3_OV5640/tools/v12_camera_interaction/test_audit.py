"""Small release-gate checks; no FPGA tools, simulations or board operations."""
import importlib.util
import re
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "v12_continue", Path(__file__).with_name("continue.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ConstraintPreparationTests(unittest.TestCase):
    def test_collection_accepts_both_pds_output_layouts(self):
        for nested in (False, True):
            with self.subTest(nested=nested), tempfile.TemporaryDirectory() as directory:
                run = Path(directory)
                output = run / "place_route" if nested else run
                output.mkdir(exist_ok=True)
                for suffix in (".prr", "_pnr.adf"):
                    (output / (helper.TOP + suffix)).write_bytes(b"fixture")
                helper.collect(run)
                self.assertEqual(
                    (run / "place_route" / (helper.TOP + "_pnr.adf")).read_bytes(),
                    b"fixture")
                self.assertIn("report_timing", (run / "timing_only.tcl").read_text())

    def test_hold_resume_is_routing_only_with_positive_margin(self):
        command = helper.hold_command()
        self.assertTrue(command.startswith("pnr "))
        self.assertIn("-input_place_db_file", command)
        self.assertIn("-fix_hold_violation_threshold 50", command)
        self.assertIn("-optimize_multi_corner_timing", command)
        self.assertNotRegex(command, r"\b(compile|synthesize|dev_map)\b")
        self.assertNotIn("false_path", command)

    def test_replace_requires_unique_anchor(self):
        with self.assertRaises(RuntimeError):
            helper.replace_once("none", "clock", "")
        with self.assertRaises(RuntimeError):
            helper.replace_once("clock clock", "clock", "")
        self.assertEqual(helper.replace_once("clock rest", "clock", "# removed"), "# removed rest")

    def test_old_failed_report_is_not_bundle_evidence(self):
        report = (helper.PREVIOUS / "report_timing/hdmi_ddr_ov5640_top.rtr").read_text()
        self.assertIn("Design Summary : All Constraints Met.", report)
        self.assertNotRegex(report, r"Startpoint\s*:\s*u_lane_local_ui[^\n]*held")

    def test_candidate_camera_mode_and_shared_reset(self):
        top = (helper.PREVIOUS / "source/rtl/hdmi_ddr_ov5640_top.v").read_text()
        self.assertRegex(top, r"parameter LOCAL_RULE_TEST\s*=\s*0")
        self.assertIn(".reset_n(rstn_out && ddr_init_done && img_rstn)", top)

    def test_accepted_v11_binary_is_unchanged(self):
        bit = helper.V11 / "builds/20261018_130743_866_resume_pnr/bitstreams/11_lane_interaction_rule_test_cmos1.sbit"
        self.assertEqual(helper.sha(bit),
                         "9c21a93bee132ed1513810b29c820309387a5b73a84de41f6851bddc22e0c442")


if __name__ == "__main__":
    unittest.main()
