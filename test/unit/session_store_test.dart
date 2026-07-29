import 'dart:convert';

import 'package:asset_recovery_app/core/services/session_store.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for `flutter_secure_storage` (no platform channels under
/// flutter_test): [disk] survives across instances, so a second store over the
/// same map is exactly "the user relaunched the app".
class FakeDiskSessionStore extends SessionStore {
  FakeDiskSessionStore(
    this.disk, {
    super.onAuthTokenChanged,
    super.onAgentIdChanged,
  });

  final Map<String, String> disk;

  static const _tokenKey = 'session.authToken';
  static const _agentKey = 'session.agent';
  static const _profileKey = 'session.profile';

  @override
  Future<PersistedSession?> load() async {
    final token = disk[_tokenKey];
    final agentJson = disk[_agentKey];
    if (token == null || token.isEmpty || agentJson == null) return null;
    final profileJson = disk[_profileKey];
    return PersistedSession(
      authToken: token,
      agent: Agent.fromJson(jsonDecode(agentJson) as Map<String, dynamic>),
      profile: profileJson == null
          ? null
          : PartnerLoginData.fromJson(
              jsonDecode(profileJson) as Map<String, dynamic>,),
    );
  }

  @override
  Future<void> persist(PersistedSession session) async {
    disk[_tokenKey] = session.authToken;
    disk[_agentKey] = jsonEncode(session.agent.toJson());
    final profile = session.profile;
    if (profile == null) {
      disk.remove(_profileKey);
    } else {
      disk[_profileKey] = jsonEncode(profile.toJson());
    }
  }

  @override
  Future<void> eraseAuthToken() async => disk.remove(_tokenKey);

  @override
  Future<void> erase() async => disk
    ..remove(_tokenKey)
    ..remove(_agentKey)
    ..remove(_profileKey);
}

