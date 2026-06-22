// Original, authored generic tarot associations — no source, no attribution,
// no vendored prose. Upright + reversed, one to two short clauses each, keyed
// by the exact card names in kTarotDeck (lib/engine/models.dart). These are
// generic starting points, not a reproduction of any published deck's text.

class TarotMeaning {
  const TarotMeaning(this.upright, this.reversed);
  final String upright;
  final String reversed;
}

const Map<String, TarotMeaning> kTarotMeanings = {
  // ---- Major Arcana --------------------------------------------------------
  'The Fool': TarotMeaning(
    'A fresh start, a leap of faith, an open road and an open mind.',
    'A reckless leap, cold feet at the edge, a risk taken without looking.',
  ),
  'The Magician': TarotMeaning(
    'Will and skill aligned, the tools at hand, making things happen.',
    'Wasted talent, empty promises, manipulation or a trick that misfires.',
  ),
  'The High Priestess': TarotMeaning(
    'Intuition, hidden knowledge, the quiet voice beneath the surface.',
    'Ignored instinct, secrets kept too long, a signal you refuse to hear.',
  ),
  'The Empress': TarotMeaning(
    'Abundance, nurture, creativity that bears fruit, comfort and growth.',
    'Smothering or neglect, creative block, giving past the point of depletion.',
  ),
  'The Emperor': TarotMeaning(
    'Structure, authority, steady control, the rules that hold things up.',
    'Rigidity or tyranny, control slipping, order that has hardened into a cage.',
  ),
  'The Hierophant': TarotMeaning(
    'Tradition, teaching, shared belief, doing things the established way.',
    'Breaking with convention, dogma questioned, a rule that no longer fits.',
  ),
  'The Lovers': TarotMeaning(
    'Union, a meaningful choice, values aligned, connection and commitment.',
    'Discord, a tempting wrong turn, a bond strained or a choice avoided.',
  ),
  'The Chariot': TarotMeaning(
    'Drive and direction, willpower steering opposing forces to victory.',
    'Loss of control, scattered effort, pushing hard but going nowhere.',
  ),
  'Strength': TarotMeaning(
    'Quiet courage, patience, mastering impulse with a gentle hand.',
    'Self-doubt, raw nerves, force used where patience was needed.',
  ),
  'The Hermit': TarotMeaning(
    'Solitude, reflection, seeking the truth by your own inner light.',
    'Isolation, withdrawal that has gone too far, advice refused.',
  ),
  'Wheel of Fortune': TarotMeaning(
    'A turning point, luck and cycles, fate moving things along.',
    'A downturn, bad timing, resisting a change already in motion.',
  ),
  'Justice': TarotMeaning(
    'Fairness, truth, cause and effect, accounts squared and consequences met.',
    'Unfairness, evasion, a reckoning dodged or a bias unexamined.',
  ),
  'The Hanged Man': TarotMeaning(
    'A pause, surrender, seeing things from a new angle by letting go.',
    'Stalling, needless sacrifice, stuck because you will not shift your view.',
  ),
  'Death': TarotMeaning(
    'An ending that clears the way, transformation, the old falling away.',
    'Clinging to what is over, stalled change, a transition that drags on.',
  ),
  'Temperance': TarotMeaning(
    'Balance, blending, patient moderation, the right mix found over time.',
    'Excess or imbalance, impatience, ingredients that will not combine.',
  ),
  'The Devil': TarotMeaning(
    'Bondage, craving, the chains of habit, a bargain that traps you.',
    'Breaking free, facing the addiction, a chain you discover was loose.',
  ),
  'The Tower': TarotMeaning(
    'Sudden upheaval, a shock that breaks a false structure, hard truth.',
    'Disaster narrowly avoided, clinging to what should fall, a slow collapse.',
  ),
  'The Star': TarotMeaning(
    'Hope, renewal, calm after the storm, healing and quiet faith.',
    'Discouragement, faith shaken, hope that feels just out of reach.',
  ),
  'The Moon': TarotMeaning(
    'Illusion, dreams and fears, the unclear path lit only by moonlight.',
    'Confusion clearing, a fear faced, deception coming to light.',
  ),
  'The Sun': TarotMeaning(
    'Joy, clarity, vitality, success out in the open and nothing hidden.',
    'A cloud over the day, dimmed enthusiasm, success that feels muted.',
  ),
  'Judgement': TarotMeaning(
    'A reckoning and a call, awakening, rising to a higher purpose.',
    'Self-doubt, a call ignored, harsh judgement of yourself or others.',
  ),
  'The World': TarotMeaning(
    'Completion, wholeness, a cycle fulfilled, arrival and integration.',
    'An unfinished chapter, a goal nearly reached, closure withheld.',
  ),

  // ---- Wands (drive, creativity, action) -----------------------------------
  'Ace of Wands': TarotMeaning(
    'A spark of inspiration, raw energy, the seed of a new venture.',
    'A false start, a spark that fizzles, motivation that will not catch.',
  ),
  'Two of Wands': TarotMeaning(
    'Planning ahead, weighing a bold move, the world held in your hand.',
    'Hesitation, a plan that stalls, playing it too safe to begin.',
  ),
  'Three of Wands': TarotMeaning(
    'Expansion, ventures underway, watching your efforts head out to sea.',
    'Delays, a plan undershooting, foresight that fell short.',
  ),
  'Four of Wands': TarotMeaning(
    'Celebration, homecoming, a milestone and stable ground to stand on.',
    'A muted celebration, instability at home, a milestone that slips.',
  ),
  'Five of Wands': TarotMeaning(
    'Friction, competition, scrappy conflict and clashing energies.',
    'Conflict cooling, avoidance, tension finally finding a release.',
  ),
  'Six of Wands': TarotMeaning(
    'Victory, recognition, riding high after a job well done.',
    'A fall from favor, a win that goes unseen, pride before a stumble.',
  ),
  'Seven of Wands': TarotMeaning(
    'Standing your ground, defending a position against all comers.',
    'Overwhelmed, giving ground, a fight you no longer have the heart for.',
  ),
  'Eight of Wands': TarotMeaning(
    'Swift movement, news arriving, events rushing forward at speed.',
    'Delays, scattered timing, momentum that stalls just short.',
  ),
  'Nine of Wands': TarotMeaning(
    'Resilience, the last stand, battered but still on your feet.',
    'Exhaustion, defenses crumbling, paranoia that wears you down.',
  ),
  'Ten of Wands': TarotMeaning(
    'A heavy load, burdens carried, responsibility weighing you down.',
    'Letting the load go, delegating, collapse under what you would not share.',
  ),
  'Page of Wands': TarotMeaning(
    'Curiosity and eagerness, a bright idea, the urge to explore.',
    'Restlessness, a flash of enthusiasm with no follow-through.',
  ),
  'Knight of Wands': TarotMeaning(
    'Bold action, charging ahead, daring and impulsive energy.',
    'Recklessness, all heat and no aim, a charge that burns out.',
  ),
  'Queen of Wands': TarotMeaning(
    'Confidence and warmth, magnetic drive, leading by sheer presence.',
    'Insecurity behind the boldness, jealousy, a fire turned to spite.',
  ),
  'King of Wands': TarotMeaning(
    'Visionary leadership, bold direction, inspiring others to act.',
    'Domineering or impulsive rule, big talk, a leader overreaching.',
  ),

  // ---- Cups (emotion, relationship, intuition) -----------------------------
  'Ace of Cups': TarotMeaning(
    'An open heart, new love or feeling, a cup that overflows.',
    'A closed or spilled heart, feeling withheld, emotion gone sour.',
  ),
  'Two of Cups': TarotMeaning(
    'Connection, partnership, a meeting of hearts and mutual regard.',
    'A rift, imbalance between two, a bond strained or breaking.',
  ),
  'Three of Cups': TarotMeaning(
    'Friendship, celebration, community and shared joy.',
    'Overindulgence, gossip, a falling-out among friends.',
  ),
  'Four of Cups': TarotMeaning(
    'Apathy, contemplation, an offer overlooked while you brood.',
    'Reawakening, stepping out of the funk, an offer finally seen.',
  ),
  'Five of Cups': TarotMeaning(
    'Grief and regret, eyes on what was lost, mourning a loss.',
    'Acceptance, turning toward what remains, healing beginning.',
  ),
  'Six of Cups': TarotMeaning(
    'Nostalgia, innocence, kindness and comfort from the past.',
    'Stuck in the past, clinging to old ways, leaving the past behind.',
  ),
  'Seven of Cups': TarotMeaning(
    'Many options, fantasy and choice, dreams not yet sorted from wishes.',
    'Clarity at last, a choice made, illusions cleared away.',
  ),
  'Eight of Cups': TarotMeaning(
    'Walking away, seeking something deeper, leaving what no longer fills you.',
    'Fear of leaving, drifting, returning to what you should have left.',
  ),
  'Nine of Cups': TarotMeaning(
    'Contentment, a wish granted, satisfaction and simple pleasure.',
    'Smugness, a hollow wish, pleasure that fails to satisfy.',
  ),
  'Ten of Cups': TarotMeaning(
    'Harmony, belonging, lasting happiness and bonds that hold.',
    'A fractured ideal, discord at home, a picture that does not match the truth.',
  ),
  'Page of Cups': TarotMeaning(
    'Tender feeling, a gentle message, imagination and openness.',
    'Moodiness, a feeling bottled up, oversensitivity or escapism.',
  ),
  'Knight of Cups': TarotMeaning(
    'Romance and charm, following the heart, an offer made with feeling.',
    'Moodiness, empty charm, a heart that promises more than it gives.',
  ),
  'Queen of Cups': TarotMeaning(
    'Compassion, deep feeling, intuition and emotional warmth.',
    'Overwhelm, feelings turned inward, care that loses its boundaries.',
  ),
  'King of Cups': TarotMeaning(
    'Emotional balance, steady kindness, mastery of deep waters.',
    'Moodiness held in check too tightly, manipulation, feelings denied.',
  ),

  // ---- Swords (intellect, conflict, truth) ---------------------------------
  'Ace of Swords': TarotMeaning(
    'A breakthrough, clear thought, truth cutting through confusion.',
    'Confusion, a harsh truth, sharp words doing more harm than good.',
  ),
  'Two of Swords': TarotMeaning(
    'A stalemate, a hard choice avoided, blindfolded between two paths.',
    'Indecision breaking, the blindfold off, a truth no longer ignored.',
  ),
  'Three of Swords': TarotMeaning(
    'Heartbreak, painful truth, sorrow that pierces.',
    'Healing from grief, releasing the hurt, pain easing at last.',
  ),
  'Four of Swords': TarotMeaning(
    'Rest, recovery, a pause to gather your strength.',
    'Restlessness, burnout, refusing the rest you need.',
  ),
  'Five of Swords': TarotMeaning(
    'Conflict won at a cost, hollow victory, ego over fairness.',
    'Reconciliation, putting down the sword, a grudge released.',
  ),
  'Six of Swords': TarotMeaning(
    'Transition, moving on, leaving troubled waters for calmer ones.',
    'Stuck in rough waters, baggage carried along, a move postponed.',
  ),
  'Seven of Swords': TarotMeaning(
    'Cunning, stealth, getting away with something or going it alone.',
    'A scheme exposed, conscience catching up, coming clean.',
  ),
  'Eight of Swords': TarotMeaning(
    'Feeling trapped, self-made limits, fear that binds more than fact.',
    'Freeing yourself, seeing the way out, limits revealed as illusion.',
  ),
  'Nine of Swords': TarotMeaning(
    'Anxiety, sleepless dread, fears that loom largest in the dark.',
    'Worry easing, a fear faced in daylight, relief after a long night.',
  ),
  'Ten of Swords': TarotMeaning(
    'A painful ending, rock bottom, the worst behind you now.',
    'Recovery, slow rising, refusing to let an ending be the end.',
  ),
  'Page of Swords': TarotMeaning(
    'Curiosity, sharp questions, vigilance and a hunger for truth.',
    'Gossip, scattered thinking, words used carelessly.',
  ),
  'Knight of Swords': TarotMeaning(
    'Decisive action, fast thinking, charging in with a clear aim.',
    'Rashness, blunt force, rushing in without weighing the cost.',
  ),
  'Queen of Swords': TarotMeaning(
    'Clear judgement, honesty, perception unclouded by sentiment.',
    'Coldness, a cutting tongue, judgement turned bitter.',
  ),
  'King of Swords': TarotMeaning(
    'Authority of mind, fair reason, principled and clear-headed rule.',
    'Cold logic, abuse of power, truth wielded as a weapon.',
  ),

  // ---- Pentacles (work, money, the material world) -------------------------
  'Ace of Pentacles': TarotMeaning(
    'A new opportunity, a seed of prosperity, solid ground to build on.',
    'A missed chance, a shaky start, a promise of plenty that does not land.',
  ),
  'Two of Pentacles': TarotMeaning(
    'Juggling, balance, adapting to keep many things in the air.',
    'Overwhelm, dropped balls, struggling to keep up with demands.',
  ),
  'Three of Pentacles': TarotMeaning(
    'Craft and collaboration, skill recognized, building something together.',
    'Poor teamwork, sloppy work, talent going unrecognized.',
  ),
  'Four of Pentacles': TarotMeaning(
    'Saving, security, holding tight to what you have.',
    'Greed or fear of loss, hoarding, or finally loosening your grip.',
  ),
  'Five of Pentacles': TarotMeaning(
    'Hardship, want, feeling left out in the cold.',
    'Recovery, help found, hard times beginning to lift.',
  ),
  'Six of Pentacles': TarotMeaning(
    'Generosity, giving and receiving, help that flows fairly.',
    'Strings attached, unequal giving, charity that controls.',
  ),
  'Seven of Pentacles': TarotMeaning(
    'Patience, tending the long game, assessing what your work has grown.',
    'Impatience, poor return, effort spent on the wrong crop.',
  ),
  'Eight of Pentacles': TarotMeaning(
    'Diligence, mastery through practice, steady focused work.',
    'Cut corners, dull routine, skill neglected or work without heart.',
  ),
  'Nine of Pentacles': TarotMeaning(
    'Self-reliance, earned comfort, enjoying the fruits of your labor.',
    'Overwork or dependence, comfort that rings hollow, security at a cost.',
  ),
  'Ten of Pentacles': TarotMeaning(
    'Lasting wealth, legacy, family and security that endures.',
    'Instability, a legacy at risk, money troubles in the long run.',
  ),
  'Page of Pentacles': TarotMeaning(
    'A new venture, study, an eager learner with a practical eye.',
    'Lack of focus, a plan unrealized, big ideas with no grounding.',
  ),
  'Knight of Pentacles': TarotMeaning(
    'Reliability, steady effort, patient and methodical progress.',
    'Stubborn plodding, dull routine, progress stalled by caution.',
  ),
  'Queen of Pentacles': TarotMeaning(
    'Practical care, nurture and resourcefulness, a warm and capable hand.',
    'Smothering or self-neglect, work-life balance lost, security overemphasized.',
  ),
  'King of Pentacles': TarotMeaning(
    'Prosperity and stability, shrewd providing, mastery of the material world.',
    'Greed, stubbornness, wealth that has made the heart hard.',
  ),
};

const _reversedSuffix = ' (reversed)';

/// Parse a drawn card string ("The Tower (reversed)") into name + orientation
/// + its meaning (null when the name isn't a tarot card, e.g. a standard draw).
({String name, bool reversed, TarotMeaning? meaning}) readTarot(String shown) {
  final reversed = shown.endsWith(_reversedSuffix);
  final name = reversed
      ? shown.substring(0, shown.length - _reversedSuffix.length)
      : shown;
  return (name: name, reversed: reversed, meaning: kTarotMeanings[name]);
}
