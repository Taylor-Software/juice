"""
Party Emulator — source of truth for Triple-O + Pettish table data.

Run to (a) self-verify table structure and (best-effort) cross-check the
literals against pdftotext extracts of the source PDFs, and (b) emit
emulator_data.json consumed by the Flutter app. Copy the output into
assets/ (same flow as build_oracle.py). Never hand-edit the emitted JSON.

Sources (hand-transcribed as literals from the user's PDFs):
- Triple-O: The Player Character Emulator v1.0.2 by Cezar Capacle
  (Critical Kit, May 2026). Text licensed CC-BY-SA 4.0 (stated in the
  zine's colophon). Derived data here stays CC-BY-SA 4.0.
- Pettish by Tam H (hedonic.ink) — PET (Player Emulator with Tags) +
  Sidekick oracle. Text licensed CC-BY 4.0 (stated in the zine).

Extracts used for cross-checks (regenerate with pdftotext -layout):
  /tmp/triple_o.txt, /tmp/pettish.txt — checks are skipped with a note
  when the files are absent; structure verification always runs.
"""
import json
import os
import re

TRIPLE_O_EXTRACT = "/tmp/triple_o.txt"
PETTISH_EXTRACT = "/tmp/pettish.txt"

D66_KEYS = [t * 10 + u for t in range(1, 7) for u in range(1, 7)]

# ---------------------------------------------------------------------------
# Triple-O spark tables (inside front cover + back cover)
# ---------------------------------------------------------------------------

SPARK_ORDER = ["action", "focus", "method", "disposition", "motivation",
               "dynamics"]

SPARK = {
    "action": {
        11: "Abort", 12: "Advance", 13: "Aim", 14: "Block", 15: "Break",
        16: "Challenge", 21: "Climb", 22: "Collide", 23: "Combat",
        24: "Concentrate", 25: "Consolidate", 26: "Coordinate", 31: "Cover",
        32: "Deceive", 33: "Deflect", 34: "Delve", 35: "Destroy",
        36: "Dodge", 41: "Endure", 42: "Force", 43: "Grab", 44: "Help",
        45: "Impact", 46: "Intensify", 51: "Invest", 52: "Knock down",
        53: "Lose", 54: "Oppose", 55: "Penetrate", 56: "Persevere",
        61: "Probe", 62: "Protect", 63: "Retreat", 64: "Separate",
        65: "Stun", 66: "Surprise",
    },
    "focus": {
        11: "Advantage", 12: "Ally", 13: "Balance", 14: "Barrier",
        15: "Chance", 16: "Control", 21: "Courage", 22: "Damage",
        23: "Defense", 24: "Determination", 25: "Environment", 26: "Fear",
        31: "Ferocity", 32: "Focus", 33: "Impulse", 34: "Instinct",
        35: "Maneuver", 36: "Object", 41: "Opening", 42: "Position",
        43: "Posture", 44: "Power", 45: "Precision", 46: "Pride",
        51: "Reach", 52: "Resource", 53: "Senses", 54: "Speed",
        55: "Strategy", 56: "Strength", 61: "Subtlety", 62: "Technique",
        63: "Weakness", 64: "Weapon", 65: "Wits", 66: "Wound",
    },
    "method": {
        11: "Adaptation", 12: "Agility", 13: "Camouflage", 14: "Coercion",
        15: "Cunning", 16: "Deception", 21: "Distraction", 22: "Fear",
        23: "Guile", 24: "Imitation", 25: "Improvisation", 26: "Ingenuity",
        31: "Instinct", 32: "Intimidation", 33: "Knowledge", 34: "Magic",
        35: "Manipulation", 36: "Observation", 41: "Patience",
        42: "Persistence", 43: "Resilience", 44: "Sacrifice",
        45: "Scheming", 46: "Sorcery", 51: "Speed", 52: "Stealth",
        53: "Strategy", 54: "Strength", 55: "Subterfuge", 56: "Surprise",
        61: "Technology", 62: "Tenacity", 63: "Terrain", 64: "Trickery",
        65: "Violence", 66: "Weapons",
    },
    "disposition": {
        11: "Aggressive", 12: "Aloof", 13: "Ambivalent", 14: "Antagonistic",
        15: "Bold", 16: "Cautious", 21: "Cheerful", 22: "Confident",
        23: "Cooperative", 24: "Curious", 25: "Defensive", 26: "Detached",
        31: "Dismissive", 32: "Distrustful", 33: "Eager",
        34: "Enthusiastic", 35: "Friendly", 36: "Guarded", 41: "Helpful",
        42: "Hostile", 43: "Indifferent", 44: "Inquisitive",
        45: "Interested", 46: "Inviting", 51: "Open", 52: "Optimistic",
        53: "Pessimistic", 54: "Reluctant", 55: "Resentful",
        56: "Respectful", 61: "Suspicious", 62: "Sympathetic", 63: "Timid",
        64: "Uninterested", 65: "Warm", 66: "Wary",
    },
    "motivation": {
        11: "Ambition", 12: "Anger", 13: "Atonement", 14: "Betrayal",
        15: "Challenge", 16: "Curiosity", 21: "Despair", 22: "Duty",
        23: "Empathy", 24: "Envy", 25: "Faith", 26: "Fear", 31: "Greed",
        32: "Guilt", 33: "Hate", 34: "Honor", 35: "Hope", 36: "Ideology",
        41: "Justice", 42: "Knowledge", 43: "Legacy", 44: "Love",
        45: "Loyalty", 46: "Mastery", 51: "Obsession", 52: "Passion",
        53: "Pride", 54: "Regret", 55: "Rivalry", 56: "Sacrifice",
        61: "Shame", 62: "Sorrow", 63: "Survival", 64: "Thrill",
        65: "Tradition", 66: "Vengeance",
    },
    "dynamics": {
        11: "Admiring", 12: "Affectionate", 13: "Amused", 14: "Comfortable",
        15: "Competitive", 16: "Conflicted", 21: "Contemptuous",
        22: "Deferential", 23: "Defiant", 24: "Dependent",
        25: "Disappointed", 26: "Distant", 31: "Envious",
        32: "Exasperated", 33: "Fascinated", 34: "Grateful", 35: "Guilty",
        36: "Indifferent", 41: "Inspired", 42: "Intimidated",
        43: "Intrigued", 44: "Judgmental", 45: "Loyal", 46: "Observant",
        51: "Patronizing", 52: "Protective", 53: "Resentful",
        54: "Respectful", 55: "Skeptical", 56: "Supportive",
        61: "Suspicious", 62: "Sympathetic", 63: "Teasing",
        64: "Threatened", 65: "Trusting", 66: "Uneasy",
    },
}