void main() {
  const agent = Agent(
    id: 'SUNMU00002340',
    name: 'Ravi Kumar',
    cluster: 'Bengaluru South',
    recoveredCount: 7,
    phone: '9876543210',
  );

  /// The `commonLogin` record the agent was resolved from. `partnerId` is what
  /// scopes every API request — deliberately different from [agent]'s id here,
  /// which models a session written by a build that stored the `userId`.
  const profile = PartnerLoginData(
    usermobileNumber: '9876543210',
    userId: 'SUNMU00002340',
    partnerId: 'SUNMU0000234',
    userName: 'Ravi Kumar',
    isActive: true,
  );

  group('SessionStore', () {
    test('no stored session on a first launch — login screen is shown', () async {
      final store = FakeDiskSessionStore({});

      expect(await store.restore(), isNull);
      expect(store.hasSession, isFalse);
      expect(store.current, isNull);
    });

    test('a saved session is restored on the next launch, so the login and '
        'OTP screens are skipped', () async {
      final disk = <String, String>{};
      await FakeDiskSessionStore(disk).save(
        const PersistedSession(authToken: 'token-1', agent: agent),
      );

      // Relaunch: a brand-new store over the same "disk".
      final restored = await FakeDiskSessionStore(disk).restore();

      expect(restored, isNotNull);
      expect(restored!.authToken, 'token-1');
      expect(restored.agent.id, agent.id);
      expect(restored.agent.phone, agent.phone);
    });

    test('logout wipes the session — the next launch asks for the OTP again',
        () async {
      final disk = <String, String>{};
      final store = FakeDiskSessionStore(disk);
      await store.save(
        const PersistedSession(authToken: 'token-1', agent: agent),
      );

      await store.clear();

      expect(store.current, isNull);
      expect(store.hasSession, isFalse);
      expect(disk, isEmpty);
      expect(await FakeDiskSessionStore(disk).restore(), isNull);
    });

    test('a 401 swaps the token in place and keeps the agent signed in',
        () async {
      final disk = <String, String>{};
      final store = FakeDiskSessionStore(disk);
      await store.save(
        const PersistedSession(authToken: 'expired-token', agent: agent),
      );

      // What ApiClient.onUnauthorized does: drop the rejected token, then
      // persist the freshly minted one.
      await store.clearAuthToken();
      expect(disk.containsKey('session.authToken'), isFalse,
          reason: 'the rejected token must not survive to the next launch',);
      expect(store.current?.agent.id, agent.id,
          reason: 'the agent stays signed in while the token is re-minted',);

      await store.replaceAuthToken('fresh-token');

      expect(store.current!.authToken, 'fresh-token');
      final restored = await FakeDiskSessionStore(disk).restore();
      expect(restored!.authToken, 'fresh-token');
      expect(restored.agent.id, agent.id);
    });

    test('a token re-mint that fails leaves no session to restore', () async {
      final disk = <String, String>{};
      final store = FakeDiskSessionStore(disk);
      await store.save(
        const PersistedSession(authToken: 'expired-token', agent: agent),
      );

      await store.clearAuthToken(); // re-mint then throws — nothing replaces it

      expect(await FakeDiskSessionStore(disk).restore(), isNull);
    });

    test('every token transition is pushed to the ApiClient sink', () async {
      final seen = <String?>[];
      final disk = <String, String>{};
      final store = FakeDiskSessionStore(disk, onAuthTokenChanged: seen.add);

      await store.restore(); // nothing stored yet
      await store.save(
        const PersistedSession(authToken: 'token-1', agent: agent),
      );
      await store.clearAuthToken();
      await store.replaceAuthToken('token-2');
      await store.clear();

      expect(seen, [null, 'token-1', null, 'token-2', null]);
    });

    test('the request-scoping agentId is the commonLogin partnerId', () async {
      final seen = <String?>[];
      final disk = <String, String>{};
      final store = FakeDiskSessionStore(disk, onAgentIdChanged: seen.add);

      await store.save(const PersistedSession(
        authToken: 'token-1',
        agent: agent,
        profile: profile,
      ),);
      expect(store.current!.apiAgentId, 'SUNMU0000234');

      // Relaunch: restored from disk, still the partnerId — and the restored
      // agent is re-projected from the profile, so the id used in `{agentId}`
      // path segments matches the query param even though this record was
      // written with the userId.
      final relaunched = FakeDiskSessionStore(disk, onAgentIdChanged: seen.add);
      await relaunched.restore();
      expect(relaunched.current!.apiAgentId, 'SUNMU0000234');
      expect(relaunched.current!.agent.id, 'SUNMU0000234');
      expect(relaunched.current!.agent.cluster, 'Bengaluru South',
          reason: 're-projection must not drop recovery-domain fields',);

      await store.clear();
      expect(seen, ['SUNMU0000234', 'SUNMU0000234', null],
          reason: 'set on login and restore, cleared on logout',);
    });

    test('logout clears the agentId, and the next login scopes calls to the '
        'agent ITS commonLogin returned', () async {
      // Stands in for `ApiClient.agentId`, which is exactly what the DI
      // container wires onAgentIdChanged to.
      String? apiAgentId;
      final disk = <String, String>{};
      final store =
          FakeDiskSessionStore(disk, onAgentIdChanged: (id) => apiAgentId = id);

      // Agent A signs in.
      await store.save(const PersistedSession(
        authToken: 'token-a',
        agent: agent,
        profile: profile,
      ),);
      expect(apiAgentId, 'SUNMU0000234');

      // …and signs out: no agent id is left on the client, and nothing of the
      // session survives on disk to be restored.
      await store.clear();
      expect(apiAgentId, isNull);
      expect(store.current, isNull);
      expect(disk, isEmpty);

      // Agent B signs in on the same device. Their own commonLogin partnerId —
      // not A's — is what every request is scoped by from here on.
      await store.save(const PersistedSession(
        authToken: 'token-b',
        agent: Agent(
          id: 'SUNMU0000999',
          name: 'Anita Rao',
          cluster: 'Bengaluru North',
          recoveredCount: 0,
          phone: '9000000001',
        ),
        profile: PartnerLoginData(
          usermobileNumber: '9000000001',
          userId: 'SUNMU00009990',
          partnerId: 'SUNMU0000999',
          userName: 'Anita Rao',
          isActive: true,
        ),
      ),);

      expect(apiAgentId, 'SUNMU0000999');
      expect(store.current!.apiAgentId, 'SUNMU0000999');
    });

    test('the 401 token swap does NOT disturb the agentId', () async {
      final seen = <String?>[];
      final store = FakeDiskSessionStore({}, onAgentIdChanged: seen.add);
      await store.save(const PersistedSession(
        authToken: 'expired-token',
        agent: agent,
        profile: profile,
      ),);

      await store.clearAuthToken();
      await store.replaceAuthToken('fresh-token');

      expect(store.current!.apiAgentId, 'SUNMU0000234',
          reason: 'the retried request still needs its agentId',);
      expect(seen, ['SUNMU0000234', 'SUNMU0000234'],
          reason: 'no null pushed mid-swap — same agent throughout',);
    });

    test('agentId falls back to the agent id when no partnerId was returned',
        () async {
      final store = FakeDiskSessionStore({});

      await store.save(
        const PersistedSession(authToken: 'token-1', agent: agent),
      );

      expect(store.current!.apiAgentId, agent.id);
    });

    test('the partner profile survives a relaunch', () async {
      final disk = <String, String>{};
      await FakeDiskSessionStore(disk).save(const PersistedSession(
        authToken: 'token-1',
        agent: agent,
        profile: profile,
      ),);

      final restored = await FakeDiskSessionStore(disk).restore();

      expect(restored!.profile!.partnerId, 'SUNMU0000234');
      expect(restored.profile!.userId, 'SUNMU00002340');
      expect(restored.profile!.userName, 'Ravi Kumar');
    });

    test('InMemorySessionStore keeps a session for the run', () async {
      final store = InMemorySessionStore();

      expect(await store.restore(), isNull);
      await store.save(
        const PersistedSession(authToken: 'token-1', agent: agent),
      );

      expect((await store.restore())!.authToken, 'token-1');
      await store.clear();
      expect(await store.restore(), isNull);
    });
  });
}
