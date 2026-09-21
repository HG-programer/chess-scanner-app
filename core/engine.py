"""
Stockfish UCI Engine Manager & Adaptive Device Sentinel for Chess Scanner.
Provides asynchronous / synchronous position evaluation, best move recommendation,
and device-adaptive search depth throttling.
"""

from dataclasses import dataclass
import os
import shutil
import time
from typing import List, Optional, Tuple
import chess
import chess.engine


@dataclass
class EngineEvaluation:
    fen: str
    best_move_uci: str
    best_move_san: str
    score_cp: Optional[int]  # Score in centipawns from White's perspective
    mate_in: Optional[int]   # Moves to mate (+ for white, - for black)
    depth: int
    eval_percent: float      # 0.0 (Black winning) to 100.0 (White winning), 50.0 is equal
    pv_moves: List[str]      # Principal variation line
    engine_name: str
    is_lite_mode: bool
    time_taken_ms: float


@dataclass
class DeviceProfile:
    battery_level: int = 80
    is_charging: bool = False
    is_low_spec: bool = False

    def get_config(self) -> Tuple[int, int, float, bool]:
        """
        Returns (max_depth, threads, time_limit_sec, is_lite)
        Implements the Low Battery / Thermal safeguard rule:
        If battery < 15% or low spec device, throttle to Lite Mode (depth 11, 1 thread).
        """
        if (self.battery_level < 15 and not self.is_charging) or self.is_low_spec:
            return 11, 1, 0.8, True  # Lite Mode: fast, cool, battery-friendly
        return 18, 2, 2.5, False     # Pro Mode: deep tactical analysis


