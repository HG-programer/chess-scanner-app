"""
Synthetic Chess Board Image Generator for Testing and Benchmarking.
Generates realistic 2D and perspective-skewed 3D board images with pieces.
"""

import os
from typing import Dict, Optional, Tuple
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


class BoardImageGenerator:
    """Generates synthetic chess board images for testing detector, classifier, and FEN builder."""

    LIGHT_SQ = (238, 238, 210)  # Light wood / lichess cream
    DARK_SQ = (118, 150, 86)    # Dark wood / lichess green

    # Unicode glyphs for pieces
    GLYPHS: Dict[str, str] = {
        "K": "♔", "Q": "♕", "R": "♖", "B": "♗", "N": "♘", "P": "♙",
        "k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟"
    }

    @classmethod
    def generate_board(
        cls,
        fen_placement: str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
        size: int = 800,
        skew_perspective: bool = False
    ) -> np.ndarray:
        """
        Creates a clean 800x800 image of the given FEN piece placement.
        If skew_perspective is True, embeds the board on a background with 3D angle.
        """
        img = Image.new("RGB", (size, size), color=(255, 255, 255))
        draw = ImageDraw.Draw(img)
        sq_size = size // 8

        # Draw squares
        for r in range(8):
            for c in range(8):
                color = cls.LIGHT_SQ if (r + c) % 2 == 0 else cls.DARK_SQ
                x1 = c * sq_size
                y1 = r * sq_size
                x2 = x1 + sq_size
                y2 = y1 + sq_size
                draw.rectangle([x1, y1, x2, y2], fill=color)

        # Parse FEN rows and draw pieces
        ranks = fen_placement.split("/")
        for r, rank_str in enumerate(ranks):
            c = 0
            for char in rank_str:
                if char.isdigit():
                    c += int(char)
                else:
                    glyph = cls.GLYPHS.get(char, char)
                    x = c * sq_size + (sq_size // 4)
                    y = r * sq_size + (sq_size // 8)
                    # Draw piece symbol
                    draw.text((x, y), glyph, fill=(20, 20, 20) if char.islower() else (240, 240, 240))
                    c += 1

        board_np = np.array(img)
        # Convert RGB to BGR for OpenCV
        board_bgr = cv2.cvtColor(board_np, cv2.COLOR_RGB2BGR)

        if not skew_perspective:
            return board_bgr

        # Embed into a 1200x1000 tabletop canvas with 4-corner perspective warp
        canvas_h, canvas_w = 1000, 1200
        canvas = np.full((canvas_h, canvas_w, 3), 45, dtype=np.uint8)  # Dark table

        src_pts = np.array([
            [0, 0],
            [size - 1, 0],
            [size - 1, size - 1],
            [0, size - 1]
        ], dtype="float32")

        # Angled quad corners on table
        dst_pts = np.array([
            [260, 180],
            [940, 160],
            [1080, 840],
            [120, 860]
        ], dtype="float32")

        matrix = cv2.getPerspectiveTransform(src_pts, dst_pts)
        warped = cv2.warpPerspective(board_bgr, matrix, (canvas_w, canvas_h))

        # Composite onto canvas
        mask = np.zeros((canvas_h, canvas_w), dtype=np.uint8)
        cv2.fillConvexPoly(mask, dst_pts.astype(np.int32), 255)
        canvas[mask > 0] = warped[mask > 0]

        return canvas


if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(__file__))
    os.makedirs(out_dir, exist_ok=True)
    flat_board = BoardImageGenerator.generate_board()
    skewed_board = BoardImageGenerator.generate_board(skew_perspective=True)
    cv2.imwrite(os.path.join(out_dir, "flat_sample.png"), flat_board)
    cv2.imwrite(os.path.join(out_dir, "skewed_sample.png"), skewed_board)
    print("Generated sample boards successfully.")
