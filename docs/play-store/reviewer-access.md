# Reviewer access & demo video

Play Console → App content → **App access**: select "All or some functionality is
restricted" and add the instructions below. Google reviewers cannot receive real
SMS OTPs, so one dedicated number signs in with a fixed code.

## How it works (implemented)
- `lib/core/config/reviewer_access.dart` defines the reviewer number and fixed OTP.
- `ApiTicketRepository` skips the SMS send and the Gupshup check **only** for that
  number + code. Any other number, or any other code for that number, goes through
  the normal flow.
- Sign-in is otherwise unchanged: the number still goes through the `commonLogin`
  directory lookup and the OAuth token is still minted.

## Backend prerequisites (must be true before submitting)
1. The reviewer number must exist in the SM-Partners directory as an **active**
   agent, otherwise `commonLogin` rejects it before the OTP step.
2. That agent must be a **dummy account** with sample tickets only. The bypass is
   readable by anyone who decompiles the app, so this account must never be a
   real agent and must never expose real customer data.
3. Optional: limit what the account can do server-side (no real recoveries).

## Known limits
- End-shift and handover OTPs still use real SMS. Tell reviewers not to use them
  (or bypass them too if needed).
- Proof photos upload to real Azure storage; dummy photos only.

## App access text (paste into Play Console)
> Sign in with mobile number 7995213738 and OTP 1234. The account has sample
> tickets. Grant location, camera and phone permissions when prompted. To test the
> call feature open any ticket → Call Customer → Start Call.

## Removing it later
Delete `reviewer_access.dart` and the two `ReviewerAccess` checks in
`ApiTicketRepository` (`requestLoginOtp`, `verifyLoginOtp`), and
`test/unit/reviewer_access_test.dart`.

## Demo video checklist (for CALL_PHONE / READ_PHONE_STATE)
Upload as unlisted YouTube/Drive link that opens without login.
1. Launch app, sign in (using the reviewer number + OTP).
2. Open a ticket → Call Customer.
3. Tap Start Call — show the permission prompt and the call being placed.
4. End call — show duration recorded in the app.
5. Show a text overlay: "Calling the customer is the core recovery workflow."
Also briefly show location (geo-fence) and camera/QR use.
