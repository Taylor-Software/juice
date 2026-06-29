import 'models.dart';
import 'oracle.dart';

enum GenSection { story, npcs, exploration, encounters, details }

extension GenSectionLabel on GenSection {
  String get label => switch (this) {
        GenSection.story => 'Story & Scenes',
        GenSection.npcs => 'NPCs & Dialog',
        GenSection.exploration => 'Exploration',
        GenSection.encounters => 'Encounters & Combat',
        GenSection.details => 'Names & Details',
      };
}

String sourceToolFor(GenSection s) => switch (s) {
      GenSection.story => 'gen-story',
      GenSection.npcs => 'gen-npcs',
      GenSection.exploration => 'gen-exploration',
      GenSection.encounters => 'gen-encounters',
      GenSection.details => 'gen-details',
    };

class GeneratorDef {
  const GeneratorDef(this.label, this.section, this.run);
  final String label;
  final GenSection section;
  final GenResult Function(Oracle o) run;
}

/// All content generators — the source of truth for the generate sheet and the contextual entity affordances.
final List<GeneratorDef> kGenerators = [
  GeneratorDef('New Quest', GenSection.story, (o) => o.newQuest()),
  GeneratorDef('New Scene', GenSection.story, (o) => o.newScene()),
  GeneratorDef('Random Event', GenSection.story, (o) => o.randomEvent()),
  GeneratorDef('Challenge', GenSection.story, (o) => o.challenge()),
  GeneratorDef('Pay the Price', GenSection.story, (o) => o.payThePrice()),
  GeneratorDef('Major Plot Twist', GenSection.story,
      (o) => o.payThePrice(critical: true)),
  GeneratorDef('Word Oracle', GenSection.story, (o) => o.wordOracle()),
  GeneratorDef('NPC', GenSection.npcs, (o) => o.npc()),
  GeneratorDef('NPC Behavior', GenSection.npcs, (o) => o.npcBehavior()),
  GeneratorDef(
      'NPC Behavior (Active)', GenSection.npcs, (o) => o.npcBehavior(skew: 1)),
  GeneratorDef('NPC Behavior (Passive)', GenSection.npcs,
      (o) => o.npcBehavior(skew: -1)),
  GeneratorDef('NPC Combat', GenSection.npcs, (o) => o.npcCombat()),
  GeneratorDef('Settlement', GenSection.exploration, (o) => o.settlement()),
  GeneratorDef(
      'Natural Hazard', GenSection.exploration, (o) => o.naturalHazard()),
  GeneratorDef(
      'Monster Encounter', GenSection.encounters, (o) => o.monsterEncounter()),
  GeneratorDef(
      'Creature Tracks', GenSection.encounters, (o) => o.creatureTracks()),
  GeneratorDef('Dungeon Name', GenSection.exploration, (o) => o.dungeonName()),
  GeneratorDef('Dungeon Room', GenSection.exploration, (o) => o.dungeonRoom()),
  GeneratorDef('Treasure', GenSection.details, (o) => o.treasure()),
  GeneratorDef('Name', GenSection.details, (o) => o.generateName()),
  GeneratorDef(
      'Discover Meaning', GenSection.details, (o) => o.discoverMeaning()),
  GeneratorDef('Immersion', GenSection.details, (o) => o.immersion()),
  GeneratorDef('Plot Point', GenSection.story, (o) => o.plotPoint()),
  GeneratorDef('Random Idea', GenSection.details, (o) => o.randomIdea()),
  GeneratorDef('Detail', GenSection.details, (o) => o.detail()),
  GeneratorDef('Property', GenSection.details, (o) => o.property()),
  GeneratorDef('NPC Plot Knowledge', GenSection.npcs, (o) => o.extendedInfo()),
  GeneratorDef(
      'Companion Response', GenSection.npcs, (o) => o.companionResponse()),
  GeneratorDef('NPC Dialog Topic', GenSection.npcs, (o) => o.dialogTopic()),
];

/// The four entity generators that get contextual homes (P2); excluded from the
/// composer's flavor sheet.
const _entityLabels = {'NPC', 'New Scene', 'Monster Encounter', 'Name'};

List<GeneratorDef> get flavorGenerators =>
    kGenerators.where((g) => !_entityLabels.contains(g.label)).toList();
