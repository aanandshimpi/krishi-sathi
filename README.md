# Krishi Saathi · कृषी साथी

Flutter Android app and responsive browser app for connecting farmers with labour providers. Both use the same Node.js/SQLite booking backend.

## Run locally

Requires Node.js 24 or later.

```sh
npm ci
npm run dev
```

Browser: http://localhost:5173 · API: http://127.0.0.1:3001

## KVK administration

Open http://localhost:5173/admin in a browser, or select **KVK admin sign in** on the Android sign-in screen. The first admin's generated login details are stored in `.data/kvk-first-login.txt` on this computer; change the temporary password on first sign-in. This is a separate admin account, so the same number can continue to use its farmer account through the normal sign-in screen.

On a fresh installation, start the API once, then create the first KVK admin with `npm run admin:create -- 10_DIGIT_MOBILE "Admin name"`. Read the generated temporary password from the private file under `.data/`. Additional admin accounts can be created from the admin dashboard. The admin can view all farmers, providers, teams and bookings; suspend accounts, verify or hide teams, cancel bookings with a reason, and review an audit history. Suspended accounts lose their sessions. Hidden teams cannot receive new requests. Normal registration cannot create an admin account.

The admin login uses a password, with no SMS verification or password reset service. Store the SQLite database and the first-login file privately, and restrict access to the admin dashboard when deploying publicly.

For physical phones on the same Wi-Fi, run `HOST=0.0.0.0 npm run dev` and configure the Android build with the computer's LAN API address. A phone's localhost refers to the phone itself.

## Farmer and provider flow

1. A provider registers with the labour-provider role and publishes crops, skills, worker count, daily rate and GPS base location.
2. A farmer registers, sets farm location and searches by crop, skill and distance.
3. The farmer sends a request with work date, worker count and farm address.
4. The provider opens Bookings and accepts or declines. Acceptance reserves daily team capacity; conflicting requests cannot be accepted.
5. The farmer refreshes Bookings for confirmation, calls the provider or cancels. The provider can open farm directions, share live foreground GPS with the confirmed farmer and mark work completed.

No providers, ratings or independent verification claims are fabricated. Real providers must register. Accounts use mobile number and password; SMS verification is not implemented.

Bookings persist in `.data/krishi.sqlite` across restarts. Server prices are preserved on each booking. Private API requests require authentication and ownership checks. Browser sessions use session storage; Android sessions use encrypted storage. Bookings share the farmer's name, phone, address and supplied farm coordinates with the selected provider.

GPS requires permission. Providers opt into sharing per confirmed booking. Farmers see a map link only when the last GPS update is at most five minutes old; Bookings refreshes every 15 seconds while visible. Sharing is removed when a booking is cancelled or completed. Live GPS updates stop when the app is hidden. Coordinates can be entered manually. Browser GPS requires HTTPS or localhost. Distances are straight-line distances calculated from actual coordinates.

## Android packaging

See [mobile/README.md](mobile/README.md) for APK/AAB builds and release signing. Implementation uses Flutter 3.47.5 and Dart 3.13.4.

## Verification

```sh
npm test
npm run test:browser
npm run build
cd mobile
flutter analyze
flutter test
```

Browser tests use an isolated in-memory API and system Chrome. Set `CHROME_PATH` if Chrome is elsewhere. They cover registration, team publishing, simulated GPS, booking, acceptance, consent-based provider GPS sharing, confirmation, cancellation and admin controls at phone width. API tests check persistence, access control, validation, retry deduplication, capacity and admin access controls. Flutter tests check navigation, networking, foreground GPS lifecycle and admin state.

## Deploy with HTTPS

Docker Compose runs the API with a persistent database volume behind Caddy HTTPS.

1. Point your domain's DNS at your server, install Docker with Compose and open ports 80 and 443.
2. Copy `.env.example` to `.env` and set `APP_DOMAIN` to your hostname.
3. Run `docker compose up --build -d`.
4. Check `https://YOUR_DOMAIN/api/health`, then register provider and farmer accounts.
5. Build Android release against `https://YOUR_DOMAIN`.

`docker compose down` retains the database. Removing the `farm-data` volume deletes accounts and bookings. Back up that volume before replacing the server. Docker is not installed here, so deployment has not been executed.

A public HTTPS server/domain and private Android signing key are needed for an internet-accessible release. Payments, SMS, push notifications, background tracking, independent skill verification and Play publication are not included. Requests reach a registered provider's account; bookings become confirmed when that provider accepts.
