# Flutter Android app

Native farmer/provider/KVK admin app with English and Marathi screens, GPS and server-backed bookings.

Farmers and labour providers sign in with a mobile number and SMS code; they do not need a password. On first use they provide a name, age, village and role. The server must have MSG91 SendOTP credentials configured; see the root README. Existing accounts sign in with the same verified phone number. KVK admin sign-in still uses a password.

## Run

From the repository root:

```sh
HOST=0.0.0.0 npm run dev
```

With Flutter and Android SDK installed, from `mobile/`:

```sh
flutter pub get
# Android emulator:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3001
# Physical phone on the same Wi-Fi:
flutter run --dart-define=API_BASE_URL=http://YOUR_COMPUTER_IP:3001
```

Debug builds permit local HTTP. Releases require HTTPS. Internet and foreground location permissions are declared. Background location permission is not requested. Secure-session backups are disabled.

To sign in as a KVK admin, open the account sign-in screen and enable **KVK admin sign in**. The first admin's generated login details are in the backend's private `.data/kvk-first-login.txt` file. Change the temporary password after first sign-in. The admin dashboard manages accounts, team verification and visibility, bookings and audit history. Admin accounts are separate from farmer/provider accounts, even when they share a phone number.

## Development APK

From the repository root:

```sh
# Set FLUTTER_BIN=/path/to/flutter if needed.
scripts/build-android.sh debug http://YOUR_COMPUTER_IP:3001
```

Output: `artifacts/krishi-saathi-debug.apk`. The phone must reach the API address used at compile time. Use `10.0.2.2` for an emulator, a LAN address for physical phones or a deployed HTTPS service.

## Production APK and Play app bundle

Deploy the backend first. Generate an upload key locally if needed:

```sh
keytool -genkeypair -v -keystore /YOUR_PRIVATE_PATH/krishi-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `android/key.properties.example` to `android/key.properties`, fill your private key path and passwords locally, then run from the repository root:

```sh
scripts/build-android.sh release https://YOUR_DOMAIN
```

The script validates and creates `artifacts/krishi-saathi-release.apk` and `artifacts/krishi-saathi-release.aab`. Gradle refuses release without your signing configuration. Keep the key and passwords out of source control and preserve the key for updates. App ID: `in.krishisaathi.krishi_saathi`. Change it before first publication if needed. Increment the version in `pubspec.yaml` for updates.

Configuration follows the [official Flutter Android packaging documentation](https://docs.flutter.dev/deployment/android). GPS uses the [Geolocator plugin](https://pub.dev/packages/geolocator).

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3001
```

Automated GPS tests simulate coordinates, permissions and lifecycle events. Physical GPS reception and installation require a real phone; none is connected here. Bookings refreshes every 15 seconds while visible. Providers can opt into sharing GPS for each confirmed booking; farmers see a map link and last update time only while the GPS fix is fresh (five minutes). GPS resumes in the foreground after an enabled provider reopens the app. SMS and push notifications are not configured.
