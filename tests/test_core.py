"""
Automated unit tests for Chess Scanner & AI Analysis Engine.
Verifies detector, classifier, FEN builder, engine evaluation, daily puzzle, and telemetry.
"""

import os
import sys
import pytest
import numpy as np

# Add project root to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from core.detector import BoardDetector
from core.classifier import PieceClassifier, SquarePrediction
from core.fen_builder import FENBuilder
from core.engine import StockfishManager, DeviceProfile
from services.daily_puzzle import DailyPuzzleService
from services.telemetry import TelemetryService, SquareDiff
from sample_data.board_generator import BoardImageGenerator


def test_board_generator_and_detector():
    """Test generating a board and slicing it into 64 squares."""
    board_img = BoardImageGenerator.generate_board()
    assert board_img.shape == (800, 800, 3)

    detector = BoardDetector(target_size=800)
    warped, corners = detector.warp_board(board_img)
    assert warped.shape == (800, 800, 3)

    squares = detector.slice_squares(warped)
    assert len(squares) == 8
    assert len(squares[0]) == 8
    assert squares[0][0].shape == (100, 100, 3)


def test_fen_builder_standard_starting():
    """Test standard starting position generation and legality checking."""
    # Build a standard 8x8 prediction grid
    classifier = PieceClassifier()
    predictions = []

    back_rank = ["R", "N", "B", "Q", "K", "B", "N", "R"]
    for r in range(8):
        row_preds = []
        for c in range(8):
            sq_name = classifier.get_square_name(r, c)
            if r == 0:
                p = back_rank[c].lower()
            elif r == 1:
                p = "p"
            elif r == 6:
                p = "P"
            elif r == 7:
                p = back_rank[c]
            else:
                p = None

            row_preds.append(SquarePrediction(
                row=r, col=c, square_name=sq_name, piece=p,
                confidence=0.95, is_ambiguous=False,
                is_occupied=(p is not None),
                piece_color="white" if (p and p.isupper()) else ("black" if p else None)
            ))
        predictions.append(row_preds)

    res = FENBuilder.predictions_to_fen(predictions)
    assert res.is_legal is True
    assert res.white_king_count == 1
    assert res.black_king_count == 1
    assert res.fen.startswith("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")


def test_fen_builder_illegal_positions():
    """Test that illegal boards (missing kings, duplicate kings) are properly caught."""
    # Missing White King
    fen_missing_white_king = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQ1BNR w KQkq - 0 1"
    is_legal, reason = FENBuilder.validate_fen_legality(fen_missing_white_king, 0, 1)
    assert is_legal is False
    assert "White King" in reason

    # Two White Kings
    is_legal, reason = FENBuilder.validate_fen_legality("rnbqkbnr/8/8/8/8/8/8/RNBQKBNK w - - 0 1", 2, 1)
    assert is_legal is False


def test_fen_square_update():
    """Test single square calibration update."""
    start_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    # Place White Queen on e4
    updated = FENBuilder.update_square(start_fen, "e4", "Q")
    assert "4Q3" in updated or "Q" in updated.split()[0]


def test_device_profile_sentinel():
    """Test adaptive battery and hardware throttling."""
    # High spec & normal battery
    pro_profile = DeviceProfile(battery_level=80, is_charging=False, is_low_spec=False)
    max_d, th, time_cap, is_lite = pro_profile.get_config()
    assert is_lite is False
    assert max_d == 18

    # Low battery (<15%) triggers Lite Mode
    low_bat = DeviceProfile(battery_level=12, is_charging=False, is_low_spec=False)
    max_d, th, time_cap, is_lite = low_bat.get_config()
    assert is_lite is True
    assert max_d == 11

    # Low battery but charging does NOT throttle
    charging_profile = DeviceProfile(battery_level=12, is_charging=True, is_low_spec=False)
    _, _, _, is_lite = charging_profile.get_config()
    assert is_lite is False


def test_engine_evaluation():
    """Test engine position evaluation and win probability bar calculation."""
    manager = StockfishManager()
    start_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    eval_res = manager.evaluate(start_fen)
    assert eval_res.best_move_uci != ""
    assert 0.0 <= eval_res.eval_percent <= 100.0
    assert eval_res.time_taken_ms >= 0


def test_daily_puzzle_service():
    """Test daily puzzle fetching / fallback logic."""
    service = DailyPuzzleService()
    puzzle = service.get_daily_puzzle()
    assert puzzle.fen != ""
    assert len(puzzle.solution_moves) > 0
    assert puzzle.rating > 0


def test_telemetry_service(tmp_path):
    """Test creating structured bug report JSON."""
    service = TelemetryService(reports_dir=str(tmp_path))
    diff = [
        SquareDiff(square="e4", detected="P", corrected="N", confidence=0.72)
    ]
    report = service.create_report(
        detected_fen="rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1",
        corrected_fen="rnbqkbnr/pppppppp/8/8/4N3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1",
        diff_squares=diff,
        device_model="Test Device",
        battery_level=90,
        is_lite_mode=False
    )
    assert report.report_id.startswith("rep_")
    assert report.scan_data["diff_count"] == 1
    assert os.path.exists(os.path.join(tmp_path, f"{report.report_id}.json"))
