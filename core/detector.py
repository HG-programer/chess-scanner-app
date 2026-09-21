"""
Board Corner Detection and Perspective Warping Module for Chess Scanner.
Detects physical chessboards from photos and warps them into a normalized top-down 8x8 grid.
"""

from typing import List, Optional, Tuple
import cv2
import numpy as np


class BoardDetector:
    """Detects chess boards in camera images and produces normalized 800x800 grids."""

    def __init__(self, target_size: int = 800):
        self.target_size = target_size

    def order_points(self, pts: np.ndarray) -> np.ndarray:
        """
        Orders coordinates: top-left, top-right, bottom-right, bottom-left.
        pts shape: (4, 2)
        """
        rect = np.zeros((4, 2), dtype="float32")
        s = pts.sum(axis=1)
        rect[0] = pts[np.argmin(s)]  # Top-left has smallest sum
        rect[2] = pts[np.argmax(s)]  # Bottom-right has largest sum

        diff = np.diff(pts, axis=1)
        rect[1] = pts[np.argmin(diff)]  # Top-right has smallest diff
        rect[3] = pts[np.argmax(diff)]  # Bottom-left has largest diff
        return rect

    def find_board_corners(self, image: np.ndarray) -> Optional[np.ndarray]:
        """
        Attempts to detect the 4 corners of the chessboard.
        Returns array of shape (4, 2) or None if not found.
        """
        h, w = image.shape[:2]
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)

        # Adaptive thresholding to isolate grid lines & square boundaries
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 11, 2
        )

        # Dilate slightly to connect broken lines
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
        dilated = cv2.dilate(thresh, kernel, iterations=1)

        contours, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        contours = sorted(contours, key=cv2.contourArea, reverse=True)[:10]

        img_area = h * w

        for cnt in contours:
            area = cv2.contourArea(cnt)
            # Board must occupy at least 15% of the total image area
            if area < img_area * 0.15:
                continue

            peri = cv2.arcLength(cnt, True)
            approx = cv2.approxPolyDP(cnt, 0.03 * peri, True)

            if len(approx) == 4:
                pts = approx.reshape(4, 2).astype("float32")
                return self.order_points(pts)

        # Fallback: if no strict 4-sided contour found, use convex hull of the largest contour
        if contours:
            hull = cv2.convexHull(contours[0])
            peri = cv2.arcLength(hull, True)
            approx = cv2.approxPolyDP(hull, 0.04 * peri, True)
            if len(approx) == 4:
                pts = approx.reshape(4, 2).astype("float32")
                return self.order_points(pts)

        return None

    def warp_board(self, image: np.ndarray, corners: Optional[np.ndarray] = None) -> Tuple[np.ndarray, np.ndarray]:
        """
        Warps the perspective of the detected board to a flat target_size x target_size image.
        If corners is None, automatically detects them, or defaults to a central square crop.
        """
        h, w = image.shape[:2]
        if corners is None:
            corners = self.find_board_corners(image)

        if corners is None:
            # Fallback to central 80% box
            margin_x = int(w * 0.1)
            margin_y = int(h * 0.1)
            corners = np.array([
                [margin_x, margin_y],
                [w - margin_x, margin_y],
                [w - margin_x, h - margin_y],
                [margin_x, h - margin_y]
            ], dtype="float32")

        dst = np.array([
            [0, 0],
            [self.target_size - 1, 0],
            [self.target_size - 1, self.target_size - 1],
            [0, self.target_size - 1]
        ], dtype="float32")

        matrix = cv2.getPerspectiveTransform(corners, dst)
        warped = cv2.warpPerspective(image, matrix, (self.target_size, self.target_size))
        return warped, corners

    def slice_squares(self, warped: np.ndarray) -> List[List[np.ndarray]]:
        """
        Slices the warped 800x800 board into an 8x8 grid of 100x100 square patches.
        Returns grid[row][col], where:
        row 0 = rank 8 (Black side by default), row 7 = rank 1 (White side)
        col 0 = file a, col 7 = file h.
        """
        sq_size = self.target_size // 8
        grid = []
        for r in range(8):
            row_squares = []
            for c in range(8):
                y1 = r * sq_size
                y2 = (r + 1) * sq_size
                x1 = c * sq_size
                x2 = (c + 1) * sq_size
                square_patch = warped[y1:y2, x1:x2]
                row_squares.append(square_patch)
            grid.append(row_squares)
        return grid
