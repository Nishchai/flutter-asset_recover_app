import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';

/// The `data` block of the SM-Partners `commonLogin` response — the real agent
/// record behind a mobile number. Mirrors the legacy Java
/// `LoginResponse.LoginData` field-for-field (the envelope's `status`/`reason`
/// are handled by the repository, which throws on a non-success).
///
/// This is the authoritative profile for the signed-in user: [toAgent] projects
/// it onto the app's [Agent] entity, and the whole record is persisted in
/// encrypted storage as part of the session (see `SessionStore`), so it survives
/// restarts along with the access token.
class PartnerLoginData {
  const PartnerLoginData({
    required this.usermobileNumber,
    required this.userId,
    this.apppartneruserId,
    this.mobileUID = '',
    this.appId,
    this.emailId = '',
    this.isLoggedIn,
    this.partnerId = '',
    this.isActive,
    this.lastloginDate = '',
    this.appVersion = '',
    this.deviceToken = '',
    this.createdDate = '',
    this.createdUser = '',
    this.lastModifiedDate = '',
    this.lastUpdatedUser = '',
    this.lowBalanceThreshold = '',
    this.latestAppVersion = '',
    this.userName = '',
    this.userRole = '',
    this.enableCustomNotification,
  });

  /// The mobile number the agent signed in with (as returned by the backend).
  final String usermobileNumber;

  /// Business user id (e.g. `SUNMU00002340`) — the id every backend request is
  /// scoped by, so it becomes [Agent.id] (see [toAgent]).
  final String userId;

  final int? apppartneruserId;
  final String mobileUID;
  final int? appId;
  final String emailId;
  final bool? isLoggedIn;

  /// The partner this agent belongs to. Retained from the directory record but
  /// NOT the request-scoping id — that is [userId] (see [toAgent]).
  final String partnerId;

  /// False for a deactivated agent — login is refused (see
  /// `RequestLoginOtpUseCase`).
  final bool? isActive;

  final String lastloginDate;
  final String appVersion;
  final String deviceToken;
  final String createdDate;
  final String createdUser;
  final String lastModifiedDate;
  final String lastUpdatedUser;
  final String lowBalanceThreshold;
  final String latestAppVersion;
  final String userName;
  final String userRole;
  final bool? enableCustomNotification;

  /// Projects the partner record onto the app's session identity.
  ///
  /// [Agent.id] is the [userId] (the `SUNMU…` series) — the app's one agent
  /// identifier, used both as the `agentId` query param on every request and in
  /// `{agentId}` path segments, so the two can never disagree. It falls back to
  /// [partnerId] and then the mobile number if the payload omits it.
  ///
  /// The rest of the identity (name, phone, role) also comes from this record —
  /// it is the authoritative directory. `cluster` / `zone` / `recoveredCount` /
  /// `currentLocation` are recovery-domain concepts the partner directory does
  /// not carry, so they are taken from [base] (the agent the recovery backend
  /// returned, if any) and otherwise left empty.
  Agent toAgent({Agent? base}) => Agent(
        id: userId.isNotEmpty
            ? userId
            : partnerId.isNotEmpty
                ? partnerId
                : usermobileNumber,
        name: userName.isNotEmpty ? userName : base?.name ?? '',
        phone: usermobileNumber.isNotEmpty
            ? usermobileNumber
            : base?.phone ?? '',
        role: userRole.isNotEmpty
            ? agentRoleFromString(userRole)
            : base?.role ?? AgentRole.fieldAgent,
        cluster: base?.cluster ?? '',
        zone: base?.zone ?? '',
        recoveredCount: base?.recoveredCount ?? 0,
        currentLocation: base?.currentLocation,
      );

  factory PartnerLoginData.fromJson(Map<String, dynamic> json) =>
      PartnerLoginData(
        // MAP: commonLogin `data` block. Field names match the backend exactly.
        usermobileNumber: json['usermobileNumber'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        apppartneruserId: _asInt(json['apppartneruserId']),
        mobileUID: json['mobileUID'] as String? ?? '',
        appId: _asInt(json['appId']),
        emailId: json['emailId'] as String? ?? '',
        isLoggedIn: json['isLoggedIn'] as bool?,
        partnerId: json['partnerId'] as String? ?? '',
        isActive: json['isActive'] as bool?,
        lastloginDate: json['lastloginDate'] as String? ?? '',
        appVersion: json['appVersion'] as String? ?? '',
        deviceToken: json['deviceToken'] as String? ?? '',
        createdDate: json['createdDate'] as String? ?? '',
        createdUser: json['createdUser'] as String? ?? '',
        lastModifiedDate: json['lastModifiedDate'] as String? ?? '',
        lastUpdatedUser: json['lastUpdatedUser'] as String? ?? '',
        lowBalanceThreshold: json['lowBalanceThreshold']?.toString() ?? '',
        latestAppVersion: json['latestAppVersion'] as String? ?? '',
        userName: json['userName'] as String? ?? '',
        userRole: json['userRole'] as String? ?? '',
        enableCustomNotification: json['enableCustomNotification'] as bool?,
      );

  Map<String, dynamic> toJson() => {
        'usermobileNumber': usermobileNumber,
        'userId': userId,
        'apppartneruserId': apppartneruserId,
        'mobileUID': mobileUID,
        'appId': appId,
        'emailId': emailId,
        'isLoggedIn': isLoggedIn,
        'partnerId': partnerId,
        'isActive': isActive,
        'lastloginDate': lastloginDate,
        'appVersion': appVersion,
        'deviceToken': deviceToken,
        'createdDate': createdDate,
        'createdUser': createdUser,
        'lastModifiedDate': lastModifiedDate,
        'lastUpdatedUser': lastUpdatedUser,
        'lowBalanceThreshold': lowBalanceThreshold,
        'latestAppVersion': latestAppVersion,
        'userName': userName,
        'userRole': userRole,
        'enableCustomNotification': enableCustomNotification,
      };

  /// The backend is inconsistent about numeric-vs-string ids; accept both.
  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
