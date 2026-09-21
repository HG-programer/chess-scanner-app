"""
FEN Builder and Board Validation Module for Chess Scanner.
Translates 8x8 piece grids into standard FEN strings and enforces chess legality rules.
"""

from dataclasses import dataclass
from typing import List, Optional, Tuple
import chess

from core.classifier import SquarePrediction


@dataclass
class FENResult:
    fen: str
    is_legal: bool
    error_reason: Optional[str] = None
    white_king_count: int = 0
    black_king_count: int = 0
    total_white_pieces: int = 0
    total_black_pieces: int = 0


class FENBuilder:
    """Constructs and validates FEN strings from 8x8 predictions."""

    VALID_PIECES = {"P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k"}

    @classmethod
    def grid_to_piece_placement(cls, grid: List[List[Optional[str]]]) -> str:
        """
        Converts an 8x8 array of piece characters (or None) into FEN piece placement.
        grid[0] = rank 8, grid[7] = rank 1.
        """
        rank_strings = []
        for r in range(8):
            empty_count = 0
            rank_str = ""
            for c in range(8):
                piece = grid[r][c]
                if piece is None or piece == "" or piece == " ":
                    empty_count += 1
                else:
                    if empty_count > 0:
                        rank_str += str(empty_count)
                        empty_count = 0
                    rank_str += piece
            if empty_count > 0:
                rank_str += str(empty_count)
            rank_strings.append(rank_str)

        return "/".join(rank_strings)

    @classmethod
    def predictions_to_fen(
        cls,
        predictions: List[List[SquarePrediction]],
        active_color: str = "w",
        castling: str = "KQkq",
        en_passant: str = "-",
        halfmove: int = 0,
        fullmove: int = 1
    ) -> FENResult:
        """Converts classifier SquarePrediction grid into a full validated FEN."""
        grid: List[List[Optional[str]]] = []
        white_kings = 0
        black_kings = 0
        total_white = 0
        total_black = 0

        for r in range(8):
            row_pieces: List[Optional[str]] = []
            for c in range(8):
                piece = predictions[r][c].piece
                if piece:
                    if piece == "K":
                        white_kings += 1
                    elif piece == "k":
                        black_kings += 1

                    if piece.isupper():
                        total_white += 1
                    else:
                        total_black += 1

                row_pieces.append(piece)
            grid.append(row_pieces)

        piece_placement = cls.grid_to_piece_placement(grid)

        # Dynamic castling availability check
        # If kings or rooks are missing from home squares, remove rights
        resolved_castling = cls._resolve_castling_rights(grid, castling)

        full_fen = f"{piece_placement} {active_color} {resolved_castling} {en_passant} {halfmove} {fullmove}"

        # Legality validation using python-chess
        is_legal, reason = cls.validate_fen_legality(full_fen, white_kings, black_kings)

        return FENResult(
            fen=full_fen,
            is_legal=is_legal,
            error_reason=reason,
            white_king_count=white_kings,
            black_king_count=black_kings,
            total_white_pieces=total_white,
            total_black_pieces=total_black
        )

    @classmethod
    def _resolve_castling_rights(cls, grid: List[List[Optional[str]]], default_rights: str) -> str:
        rights = ""
        # White king on e1 (row 7, col 4)
        if grid[7][4] == "K":
            if grid[7][7] == "R" and "K" in default_rights:
                rights += "K"
            if grid[7][0] == "R" and "Q" in default_rights:
                rights += "Q"
        # Black king on e8 (row 0, col 4)
        if grid[0][4] == "k":
            if grid[0][7] == "r" and "k" in default_rights:
                rights += "k"
            if grid[0][0] == "r" and "q" in default_rights:
                rights += "q"
        return rights if rights else "-"

    @classmethod
    def validate_fen_legality(cls, fen: str, white_kings: int, black_kings: int) -> Tuple[bool, Optional[str]]:
        """Checks if the board configuration is physically and rule-legal in chess."""
        if white_kings == 0:
            return False, "Missing White King (add 'K' to the board)"
        if white_kings > 1:
            return False, f"Too many White Kings ({white_kings})"
        if black_kings == 0:
            return False, "Missing Black King (add 'k' to the board)"
        if black_kings > 1:
            return False, f"Too many Black Kings ({black_kings})"

        try:
            board = chess.Board(fen)
            # Check for pawns on back ranks (illegal in chess)
            rank_pieces = fen.split()[0].split("/")
            rank_8 = rank_pieces[0]
            rank_1 = rank_pieces[7]
            if "P" in rank_8 or "p" in rank_8:
                return False, "Pawns cannot be on the 8th rank"
            if "P" in rank_1 or "p" in rank_1:
                return False, "Pawns cannot be on the 1st rank"

            # Check if king is in check by opponent when it's not their turn
            if board.was_into_check():
                return False, "Opponent king is in an impossible check position"

            return True, None
        except Exception as e:
            return False, f"Invalid board structure: {str(e)}"

    @classmethod
    def update_square(cls, fen: str, square_name: str, new_piece: Optional[str]) -> str:
        """
        Updates a single square on an existing FEN.
        square_name: e.g. "e4"
        new_piece: "P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k", or None / ""
        """
        board = chess.Board(fen)
        sq = chess.parse_square(square_name)
        if new_piece is None or new_piece == "":
            board.remove_piece_at(sq)
        else:
            piece_type = chess.PIECE_SYMBOLS.index(new_piece.lower())
            color = chess.WHITE if new_piece.isupper() else chess.BLACK
            board.set_piece_at(sq, chess.Piece(piece_type, color))

        return board.fen()
