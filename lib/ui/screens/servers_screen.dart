import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/managers/sutemi_controller.dart';
import '../../core/models/vpn_models.dart';
import '../../core/sources/builtin_sources.dart';
import '../theme/sutemi_theme.dart';
import '../widgets/country_badge.dart';

class ServersScreen extends StatefulWidget {
  final SutemiController controller;
  final VoidCallback onConnectedNavigateHome;

  const ServersScreen({
    super.key,
    required this.controller,
    required this.onConnectedNavigateHome,
  });

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _importCtrl = TextEditingController();
  int _selectedGroupId = -1;
  final Set<int> _checkedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _importCtrl.dispose();
    super.dispose();
  }

  List<VpnProfile> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final list = widget.controller.profiles.where((p) {
      if (_selectedGroupId != -1 && p.groupId != _selectedGroupId) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.country.toLowerCase().contains(q) ||
          p.protocol.name.toLowerCase().contains(q) ||
          p.address.toLowerCase().contains(q);
    }).toList();

    list.sort((a, b) {
      int rank(VpnProfile p) {
        final l = p.latencyMs;
        if (l != null && l > 0) return l;
        if (l != null && l < 0) return 400000;
        return 300000;
      }

      return rank(a).compareTo(rank(b));
    });
    return list;
  }

  void _showCuratedSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SutemiColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Curated Collections', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                FilterChip(
                  label: const Text('Smart Filter'),
                  selected: widget.controller.settings.smartFilter,
                  onSelected: (v) => widget.controller.updateSettings(
                    widget.controller.settings.copyWith(smartFilter: v),
                  ),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Strict TLS'),
                  selected: widget.controller.settings.strictTls,
                  onSelected: (v) => widget.controller.updateSettings(
                    widget.controller.settings.copyWith(strictTls: v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: ListView.separated(
                itemCount: kBuiltinSources.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, idx) {
                  final src = kBuiltinSources[idx];
                  final existing = widget.controller.groups
                      .where((g) => g.url == src.url || g.name == src.name)
                      .firstOrNull;
                  return ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    tileColor: Colors.white.withValues(alpha: 0.05),
                    title: Text(src.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(src.desc, style: const TextStyle(fontSize: 11, color: SutemiColors.textSecondary)),
                    trailing: FilledButton.tonal(
                      onPressed: widget.controller.isImporting
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              try {
                                final msg = await widget.controller.addBuiltinSource(src.id);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                                }
                              }
                            },
                      child: Text(existing != null ? 'Update' : 'Load'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _importCtrl,
                      decoration: InputDecoration(
                        hintText: 'Paste vless://, hy2://, tuic:// or sub URL...',
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: widget.controller.isImporting
                        ? null
                        : () async {
                            try {
                              final msg = await widget.controller.importTextOrUrl(_importCtrl.text);
                              _importCtrl.clear();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                              }
                            }
                          },
                    child: const Text('Add'),
                  ),
                  IconButton(
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _importCtrl.text = data!.text!;
                      }
                    },
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _showCuratedSheet,
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('Curated'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: items.isEmpty ? null : widget.controller.connectFastest,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Fastest'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: widget.controller.isScanningPing
                          ? widget.controller.cancelPingScan
                          : () => widget.controller.runPingScan(items),
                      icon: Icon(widget.controller.isScanningPing ? Icons.stop_rounded : Icons.speed_rounded, size: 18),
                      label: Text(widget.controller.isScanningPing ? 'Stop' : 'Ping all'),
                    ),
                    if (_checkedIds.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () async {
                          final toRemove = Set<int>.from(_checkedIds);
                          _checkedIds.clear();
                          await widget.controller.deleteProfiles(toRemove);
                        },
                        child: Text('Delete (${_checkedIds.length})'),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.controller.isImporting || widget.controller.isScanningPing) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: widget.controller.isScanningPing && widget.controller.scanTotal > 0
                      ? widget.controller.scanDone / widget.controller.scanTotal
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.controller.isImporting
                      ? widget.controller.importStatusLabel
                      : 'Scanning ${widget.controller.scanDone}/${widget.controller.scanTotal} · ${widget.controller.scanOnline} online',
                  style: const TextStyle(fontSize: 11, color: SutemiColors.textSecondary),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search (DE, NL, VLESS, HY2...)',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (widget.controller.groups.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ChoiceChip(
                        label: Text('All (${widget.controller.profiles.length})'),
                        selected: _selectedGroupId == -1,
                        onSelected: (_) => setState(() => _selectedGroupId = -1),
                      ),
                      for (final g in widget.controller.groups) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text(g.name),
                          selected: _selectedGroupId == g.id,
                          onSelected: (_) => setState(() => _selectedGroupId = g.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'No servers found. Paste a link or open Curated collections.',
                    style: TextStyle(color: SutemiColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  itemCount: items.length,
                  itemBuilder: (_, idx) {
                    final p = items[idx];
                    final isActive = widget.controller.connectedProfileId == p.id &&
                        widget.controller.connectionState == VpnConnectionState.connected;
                    return Card(
                      color: isActive
                          ? SutemiColors.mint.withValues(alpha: 0.12)
                          : Colors.white.withValues(alpha: 0.04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isActive
                              ? SutemiColors.mint.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: ListTile(
                        onTap: () async {
                          await widget.controller.selectProfile(p.id);
                          await widget.controller.connect(p.id);
                          widget.onConnectedNavigateHome();
                        },
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _checkedIds.contains(p.id),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _checkedIds.add(p.id);
                                } else {
                                  _checkedIds.remove(p.id);
                                }
                              }),
                            ),
                            CountryBadge(code: p.country, verified: p.countryVerified, compact: true),
                          ],
                        ),
                        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${p.protocol.name.toUpperCase()} · ${p.address}:${p.port}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: SutemiColors.textSecondary),
                        ),
                        trailing: Text(
                          p.latencyMs != null && p.latencyMs! > 0
                              ? '${p.latencyMs} ms'
                              : (p.latencyMs != null && p.latencyMs! < 0 ? 'ERR' : '—'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.latencyMs != null && p.latencyMs! > 0 && p.latencyMs! <= 150
                                ? SutemiColors.mint
                                : SutemiColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
