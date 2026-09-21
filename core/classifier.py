"""
Piece Occupancy and Classification Module for Chess Scanner.
Analyzes each square patch to detect piece presence, color, and piece candidates
along with per-square confidence scores for the calibration UI.
"""

from dataclasses import dataclass
from typing import List, Optional, Tuple
import cv2
import numpy as np


@dataclass
class SquarePrediction:
    row: int          # 0 to 7 (0 = 8th rank, 7 = 1st rank)
    col: int          # 0 to 7 (0 = a-file, 7 = h-file)
    square_name: str  # e.g. "e4"
    piece: Optional[str]  # "P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k", or None
    confidence: float # 0.0 to 1.0
    is_ambiguous: bool # True if confidence < threshold
    is_occupied: bool
    piece_color: Optional[str] # "white", "black", or None


class PieceClassifier:
    """Classifies individual chess square patches and assigns confidence ratings."""

    FILES = ["a", "b", "c", "d", "e", "f", "g", "h"]
    RANKS = ["8", "7", "6", "5", "4", "3", "2", "1"]

    def __init__(self, confidence_threshold: float = 0.85):
        self.confidence_threshold = confidence_threshold

    @classmethod
    def get_square_name(cls, row: int, col: int) -> str:
        return f"{cls.FILES[col]}{cls.RANKS[row]}"

    def analyze_square(self, square_img: np.ndarray, row: int, col: int) -> SquarePrediction:
        """
        Analyzes a single 100x100 square patch.
        Uses inner central crop (60x60) to avoid edge boundary lines of neighboring squares.
        """
        h, w = square_img.shape[:2]
        pad_y = int(h * 0.18)
        pad_x = int(w * 0.18)
        inner = square_img[pad_y:h - pad_y, pad_x:w - pad_x]

        gray = cv2.cvtColor(inner, cv2.COLOR_BGR2GRAY)
        sq_name = self.get_square_name(row, col)

        # Measure variance and edge energy inside the square
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        std_dev = float(np.std(gray))
        mean_val = float(np.mean(gray))

        # Check square color based on chessboard geometry: (row + col) % 2 == 0 is light square
        is_light_square = ((row + col) % 2 == 0)

        # Occupancy heuristic: pieces have complex textures, edges, and high contrast against square
        # An empty square has uniform color (low std dev and low laplacian variance)
        is_occupied = (laplacian_var > 65.0) or (std_dev > 28.0)

        if not is_occupied:
            # High confidence empty square
            confidence = min(1.0, max(0.85, 1.0 - (laplacian_var / 150.0)))
            return SquarePrediction(
                row=row,
                col=col,
                square_name=sq_name,
                piece=None,
                confidence=float(confidence),
                is_ambiguous=confidence < self.confidence_threshold,
                is_occupied=False,
                piece_color=None
            )

        # Square is occupied: determine color (White vs Black)
        # We compare center luminance against the expected background
        # White pieces typically have higher brightness than black pieces
        # In grayscale: white pieces usually > 130, black pieces usually < 95
        if mean_val > 120:
            piece_color = "white"
        else:
            piece_color = "black"

        # Determine piece type heuristic based on typical starting rank setup and edge structure
        # Rank 0 (8th): Black back rank
        # Rank 1 (7th): Black pawns
        # Rank 6 (2nd): White pawns
        # Rank 7 (1st): White back rank
        predicted_piece = self._guess_piece_type(row, col, piece_color, laplacian_var, std_dev)

        # Compute confidence score
        # Edge cases near threshold get lower confidence (flagged for calibration)
        if 50.0 < laplacian_var < 80.0 or 25.0 < std_dev < 33.0:
            confidence = 0.65  # Ambiguous, trigger calibration highlight
        else:
            confidence = 0.92

        return SquarePrediction(
            row=row,
            col=col,
            square_name=sq_name,
            piece=predicted_piece,
            confidence=float(confidence),
            is_ambiguous=confidence < self.confidence_threshold,
            is_occupied=True,
            piece_color=piece_color
        )

    def _guess_piece_type(self, row: int, col: int, color: str, laplacian: float, std_dev: float) -> str:
        """Initial piece type guess using positional heuristics and contour characteristics."""
        back_rank_pieces = ["R", "N", "B", "Q", "K", "B", "N", "R"]

        if color == "white":
            if row == 6:
                return "P"
            elif row == 7:
                return back_rank_pieces[col]
            else:
                # Mid-board piece: default to Pawn or Knight/Bishop based on texture
                return "N" if laplacian > 150 else "P"
        else:
            if row == 1:
                return "p"
            elif row == 0:
                return back_rank_pieces[col].lower()
            else:
                return "n" if laplacian > 150 else "p"

    def classify_board(self, square_grid: List[List[np.ndarray]]) -> List[List[SquarePrediction]]:
        """Classifies all 64 squares of the board."""
        results = []
        for r in range(8):
            row_preds = []
            for c in range(8):
                pred = self.analyze_square(square_grid[r][c], r, c)
                row_preds.append(pred)
            results.append(row_preds)
        return results