# ---------------------------------------------------------------------------
# Triple-O specific tables (zine pages 38-51)
# ---------------------------------------------------------------------------

SPECIFIC_ORDER = ["combat", "social", "exploration", "delving",
                  "interpretation", "downtime", "planning"]

SPECIFIC = {
    "combat": {
        11: "Aim carefully, wait for an opening",
        12: "Attack directly with primary weapon",
        13: "Attack with secondary weapon",
        14: "Attempt to disarm the enemy",
        15: "Attempt to flee",
        16: "Call for a combined action",
        21: "Call for parley",
        22: "Cast a spell or use a special ability",
        23: "Change elevation (climb, jump)",
        24: "Charge recklessly",
        25: "Create difficult terrain or obstacles",
        26: "Destroy enemy cover or resources",
        31: "Distract or mislead",
        32: "Draw attention/taunt the enemy",
        33: "Drop your weapons/surrender",
        34: "Fall back and regroup",
        35: "Flank or reposition",
        36: "Force movement (push, pull, reposition)",
        41: "Grapple or restrain an opponent",
        42: "Heal, buff, or protect an ally",
        43: "Help or assist an ally’s action",
        44: "Hold position and guard",
        45: "Improvise a weapon",
        46: "Look for a weakness",
        51: "Make a feint or fake attack",
        52: "Rally/inspire to boost morale",
        53: "Ready an action to respond to a trigger",
        54: "Set up an ambush or trap",
        55: "Switch weapons or tactics",
        56: "Take cover or duck behind something",
        61: "Target a leader or key figure",
        62: "Try to intimidate or scare them off",
        63: "Use a consumable item",
        64: "Use environment to their advantage",
        65: "Withdraw or disengage safely",
        66: "Yell a warning or call for help",
    },
    "social": {
        11: "Appeal to emotion",
        12: "Appeal to logic",
        13: "Appeal to rules, laws, or customs",
        14: "Appeal to their values or beliefs",
        15: "Apply leverage/blackmail",
        16: "Ask probing questions",
        21: "Bluff or exaggerate",
        22: "Bribe or offer incentive",
        23: "Challenge to a duel, contest, or wager",
        24: "Compliment or flatter someone",
        25: "Confide a secret",
        26: "Directly inquire about a piece of information",
        31: "Empathize with their situation or feelings",
        32: "Exploit rivalries or conflicting interests",
        33: "Give a gift or token of goodwill",
        34: "Haggle over price or terms",
        35: "Invoke shared values, traditions, or history",
        36: "Invoke status, rank, or reputation",
        41: "Make a concession to move talks",
        42: "Misdirect or change the subject",
        43: "Name-drop important connections",
        44: "Offer a trade or bargain",
        45: "Offer help or assistance",
        46: "Perform/entertain to win favor",
        51: "Pretend to agree",
        52: "Promise something uncertain",
        53: "Read the room for mood and dynamics",
        54: "Set and enforce boundaries",
        55: "Share a personal story or vulnerability",
        56: "Speak honestly and openly",
        61: "Stay silent and observe",
        62: "Tell a joke or lighten the mood",
        63: "Try to charm or impress",
        64: "Try to find common ground",
        65: "Try to read their intentions",
        66: "Use threats or a show of force",
    },
    "exploration": {
        11: "Assess the terrain ahead",
        12: "Check for traps or hazards",
        13: "Climb or seek vantage point",
        14: "Collect specimens or samples",
        15: "Cover tracks",
        16: "Document discoveries",
        21: "Forage for food, water, or supplies",
        22: "Hold back and observe",
        23: "Hunt or fish",
        24: "Leave messages or signs",
        25: "Listen for echoes/water/wind/animals",
        26: "Look for magical or strange phenomena",
        31: "Look for shelter from the elements",
        32: "Look for signs of civilization",
        33: "Look for tracks or signs of passage",
        34: "Map or mark the area",
        35: "Navigate by stars/sun/landmarks",
        36: "Observe wildlife patterns for clues",
        41: "Produce source of light or heat",
        42: "Propose a change in marching order or pace",
        43: "Propose a short rest",
        44: "Rush to cover more ground",
        45: "Scout ahead carefully",
        46: "Search for hidden paths",
        51: "Send a companion or summoned being ahead",
        52: "Stand guard or keep watch",
        53: "Stay alert and move slowly",
        54: "Study the weather",
        55: "Suggest to press on for longer",
        56: "Suggest to split up the group",
        61: "Take a risk to save time",
        62: "Test the air or water",
        63: "Test the ground or depth",
        64: "Try a different route",
        65: "Try to identify a plant, creature, or landmark",
        66: "Use a specialized instrument",
    },
    "delving": {
        11: "Adjust formation or spacing",
        12: "Backtrack to a previous junction",
        13: "Check for pressure plates or tripwires",
        14: "Check for recent signs of passage or presence",
        15: "Check the ceiling for hazards or instability",
        16: "Climb or take the high ground",
        21: "Collect samples",
        22: "Cover tracks or conceal presence",
        23: "Create a distraction, lure, or decoy",
        24: "Document findings and warnings",
        25: "Examine remains or debris for clues",
        26: "Examine the structure for weaknesses",
        31: "Feel for air currents or temperature changes",
        32: "Follow an unexplored route",
        33: "Hide in the shadows or a crawlspace",
        34: "Listen at a door, wall, or passage",
        35: "Look for creature tracks, territorial signs, or lair markings",
        36: "Map the layout and connections",
        41: "Mark your path to avoid going in circles",
        42: "Peek into a room using a mirror or tool",
        43: "Probe the floor or walls with a pole",
        44: "Push recklessly onward",
        45: "Rally the group for a breather",
        46: "Scout ahead of the party",
        51: "Seal, block, or barricade an entry",
        52: "Search for hidden doors, passages, or mechanisms",
        53: "Search for hidden loot or cached supplies",
        54: "Search for inscriptions, carvings, or symbols",
        55: "Send a familiar or summoned creature ahead first",
        56: "Send a light source ahead",
        61: "Sense for magical residues",
        62: "Set tripwires, alarms, or warning markers",
        63: "Sniff the air for gas, smoke, rot, or chemicals",
        64: "Study architecture for purpose, origin, logic, or age",
        65: "Tend to wounds, fatigue, or morale",
        66: "Toss something ahead to test a room",
    },
    "interpretation": {
        11: "Believe it’s a trap or test",
        12: "Believe they are being lied to or deceived",
        13: "Connect it to a larger pattern",
        14: "Dismiss it as a distraction or misdirection",
        15: "Feel a strong sense of personal duty or responsibility",
        16: "Feel distrust or suspicion",
        21: "Feel intense, unfiltered curiosity or fascination",
        22: "Feel nostalgia or déjà vu",
        23: "Feel overwhelmed",
        24: "Get a strong gut feeling that something is wrong",
        25: "Interpret it as a symbolic message or warning",
        26: "Misinterpret the situation entirely",
        31: "Misjudge the intentions of others",
        32: "Obsess over one detail",
        33: "Overanalyze every detail",
        34: "Rationalize it away",
        35: "Read it as a bad omen or a dark portent",
        36: "Recognize something as valuable or useful",
        41: "See connections to previous events",
        42: "See hidden danger or threat",
        43: "See it as a challenge or provocation",
        44: "Seize it as the perfect chance to act",
        45: "Sense opportunity or advantage",
        46: "Suspect a hidden reward or secret is nearby",
        51: "Suspect an ambush",
        52: "Take it as an invitation or welcome",
        53: "Take it at face value",
        54: "Take it personally",
        55: "Think it’s a coincidence",
        56: "Think it’s a performance or an act",
        61: "Treat it as a key clue to a larger mystery",
        62: "Treat it as fate or destiny",
        63: "Trust intuition over logic",
        64: "Try to read between the lines",
        65: "View it as a puzzle that needs to be solved",
        66: "View it as an audition or chance to impress",
    },
    "downtime": {
        11: "Admit a fear or weakness",
        12: "Ask an ally for advice on a personal dilemma",
        13: "Ask someone about their motives",
        14: "Compare beliefs or philosophies",
        15: "Confess a secret, a lie, or a hidden motive",
        16: "Confide a lingering doubt",
        21: "Cook, share food, or offer a drink with intention",
        22: "Debate a moral choice",
        23: "Discuss long-term dreams for when the journey ends",
        24: "Express admiration or gratitude",
        25: "Express homesickness or longing",
        26: "Gamble or play a game of chance or skill",
        31: "Grieve something lost",
        32: "Indulge in a personal coping mechanism or vice",
        33: "Inquire about an ally’s homeland or family",
        34: "Offer comfort or encouragement",
        35: "Ponder about the true nature of their enemies",
        36: "Practice a skill or hobby",
        41: "Pray, meditate, or observe a personal tradition",
        42: "Propose a solemn pact",
        43: "Question the group’s direction or purpose",
        44: "Rally the group with a speech or toast",
        45: "Share a cultural ritual, song, or saying",
        46: "Share a keepsake or memento and its story",
        51: "Share a story from their childhood",
        52: "Share rumors or speculation",
        53: "Sing, play music, or perform for the group",
        54: "Suggest a change in plans",
        55: "Talk about a dream you once had",
        56: "Talk about someone you left behind",
        61: "Tease, joke, or try to lighten the mood",
        62: "Tell a story of failure or glory",
        63: "Tend to wounds or worn gear",
        64: "Try to teach an ally a minor skill, trick, or phrase",
        65: "Wander off alone into the dark",
        66: "Write, sketch, or record thoughts",
    },
    "planning": {
        11: "Avoid confrontation entirely",
        12: "Call in a favor or old debt",
        13: "Consult omens, divination, or spiritual guidance",
        14: "Contact or negotiate with a potential ally/faction",
        15: "Debate moral/ethical/practical costs",
        16: "Defer to the party’s leader",
        21: "Eliminate a specific threat first",
        22: "Follow instinct and improvise",
        23: "Gather more local rumors or intel",
        24: "Hire local help or muscle",
        25: "Learn the local terrain",
        26: "Look for a local contact, fence, informant, or insider",
        31: "Make final personal preparations",
        32: "Pivot to a secondary lead",
        33: "Plan a distraction or diversion",
        34: "Prepare healing or protective measures",
        35: "Propose a high-stakes gamble",
        36: "Push for a direct, immediate strike",
        41: "Question the entire mission’s purpose",
        42: "Repair, upgrade, enchant, or modify equipment",
        43: "Rest and recover before acting",
        44: "Restock and audit supplies",
        45: "Scrap the plan and start over",
        46: "Seek an expert, sage, guide, or specialist",
        51: "Send someone undercover",
        52: "Set a trap or ambush",
        53: "Set signals, code words, or fallback points",
        54: "Share previously withheld knowledge",
        55: "Split the party",
        56: "Study maps, charts, myths, or historical records",
        61: "Train or practice a specific skill/tactic",
        62: "Use bribery or social leverage",
        63: "Volunteer for the dangerous part",
        64: "Volunteer to scout ahead alone",
        65: "Wait for better timing/weather/specific event",
        66: "Warn of a potential trap",
    },
}

