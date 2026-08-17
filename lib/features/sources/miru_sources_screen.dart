import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';

import '../../core/app_config.dart';
import '../../core/di/injector.dart';
import '../../core/miru/miru_extension_service.dart';
import '../../core/miru/miru_manager.dart';
import '../../core/miru/miru_repo.dart';
import '../../core/miru/miru_script.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/states.dart';
import 'sources_search_field.dart';

/// Phone + TV screen for the Miru extension catalog. Twin of
/// [LnReaderSourcesScreen]: Installed / Repositories tabs, user-added
/// `index.json` URLs in [kMiruReposBoxName].
class MiruSourcesScreen extends StatefulWidget {
  const MiruSourcesScreen({super.key});

  @override
  State<MiruSourcesScreen> createState() => _MiruSourcesScreenState();
}

enum _LoadState { loading, loaded }

class _RepoCatalog {
  const _RepoCatalog({this.entries, this.error});
  final List<MiruExtensionMeta>? entries;
  final Object? error;
}

class _MiruSourcesScreenState extends State<MiruSourcesScreen> {
  _LoadState _state = _LoadState.loading;
  List<String> _repoUrls = [];
  final Map<String, _RepoCatalog> _catalogs = {};
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _typeFilter; // bangumi | manga | fikushon | null

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh || _repoUrls.isEmpty) {
      setState(() => _state = _LoadState.loading);
    }
    if (!Hive.isBoxOpen(kMiruReposBoxName)) {
      await openBoxSafely<String>(kMiruReposBoxName);
    }
    final urls = Hive.box<String>(kMiruReposBoxName).values.toList();
    final service = sl<MiruExtensionService>();
    final fetched = await Future.wait(urls.map((url) async {
      try {
        return MapEntry(url, _RepoCatalog(entries: await service.fetchIndex(url)));
      } catch (e) {
        return MapEntry(url, _RepoCatalog(error: e));
      }
    }));
    if (!mounted) return;
    setState(() {
      _repoUrls = urls;
      _catalogs
        ..clear()
        ..addEntries(fetched);
      _state = _LoadState.loaded;
    });
  }

  Future<void> _addRepo(String raw) async {
    final url = normalizeMiruRepoUrl(raw);
    if (url.isEmpty) return;
    if (!Hive.isBoxOpen(kMiruReposBoxName)) {
      await openBoxSafely<String>(kMiruReposBoxName);
    }
    final box = Hive.box<String>(kMiruReposBoxName);
    if (box.values.contains(url)) return;
    await box.add(url);
    await _load(refresh: true);
  }

  Future<void> _removeRepo(String url) async {
    if (!Hive.isBoxOpen(kMiruReposBoxName)) return;
    final box = Hive.box<String>(kMiruReposBoxName);
    final key = box
        .toMap()
        .entries
        .where((e) => e.value == url)
        .map((e) => e.key)
        .firstOrNull;
    if (key != null) await box.delete(key);
    if (mounted) {
      setState(() {
        _repoUrls = box.values.toList();
        _catalogs.remove(url);
      });
    }
  }

  bool _matches(MiruExtensionMeta m) {
    if (_typeFilter != null && m.type != _typeFilter) return false;
    return sourceSearchMatches(_query, m.name, m.lang);
  }

  Future<void> _showAddRepoDialog() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _MiruAddRepoDialog(),
    );
    if (url == null || url.isEmpty) return;
    await _addRepo(url);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text('Miru', style: AppText.barTitle),
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: AppText.headline,
            unselectedLabelStyle: AppText.headline,
            dividerHeight: 0,
            tabs: const [
              Tab(text: 'Installed'),
              Tab(text: 'Repositories'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          onPressed: _showAddRepoDialog,
          icon: const Icon(Icons.add),
          label: Text(
            'Add repository',
            style: AppText.button.copyWith(color: Colors.white),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SourcesSearchField(
                controller: _searchCtrl,
                onChanged: (q) => setState(() => _query = q),
                hint: 'Search Miru sources',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final t in [
                    (null, 'All'),
                    ('bangumi', 'Video'),
                    ('manga', 'Manga'),
                    ('fikushon', 'Novel'),
                  ])
                    FilterChip(
                      label: Text(t.$2),
                      selected: _typeFilter == t.$1,
                      onSelected: (_) => setState(() => _typeFilter = t.$1),
                      selectedColor: AppColors.accent.withValues(alpha: 0.2),
                      checkmarkColor: AppColors.accent,
                      labelStyle: AppText.caption,
                      side: const BorderSide(color: AppColors.hairline),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [_installedTab(), _repositoriesTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _installedTab() {
    final installed = sl<MiruExtensionService>()
        .installed()
        .where(_matches)
        .toList();
    if (installed.isEmpty) {
      return EmptyState(
        icon: Icons.extension_outlined,
        message: _query.trim().isEmpty
            ? 'No sources installed yet.\n'
                'Add the official Miru repo from Repositories to browse extensions.'
            : 'No installed sources match.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        for (final m in installed)
          _MiruSourceRow(
            meta: m,
            installed: true,
            iconOnly: true,
            onChanged: () => setState(() {}),
          ),
      ],
    );
  }

  Widget _repositoriesTab() {
    if (_state == _LoadState.loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    final installedIds =
        sl<MiruExtensionService>().installed().map((m) => m.package).toSet();
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (_repoUrls.isEmpty)
            EmptyState(
              icon: Icons.extension_outlined,
              message: 'No repositories added.\n'
                  'Add the official Miru repo to browse extensions.',
            )
          else
            for (final url in _repoUrls)
              _repoSection(url, installedIds),
        ],
      ),
    );
  }

  Widget _repoSection(String url, Set<String> installedIds) {
    final catalog = _catalogs[url];
    final error = catalog?.error;
    final entries = [
      for (final m in catalog?.entries ?? const <MiruExtensionMeta>[])
        if (_matches(m)) m,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  style: AppText.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Remove repository',
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.textSecondary,
                onPressed: () => _removeRepo(url),
              ),
            ],
          ),
          if (error != null)
            Text(
              'Failed to load: $error',
              style: AppText.caption.copyWith(color: AppColors.accent),
            )
          else if (entries.isEmpty)
            Text('No sources in this repo.', style: AppText.caption)
          else
            for (final m in entries)
              _MiruSourceRow(
                meta: m,
                installed: installedIds.contains(m.package),
                iconOnly: false,
                onChanged: () => setState(() {}),
              ),
        ],
      ),
    );
  }
}

