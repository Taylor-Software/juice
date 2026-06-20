/// How a [Suggestion] resolves when tapped. The rail maps the suggestion's
/// [Suggestion.id] to the concrete inline roll or navigation target; the
/// engine stays free of UI/routing types.
enum SuggestionAction { inline, navigate }

class Suggestion {
  const Suggestion(this.id, this.label, this.action);
  final String id;
  final String label;
  final SuggestionAction action;
}

/// Ranked next-move suggestions for the current play state. Pure: callers pass
/// the booleans (derived elsewhere) so this is trivially testable.
List<Suggestion> suggestionsFor({
  required bool hasScenes,
  required bool hasOpenThreads,
  required bool encounterActive,
  required bool ironswornFamily,
  required bool hasFocusCharacter,
  required bool partyMode,
}) {
  return [
    const Suggestion('roll-oracle', 'Roll the oracle', SuggestionAction.inline),
    if (hasScenes)
      const Suggestion('scene-event', 'Scene event', SuggestionAction.inline)
    else
      const Suggestion(
          'start-scene', 'Start a scene', SuggestionAction.navigate),
    if (hasOpenThreads)
      const Suggestion(
          'advance-thread', 'Advance a thread', SuggestionAction.navigate),
    if (encounterActive)
      const Suggestion('combat-turn', 'Take a turn', SuggestionAction.navigate),
    // Moves live on the Sheet's party-only Moves subtab — hidden in gm mode.
    if (ironswornFamily && hasFocusCharacter && partyMode)
      const Suggestion('make-move', 'Make a move', SuggestionAction.navigate),
    // GM-mode prep moves (mirrors the party-only make-move): the Rumors subtab
    // is gm-only, and NPC stocking is core GM prep.
    if (!partyMode) ...[
      const Suggestion(
          'develop-rumor', 'Develop a rumor', SuggestionAction.navigate),
      const Suggestion('seed-npc', 'Add an NPC', SuggestionAction.navigate),
    ],
  ];
}
