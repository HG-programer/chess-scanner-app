"""
Telemetry and Bug Report Service for Chess Scanner.
Generates structured JSON payloads for misidentified chess boards to enable continuous model retraining.
"""

from dataclasses import asdict, dataclass
import json
import os
import time
from typing import Any, Dict, List, Optional
import uuid


@dataclass
class SquareDiff:
    square: str
    detected: Optional[str]
    corrected: Optional[str]
    confidence: float


@dataclass
class TelemetryReport:
    report_id: str
    timestamp: str
    app_version: str
    device: Dict[str, Any]
    environment: Dict[str, Any]
    scan_data: Dict[str, Any]
    image_storage_path: Optional[str] = None


class TelemetryService:
    """Manages creation and saving of misidentification reports."""

    def __init__(self, reports_dir: Optional[str] = None):
        if reports_dir is None:
            reports_dir = os.path.join(os.path.dirname(__file__), "..", "reports")
        self.reports_dir = reports_dir
        os.makedirs(self.reports_dir, exist_ok=True)

    def create_report(
        self,
        detected_fen: str,
        corrected_fen: str,
        diff_squares: List[SquareDiff],
        device_model: str = "Desktop / Web Emulator",
        battery_level: int = 85,
        is_lite_mode: bool = False,
        estimated_lighting: str = "medium",
        average_luminance: float = 128.0,
        board_type: str = "wooden_3d",
        image_path: Optional[str] = None,
        app_version: str = "1.0.0"
    ) -> TelemetryReport:
        """Constructs a structured bug report payload matching the production schema."""
        report_id = f"rep_{int(time.time())}_{uuid.uuid4().hex[:6]}"
        timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        diff_list = [asdict(d) for d in diff_squares]

        report = TelemetryReport(
            report_id=report_id,
            timestamp=timestamp,
            app_version=app_version,
            device={
                "model": device_model,
                "battery_level": battery_level,
                "is_lite_mode": is_lite_mode
            },
            environment={
                "estimated_lighting": estimated_lighting,
                "average_luminance": round(average_luminance, 1),
                "board_type": board_type
            },
            scan_data={
                "detected_fen": detected_fen,
                "corrected_fen": corrected_fen,
                "diff_squares": diff_list,
                "diff_count": len(diff_list)
            },
            image_storage_path=image_path
        )

        self._save_report(report)
        return report

    def _save_report(self, report: TelemetryReport) -> str:
        file_path = os.path.join(self.reports_dir, f"{report.report_id}.json")
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(asdict(report), f, indent=2)
        return file_path
