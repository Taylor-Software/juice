import 'models.dart';

/// Role affinity of a mode-filtered sub-option.
enum SubtabRole { gm, party, both }

/// Sub-options that are role-specific. Anything absent is [SubtabRole.both]
/// (always visible). Keys match SubtabDef keys (Track) / Sheet 'moves'.
const Map<String, SubtabRole> kSubtabRoles = {
  'rumors': SubtabRole.gm,
  'emulator': SubtabRole.party,
  'sidekick': SubtabRole.party,
  'behavior': SubtabRole.party,
  'moves': SubtabRole.party,
};

/// Whether a sub-option [key] is shown in [mode]. Untagged → always.
bool visibleForMode(String key, CampaignMode mode) {
  switch (kSubtabRoles[key] ?? SubtabRole.both) {
    case SubtabRole.both:
      return true;
    case SubtabRole.gm:
      return mode == CampaignMode.gm;
    case SubtabRole.party:
      return mode == CampaignMode.party;
  }
}
