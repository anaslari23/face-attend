import numpy as np

from .repository import EmployeeEmbedding


def cosine_similarity(left: np.ndarray, right: np.ndarray) -> float:
    length = min(left.shape[0], right.shape[0])
    if length == 0:
        return 0.0
    a = left[:length]
    b = right[:length]
    denominator = float(np.linalg.norm(a) * np.linalg.norm(b))
    if denominator == 0:
        return 0.0
    return float(np.dot(a, b) / denominator)


def best_match(query: np.ndarray, candidates: list[EmployeeEmbedding]) -> tuple[EmployeeEmbedding | None, float]:
    winner = None
    winner_score = -1.0
    for candidate in candidates:
        score = cosine_similarity(query, candidate.embedding)
        if score > winner_score:
            winner = candidate
            winner_score = score
    return winner, winner_score
