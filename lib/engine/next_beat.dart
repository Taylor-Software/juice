/// The distinct beats the loop's "Next beat" launcher can offer. Pure — no
/// Flutter. The widget maps each to a label + icon + handler.
enum BeatAction { nameScene, ask, askAgain, interpret, inspire, capture }

/// Chooses the 2-3 most relevant beats for the current play state, priority
/// ordered, capped at 3. Deterministic; see the design spec's state table.
List<BeatAction> nextBeatActions({
  required bool hasScene,
  required bool hasRecentAsk,
  required bool interpretDone,
  required bool aiReady,
}) {
  if (!hasScene) return const [BeatAction.nameScene];
  if (!hasRecentAsk) {
    return const [BeatAction.ask, BeatAction.inspire, BeatAction.capture];
  }
  if (aiReady && !interpretDone) {
    return const [BeatAction.interpret, BeatAction.capture, BeatAction.askAgain];
  }
  return const [BeatAction.askAgain, BeatAction.capture, BeatAction.inspire];
}
