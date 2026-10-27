"""Focused regression for the build-log checker; no FPGA tools or board access."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

EXPERIMENT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("v11_build", EXPERIMENT / "build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildLogTests(unittest.TestCase):
    def test_pds_memory_errors(self):
        log = "E: Memory alloc failed for size 1048512.\n  E: second failure"
        self.assertEqual(build.fatal_log_lines(log), log.splitlines())

    def test_existing_error_formats(self):
        lines = ["ERROR: failed", "Error: failed", "FATAL: failed",
                 "Fatal: failed", "prefix Error: failed"]
        self.assertEqual(build.fatal_log_lines("\n".join(lines)), lines)

    def test_windows_path_and_nonfatal_lines(self):
        log = "E:/work/design.v\nW: warning\nC: comment\nI: complete"
        self.assertEqual(build.fatal_log_lines(log), [])

    def test_historical_failure_is_detected_without_rewrite(self):
        run = EXPERIMENT / "builds/20261018_114715_310_rule_test"
        lines = build.fatal_log_lines((run / "build.log").read_text(
            encoding="utf-8", errors="replace"))
        self.assertEqual(len(lines), 2)
        self.assertTrue(all("Memory alloc failed" in line for line in lines))

    def test_upstream_manifest_detects_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            for name in ("compile", "synthesize", "device_map"):
                (run / name).mkdir()
                (run / name / "sample.db").write_bytes(b"checkpoint")
            before = build.upstream_manifest(run)
            self.assertEqual(len(before), 3)
            self.assertEqual(before, build.upstream_manifest(run))
            (run / "device_map/sample.db").write_bytes(b"changed")
            self.assertNotEqual(before, build.upstream_manifest(run))

    def test_explicit_db_scripts_have_no_upstream_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory)
            for name in (f"{build.TOP}.prr", f"{build.TOP}_pnr.adf",
                         "place_route.log"):
                (run / name).write_bytes(b"fixture")
            build.collect_pnr(run)
            for name, action in (("timing_only", "report_timing"),
                                 ("bitstream_only", "gen_bit_stream")):
                script = (run / f"{name}.tcl").read_text()
                commands = [line.split()[0] for line in script.splitlines()
                            if line and not line.startswith("#")]
                self.assertEqual(commands, ["set_arch", action])
                self.assertIn("-input_db_file", script)
                self.assertIn("-force_to_run", script)


if __name__ == "__main__":
    unittest.main()
