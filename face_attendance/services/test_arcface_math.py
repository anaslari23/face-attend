import importlib.util
import pathlib
import unittest

import numpy as np


_path = pathlib.Path(__file__).with_name("arcface.py")
_spec = importlib.util.spec_from_file_location("arcface", _path)
_arcface = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_arcface)


class SimilarityTransformTest(unittest.TestCase):
    def test_identity_for_arcface_template(self):
        points = np.asarray(_arcface._DESTINATION, dtype=np.float32)
        matrix = _arcface._similarity_transform(points, np)
        np.testing.assert_allclose(matrix, ((1, 0, 0), (0, 1, 0)), atol=1e-5)


if __name__ == "__main__":
    unittest.main()