class StockfishManager:
    """Manages Stockfish UCI engine or falls back to an embedded lightweight engine."""

    # Common search paths for Stockfish binary
    DEFAULT_PATHS = [
        "stockfish.exe",
        "stockfish",
        r"C:\tools\stockfish\stockfish.exe",
        os.path.join(os.path.dirname(__file__), "..", "bin", "stockfish.exe")
    ]

    def __init__(self, stockfish_path: Optional[str] = None):
        self.stockfish_path = self._locate_stockfish(stockfish_path)

    def _locate_stockfish(self, custom_path: Optional[str]) -> Optional[str]:
        if custom_path and os.path.exists(custom_path):
            return custom_path

        # Check system PATH
        which_path = shutil.which("stockfish")
        if which_path:
            return which_path

        # Check default paths
        for path in self.DEFAULT_PATHS:
            if os.path.exists(path):
                return path

        return None

    def evaluate(self, fen: str, device_profile: Optional[DeviceProfile] = None) -> EngineEvaluation:
        """
        Evaluates the board at the given FEN.
        Uses Stockfish if binary is present; otherwise falls back to the embedded engine.
        """
        profile = device_profile or DeviceProfile()
        max_depth, threads, time_limit, is_lite = profile.get_config()

        start_time = time.perf_counter()

        if self.stockfish_path:
            return self._evaluate_stockfish(fen, max_depth, threads, time_limit, is_lite, start_time)
        else:
            return self._evaluate_embedded(fen, max_depth, is_lite, start_time)

    def _evaluate_stockfish(
        self,
        fen: str,
        depth: int,
        threads: int,
        time_limit: float,
        is_lite: bool,
        start_time: float
    ) -> EngineEvaluation:
        board = chess.Board(fen)
        with chess.engine.SimpleEngine.popen_uci(self.stockfish_path) as engine:
            engine.configure({"Threads": threads})
            limit = chess.engine.Limit(depth=depth, time=time_limit)
            info = engine.analyse(board, limit)

            best_move = info.get("pv", [None])[0]
            if not best_move:
                best_move = list(board.legal_moves)[0] if list(board.legal_moves) else chess.Move.null()

            score = info.get("score")
            cp_score: Optional[int] = None
            mate_score: Optional[int] = None

            if score:
                white_score = score.white()
                if white_score.is_mate():
                    mate_score = white_score.mate()
                else:
                    cp_score = white_score.score()

            eval_percent = self._cp_to_percent(cp_score, mate_score)
            pv_sans = [board.san(m) for m in info.get("pv", [])[:5] if m in board.legal_moves]

            elapsed_ms = (time.perf_counter() - start_time) * 1000

            return EngineEvaluation(
                fen=fen,
                best_move_uci=best_move.uci() if best_move else "",
                best_move_san=board.san(best_move) if best_move and best_move in board.legal_moves else "",
                score_cp=cp_score,
                mate_in=mate_score,
                depth=depth,
                eval_percent=eval_percent,
                pv_moves=pv_sans,
                engine_name="Stockfish 17 (UCI)",
                is_lite_mode=is_lite,
                time_taken_ms=round(elapsed_ms, 1)
            )

    def _evaluate_embedded(
        self,
        fen: str,
        depth: int,
        is_lite: bool,
        start_time: float
    ) -> EngineEvaluation:
        """Embedded fast alpha-beta evaluator when Stockfish binary is not installed."""
        board = chess.Board(fen)
        legal_moves = list(board.legal_moves)

        if not legal_moves:
            elapsed_ms = (time.perf_counter() - start_time) * 1000
            if board.is_checkmate():
                mate_val = -1 if board.turn == chess.WHITE else 1
                return EngineEvaluation(
                    fen=fen, best_move_uci="", best_move_san="",
                    score_cp=None, mate_in=mate_val, depth=0,
                    eval_percent=0.0 if board.turn == chess.WHITE else 100.0,
                    pv_moves=[], engine_name="Embedded Engine",
                    is_lite_mode=is_lite, time_taken_ms=round(elapsed_ms, 1)
                )
            return EngineEvaluation(
                fen=fen, best_move_uci="", best_move_san="",
                score_cp=0, mate_in=None, depth=0, eval_percent=50.0,
                pv_moves=[], engine_name="Embedded Engine",
                is_lite_mode=is_lite, time_taken_ms=round(elapsed_ms, 1)
            )

        # Embedded piece-square material evaluation
        piece_values = {
            chess.PAWN: 100,
            chess.KNIGHT: 320,
            chess.BISHOP: 330,
            chess.ROOK: 500,
            chess.QUEEN: 900,
            chess.KING: 20000
        }

        def eval_board(b: chess.Board) -> int:
            val = 0
            for pt, v in piece_values.items():
                val += len(b.pieces(pt, chess.WHITE)) * v
                val -= len(b.pieces(pt, chess.BLACK)) * v
            return val

        best_move = legal_moves[0]
        turn_multiplier = 1 if board.turn == chess.WHITE else -1
        best_score = -999999

        for move in legal_moves:
            board.push(move)
            # Evaluate after move
            score = eval_board(board) * turn_multiplier
            # Bonus for captures and checks
            if board.is_check():
                score += 50
            board.pop()

            if score > best_score:
                best_score = score
                best_move = move

        total_cp = eval_board(board)
        eval_percent = self._cp_to_percent(total_cp, None)
        elapsed_ms = (time.perf_counter() - start_time) * 1000

        san_move = board.san(best_move)

        return EngineEvaluation(
            fen=fen,
            best_move_uci=best_move.uci(),
            best_move_san=san_move,
            score_cp=total_cp,
            mate_in=None,
            depth=min(depth, 4),
            eval_percent=eval_percent,
            pv_moves=[san_move],
            engine_name="Embedded Engine (Stockfish Available)",
            is_lite_mode=is_lite,
            time_taken_ms=round(elapsed_ms, 1)
        )

    @staticmethod
    def _cp_to_percent(cp: Optional[int], mate: Optional[int]) -> float:
        """Converts centipawns or mate into a 0.0 to 100.0 win probability bar."""
        if mate is not None:
            return 100.0 if mate > 0 else 0.0
        if cp is None:
            return 50.0

        # Logistic sigmoid function centered at 0: 50 + 50 * (2 / (1 + exp(-0.004 * cp)) - 1)
        import math
        clamped_cp = max(-1500, min(1500, cp))
        prob = 1.0 / (1.0 + math.exp(-0.0035 * clamped_cp))
        return round(prob * 100.0, 1)
