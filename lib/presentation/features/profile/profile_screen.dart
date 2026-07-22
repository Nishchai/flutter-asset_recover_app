import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/localization/locale_provider.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Profile + settings: language switching (6 languages) and session info.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final agent = context.read<AuthProvider>().agent!;
    final config = context.read<AppServices>().config;
    final localeProvider = context.watch<LocaleProvider>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: palette.primary,
                  child: Text(agent.initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,),),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold,),),
                    Text('${l.t('profile.role')} · ${agent.cluster}',
                        style: TextStyle(color: palette.muted),),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            _statRow(l, agent.recoveredCount, palette),
            const SizedBox(height: 16),
            _SectionTitle(l.t('profile.language'), palette),
            _LanguagePicker(
              config: config,
              current: localeProvider.locale.languageCode,
              palette: palette,
              onSelect: (code) => localeProvider.setLanguage(code),
            ),
            const SizedBox(height: 16),
            _SectionTitle(l.t('profile.session'), palette),
            _InfoTile(
              icon: Icons.timer_outlined,
              title: l.t('profile.autoLogout', {'hours': config.autoLogoutHours}),
              palette: palette,
            ),
            _InfoTile(
              icon: Icons.cloud_outlined,
              title: '${l.t('profile.environment')}: ${config.env.label}',
              palette: palette,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.read<AuthProvider>().logout(),
                style: OutlinedButton.styleFrom(foregroundColor: palette.danger),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(l.t('common.logout')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(AppLocalizations l, int recovered, AppPalette palette) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: palette.primary),
          const SizedBox(width: 10),
          Text('$recovered ${l.t('common.recovered')}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: palette.primaryDark,),),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.palette);
  final String text;
  final AppPalette palette;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: palette.onSurface,),),
      );
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.config,
    required this.current,
    required this.palette,
    required this.onSelect,
  });

  final dynamic config;
  final String current;
  final AppPalette palette;
  final ValueChanged<String> onSelect;

  static const _names = {
    'en': 'English',
    'hi': 'हिन्दी',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'kn': 'ಕನ್ನಡ',
    'mr': 'मराठी',
  };

  @override
  Widget build(BuildContext context) {
    final langs = (config.supportedLanguages as List).cast<String>();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final code in langs)
          ChoiceChip(
            label: Text(_names[code] ?? code),
            selected: code == current,
            onSelected: (_) => onSelect(code),
            selectedColor: palette.primary,
            labelStyle: TextStyle(
              color: code == current ? Colors.white : palette.onSurface,
            ),
          ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.icon, required this.title, required this.palette,});
  final IconData icon;
  final String title;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
        ],
      ),
    );
  }
}