# ---------------------------------------------------------------------------
# Pettish — PET (Player Emulator with Tags)
# ---------------------------------------------------------------------------

# Agenda chart: 2d6 sum (curved) in play, flat d12 (reroll 1s) during
# creation. Six named groups, two agendas each except Friendship. The
# apostrophe/quote style varies by entry exactly as the zine prints it.
PET_AGENDA = {
    2: {
        "group": "Drama", "name": "DRAMA",
        "flavor": "Introduces dark secrets and juicy dramatic reveals at "
                  "every opportunity.",
        "ask": "what would be the worst thing to reveal right now?",
    },
    3: {
        "group": "Drama", "name": "INSTIGATOR",
        "flavor": "Acts as if they aren’t paying attention or missed "
                  "the context but is somehow still constantly stirring "
                  "the pot.",
        "ask": "what would be the worst thing they could (obliviously) do "
               "to make trouble right now?",
    },
    4: {
        "group": "Action", "name": "IMPULSIVE",
        "flavor": "Craves new experiences, and escapes into the game. "
                  "Doesn't usually think about their allies before acting "
                  "on temptation.",
        "ask": "what’s a temptation and how do they indulge it "
               "thoughtlessly?",
    },
    5: {
        "group": "Action", "name": "TEAM PLAYER",
        "flavor": "Brings their best game. Always pushes the story and "
                  "adventure towards a dramatic and satisfying conclusion.",
        "ask": "what is the optimal action here?",
    },
    6: {
        "group": "Power", "name": "SELFISH",
        "flavor": "Cares about keeping their character intact and about "
                  "amassing something of value, like wealth, experience, "
                  "or powerful items.",
        "ask": "what here is of value to them and how do they seize it?",
    },
    7: {
        "group": "Power", "name": "HERO",
        "flavor": "Wants to do the right thing, to be a hero, to be "
                  "recognized as such.",
        "ask": "how can they show heroism and what does it cost?",
    },
    8: {
        "group": "System", "name": "SAFE",
        "flavor": "Wants to play the game they signed up for, do what's "
                  "on their character sheet, and avoid extremes in rules "
                  "& story.",
        "ask": "what is the most expected thing to do here?",
    },
    9: {
        "group": "System", "name": "VIRTUOSO",
        "flavor": "Plays skilled characters or ones that demonstrate "
                  "system mastery; wants to show that off. Motto: \"if "
                  "all you've got is a hammer, everything looks like a "
                  "nail\".",
        "ask": "how can this character demonstrate their strength?",
    },
    10: {
        "group": "Story", "name": "AUTHOR",
        "flavor": "All about history and character development, but "
                  "focused on their own character and pet NPCs.",
        "ask": "what in their backstory can negatively affect or motivate "
               "them, and how do they act because of it?",
    },
    11: {
        "group": "Story", "name": "EXPLORER",
        "flavor": "All about history and character development, but wants "
                  "to see the whole world explored, and everyone’s "
                  "story honored.",
        "ask": "what in their backstory can positively affect or motivate "
               "them, and how do they act because of it?",
    },
    12: {
        "group": "Friendship", "name": "AGREEABLE",
        "flavor": "Wants to hang out, to go along with what everyone else "
                  "is doing, to enjoy their company. Often disappears to "
                  "make food and drinks, delegating their character to "
                  "another player.",
        "ask": "what would benefit another player most?",
    },
}

