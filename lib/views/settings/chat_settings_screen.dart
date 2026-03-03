import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_chat_app/providers/theme_provider.dart';
import 'package:flutter_chat_app/services/settings_service.dart';
import 'package:flutter_chat_app/widgets/glass_scaffold.dart';
import 'package:flutter_chat_app/widgets/glass_container.dart';

class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({super.key});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  final SettingsService _settings = SettingsService();

  bool _enterSendsMessage = true;
  String _mediaAutoDownload = 'always';
  String _backupFrequency = 'weekly';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enter = await _settings.isEnterSendsMessage();
    final media = await _settings.getMediaAutoDownload();
    final backup = await _settings.getBackupFrequency();
    if (mounted) {
      setState(() {
        _enterSendsMessage = enter;
        _mediaAutoDownload = media;
        _backupFrequency = backup;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isGlass = themeProvider.isGlassMode;

    return GlassScaffold(
      appBar: isGlass
          ? GlassAppBar(
              title: const Text('Chat'),
            )
          : AppBar(
              title: const Text('Chat'),
              centerTitle: true,
              elevation: 0,
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── Bubble Style ──
                _buildSectionHeader('Chat Bubble Style'),
                _buildCard([
                  _buildBubbleStyleSelector(themeProvider),
                ]),
                const SizedBox(height: 12),

                // ── Input Behavior ──
                _buildSectionHeader('Input'),
                _buildCard([
                  SwitchListTile(
                    title: const Text('Enter Key Sends Message'),
                    subtitle: const Text(
                        'Press Enter to send, Shift+Enter for new line'),
                    value: _enterSendsMessage,
                    activeColor: colorScheme.primary,
                    onChanged: (value) async {
                      setState(() => _enterSendsMessage = value);
                      await _settings.setEnterSendsMessage(value);
                    },
                  ),
                ]),
                const SizedBox(height: 12),

                // ── Media ──
                _buildSectionHeader('Media'),
                _buildCard([
                  _buildMediaAutoDownload(colorScheme),
                ]),
                const SizedBox(height: 12),

                // ── Backup ──
                _buildSectionHeader('Chat Backup'),
                _buildCard([
                  _buildBackupFrequency(colorScheme),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ── Bubble Style Selector ──

  Widget _buildBubbleStyleSelector(ThemeProvider themeProvider) {
    const styles = ['Modern', 'Classic', 'Minimal'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: styles.map((style) {
          final isSelected = themeProvider.chatBubbleStyle == style;
          return Expanded(
            child: GestureDetector(
              onTap: () => themeProvider.setChatBubbleStyle(style),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 80,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.08)
                            : Colors.grey.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.withOpacity(0.2),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: _buildBubblePreview(style, isSelected),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      style,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBubblePreview(String style, bool isSelected) {
    final cs = Theme.of(context).colorScheme;
    final radius = style == 'Modern'
        ? 16.0
        : style == 'Classic'
            ? 8.0
            : 2.0;
    final padding = style == 'Minimal'
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Text('Hi',
                  style: TextStyle(fontSize: 10, color: Colors.grey[800])),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.8),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Text('Hey!',
                  style: TextStyle(fontSize: 10, color: cs.onPrimary)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Media Auto-Download ──

  Widget _buildMediaAutoDownload(ColorScheme cs) {
    const options = {
      'always': ('Always', 'Download all media automatically'),
      'wifi': ('Wi-Fi Only', 'Download only on Wi-Fi'),
      'never': ('Never', 'Ask before downloading'),
    };
    return Column(
      children: options.entries.map((e) {
        final isLast = e.key == options.keys.last;
        return Column(
          children: [
            RadioListTile<String>(
              title: Text(e.value.$1),
              subtitle: Text(e.value.$2,
                  style: const TextStyle(fontSize: 12)),
              value: e.key,
              groupValue: _mediaAutoDownload,
              activeColor: cs.primary,
              onChanged: (value) async {
                if (value != null) {
                  setState(() => _mediaAutoDownload = value);
                  await _settings.setMediaAutoDownload(value);
                }
              },
            ),
            if (!isLast)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        );
      }).toList(),
    );
  }

  // ── Backup Frequency ──

  Widget _buildBackupFrequency(ColorScheme cs) {
    const options = {
      'daily': 'Daily',
      'weekly': 'Weekly',
      'monthly': 'Monthly',
      'never': 'Never',
    };
    return Column(
      children: options.entries.map((e) {
        final isLast = e.key == options.keys.last;
        return Column(
          children: [
            RadioListTile<String>(
              title: Text(e.value),
              value: e.key,
              groupValue: _backupFrequency,
              activeColor: cs.primary,
              onChanged: (value) async {
                if (value != null) {
                  setState(() => _backupFrequency = value);
                  await _settings.setBackupFrequency(value);
                }
              },
            ),
            if (!isLast)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        );
      }).toList(),
    );
  }

  // ── Building Helpers ──

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.15),
          ),
        ),
        child: Column(children: children),
      ),
    );
  }
}
