import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/constructed_oracle.dart';
import '../state/providers.dart';

const _kOracleDieSides = [4, 6, 8, 10, 12, 20, 100];

/// Create/edit dialog for a [ConstructedOracle]. Returns the saved oracle (or
/// null on cancel) and persists it via [constructedOraclesProvider].
Future<void> showOracleConstructor(
    BuildContext context, WidgetRef ref, ConstructedOracle? existing) async {
  final saved = await showDialog<ConstructedOracle>(
    context: context,
    builder: (_) => _OracleConstructorDialog(existing: existing),
  );
  if (saved == null) return;
  await ref.read(constructedOraclesProvider.notifier).upsert(saved);
}

class _OracleConstructorDialog extends StatefulWidget {
  const _OracleConstructorDialog({this.existing});
  final ConstructedOracle? existing;

  @override
  State<_OracleConstructorDialog> createState() =>
      _OracleConstructorDialogState();
}

class _OracleConstructorDialogState extends State<_OracleConstructorDialog> {
  late final _nameCtl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _formulaCtl =
      TextEditingController(text: widget.existing?.notation ?? 'd100');
  late OracleDirection _dir =
      widget.existing?.direction ?? OracleDirection.rollHigh;
  late Set<OutcomeBand> _bands = {
    ...(widget.existing?.bands ?? OutcomeBand.values.toSet())
  };
  late int? _chaos = widget.existing?.chaos;
  // Preview likelihood (not stored — the tier is chosen live at roll time).
  OracleLikelihood _preview = OracleLikelihood.likely;

  @override
  void dispose() {
    _nameCtl.dispose();
    _formulaCtl.dispose();
    super.dispose();
  }

  ConstructedOracle _draft() => ConstructedOracle(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameCtl.text.trim(),
        notation:
            _formulaCtl.text.trim().isEmpty ? 'd100' : _formulaCtl.text.trim(),
        direction: _dir,
        bands: _bands,
        chaos: _chaos,
      );

  void _setDie(int sides) => setState(() => _formulaCtl.text = 'd$sides');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _draft();
    final parsed = parseOracleDice(draft.notation);
    final ranges = parsed == null ? null : resolveOracle(draft, _preview);
    final canSave =
        _nameCtl.text.trim().isNotEmpty && _bands.length >= 2 && parsed != null;

    return AlertDialog(
      title: Text(widget.existing == null ? 'New oracle' : 'Edit oracle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('oracle-name'),
              controller: _nameCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Dice', style: theme.textTheme.labelMedium),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in _kOracleDieSides)
                ChoiceChip(
                  key: Key('oracle-die-$s'),
                  label: Text('d$s'),
                  selected: draft.notation == 'd$s',
                  onSelected: (_) => _setDie(s),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const Key('oracle-formula'),
              controller: _formulaCtl,
              decoration: InputDecoration(
                labelText: 'Formula',
                hintText: '2d6, 3d8+1…',
                errorText: parsed == null ? 'Try NdM like 2d6 or 3d8+1' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<OracleDirection>(
              key: const Key('oracle-direction'),
              segments: const [
                ButtonSegment(
                    value: OracleDirection.rollHigh, label: Text('Roll high')),
                ButtonSegment(
                    value: OracleDirection.rollLow, label: Text('Roll low')),
              ],
              selected: {_dir},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _dir = s.first),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Outcomes — pick at least 2',
                  style: theme.textTheme.labelMedium),
            ),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final b in kOracleBandOrder)
                FilterChip(
                  key: Key('oracle-band-${b.name}'),
                  label: Text(b.label),
                  selected: _bands.contains(b),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _bands = {..._bands, b};
                    } else if (_bands.length > 2) {
                      _bands = {..._bands}..remove(b);
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(
                key: const Key('oracle-chaos-on'),
                value: _chaos != null,
                onChanged: (v) =>
                    setState(() => _chaos = (v ?? false) ? 5 : null),
              ),
              const Text('Chaos factor'),
              Expanded(
                child: Slider(
                  key: const Key('oracle-chaos'),
                  min: 1,
                  max: 9,
                  divisions: 8,
                  label: '${_chaos ?? 5}',
                  value: (_chaos ?? 5).toDouble(),
                  onChanged: _chaos == null
                      ? null
                      : (v) => setState(() => _chaos = v.round()),
                ),
              ),
            ]),
            const Divider(),
            Row(children: [
              Text('Preview', style: theme.textTheme.labelMedium),
              const Spacer(),
              DropdownButton<OracleLikelihood>(
                key: const Key('oracle-preview-likelihood'),
                value: _preview,
                isDense: true,
                onChanged: (v) => setState(() => _preview = v ?? _preview),
                items: [
                  for (final l in OracleLikelihood.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
              ),
            ]),
            const SizedBox(height: 4),
            if (ranges == null || ranges.isEmpty)
              const Text('—')
            else
              _RangePreview(ranges: ranges),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('oracle-save'),
          onPressed: canSave ? () => Navigator.of(context).pop(draft) : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Compact read-only table of the computed band ranges + odds.
class _RangePreview extends StatelessWidget {
  const _RangePreview({required this.ranges});
  final List<OracleBandRange> ranges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bg(OracleBandRange r) => r.band.isYes
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.errorContainer;
    Color fg(OracleBandRange r) => r.band.isYes
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onErrorContainer;
    return Column(
      children: [
        for (final r in ranges)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: bg(r), borderRadius: BorderRadius.circular(6)),
                child: Text(r.band.label,
                    style: TextStyle(
                        color: fg(r),
                        fontWeight:
                            r.band.isExceptional ? FontWeight.w500 : null)),
              ),
              const SizedBox(width: 10),
              Text(r.lo == r.hi ? '${r.lo}' : '${r.lo}–${r.hi}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFeatures: const [])),
              const Spacer(),
              Text('${(r.probability * 100).round()}%',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
      ],
    );
  }
}
