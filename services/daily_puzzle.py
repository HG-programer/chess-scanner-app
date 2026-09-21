"""
Daily Chess Puzzle Service for Chess Scanner.
Fetches daily puzzle from Lichess public API with offline caching for Day-1 and Day-7 retention.
"""

from dataclasses import dataclass
import json
import os
import time
from typing import List, Optional
import urllib.request


@dataclass
class DailyPuzzle:
    puzzle_id: str
    fen: str
    solution_moves: List[str]  # UCI format e.g. ["e4e5", "g1f3"]
    rating: int
    themes: List[str]
    game_url: str
    fetched_at: float
    is_cached: bool


class DailyPuzzleService:
    """Provides daily chess puzzles with local caching to drive user retention."""

    API_URL = "https://lichess.org/api/puzzle/daily"
    CACHE_DURATION_SEC = 86400  # 24 hours

    def __init__(self, cache_dir: Optional[str] = None):
        if cache_dir is None:
            cache_dir = os.path.join(os.path.dirname(__file__), "..", ".cache")
        self.cache_dir = cache_dir
        self.cache_file = os.path.join(self.cache_dir, "daily_puzzle.json")
        os.makedirs(self.cache_dir, exist_ok=True)

    def get_daily_puzzle(self) -> DailyPuzzle:
        """Returns today's puzzle, reading from 24h cache or fetching from Lichess API."""
        cached = self._read_cache()
        if cached and (time.time() - cached.fetched_at < self.CACHE_DURATION_SEC):
            return cached

        try:
            req = urllib.request.Request(
                self.API_URL,
                headers={"User-Agent": "ChessScanner-App/1.0 (daily-puzzle-service)"}
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status == 200:
                    data = json.loads(response.read().decode("utf-8"))
                    puzzle_obj = data.get("puzzle", {})
                    game_obj = data.get("game", {})

                    puzzle = DailyPuzzle(
                        puzzle_id=puzzle_obj.get("id", "daily"),
                        fen=puzzle_obj.get("fen") or game_obj.get("fen") or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                        solution_moves=puzzle_obj.get("solution", []),
                        rating=puzzle_obj.get("rating", 1500),
                        themes=puzzle_obj.get("themes", ["tactics"]),
                        game_url=f"https://lichess.org/training/{puzzle_obj.get('id', '')}",
                        fetched_at=time.time(),
                        is_cached=False
                    )
                    self._write_cache(puzzle)
                    return puzzle
        except Exception:
            # If network request fails, return cached if available, else static fallback
            if cached:
                return cached

        return self._get_fallback_puzzle()

    def _read_cache(self) -> Optional[DailyPuzzle]:
        if not os.path.exists(self.cache_file):
            return None
        try:
            with open(self.cache_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                return DailyPuzzle(**data)
        except Exception:
            return None

    def _write_cache(self, puzzle: DailyPuzzle) -> None:
        try:
            with open(self.cache_file, "w", encoding="utf-8") as f:
                d = puzzle.__dict__.copy()
                d["is_cached"] = True
                json.dump(d, f, indent=2)
        except Exception:
            pass

    def _get_fallback_puzzle(self) -> DailyPuzzle:
        """Pre-packaged tactical puzzle for offline first launches."""
        return DailyPuzzle(
            puzzle_id="offline_opera_game",
            fen="4kb1r/p2rqppp/5n2/1B2p1B1/4P3/1Q6/PPP2PPP/2KR4 w k - 0 14",
            solution_moves=["b5d7", "f6d7", "b3b8", "d7b8", "d1d8"],
            rating=1600,
            themes=["mateIn3", "queenSacrifice", "attraction"],
            game_url="https://lichess.org/study/opera-mate",
            fetched_at=time.time(),
            is_cached=True
        )