PET_FOCUS = {
    2: {
        "name": "PLAYFUL",
        "blurb": "a focus on relaxing, on entertaining themselves, on "
                 "pursuing pleasure or enjoying a hobby. Chill out. Who "
                 "does it hurt?",
    },
    3: {
        "name": "SERIOUS",
        "blurb": "a focus on a long-term plan or achieving an immediate "
                 "goal that will serve as a stepping stone. Focus. Rome "
                 "wasn’t built in a day.",
    },
    4: {
        "name": "POWER",
        "blurb": "a focus on directing the group, on gaining influence or "
                 "manipulating others. Control. Exploit all the angles.",
    },
    5: {
        "name": "BUILDING",
        "blurb": "a focus on building up, whether that’s a community "
                 "or a friend, on figuring out how to move forward, "
                 "together. Empathy.",
    },
    6: {
        "name": "AMBITIOUS",
        "blurb": "a focus on winning, on achieving a goal, on negotiation "
                 "from a position of strength. Competitiveness.",
    },
    7: {
        "name": "HELPING HAND",
        "blurb": "a focus on helping others, on understanding emotions, "
                 "to negotiate from a position of understanding. Sympathy.",
    },
    8: {
        "name": "CONFORMING",
        "blurb": "a focus on fitting in, on running with the pack, on "
                 "enjoying being part of the team or knuckling under "
                 "authority, for now. Safety in numbers.",
    },
    9: {
        "name": "REBELLIOUS",
        "blurb": "a focus on fighting authority, on creation, especially "
                 "creating something that the team won’t approve of "
                 "or maybe even won’t understand. Marching to my own "
                 "beat.",
    },
    10: {
        "name": "MY NEEDS",
        "blurb": "a focus on myself, on my own needs, on getting what I "
                 "want or what I think I deserve. I deserve this.",
    },
    11: {
        "name": "OUR NEEDS",
        "blurb": "a focus on others, on meeting their needs, on providing "
                 "or not what someone wants, but what they need to "
                 "thrive. This is for your own good.",
    },
    12: {
        "name": "APATHETIC",
        "blurb": "they don’t care, or they really can’t bring "
                 "themselves to care, regardless, can’t be bothered. "
                 "Can’t deal.",
    },
}

