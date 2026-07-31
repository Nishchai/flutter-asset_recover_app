import 'dart:convert';
import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/utils/ist_time.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in session as persisted between app launches: the backend access
/// token plus the agent it belongs to.
///
/// [authToken] and [agent] are both required — a token with no agent (or
/// vice-versa) is not a usable session, so [SessionStore.restore] treats a
/// half-written record as "no session" and the login screen is shown again.
/// [profile] is the full `commonLogin` record the agent was resolved from
/// (partnerId, role, email, thresholds…); it is stored whenever the real backend
/// supplied one.
class PersistedSession {
  const PersistedSession({
    required this.authToken,
    required this.agent,
    this.profile,
    this.loginAt,
  });

  final String authToken;
  final Agent agent;
  final PartnerLoginData? profile;

  /// The IST wall-clock moment the OTP was verified — the anchor of the fixed
  /// auto-logout window (see [sessionRemaining]). Written once, at sign-in, and
  /// deliberately never refreshed afterwards: neither activity nor the 401
  /// token re-mint may extend the window.
  ///
  /// Null only for a session written by a build from before this existed, which
  /// [sessionRemaining] reports as already elapsed — costing that agent one
  /// extra OTP, once.
  final DateTime? loginAt;

  /// The id every backend request is scoped to (`agentId` query param): the
  /// `commonLogin` [PartnerLoginData.partnerId].
  ///
  /// [Agent.id] is already the partnerId (`PartnerLoginData.toAgent`), so for a
  /// current session the two agree — reading the profile first is what keeps a
  /// session persisted by an older build (whose `agent.id` was the `userId`)
  /// scoped correctly, and covers mock sessions that carry no profile at all.
  String get apiAgentId {
    final partnerId = profile?.partnerId ?? '';
    return partnerId.isNotEmpty ? partnerId : agent.id;
  }

  /// How much of the fixed post-login [window] is left, measured on the IST
  /// clock: `window - (now - loginAt)`.
  ///
  /// The window is ABSOLUTE, not idle-based (PRD §4.9). An agent who signs in
  /// at 08:00 IST with a 12-hour window has 8 hours left when they open the app
  /// at 12:00, and a NEGATIVE duration at 20:30 — at which point the session is
  /// already over and they are signed out on the spot.
  ///
  /// Zero when there is no [loginAt] to anchor to: an unanchored session cannot
  /// be shown to be inside its window, so it is treated as outside it.
  Duration sessionRemaining(Duration window) {
    final start = loginAt;
    if (start == null) return Duration.zero;
    return window - nowIst().difference(start);
  }

  /// True once [sessionRemaining] has run out — the agent must sign in again.
  bool isSessionExpired(Duration window) =>
      sessionRemaining(window) <= Duration.zero;

  PersistedSession copyWith({
    String? authToken,
    Agent? agent,
    PartnerLoginData? profile,
    DateTime? loginAt,
  }) =>
      PersistedSession(
        authToken: authToken ?? this.authToken,
        agent: agent ?? this.agent,
        profile: profile ?? this.profile,
        loginAt: loginAt ?? this.loginAt,
      );
}

/// Persists the signed-in session so the mobile-number + OTP screens are shown
/// only ONCE — on every later launch [restore] hands back the saved token and
/// agent and the app opens straight on the home shell.
///
/// [current] mirrors what is on disk in memory, so anything constructed after
/// [restore] (e.g. `AuthProvider`) can read the session synchronously.
///
/// Lifecycle:
/// * OTP verified → [save] (token + agent + the IST [PersistedSession.loginAt]
///   the auto-logout window is measured from)
/// * 401 on any API call → [clearAuthToken] then [replaceAuthToken] with the
///   freshly minted one (see `configureDependencies`)
/// * logout / session expiry → [clear]
abstract class SessionStore {
  SessionStore({this.onAuthTokenChanged, this.onAgentIdChanged});

  /// Notified with the live access token (null when there is none) on every
  /// transition: restore, save, 401 swap and logout. The DI container wires it
  /// to `ApiClient.authToken`, so the store is the single owner of the
  /// credential and no caller has to remember to sync the HTTP layer.
  final void Function(String? authToken)? onAuthTokenChanged;

  /// Notified with [PersistedSession.apiAgentId] whenever the signed-in identity
  /// changes — restore, login and logout ONLY. Deliberately silent during the
  /// 401 token swap: the credential is being replaced, but it is the same agent,
  /// and the retried request still needs its `agentId`. Wired to
  /// `ApiClient.agentId`.
  final void Function(String? agentId)? onAgentIdChanged;

  PersistedSession? _current;

  /// The restored/last-saved session, or null when signed out. Valid only after
  /// [restore] has run once (the DI container does this at startup).
  PersistedSession? get current => _current;

  bool get hasSession => _current != null;

  /// Time left in the signed-in agent's fixed auto-logout [window], on the IST
  /// clock. [Duration.zero] when nobody is signed in — there is nothing left to
  /// expire. See [PersistedSession.sessionRemaining].
  Duration remainingSession(Duration window) =>
      _current?.sessionRemaining(window) ?? Duration.zero;