class _MiruAddRepoDialog extends StatefulWidget {
  const _MiruAddRepoDialog();

  @override
  State<_MiruAddRepoDialog> createState() => _MiruAddRepoDialogState();
}

class _MiruAddRepoDialogState extends State<_MiruAddRepoDialog> {
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: kMiruOfficialRepoUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlCtrl.text.trim();
    if (url.isNotEmpty) Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Add Miru repo', style: AppText.headline),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              cursorColor: AppColors.accent,
              style: AppText.body.copyWith(color: AppColors.textPrimary),
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'index.json URL',
                hintText: kMiruOfficialRepoUrl,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Paste a Miru catalog URL (GitHub repo or index.json). '
              'The official catalog is pre-filled as a starting point.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _MiruSourceRow extends StatefulWidget {
  const _MiruSourceRow({
    required this.meta,
    required this.installed,
    required this.iconOnly,
    required this.onChanged,
  });

  final MiruExtensionMeta meta;
  final bool installed;
  final bool iconOnly;
  final VoidCallback onChanged;

  @override
  State<_MiruSourceRow> createState() => _MiruSourceRowState();
}

class _MiruSourceRowState extends State<_MiruSourceRow> {
  bool _busy = false;

  String get _typeLabel => switch (widget.meta.type) {
    'manga' => 'manga',
    'fikushon' => 'novel',
    _ => 'video',
  };

  Future<void> _install() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await sl<MiruManager>().install(widget.meta);
      widget.onChanged();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Installed ${widget.meta.name}')));
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Install failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    await sl<MiruManager>().setEnabled(widget.meta.package, enabled);
    widget.onChanged();
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await sl<MiruManager>().uninstall(widget.meta.package);
      widget.onChanged();
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Removed ${widget.meta.name}')));
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final nameColor = meta.enabled
        ? AppColors.textPrimary
        : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.name,
                  style: AppText.headline.copyWith(
                    fontSize: 15,
                    color: nameColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${meta.lang.isEmpty ? 'all' : meta.lang} · $_typeLabel',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
            )
          else if (widget.installed && widget.iconOnly) ...[
            Switch.adaptive(
              value: meta.enabled,
              activeThumbColor: AppColors.accent,
              onChanged: _setEnabled,
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: AppColors.textSecondary,
              onPressed: _remove,
            ),
          ]
          else if (widget.installed)
            OutlinedButton(
              onPressed: _remove,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                minimumSize: const Size(100, 36),
                side: const BorderSide(color: AppColors.hairline),
              ),
              child: const Text('Uninstall'),
            )
          else
            FilledButton(
              onPressed: _install,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(96, 36),
              ),
              child: const Text('Install'),
            ),
        ],
      ),
    );
  }
}