# Six numbered columns of six, flattened in column order 1-6.
PET_PERSONALITY_TAGS = [
    "chatty", "ruthless", "casual", "cheerful", "indecisive", "assertive",
    "blunt", "gloomy", "clumsy", "rigid", "invested", "argues",
    "gambler", "greedy", "turtle", "tactical", "whimsical", "mercurial",
    "needy", "kind", "curious", "bossy", "vengeful", "peacemaker",
    "smart", "romantic", "flaky", "restless", "arrogant", "charismatic",
    "creative", "dramatic", "warm", "mischievous", "leader", "forgetful",
]

PET_CONSEQUENCES = [  # d6 consequences/gm moves
    "expose a weakness", "reveal a danger", "tempt a reaction",
    "introduce an npc", "take it away", "inflict harm",
]

PET_REAL_LIFE = [  # d6 real life stuff
    "tired", "stressed", "scolded", "facing a choice", "elated",
    "victorious",
]

# ---------------------------------------------------------------------------
# Pettish — Sidekick dialogue oracle
# ---------------------------------------------------------------------------

# 2d6-sum dialogue lines per mood. The zine numbers the High-Strung column
# 1-11 (a printing slip; every other mood runs 2-12); remapped here to 2-12
# in printed order.
SIDEKICK_DIALOGUE = {
    "default": {
        2: "Look out!",
        3: "You tell me.",
        4: "Why do you think that?",
        5: "What makes you ask?",
        6: "You got it.",
        7: "Well, that’s mostly true...",
        8: "That’s completely wrong.",
        9: "Why?",
        10: "Let’s do this thing!",
        11: "I got nothing.",
        12: "Oh, crap!",
    },
    "taciturn": {
        2: "Duck.",
        3: "...",
        4: "Why?",
        5: "What do you want?",
        6: "Yes.",
        7: "Yes, but...",
        8: "Hell no.",
        9: "Huh?",
        10: "Go.",
        11: "Shut up.",
        12: "Move!",
    },
    "savvy": {
        2: "Watch out!",
        3: "Explain.",
        4: "Who stood to gain?",
        5: "What are your orders?",
        6: "As you say.",
        7: "Sounds like you’ve considered all the angles.",
        8: "You’re off base.",
        9: "What’s your gut tell you?",
        10: "Locked and loaded.",
        11: "I don’t know.",
        12: "Behind you!",
    },
    "high_strung": {
        2: "I’m outta here.",
        3: "Can’t someone else do it?",
        4: "I want to go home!",
        5: "I’ll try, I guess.",
        6: "Yes. I think. Maybe?",
        7: "Ok, but it sounds dangerous.",
        8: "Won’t work, try something else.",
        9: "Why do you think?",
        10: "I guess, let’s go.",
        11: "Well, I can tell you all about...",
        12: "Oh, crap, oh, crap, oh–",
    },
    "sassy": {
        2: "I’ve got your back.",
        3: "Hmmm?",
        4: "I could use a drink.",
        5: "My secrets are my own.",
        6: "Sure, whatever you say.",
        7: "Sounds like a thrill.",
        8: "Not even if you paid double.",
        9: "You just figured this out?",
        10: "I’m not getting any younger.",
        11: "I’m as baffled as you are.",
        12: "Now is not a good time!",
    },
    "selfish": {
        2: "Help me!",
        3: "How does that help me?",
        4: "What’s in it for me?",
        5: "I don’t know nothing!",
        6: "Sure, good deal.",
        7: "Let’s cut a deal.",
        8: "I could get more for your corpse than that.",
        # The extract renders this as "off ?" (font-spacing artifact);
        # the stray space before "?" is dropped.
        9: "What tipped you off?",
        10: "Right behind you.",
        11: "Look, I needed it more.",
        12: "Hurt them, not me!",
    },
}

SIDEKICK_TONE = ["aggressive", "defensive", "neutral", "distant", "eager",
                 "helpful"]
SIDEKICK_TOPIC = ["a fact", "a query", "a want/desire", "a need/lack",
                  "demand action", "anecdote"]
SIDEKICK_SAID_HOW_A = ["wailed", "cried", "shouted", "growled", "frowning",
                       "neutrally"]
SIDEKICK_SAID_HOW_B = ["ruefully", "smiling", "quickly", "amused", "tartly",
                       "sharply"]

