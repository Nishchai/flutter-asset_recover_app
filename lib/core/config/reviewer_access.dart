/// Fixed sign-in credentials for the app-store reviewer account.
///
/// Google Play reviewers cannot receive a real SMS OTP, so ONE dedicated number
/// signs in with a fixed code instead. Everything else about sign-in is
/// unchanged: the number must still resolve through the `commonLogin` directory
/// lookup, and the OAuth token is still minted. Only the SMS send and the
/// Gupshup verification are skipped, and only for [mobile].
///
/// SECURITY: this is a deliberate, narrow bypass. The code below is public to
/// anyone who decompiles the app, so [mobile] MUST be a dummy agent in the
/// backend that is assigned sample tickets only — never a real agent and never
/// real customer data. Remove this class (and its two call sites in
/// `ApiTicketRepository`) if the account is retired.
class ReviewerAccess {
  const ReviewerAccess._();

  /// The reviewer account's registered mobile number.
  static const String mobile = '7995213738';

  /// The fixed login OTP accepted for [mobile] (matches the 4-digit login OTP
  /// length configured in `gupshup.otpCodeLength`).
  static const String otp = '1234';

  /// True when [candidate] is the reviewer number.
  static bool isReviewer(String candidate) => candidate.trim() == mobile;

  /// True when [candidateMobile]/[candidateOtp] are exactly the reviewer pair.
  static bool accepts(String candidateMobile, String candidateOtp) =>
      isReviewer(candidateMobile) && candidateOtp.trim() == otp;
}