  /// Loads the persisted session into [current] and returns it.
  ///
  /// The stored agent is re-projected from the stored profile, so the id the app
  /// runs on is always the current mapping (the `partnerId`) even for a session
  /// written by a build that persisted something else.
  Future<PersistedSession?> restore() async {
    var loaded = await load();
    final profile = loaded?.profile;
    if (loaded != null && profile != null) {
      loaded = loaded.copyWith(agent: profile.toAgent(base: loaded.agent));
    }
    _current = loaded;
    onAuthTokenChanged?.call(loaded?.authToken);
    onAgentIdChanged?.call(loaded?.apiAgentId);
    return loaded;
  }

  Future<void> save(PersistedSession session) async {
    _current = session;
    onAuthTokenChanged?.call(session.authToken);
    onAgentIdChanged?.call(session.apiAgentId);
    await persist(session);
  }

  /// Erases the rejected access token from disk, so a token we know the backend
  /// refuses is never restored on a later launch. [current] deliberately keeps
  /// the in-memory session: the agent is still signed in, we are only swapping
  /// their credential. If the re-mint that follows fails, the next launch finds
  /// no token and asks for the OTP again.
  Future<void> clearAuthToken() async {
    onAuthTokenChanged?.call(null);
    await eraseAuthToken();
  }

  /// Stores a freshly minted token against the agent that was signed in when
  /// the 401 happened. No-op when nobody is signed in.
  Future<void> replaceAuthToken(String authToken, {Agent? agent}) async {
    final existing = _current;
    if (existing == null) {
      if (agent == null) return;
      await save(PersistedSession(authToken: authToken, agent: agent));
      return;
    }
    await save(existing.copyWith(authToken: authToken, agent: agent));
  }

  Future<void> clear() async {
    _current = null;
    onAuthTokenChanged?.call(null);
    onAgentIdChanged?.call(null);
    await erase();
  }

  // --- Storage backend (implemented per platform / per test) ----------------
  Future<PersistedSession?> load();
  Future<void> persist(PersistedSession session);
  Future<void> eraseAuthToken();
  Future<void> erase();
}

/// Real implementation backed by `flutter_secure_storage`: Android
/// EncryptedSharedPreferences (AES-256, key in the platform keystore) and the
/// iOS Keychain. The token never lands in plain SharedPreferences.
class SecureSessionStore extends SessionStore {
  SecureSessionStore({
    FlutterSecureStorage? storage,
    super.onAuthTokenChanged,
    super.onAgentIdChanged,
  })
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  static const _tokenKey = 'session.authToken';
  static const _agentKey = 'session.agent';
  static const _profileKey = 'session.profile';
  static const _loginAtKey = 'session.loginAt';

  final FlutterSecureStorage _storage;

  @override
  Future<PersistedSession?> load() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      final agentJson = await _storage.read(key: _agentKey);
      if (token == null || token.isEmpty || agentJson == null) return null;
      final decoded = jsonDecode(agentJson);
      if (decoded is! Map<String, dynamic>) return null;
      final profileJson = await _storage.read(key: _profileKey);
      final decodedProfile =
          profileJson == null ? null : jsonDecode(profileJson);
      return PersistedSession(
        authToken: token,
        agent: Agent.fromJson(decoded),
        profile: decodedProfile is Map<String, dynamic>
            ? PartnerLoginData.fromJson(decodedProfile)
            : null,
        loginAt: istFromIso(await _storage.read(key: _loginAtKey)),
      );
    } catch (e, st) {
      // A rotated/invalidated keystore key (device restore, "clear data" on
      // some OEMs) makes reads throw. An unreadable session is no session:
      // wipe it and fall back to the login screen rather than crashing at
      // startup.
      developer.log('session restore failed; clearing',
          name: 'SessionStore', error: e, stackTrace: st,);
      await erase();
      return null;
    }
  }

  @override
  Future<void> persist(PersistedSession session) async {
    await _storage.write(key: _tokenKey, value: session.authToken);
    await _storage.write(
      key: _agentKey,
      value: jsonEncode(session.agent.toJson()),
    );
    final profile = session.profile;
    if (profile == null) {
      await _storage.delete(key: _profileKey);
    } else {
      await _storage.write(key: _profileKey, value: jsonEncode(profile.toJson()));
    }
    final loginAt = session.loginAt;
    if (loginAt == null) {
      await _storage.delete(key: _loginAtKey);
    } else {
      await _storage.write(key: _loginAtKey, value: loginAt.toIso8601String());
    }
  }

  @override
  Future<void> eraseAuthToken() => _storage.delete(key: _tokenKey);

  @override
  Future<void> erase() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _agentKey);
    await _storage.delete(key: _profileKey);
    await _storage.delete(key: _loginAtKey);
  }
}

/// Non-persistent store for the deterministic `test` environment, where the
/// platform channels `flutter_secure_storage` needs aren't available. Behaves
/// identically within a run; nothing survives it.
class InMemorySessionStore extends SessionStore {
  InMemorySessionStore({super.onAuthTokenChanged, super.onAgentIdChanged});

  PersistedSession? _stored;

  @override
  Future<PersistedSession?> load() async => _stored;

  @override
  Future<void> persist(PersistedSession session) async => _stored = session;

  @override
  Future<void> eraseAuthToken() async => _stored = null;

  @override
  Future<void> erase() async => _stored = null;
}