# ---------------------------------------------------------------------------
# Pettish — Sidekick hexflower (zine page 10)
# ---------------------------------------------------------------------------
# FLAGGED: derived from a figure; reviewer must re-derive independently.
# The flower is read as five flat-top columns of 3-4-5-4-3 hexes in axial
# coordinates (q = column -2..2, r grows downward; |q|, |r|, |q+r| <= 2).
# Index 0 = center (0,0); 1-6 = ring 1 clockwise from N; 7-18 = ring 2
# clockwise from N. Context: 'gray' = history (top of the figure),
# 'red' = current events (bottom); the printed figure shades a few hexes
# only partially (e.g. the "partly gray need" called out in the caption) —
# encoded binary here per the plan's reading.
HEXFLOWER_HEXES = [
    # (index, q, r, topic, context)
    (0, 0, 0, "fact", "red"),        # center; usual start
    (1, 0, -1, "query", "gray"),
    (2, 1, -1, "query", "gray"),
    (3, 1, 0, "action", "red"),
    (4, 0, 1, "query", "red"),
    (5, -1, 1, "query", "red"),
    (6, -1, 0, "need", "red"),
    (7, 0, -2, "denial", "gray"),    # top of the flower
    (8, 1, -2, "query", "gray"),
    (9, 2, -2, "denial", "gray"),
    (10, 2, -1, "fact", "gray"),
    (11, 2, 0, "denial", "red"),
    (12, 1, 1, "want", "red"),
    (13, 0, 2, "support", "red"),    # bottom of the flower
    (14, -1, 2, "query", "red"),
    (15, -2, 2, "support", "red"),
    (16, -2, 1, "need", "red"),
    (17, -2, 0, "action", "red"),
    (18, -1, -1, "want", "gray"),
]

HEX_TOPICS = {"fact", "query", "want", "need", "action", "support",
              "denial"}

# Topic tally of the reading above (documents the figure interpretation).
HEX_TOPIC_TALLY = {"fact": 2, "query": 6, "want": 2, "need": 2,
                   "action": 2, "support": 2, "denial": 3}

# 2d6 direction overlay (the rose around the flower) + its tone labels.
HEX_DIRECTIONS = {2: "NE", 3: "NE", 4: "SE", 5: "SE", 6: "S", 7: "S",
                  8: "SW", 9: "SW", 10: "NW", 11: "NW", 12: "N"}
HEX_DIRECTION_TONES = {"N": "aggressive", "NE": "defensive",
                       "SE": "helpful", "S": "aggressive",
                       "SW": "defensive", "NW": "neutral"}
# Axial step per direction (flat-top columns: N/S stay in the column).
HEX_DIRECTION_DELTAS = {"N": (0, -1), "NE": (1, -1), "SE": (1, 0),
                        "S": (0, 1), "SW": (-1, 1), "NW": (-1, 0)}


def hexflower_adjacency():
    """Index-based adjacency derived from the axial coords (movement off
    the flower edge clamps = stay; interrupts are handled by the UI)."""
    by_coord = {(q, r): i for i, q, r, _, _ in HEXFLOWER_HEXES}
    return {
        i: sorted(by_coord[(q + dq, r + dr)]
                  for dq, dr in HEX_DIRECTION_DELTAS.values()
                  if (q + dq, r + dr) in by_coord)
        for i, q, r, _, _ in HEXFLOWER_HEXES
    }

# ---------------------------------------------------------------------------
# Meta / licensing
# ---------------------------------------------------------------------------

META = {
    "attribution": [
        "PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0",
        "Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0",
    ],
    "license_note": "Data derived from Triple-O is CC-BY-SA 4.0; data "
                    "derived from Pettish is CC-BY 4.0.",
}

# ---------------------------------------------------------------------------
# VERIFICATION
# ---------------------------------------------------------------------------


def _check_d66(failures, label, table):
    if sorted(table) != D66_KEYS:
        failures.append(f"{label}: keys != 11..66 (d6 digits)")
        return
    values = list(table.values())
    if any(not isinstance(v, str) or not v.strip() for v in values):
        failures.append(f"{label}: empty/non-string value")
    if len(set(values)) != 36:
        failures.append(f"{label}: duplicate values")


def _check_2_12(failures, label, table):
    if sorted(table) != list(range(2, 13)):
        failures.append(f"{label}: keys != 2..12")


