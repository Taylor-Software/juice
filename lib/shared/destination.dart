import 'package:flutter/material.dart';

import '../engine/models.dart';

/// Top-level verbs of the home shell.
enum Destination { journal, sheet, ask, map, track, run }

/// The verb a campaign lands on when entered, by player-focus mode: GM runs the
/// world (Track = scenes/threads/encounter), Party directs characters (Sheet =
/// roster + Moves). Applied at campaign entry via `ShellRouteNotifier.landFor`.
Destination landingDestination(CampaignMode mode) =>
    mode == CampaignMode.gm ? Destination.run : Destination.sheet;

class DestinationMeta {
  const DestinationMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

const destinationMeta = <Destination, DestinationMeta>{
  Destination.journal: DestinationMeta('Journal', Icons.book_outlined),
  Destination.sheet: DestinationMeta('Sheet', Icons.person_outline),
  Destination.ask: DestinationMeta('Ask', Icons.casino_outlined),
  Destination.map: DestinationMeta('Map', Icons.map_outlined),
  Destination.track: DestinationMeta('Track', Icons.checklist_outlined),
  Destination.run: DestinationMeta('Run', Icons.play_circle_outline),
};

/// Registry tool id -> (destination, subtab key). Tools absent here have no
/// tab home (e.g. 'dice' lives on the entry line; 'help' opens as a route).
const toolLocation = <String, (Destination, String)>{
  'maps': (Destination.map, 'world'),
  'verdant': (Destination.map, 'journey'),
  'hexcrawl': (Destination.map, 'hexcrawl'),
  'party-emulator': (Destination.track, 'emulator'),
  'sidekick-dialogue': (Destination.track, 'sidekick'),
  'behavior-tables': (Destination.track, 'behavior'),
  'threads-characters': (Destination.sheet, 'characters'),
  'encounter': (Destination.track, 'encounter'),
  'resources': (Destination.track, 'resources'),
  'battle': (Destination.track, 'battle'),
  'fate-check': (Destination.ask, 'oracle'),
  'roll-high': (Destination.ask, 'oracle'),
  'mythic': (Destination.ask, 'oracle'),
  'tables': (Destination.ask, 'tables'),
  'lonelog-ref': (Destination.ask, 'lonelog'),
  'moves': (Destination.sheet, 'moves'),
};
