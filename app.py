"""
Interactive Chess Scanner & AI Analysis Workbench.
Provides live camera/image scanning, 4-corner perspective warping, interactive calibration,
real-time engine evaluation, daily tactical puzzle, and telemetry bug reporting.
"""

import os
import sys

# Add project root to path
sys.path.insert(0, os.path.dirname(__file__))

import cv2
import numpy as np
from PIL import Image
import streamlit as st

from core.detector import BoardDetector
from core.classifier import PieceClassifier, SquarePrediction
from core.fen_builder import FENBuilder
from core.engine import StockfishManager, DeviceProfile
from services.daily_puzzle import DailyPuzzleService
from services.telemetry import TelemetryService, SquareDiff


# Configure Streamlit page
st.set_page_config(
    page_title="Chess Scanner & AI Analysis Engine",
    page_icon="♟️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for chessboard styling, eval bar, and calibration highlights
st.markdown("""
<style>
    .reportview-container { background: #0e1117; }
    .eval-container {
        width: 100%;
        height: 28px;
        background-color: #2b2b2b;
        border-radius: 6px;
        overflow: hidden;
        border: 2px solid #444;
        display: flex;
        margin-bottom: 12px;
    }
    .eval-white {
        background-color: #f0f0f0;
        height: 100%;
        transition: width 0.3s ease;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        padding-left: 8px;
        color: #111;
        font-weight: bold;
        font-size: 13px;
    }
    .eval-black {
        background-color: #2b2b2b;
        height: 100%;
        flex-grow: 1;
        display: flex;
        align-items: center;
        justify-content: flex-end;
        padding-right: 8px;
        color: #f0f0f0;
        font-weight: bold;
        font-size: 13px;
    }
    .ambiguous-badge {
        background-color: #e6a700;
        color: #111;
        font-weight: bold;
        padding: 2px 8px;
        border-radius: 4px;
        font-size: 12px;
    }
    .calib-sq {
        border: 2px dashed #f59e0b;
        padding: 4px;
        border-radius: 4px;
        background: rgba(245, 158, 11, 0.1);
    }
</style>
""", unsafe_allow_html=True)


@st.cache_resource
def get_services():
    detector = BoardDetector()
    classifier = PieceClassifier(confidence_threshold=0.85)
    engine = StockfishManager()
    puzzle_service = DailyPuzzleService()
    telemetry_service = TelemetryService()
    return detector, classifier, engine, puzzle_service, telemetry_service


detector, classifier, engine, puzzle_service, telemetry_service = get_services()

# ----------------- SIDEBAR CONTROLS -----------------
st.sidebar.title("♟️ Chess Scanner Pro")
st.sidebar.caption("v1.0.0 • On-Device AI & Stockfish Engine")

st.sidebar.markdown("---")
st.sidebar.subheader("⚡ Device Sentinel (Battery / Thermal)")
battery_level = st.sidebar.slider("Simulate Battery Level (%)", min_value=5, max_value=100, value=85)
is_charging = st.sidebar.checkbox("Device Charging", value=False)
is_low_spec = st.sidebar.checkbox("Low-Spec Device (32-bit / <3GB RAM)", value=False)

dev_profile = DeviceProfile(battery_level=battery_level, is_charging=is_charging, is_low_spec=is_low_spec)
max_depth, threads, time_limit, is_lite = dev_profile.get_config()

if is_lite:
    st.sidebar.warning(f"🔋 Lite Mode Active (Depth {max_depth}, {threads} Thread, {time_limit}s cap)")
else:
    st.sidebar.success(f"⚡ Pro Mode Active (Depth {max_depth}, {threads} Threads)")

st.sidebar.markdown("---")
st.sidebar.subheader("💎 Monetization Tier")
user_tier = st.sidebar.radio("Active Tier:", ["Free (Depth 12 + Ads)", "Rewarded Video Boost (Depth 18)", "Grandmaster Premium (Depth 22+ No Ads)"])
if "Rewarded" in user_tier:
    st.sidebar.info("🎬 Ad watched! 1 Deep Analysis unlocked.")

# ----------------- NAVIGATION TABS -----------------
tab1, tab2, tab3, tab4 = st.tabs([
    "📸 Board Scanner & Analysis",
    "✏️ Interactive Calibration",
    "🧩 Daily Tactical Puzzle (Retention)",
    "💰 Monetization & ASO Preview"
])

# Initialize session state for FEN and predictions
if "current_fen" not in st.session_state:
    st.session_state.current_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
if "detected_fen" not in st.session_state:
    st.session_state.detected_fen = st.session_state.current_fen
if "predictions" not in st.session_state:
    st.session_state.predictions = None
if "warped_img" not in st.session_state:
    st.session_state.warped_img = None

# ==================== TAB 1: SCANNER & ANALYSIS ====================
with tab1:
    st.header("📸 Physical Chess Board Scanner")
    st.caption("Point your camera at any 2D diagram or 3D physical board for instant AI recognition and evaluation.")

    col_input, col_results = st.columns([1, 1])

    with col_input:
        st.subheader("1. Input Image")
        source = st.radio("Image Source:", ["Sample Synthetic Board", "Sample 3D Skewed Board", "Upload Custom Image"], horizontal=True)

        input_cv_img = None
        sample_dir = os.path.join(os.path.dirname(__file__), "sample_data")

        if source == "Sample Synthetic Board":
            flat_path = os.path.join(sample_dir, "flat_sample.png")
            if os.path.exists(flat_path):
                input_cv_img = cv2.imread(flat_path)
        elif source == "Sample 3D Skewed Board":
            skew_path = os.path.join(sample_dir, "skewed_sample.png")
            if os.path.exists(skew_path):
                input_cv_img = cv2.imread(skew_path)
        else:
            uploaded_file = st.file_uploader("Upload Board Photo (JPG/PNG)", type=["jpg", "jpeg", "png"])
            if uploaded_file:
                file_bytes = np.asarray(bytearray(uploaded_file.read()), dtype=np.uint8)
                input_cv_img = cv2.imdecode(file_bytes, cv2.IMREAD_COLOR)

        if input_cv_img is not None:
            st.image(cv2.cvtColor(input_cv_img, cv2.COLOR_BGR2RGB), caption="Captured Image", use_container_width=True)

            if st.button("🔍 Scan & Analyze Board", type="primary"):
                with st.spinner("Detecting board corners & warping perspective..."):
                    warped, corners = detector.warp_board(input_cv_img)
                    st.session_state.warped_img = warped

                    squares = detector.slice_squares(warped)
                    preds = classifier.classify_board(squares)
                    st.session_state.predictions = preds

                    fen_res = FENBuilder.predictions_to_fen(preds)
                    st.session_state.current_fen = fen_res.fen
                    st.session_state.detected_fen = fen_res.fen
                    st.success("Board recognized successfully!")

    with col_results:
        st.subheader("2. AI Analysis & FEN")
        if st.session_state.warped_img is not None:
            st.image(
                cv2.cvtColor(st.session_state.warped_img, cv2.COLOR_BGR2RGB),
                caption="Normalized 8x8 Top-Down Grid (800x800)",
                width=340
            )

        fen_input = st.text_input("Active FEN:", value=st.session_state.current_fen)
        if fen_input != st.session_state.current_fen:
            st.session_state.current_fen = fen_input

        # Run Engine Evaluation
        with st.spinner("Stockfish evaluating position..."):
            eval_res = engine.evaluate(st.session_state.current_fen, dev_profile)

        # Evaluation Bar
        white_pct = eval_res.eval_percent
        black_pct = round(100.0 - white_pct, 1)

        score_text = ""
        if eval_res.mate_in is not None:
            score_text = f"M{eval_res.mate_in}" if eval_res.mate_in > 0 else f"-M{abs(eval_res.mate_in)}"
        elif eval_res.score_cp is not None:
            score_text = f"{'+' if eval_res.score_cp >= 0 else ''}{eval_res.score_cp / 100.0:.2f}"
        else:
            score_text = "0.00"

        st.markdown(f"""
        <div class="eval-container">
            <div class="eval-white" style="width: {white_pct}%;">White: {score_text}</div>
            <div class="eval-black">Black</div>
        </div>
        """, unsafe_allow_html=True)

        # Engine Stats Cards
        stat_c1, stat_c2, stat_c3 = st.columns(3)
        stat_c1.metric("Best Move", eval_res.best_move_san or eval_res.best_move_uci)
        stat_c2.metric("Depth", f"{eval_res.depth} plies")
        stat_c3.metric("Eval Time", f"{eval_res.time_taken_ms} ms")

        st.info(f"Engine: **{eval_res.engine_name}** | Principal Variation: `{' '.join(eval_res.pv_moves)}`")

        # Quick Actions
        act_c1, act_c2 = st.columns(2)
        if act_c1.button("📋 Copy FEN"):
            st.toast("FEN copied to clipboard!")
        if act_c2.button("🌐 Open in Lichess Analysis"):
            encoded = st.session_state.current_fen.replace(" ", "_")
            st.markdown(f"[Click to view on Lichess](https://lichess.org/analysis/{encoded})")

# ==================== TAB 2: INTERACTIVE CALIBRATION ====================
with tab2:
    st.header("✏️ Fast-Calibration Workbench (The Rating Saver)")
    st.write(
        "Ambiguous or low-confidence squares ($<0.85$) are highlighted. "
        "Tap or select any square to correct piece identification in under 1 second."
    )

    calib_c1, calib_c2 = st.columns([1, 1])

    with calib_c1:
        st.subheader("Interactive Board Editor")
        squares_list = [f"{f}{r}" for r in ["8","7","6","5","4","3","2","1"] for f in ["a","b","c","d","e","f","g","h"]]
        selected_sq = st.selectbox("Select Square to Edit:", squares_list, index=squares_list.index("e4"))

        pieces = ["(Empty)", "White Pawn (P)", "White Knight (N)", "White Bishop (B)", "White Rook (R)", "White Queen (Q)", "White King (K)",
                  "Black Pawn (p)", "Black Knight (n)", "Black Bishop (b)", "Black Rook (r)", "Black Queen (q)", "Black King (k)"]
        piece_map = {
            "(Empty)": None, "White Pawn (P)": "P", "White Knight (N)": "N", "White Bishop (B)": "B",
            "White Rook (R)": "R", "White Queen (Q)": "Q", "White King (K)": "K",
            "Black Pawn (p)": "p", "Black Knight (n)": "n", "Black Bishop (b)": "b",
            "Black Rook (r)": "r", "Black Queen (q)": "q", "Black King (k)": "k"
        }

        new_piece_label = st.selectbox("Assign Piece:", pieces)

        if st.button("Apply Correction", type="primary"):
            updated_fen = FENBuilder.update_square(
                st.session_state.current_fen,
                selected_sq,
                piece_map[new_piece_label]
            )
            st.session_state.current_fen = updated_fen
            st.success(f"Updated square {selected_sq} -> {piece_map[new_piece_label] or 'Empty'}")
            st.rerun()

    with calib_c2:
        st.subheader("Automated Retraining Telemetry")
        st.write("When a piece is corrected, generate the production bug report payload for retraining:")

        board_material = st.selectbox("Board Style:", ["wood_dark_squares", "vinyl_roll_up", "printed_book", "magnetic_travel"])
        lighting_tag = st.selectbox("Lighting:", ["low", "medium", "direct_sunlight", "indoor_shadows"])

        if st.button("📤 Submit Anonymous Bug Report"):
            diff = [
                SquareDiff(
                    square=selected_sq,
                    detected="P",
                    corrected=piece_map[new_piece_label],
                    confidence=0.68
                )
            ]
            report = telemetry_service.create_report(
                detected_fen=st.session_state.detected_fen,
                corrected_fen=st.session_state.current_fen,
                diff_squares=diff,
                device_model="Android Pixel 7 / Desktop Testbench",
                battery_level=battery_level,
                is_lite_mode=is_lite,
                estimated_lighting=lighting_tag,
                board_type=board_material
            )
            st.success(f"Report saved: `{report.report_id}.json`")
            st.json(report.__dict__)

# ==================== TAB 3: DAILY PUZZLE (RETENTION) ====================
with tab3:
    st.header("🧩 Daily Tactical Puzzle (Day 1 / Day 7 Retention Engine)")
    st.caption("Pulls directly from Lichess Daily API with 24-hour local caching to keep users returning every day.")

    puzzle = puzzle_service.get_daily_puzzle()

    p_col1, p_col2 = st.columns([1, 1])

    with p_col1:
        st.metric("Puzzle ID", puzzle.puzzle_id)
        st.metric("Puzzle Rating", f"{puzzle.rating} ELO")
        st.info(f"Themes: {', '.join(puzzle.themes)}")
        st.caption(f"Cache Status: {'Loaded from local 24h cache' if puzzle.is_cached else 'Fresh API Fetch'}")

    with p_col2:
        st.subheader("Puzzle Position")
        st.code(puzzle.fen, language="text")
        if st.button("Load Puzzle onto Board"):
            st.session_state.current_fen = puzzle.fen
            st.success("Loaded daily puzzle into scanner analysis!")

        with st.expander("Reveal Solution Moves"):
            st.write(f"Solution: `{' -> '.join(puzzle.solution_moves)}`")
            st.markdown(f"[Play Puzzle on Lichess]({puzzle.game_url})")

# ==================== TAB 4: MONETIZATION & ASO ====================
with tab4:
    st.header("💰 Monetization Architecture & Global Regional Pricing")
    st.caption("Configured for RevenueCat IAPs and Google AdMob Rewarded Video depth boosts.")

    m_col1, m_col2 = st.columns(2)

    with m_col1:
        st.subheader("Regional Pricing Strategy (Purchasing Power Parity)")
        st.table({
            "Region": ["United States (Tier 1)", "United Kingdom (Tier 1)", "Germany / EU (Tier 1)", "India (Tier 3)", "Brazil (Tier 3)"],
            "Monthly": ["$4.99", "£4.49", "€4.99", "₹99 ($1.20)", "R$ 14.90 ($2.70)"],
            "Lifetime Unlock": ["$29.99", "£26.99", "€29.99", "₹499 ($6.00)", "R$ 59.90 ($10.80)"]
        })

    with m_col2:
        st.subheader("AdMob Strategy & eCPM Maximization")
        st.markdown("""
        *   **Rewarded Video:** User watches 30s ad $\\rightarrow$ unlocks 1 Deep Analysis scan at Depth 20 ($10\\times$ eCPM of banners).
        *   **Native Ads:** Embedded naturally below the Evaluation Bar.
        *   **Deferred Permission Hook:** Never ask for camera on first screen; prompt only after user taps "Scan Board".
        *   **Delight Review Trigger:** Prompt `InAppReview` only after 3 successful scans and $>85\\%$ confidence.
        """)

    st.markdown("---")
    st.subheader("Google Play Console ASO Package (Ready to Deploy)")
    st.text_input("Optimized App Title (29/30):", "Chess Scanner: Camera FEN & AI", disabled=True)
    st.text_input("Short Description (79/80):", "Scan physical chess boards with your camera. Instant FEN and Stockfish AI engine.", disabled=True)