def verify():
    failures = []

    # 1. d66 tables: exactly 36 keys 11-66, non-empty distinct values.
    for name in SPARK_ORDER:
        _check_d66(failures, f"spark.{name}", SPARK[name])
    for name in SPECIFIC_ORDER:
        _check_d66(failures, f"specific.{name}", SPECIFIC[name])
    if sorted(SPARK) != sorted(SPARK_ORDER):
        failures.append("spark order list out of sync with tables")
    if sorted(SPECIFIC) != sorted(SPECIFIC_ORDER):
        failures.append("specific order list out of sync with tables")

    # 2. PET: agenda + focus keyed 2-12; groups/names as published.
    _check_2_12(failures, "pet.agenda", PET_AGENDA)
    _check_2_12(failures, "pet.focus", PET_FOCUS)
    for k, row in PET_AGENDA.items():
        if set(row) != {"group", "name", "flavor", "ask"} or \
                not all(row.values()):
            failures.append(f"pet.agenda[{k}]: malformed row")
    groups = [row["group"] for row in PET_AGENDA.values()]
    if [groups.count(g) for g in
            ["Drama", "Action", "Power", "System", "Story", "Friendship"]] \
            != [2, 2, 2, 2, 2, 1]:
        failures.append("pet.agenda: group sizes != 2/2/2/2/2/1")
    for k, row in PET_FOCUS.items():
        if set(row) != {"name", "blurb"} or not all(row.values()):
            failures.append(f"pet.focus[{k}]: malformed row")

    # 3. Tags 36 distinct; small d6 tables exactly 6.
    if len(PET_PERSONALITY_TAGS) != 36 or \
            len(set(PET_PERSONALITY_TAGS)) != 36:
        failures.append("pet.personality_tags: not 36 distinct")
    for label, table in [("pet.consequences", PET_CONSEQUENCES),
                         ("pet.real_life", PET_REAL_LIFE),
                         ("sidekick.tone", SIDEKICK_TONE),
                         ("sidekick.topic", SIDEKICK_TOPIC),
                         ("sidekick.said_how_a", SIDEKICK_SAID_HOW_A),
                         ("sidekick.said_how_b", SIDEKICK_SAID_HOW_B)]:
        if len(table) != 6 or len(set(table)) != 6 or not all(table):
            failures.append(f"{label}: not 6 distinct non-empty entries")

    # 4. Dialogue: six moods, 11 lines each keyed 2-12, distinct per mood.
    if sorted(SIDEKICK_DIALOGUE) != sorted(
            ["default", "taciturn", "savvy", "high_strung", "sassy",
             "selfish"]):
        failures.append("sidekick.dialogue: mood set wrong")
    for mood, lines in SIDEKICK_DIALOGUE.items():
        _check_2_12(failures, f"sidekick.dialogue.{mood}", lines)
        if len(set(lines.values())) != 11 or not all(lines.values()):
            failures.append(f"sidekick.dialogue.{mood}: lines not 11 "
                            "distinct non-empty")

    # 5. Hexflower: 19 hexes (center + ring1 x6 + ring2 x12), valid topics
    # and contexts, symmetric adjacency, center has all 6 neighbors.
    idxs = [h[0] for h in HEXFLOWER_HEXES]
    coords = [(h[1], h[2]) for h in HEXFLOWER_HEXES]
    if idxs != list(range(19)) or len(set(coords)) != 19:
        failures.append("hexflower: indexes/coords not 19 unique")
    for i, q, r, topic, context in HEXFLOWER_HEXES:
        if max(abs(q), abs(r), abs(q + r)) > 2:
            failures.append(f"hexflower[{i}]: ({q},{r}) outside radius 2")
        if topic not in HEX_TOPICS:
            failures.append(f"hexflower[{i}]: unknown topic {topic!r}")
        if context not in ("gray", "red"):
            failures.append(f"hexflower[{i}]: unknown context {context!r}")
    dist = {i: max(abs(q), abs(r), abs(q + r))
            for i, q, r, _, _ in HEXFLOWER_HEXES}
    if dist[0] != 0 or sorted(dist.values()) != [0] + [1] * 6 + [2] * 12:
        failures.append("hexflower: not center + ring1 x6 + ring2 x12")
    if sorted(dist[i] for i in range(1, 7)) != [1] * 6:
        failures.append("hexflower: indexes 1-6 must be ring 1")
    tally = {}
    for _, _, _, topic, _ in HEXFLOWER_HEXES:
        tally[topic] = tally.get(topic, 0) + 1
    if tally != HEX_TOPIC_TALLY:
        failures.append(f"hexflower: topic tally {tally} != documented "
                        f"reading {HEX_TOPIC_TALLY}")
    adj = hexflower_adjacency()
    for i, ns in adj.items():
        if not 3 <= len(ns) <= 6 or i in ns:
            failures.append(f"hexflower adjacency[{i}]: bad degree/self")
        for n in ns:
            if i not in adj[n]:
                failures.append(f"hexflower adjacency: {i}->{n} asymmetric")
    if len(adj[0]) != 6:
        failures.append("hexflower: center must have 6 neighbors")
    if sum(len(ns) for ns in adj.values()) != 84:  # 42 edges
        failures.append("hexflower adjacency: edge count != 42")

    # 6. Direction overlay: 2d6 sums 2-12 covered; six distinct unit
    # deltas; a tone label per direction.
    if sorted(HEX_DIRECTIONS) != list(range(2, 13)):
        failures.append("hex directions: sums 2-12 not covered exactly")
    dirs = set(HEX_DIRECTIONS.values())
    if dirs != set(HEX_DIRECTION_DELTAS) or dirs != set(
            HEX_DIRECTION_TONES):
        failures.append("hex directions: deltas/tones out of sync")
    deltas = set(HEX_DIRECTION_DELTAS.values())
    if len(deltas) != 6 or deltas != {(0, -1), (1, -1), (1, 0), (0, 1),
                                      (-1, 1), (-1, 0)}:
        failures.append("hex direction deltas: not the six axial steps")

    # 7. Meta strings.
    if len(META["attribution"]) != 2 or not META["license_note"]:
        failures.append("meta: attribution/license_note malformed")

    cross_check_triple_o(failures)
    cross_check_pettish(failures)
    return failures


# -- Best-effort cross-checks against the pdftotext extracts -----------------


def _collapse(s):
    return " ".join(s.split())


