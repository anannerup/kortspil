"""The es-makker engine in Python, kept equal to the Ruby engine
(app/models/esmakker) by a parity check, for self-play training."""

import os

# numpy's OpenBLAS commits ~30 MB per CPU thread for its buffers when numpy is
# imported (~600 MB on 20 threads, measured), in every process: the learner,
# each actor, the inference server, the rating. Nothing here does BLAS work
# in numpy (torch has its own), so one thread. Set before numpy is imported.
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

from .engine import IllegalAction, Round  # noqa: E402
from .rules import Points, Rules  # noqa: E402

__all__ = ["IllegalAction", "Points", "Round", "Rules"]
