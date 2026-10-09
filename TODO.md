# Firebase Phone Auth Integration TODO & Roadmap · Krishi Saathi

> **Objective:** Integrate **Google Firebase Phone Authentication** into Krishi Saathi (Flutter Android + Node.js backend + Web app) so that farmers and labour providers receive **real SMS OTPs directly on their physical mobile phones** at **₹0 cost** (10,000 free SMS/month on Firebase Spark plan, no DLT registration fees required).

---

## 🏛 Architecture Overview

```
 ┌────────────────────────┐
 │   Flutter Android App  │ (or Web Client)
 └───────────┬────────────┘
             │ 1. Request OTP with Phone Number (+91...)
             ▼
 ┌────────────────────────┐
 │  Google Firebase Auth  │ ──► [Sends REAL SMS with 6-digit OTP to Phone]
 └───────────┬────────────┘
             │ 2. User enters 6-digit code received on SMS
             │ 3. Firebase verifies code and issues Firebase ID Token (JWT)
             ▼
 ┌────────────────────────┐
 │   Flutter Android App  │
 └───────────┬────────────┘
             │ 4. POST /api/auth/firebase/verify { idToken }
             ▼
 ┌────────────────────────┐
 │ Node.js SQLite Backend │ ──► Verifies Firebase ID Token using Firebase Admin SDK
 └───────────┬────────────┘     Extracts verified Indian phone number (+91XXXXXXXXXX)
             │
             ├─► [User exists in DB] ──► Returns session token & user profile
             └─► [New user]         ──► Returns temporary signupToken (10 mins)
                                         Client submits /api/auth/otp/complete (Name, Age, Role, Address)
```

---

## 📋 Step-by-Step Task Checklist

### Phase 1: Firebase Project Setup (Google Console)
- [ ] **1.1. Create a Firebase Project**
  - Go to [Firebase Console](https://console.firebase.google.com/).
  - Click **Add Project**, name it `krishi-saathi` (or any preferred name).
  - Google Analytics can be enabled or disabled (not required for Auth).
- [ ] **1.2. Enable Phone Authentication**
  - In the Firebase Console sidebar, navigate to **Build > Authentication**.
  - Click **Get Started**.
  - Under the **Sign-in method** tab, select **Phone**.
  - Toggle **Enable** to ON and save.
  - *(Optional)* Under **Phone numbers for testing**, add a test number (e.g., `+91 9999999999` with code `123456`) for free instant testing without consuming SMS quotas.
- [ ] **1.3. Add Android App to Firebase**
  - In Project Overview, click the **Android** icon.
  - **Android package name:** `in.krishisaathi.krishi_saathi` (from `mobile/android/app/build.gradle.kts`).
  - **App nickname:** `Krishi Saathi Android`.
  - **Debug signing certificate SHA-1 and SHA-256:**
    - Run the following command in terminal:
      ```powershell
      keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
      ```
    - Copy the `SHA1` and `SHA256` fingerprints and paste them into Firebase (SHA-256 is required for Android SMS auto-retrieval / Play Integrity).
  - Click **Register App**.
- [ ] **1.4. Download Configuration Files**
  - Download `google-services.json`.
  - Place `google-services.json` inside the directory:
    ```
    mobile/android/app/google-services.json
    ```
- [ ] **1.5. Generate Firebase Admin Service Account Key for Backend**
  - In Firebase Console, go to **Project Settings > Service accounts**.
  - Select **Node.js** and click **Generate new private key**.
  - Save the downloaded JSON file as `server/firebase-service-account.json` (ensure this file is added to `.gitignore`).

---

### Phase 2: Android & Flutter App Configuration
- [x] **2.1. Update Android Gradle Configuration** (Done: added google-services plugin in `settings.gradle.kts` and `app/build.gradle.kts`)
- [x] **2.2. Add Flutter Dependencies** (Done: added `firebase_core` & `firebase_auth` in `pubspec.yaml` and ran `flutter pub get`)
- [x] **2.3. Initialize Firebase in Flutter** (Done: added `Firebase.initializeApp()` in `mobile/lib/main.dart`)
- [x] **2.4. Update Auth Flow in `mobile/lib/app_state.dart` and `mobile/lib/main.dart`** (Done: added phone verification, SMS code verification, resend code, auto-retrieval, and fallback)

---

### Phase 3: Backend Node.js Integration
- [x] **3.1. Install `firebase-admin`** (Done: installed `firebase-admin` in root `package.json`)
- [x] **3.2. Create Firebase Auth Service (`server/firebase.mjs`)** (Done: implemented `verifyFirebaseIdToken`)
- [x] **3.3. Add Endpoint in `server/app.mjs`** (Done: added `POST /api/auth/firebase/verify`)
- [x] **3.4. Maintain Backward Compatibility and Test Suite** (Done: all 14 node tests + 4 flutter tests pass)

---

### Phase 4: Web Application Integration (Optional)

- [ ] **4.1. Add Firebase JS SDK to `index.html`**
  - Include `<script type="module">` with `firebase/app` and `firebase/auth`.
  - Add invisible `recaptcha-container` div.
- [ ] **4.2. Update `src/main.js`**
  - When user clicks Submit phone on web, invoke `signInWithPhoneNumber`.
  - When 6-digit SMS code is entered, confirm verification and send `idToken` to `/api/auth/firebase/verify`.

---

## 🧪 Verification & Acceptance Criteria

1. **Physical Device SMS Test**:
   - Open app on physical Android phone or emulator.
   - Enter your actual 10-digit Indian mobile number.
   - Check phone: Real SMS from Google Firebase is received with a 6-digit code.
2. **Registration Flow**:
   - For a new phone number: after entering the 6-digit code, the app transitions to "A few details about you" (Name, Age, Role, Address).
   - Submitting the form creates the account in the SQLite DB and opens the dashboard.
3. **Login Flow**:
   - Signing out and entering the same phone number logs in immediately upon OTP verification (no profile form prompted).
4. **Offline / Unit Test Integrity**:
   - Run `npm test` in the root directory. All 13+ tests must continue passing without regression.
