# Privacy Policy for ChessSnap: AI Board Scanner

**Effective Date:** September 22, 2026  
**Last Updated:** September 22, 2026  

ChessSnap ("we", "our", or "us") is dedicated to protecting your privacy. This Privacy Policy explains how our mobile application **ChessSnap: AI Board Scanner** ("the App") handles information and permissions when you use our services.

---

## 1. Summary of Our Privacy Principles
- **No Personal Data Collected:** ChessSnap does not require user accounts, registration, email addresses, phone numbers, or passwords.
- **On-Device Camera Processing:** Camera feed and captured frames are processed live on your device strictly to detect chessboard squares and chess pieces. Images are never uploaded to our servers, sold, or shared.
- **Zero Audio / Microphone Access:** The App does not record audio. The `RECORD_AUDIO` permission is explicitly disabled.
- **Zero Storage Access:** The App does not request access to your device's external storage, photos, or media files.

---

## 2. Permissions We Use and Why

### A. Camera (`android.permission.CAMERA`)
- **Purpose:** Enables optical recognition of 2D diagrams, screen displays, and 3D physical chessboards.
- **Data Handling:** The camera feed is analyzed in real-time by on-device computer vision algorithms to convert the position into standard chess Forsyth–Edwards Notation (FEN). Captured camera frames are transient, kept only in device RAM during scanning, and immediately discarded.

### B. Internet Access (`android.permission.INTERNET`)
- **Purpose:** 
  1. To query the public Lichess Cloud API (`https://lichess.org/api/cloud-eval`) for master opening book evaluations when requested.
  2. To serve non-intrusive banner and rewarded ads via the Google Mobile Ads SDK.
  3. To process subscriptions and in-app purchases via Google Play Billing.
- **Data Handling:** Only standard chess position strings (FEN) and anonymous device identifiers required by Google Play and AdMob are transmitted.

---

## 3. Advertising and Monetization (Google Mobile Ads & AdMob)
ChessSnap uses Google AdMob to display banner advertisements and optional rewarded video ads (e.g. to temporarily unlock Pro engine access).
- **Consent & Privacy Regulations:** We implement Google's User Messaging Platform (UMP) SDK to comply with GDPR (General Data Protection Regulation), UK GDPR, and CCPA regulations. Users in relevant jurisdictions can manage their advertising consent preferences at any time.
- **Ad Identifiers:** In accordance with Google Play policy, Google Mobile Ads may use the Android Advertising ID (AAID) for fraud prevention, frequency capping, and ad delivery in compliance with Google Play Developer Program Policies.

---

## 4. In-App Purchases and Subscriptions (Google Play Billing)
- All financial transactions, subscriptions (Pro Pass), and one-time purchases are processed securely through **Google Play In-App Billing (Google Play Billing Library 9)**.
- ChessSnap does not have access to, receive, or store credit card numbers, banking details, or billing addresses.

---

## 5. Third-Party Services
The App integrates the following third-party libraries and APIs:
- **Google Play Services / Google Mobile Ads:** [Google Privacy Policy](https://policies.google.com/privacy)
- **Lichess Open API:** [Lichess Privacy Policy](https://lichess.org/privacy)
- **RevenueCat SDK:** [RevenueCat Privacy Policy](https://www.revenuecat.com/privacy)

---

## 6. Open Source Software and Licenses
ChessSnap respects and complies with open-source licenses:
- **Stockfish Chess Engine:** Stockfish is licensed under the **GNU General Public License v3.0 (GPLv3)**. Original author copyrights belong to Tord Romstad, Marco Costalba, Joona Kiiski, Gary Linscott, and the Stockfish community. The complete corresponding source code for Stockfish is available at [https://github.com/official-stockfish/Stockfish](https://github.com/official-stockfish/Stockfish).
- **Chessground:** Licensed under the MIT License, Copyright © Niklas Fiekas and Lichess developers.

---

## 7. Children's Privacy (COPPA Compliance)
ChessSnap does not knowingly collect any personal information from children under the age of 13. The App is a general-audience utility for chess players of all ages.

---

## 8. Changes to This Privacy Policy
We may update this Privacy Policy from time to time to reflect technological updates or Google Play policy updates. Any updates will be reflected with a revised "Last Updated" date.

---

## 9. Contact Information
If you have questions, inquiries, or feedback regarding this Privacy Policy, please contact:
- **Developer / Publisher:** ChessSnap Support Team
- **GitHub Repository:** [https://github.com/HG-programer/chess-scanner-app](https://github.com/HG-programer/chess-scanner-app)
