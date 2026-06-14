import 'package:flutter/material.dart';

/// Top-level sections of the home shell.
enum Destination { journal, maps, party, tracking, oracles }

class DestinationMeta {
  const DestinationMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

const destinationMeta = <Destination, DestinationMeta>{
  Destination.journal: DestinationMeta('Journal', Icons.book_outlined),
  Destination.maps: DestinationMeta('Maps', Icons.map_outlined),
  Destination.party: DestinationMeta('Party', Icons.groups_outlined),
  Destination.tracking: DestinationMeta('Tracking', Icons.checklist_outlined),
  Destination.oracles: DestinationMeta('Oracles', Icons.casino_outlined),
};

/// Registry tool id -> (destination, subtab key). Tools absent here have no
/// tab home (e.g. 'dice' lives on the entry line; 'help' opens as a route).
const toolLocation = <String, (Destination, String)>{
  'maps': (Destination.maps, 'world'),
  'verdant': (Destination.maps, 'journey'),
  'party-emulator': (Destination.party, 'emulator'),
  'sidekick-dialogue': (Destination.party, 'sidekick'),
  'behavior-tables': (Destination.party, 'behavior'),
  'threads-characters': (Destination.tracking, 'npcs'),
  'encounter': (Destination.tracking, 'encounter'),
  'fate-check': (Destination.oracles, 'oracle'),
  'roll-high': (Destination.oracles, 'oracle'),
  'mythic': (Destination.oracles, 'oracle'),
  'gen-story': (Destination.oracles, 'generators'),
  'gen-npcs': (Destination.oracles, 'generators'),
  'gen-exploration': (Destination.oracles, 'generators'),
  'gen-encounters': (Destination.oracles, 'generators'),
  'gen-details': (Destination.oracles, 'generators'),
  'tables': (Destination.oracles, 'tables'),
  'lonelog-ref': (Destination.oracles, 'lonelog'),
  'moves': (Destination.oracles, 'moves'),
};
