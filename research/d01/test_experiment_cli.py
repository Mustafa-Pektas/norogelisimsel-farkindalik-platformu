"""Packaging checks only: no media decode, model load, filtering or GUI."""
import contextlib
import io
from pathlib import Path
import runpy
import sys
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SCRIPTS = ('roi_review.py', 'infer_c_cpu.py', 'smooth_rotations.py')

class PackagingTests(unittest.TestCase):
    def test_help_does_not_create_output_or_start_work(self):
        for name in SCRIPTS:
            with self.subTest(name=name), patch.object(sys, 'argv', [name, '--help']), \
                    patch.object(Path, 'mkdir') as mkdir, contextlib.redirect_stdout(io.StringIO()) as output:
                with self.assertRaises(SystemExit) as result:
                    runpy.run_path(str(HERE/name), run_name='__packaging_check__')
                self.assertEqual(result.exception.code, 0)
                self.assertIn('--data-root', output.getvalue())
                self.assertIn('--output-dir', output.getvalue())
                mkdir.assert_not_called()

    def test_experiment_outputs_cannot_be_written_inside_checkout(self):
        repo = HERE.parents[1]
        for name in SCRIPTS:
            with self.subTest(name=name), patch.object(sys, 'argv', [name,
                    '--data-root', str(repo.parent), '--output-dir', str(repo/'forbidden-output')]), \
                    patch.object(Path, 'mkdir') as mkdir:
                with self.assertRaisesRegex(ValueError, 'outside the Git checkout'):
                    runpy.run_path(str(HERE/name), run_name='__packaging_check__')
                mkdir.assert_not_called()

if __name__ == '__main__': unittest.main()
