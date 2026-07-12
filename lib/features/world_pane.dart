import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/destination.dart';
import '../shared/shell_route.dart';
import 'people_pane.dart';
import 'places_pane.dart';

/// Tracking → World: People + Places under one subtab (the Track bar was
/// eleven tabs deep). A SegmentedButton switches panes; legacy
/// `goTo(track, subtab: 'people'/'places')` routes still land here (via the
/// SubtabDef alias) and this pane picks the matching segment.
class WorldPane extends ConsumerStatefulWidget {
  const WorldPane({super.key});

  @override
  ConsumerState<WorldPane> createState() => _WorldPaneState();
}

class _WorldPaneState extends ConsumerState<WorldPane> {
  late int _seg; // 0 = People, 1 = Places

  @override
  void initState() {
    super.initState();
    _seg = _segFor(ref.read(shellRouteProvider)) ?? 0;
  }

  int? _segFor(ShellRoute r) {
    if (r.destination != Destination.track) return null;
    return switch (r.subtab) { 'places' => 1, 'people' => 0, _ => null };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(shellRouteProvider, (_, r) {
      final want = _segFor(r);
      if (want != null && want != _seg) setState(() => _seg = want);
    });
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<int>(
            key: const Key('world-seg'),
            segments: const [
              ButtonSegment(
                  value: 0,
                  label: Text('People'),
                  icon: Icon(Icons.groups_outlined)),
              ButtonSegment(
                  value: 1,
                  label: Text('Places'),
                  icon: Icon(Icons.location_on_outlined)),
            ],
            selected: {_seg},
            onSelectionChanged: (s) => setState(() => _seg = s.first),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _seg,
            children: const [PeoplePane(), PlacesPane()],
          ),
        ),
      ],
    );
  }
}