def cross_check_triple_o(failures):
    """Each d66 table: >=30 of 36 literals verbatim in the extract, and
    (specific tables) >=30 'NN text' rows parsed inside the table's own
    page region. Catches paraphrase/typo drift."""
    if not os.path.exists(TRIPLE_O_EXTRACT):
        print(f"note: {TRIPLE_O_EXTRACT} missing; "
              "skipped Triple-O extract cross-check")
        return
    with open(TRIPLE_O_EXTRACT, encoding="utf-8") as f:
        lines = f.read().splitlines()
    text = "\n".join(lines)

    # Spark tables print as 'NN. Word' (several columns per line).
    for name in SPARK_ORDER:
        hits = sum(1 for k, v in SPARK[name].items() if f"{k}. {v}" in text)
        if hits < 30:
            failures.append(f"cross-check spark.{name}: only {hits}/36 "
                            "'NN. value' literals in extract")

    # Specific tables: one 'NN text' row per line between table headers
    # (exact-line headers; the contents page entries carry dot leaders).
    headers = [n.upper() for n in SPECIFIC_ORDER] + ["SAMPLE TRAIT SHEET"]
    pos = {}
    for i, line in enumerate(lines):
        s = line.strip()
        if s in headers and s not in pos and i > 200:  # skip contents page
            pos[s] = i
    row_re = re.compile(r"^\s*([1-6][1-6])\s+(\S.*)$")
    for name, nxt in zip(SPECIFIC_ORDER, SPECIFIC_ORDER[1:] +
                         ["sample trait sheet"]):
        start, end = pos.get(name.upper()), pos.get(nxt.upper())
        if start is None or end is None:
            failures.append(f"cross-check specific.{name}: region not "
                            "found in extract")
            continue
        rows = {}
        for line in lines[start:end]:
            m = row_re.match(line)
            if m:
                rows.setdefault(int(m.group(1)), m.group(2).strip())
        matched = sum(1 for k, v in SPECIFIC[name].items()
                      if rows.get(k) == v)
        if len(rows) < 30:
            failures.append(f"cross-check specific.{name}: only "
                            f"{len(rows)}/36 'NN text' rows in region")
        if matched < 30:
            failures.append(f"cross-check specific.{name}: only "
                            f"{matched}/36 rows match the extract "
                            "verbatim")


def cross_check_pettish(failures):
    """Pettish literals (best-effort; the hexflower figure is exempt —
    visual only). Wrapped two-column text is handled by also matching
    against per-column line streams (gutter at col 41)."""
    if not os.path.exists(PETTISH_EXTRACT):
        print(f"note: {PETTISH_EXTRACT} missing; "
              "skipped Pettish extract cross-check")
        return
    with open(PETTISH_EXTRACT, encoding="utf-8") as f:
        lines = f.read().splitlines()
    corpora = [
        _collapse(" ".join(lines)),                    # single-column wraps
        _collapse(" ".join(ln[:41] for ln in lines)),  # left column stream
        _collapse(" ".join(ln[41:] for ln in lines)),  # right column stream
    ]

    def found(value):
        v = _collapse(value)
        return any(v in c for c in corpora)

    def check_all(label, values, minimum=None):
        missing = [v for v in values if not found(v)]
        if len(values) - len(missing) < (minimum or len(values)):
            failures.append(f"cross-check {label}: missing from extract: "
                            f"{missing!r}")

    check_all("pet.personality_tags", PET_PERSONALITY_TAGS)
    check_all("pet.consequences", PET_CONSEQUENCES)
    check_all("pet.real_life", PET_REAL_LIFE)
    check_all("sidekick.tone", SIDEKICK_TONE)
    check_all("sidekick.topic", SIDEKICK_TOPIC)
    check_all("sidekick.said_how_a", SIDEKICK_SAID_HOW_A)
    check_all("sidekick.said_how_b", SIDEKICK_SAID_HOW_B)
    for k, row in PET_AGENDA.items():
        check_all(f"pet.agenda[{k}]",
                  [row["name"], row["flavor"], row["ask"]])
    for k, row in PET_FOCUS.items():
        check_all(f"pet.focus[{k}]", [row["name"], row["blurb"]])
    for mood, table in SIDEKICK_DIALOGUE.items():
        # "What tipped you off?" is normalized from the extract's
        # "off ?" spacing artifact, so allow one miss per mood.
        check_all(f"sidekick.dialogue.{mood}", list(table.values()),
                  minimum=10)


# ---------------------------------------------------------------------------
# EMIT
# ---------------------------------------------------------------------------


def emit_json(path):
    data = {
        "meta": META,
        "triple_o": {
            "spark": SPARK,
            "spark_order": SPARK_ORDER,
            "specific": SPECIFIC,
            "specific_order": SPECIFIC_ORDER,
        },
        "pet": {
            "agenda": PET_AGENDA,
            "focus": PET_FOCUS,
            "personality_tags": PET_PERSONALITY_TAGS,
            "consequences": PET_CONSEQUENCES,
            "real_life": PET_REAL_LIFE,
        },
        "sidekick": {
            "dialogue": SIDEKICK_DIALOGUE,
            "tone": SIDEKICK_TONE,
            "topic": SIDEKICK_TOPIC,
            "said_how_a": SIDEKICK_SAID_HOW_A,
            "said_how_b": SIDEKICK_SAID_HOW_B,
            "hexflower": {
                "hexes": [
                    {"index": i, "q": q, "r": r, "topic": topic,
                     "context": context}
                    for i, q, r, topic, context in HEXFLOWER_HEXES
                ],
                "adjacency": hexflower_adjacency(),
                "directions": HEX_DIRECTIONS,
                "direction_tones": HEX_DIRECTION_TONES,
                "direction_deltas": {
                    d: list(v) for d, v in HEX_DIRECTION_DELTAS.items()
                },
            },
        },
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    return data


if __name__ == "__main__":
    fails = verify()
    if fails:
        print("VERIFICATION FAILED:")
        for f_ in fails:
            print("  -", f_)
        raise SystemExit(1)
    print("All emulator data verifications passed.")
    data = emit_json("emulator_data.json")
    n_d66 = len(data["triple_o"]["spark"]) + len(data["triple_o"]["specific"])
    print(f"Emitted emulator_data.json: {n_d66} d66 tables + PET "
          "(agenda/focus/tags) + Sidekick (dialogue/hexflower).")
