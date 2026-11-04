# Reviewer access & demo video

Play Console → App content → **App access**: select "All or some functionality is
restricted" and add instructions + credentials. Google reviewers cannot receive
real SMS OTPs, so they need a way in.

## Findings in the code
- `useMockData` (EnvironmentConfig) swaps in `MockTicketRepository`; in that mode
  the login screen accepts **any 10-digit mobile + any 6-digit OTP**
  (login_screen.dart) and shows a demo hint.
- The release build uses `prod.json` (`defaultEnvironment: "prod"`) with
  `useMockData: false`, so reviewers **cannot** log in today.

## Options (pick one — needs backend/product decision)
1. **Backend test agent (recommended):** create a dedicated test agent in prod
   with a fixed OTP the Gupshup/backend flow accepts, plus a few dummy tickets.
   No app change; list the number + OTP in App access instructions.
2. **Allow-listed demo number in the app:** hard-coded number → mock repository.
   Simple but ships a login bypass in prod; not recommended.
3. **Separate reviewer build flavor with `useMockData: true`:** only for Play
   internal/closed track; never promoted to production.

## App access text (fill in after choosing option 1)
> Sign in with mobile number [[NUMBER]] and OTP [[OTP]]. The account has sample
> tickets. Grant location, camera and phone permissions when prompted. To test the
> call feature open any ticket → Call Customer → Start Call.

## Demo video checklist (for CALL_PHONE / READ_PHONE_STATE)
Upload as unlisted YouTube/Drive link that opens without login.
1. Launch app, sign in.
2. Open a ticket → Call Customer.
3. Tap Start Call — show the permission prompt and the call being placed.
4. End call — show duration recorded in the app.
5. Show a text overlay: "Calling the customer is the core recovery workflow."
Also briefly show location (geo-fence) and camera/QR use.
