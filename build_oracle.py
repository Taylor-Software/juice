"""
Juice Oracle — source of truth for table data + engine logic.

Run to (a) self-verify the engine against the PDF's documented Fate Check table
and probabilities, and (b) emit oracle_data.json consumed by the Flutter app.

Source: github.com/jrruethe/juice (CC BY-NC-SA), version 7/10/25, as transcribed
from juice_081425_screen.pdf (authoritative compact reference) and the
instructions deep-dive. Tables flagged BEST_EFFORT are OCR-ambiguous or visual
in the source and need a human pass against the PDF.
"""
import json
import random
from collections import Counter

# ---------------------------------------------------------------------------
# Simple d10 tables: index 1..9,0  -> we store as list[0..9] where list[0] is
# the "1" entry and list[9] is the "0/10" entry.
# ---------------------------------------------------------------------------

D10 = "1,2,3,4,5,6,7,8,9,0".split(",")  # display labels for a d10 roll

TABLES = {
    # ---- Fate intensity (d6) ----
    "intensity": ["Minimal", "Minor", "Mundane", "Average", "Major", "Maximum"],

    # ---- Quest ----
    "quest_objective": ["Attain", "Create", "Deliver", "Destroy", "Fetch",
                        "Infiltrate", "Investigate", "Negotiate", "Protect", "Survive"],
    "quest_description": ["Abandoned", "Cold", "Colorful", "Connected", "Dark",
                          "Friendly", "Hidden", "Mystical", "Remote", "Wounded"],
    "quest_focus": ["Enemy", "Monster", "Event", "Environment", "Community",
                    "Person", "Information", "Location", "Object", "Ally"],
    "quest_preposition": ["Around", "Behind", "In Front Of", "Near", "On Top Of",
                          "At", "From", "Inside Of", "Outside Of", "Under"],
    "quest_location": ["Community", "Dungeon Feature", "Dungeon", "Environment",
                       "Event", "Natural Hazard", "Outpost", "Settlement",
                       "Transportation", "Wilderness Feature"],

    # ---- Random Event / Challenge ----
    "random_event": ["Advance Time", "Close Thread", "Converge Thread",
                     "Diverge Thread", "Immersion", "Keyed Event", "New Character",
                     "NPC Action", "Plot Armor", "Remote Event"],
    "challenge_physical": ["Medicine", "Survival", "Animal Handling", "Performance",
                           "Intimidation", "Perception", "Sleight of Hand", "Stealth",
                           "Acrobatics", "Athletics"],
    "challenge_mental": ["Tool", "Nature", "Investigate", "Persuasion", "Deception",
                         "Language", "Religion", "Arcana", "History", "Insight"],
    # DC per d10 index (1->17 ... 0->8)
    "dc": ["17", "16", "15", "14", "13", "12", "11", "10", "9", "8"],

    # ---- Pay the Price ----
    "pay_the_price": ["Action has Unintended Effect", "Current Situation Worsens",
                      "Delayed / Disadvantaged", "Forced to Act Against Intentions",
                      "New Danger/Foe Revealed", "Person/Community Exposed to Danger",
                      "Separated From Person/Thing", "Something of Value Lost/Destroyed",
                      "Surprise Complication", "Trusted Person Betrays You"],
    "major_plot_twist": ["Actions Benefit Enemy", "Assumption Is False",
                         "Dark Secret Revealed", "Enemy Gains New Allies",
                         "Enemy Shares A Common Goal", "It Was All A Diversion",
                         "Secret Alliance Revealed", "Someone Returns Unexpectedly",
                         "Unrelated Situations Connected", "You Are Too Late"],

    # ---- Details / meaning ----
    "color": ["Shade Black", "Leather Brown", "Highlight Yellow", "Forest Green",
              "Cobalt Blue", "Crimson Red", "Royal Violet", "Metallic Silver",
              "Midas Gold", "Holy White"],
    "property": ["Age", "Durability", "Familiarity", "Power", "Quality", "Rarity",
                 "Size", "Style", "Value", "Weight"],
    "detail": ["Negative Emotion", "Disfavors PC", "Disfavors Thread", "Disfavors NPC",
               "History", "Property", "Favors NPC", "Favors Thread", "Favors PC",
               "Positive Emotion"],
    "history": ["Backstory", "Past Thread", "Previous Thread", "Past Scene",
                "Previous Scene", "Current Thread", "Past Action", "Current Scene",
                "Previous Action", "Current Action"],

    # ---- Immersion ----
    "immersion_see": ["Broken", "Colorful", "Discarded", "Edible", "Liquid",
                      "Natural", "Odd", "Round", "Shiny", "Written"],
    "immersion_hear": ["Dripping", "Fire", "Footsteps", "Growling", "Laughter",
                       "Music", "Scratching", "Silence", "Talking", "Wind"],
    "immersion_smell": ["Alcohol", "Blood", "Smoke", "Cooking", "Decay", "Dust",
                        "Flowers", "Leather", "Oil", "Soil"],
    "immersion_feel": ["Cold", "Damp", "Flexible", "Furry", "Rough", "Sharp",
                       "Slippery", "Smooth", "Sticky", "Warm"],
    "immersion_where": ["Above", "Behind", "In Front", "In The Air", "In The Distance",
                        "In The Next Room", "In The Shadows", "Next To You",
                        "On The Ground", "Under"],
    "emotion_negative": ["Despair", "Panic", "Fear", "Disgust", "Anger", "Sadness",
                         "Arrogance", "Confusion", "Apathy", "Deja Vu"],
    "emotion_positive": ["Hope", "Relief", "Courage", "Desire", "Calm", "Joy",
                         "Selflessness", "Clarity", "Nostalgia", "Awe"],
    "because": ["help is on the way", "it is getting closer", "it may be valuable",
                "of a childhood event", "of a recent memory", "the source is unknown",
                "then it is suddenly gone", "you recognize it", "you were warned about it",
                "you weren't expecting it"],

    # ---- Interrupt / Plot Point ----
    "interrupt_action": ["Abduction", "Barrier", "Battle", "Chase", "Collateral",
                         "Crash", "Culmination", "Distraction", "Harm", "Intensify"],
    "interrupt_tension": ["Choice", "Depletion", "Enemy", "Intimidation", "Night",
                         "Public", "Recurrence", "Remote", "Shady", "Trapped"],
    "interrupt_mystery": ["Alternate", "Behavior", "Connected", "Information",
                         "Intercept", "Lucky", "Reappearance", "Revelation", "Secret",
                         "Source"],
    "interrupt_social": ["Agreement", "Gathering", "Government", "Inadequate",
                        "Injustice", "Misbehave", "Outcast", "Outside", "Reinforcements",
                        "Savior"],
    "interrupt_personal": ["Animosity", "Connection", "Dependent", "Ethical", "Flee",
                          "Friend", "Help", "Home", "Humiliation", "Offer"],

    # ---- Random idea tables ----
    "idea_modifier": ["Change", "Continue", "Decrease", "Extra", "Increase", "Mundane",
                      "Mysterious", "Start", "Stop", "Strange"],
    "idea_idea": ["Attention", "Communication", "Danger", "Element", "Food", "Home",
                 "Resource", "Rumor", "Secret", "Vow"],
    "idea_event": ["Ambush", "Anomaly", "Blessing", "Caravan", "Curse", "Discovery",
                  "Escape", "Journey", "Prophecy", "Ritual"],
    "idea_person": ["Criminal", "Entertainer", "Expert", "Mage", "Mercenary", "Noble",
                   "Priest", "Ranger", "Soldier", "Transporter"],
    "idea_object": ["Arrow", "Candle", "Cauldron", "Chain", "Claw", "Hook", "Hourglass",
                   "Quill", "Rose", "Skull"],

    # ---- NPC ----
    "npc_personality": ["Cautious", "Curious", "Careless", "Organized", "Reserved",
                       "Outgoing", "Critical", "Compassionate", "Confident", "Sensitive"],
    "npc_need": ["Sustenance", "Shelter", "Recovery", "Security", "Stability",
                "Friendship", "Acceptance", "Status", "Recognition", "Fulfillment"],
    "npc_motive": ["History", "Family", "Experience", "Flaws", "Reputation", "Superiors",
                  "Wealth", "Equipment", "Treasure", "Focus"],
    "npc_behavior": ["Ambiguous Action", "Talks", "Continues", "Act: PC Interest",
                    "Next Most Logical", "Gives Something", "End Encounter",
                    "Act: Self Interest", "Takes Something", "Enters Combat"],
    "npc_combat": ["Defend", "Shift Focus", "Seize", "Intimidate", "Advantage",
                  "Coordinate", "Lure", "Destroy", "Precision", "Power"],

    # ---- Settlement ----
    "settlement_name": ["Frost Barrow", "High Brook", "Long Fall", "Lost Haven",
                       "Raven Ridge", "Shield River", "Storm Rock", "Sword Stead",
                       "Thorn Stone", "Wolf Wood"],
    "settlement_establishment": ["Stable", "Tavern", "Inn", "Entertainment",
                                "General Store", "Artisan", "Courier", "Temple",
                                "Guild Hall", "Magic Shop"],
    "settlement_artisan": ["Artist", "Baker", "Tailor", "Tanner", "Archer", "Blacksmith",
                          "Carpenter", "Apothecary", "Jeweler", "Scribe"],
    "settlement_news": ["War", "Sickness", "Natural Disaster", "Crime", "Succession",
                       "Remote Event", "Arrival", "Mail", "Sale", "Celebration"],

    # ---- Wilderness ----
    "wilderness_environment": ["Snowy - Arctic", "Rocky - Mountains", "Expansive 0 Cavern",
                              "Windy - Hills", "Scrub 0 Grassland", "Tropical 0 Forest*",
                              "Dark + Swamp", "Exotic + Water", "Sandy 0 Coast",
                              "Arid + Desert"],
    "wilderness_encounter": ["Natural Hazard", "Monster", "Weather", "Challenge",
                            "Dungeon", "River/Road", "Feature", "Settlement/Camp",
                            "Advance Plot", "Destination/Lost"],
    "wilderness_weather": ["Blizzard", "Snow Flurries", "Freezing Cold", "Thunder Storm",
                          "Heavy Rain", "Light Rain", "Heavy Clouds", "High Winds",
                          "Clear Skies", "Scorching Heat"],

    # ---- Natural hazard / feature / dungeon name ----
    "natural_hazard": ["Creature Tracks", "Dust Storm", "Flood", "Fog", "Rockslide",
                      "Unstable Ground", "Crevice", "Escarpment", "River Crossing",
                      "Thick Plants"],
    "wilderness_feature": ["Bones", "Cairn", "Chasm", "Circle", "Spring", "Grave",
                         "Monument", "Tower", "Tree", "Well"],
    "dungeon_name": ["Catacombs", "Cavern", "Crypt", "Fortress", "Hideout", "Lair",
                    "Mine", "Ruins", "Sanctuary", "Temple"],
    "dungeon_description": ["Bloodstained", "Chaotic", "Endless", "Fallen", "Forbidden",
                          "Forgotten", "Shattered", "Shrouded", "Silent", "Unknown"],
    "dungeon_subject": ["Blades", "Blight", "Darkness", "Fury", "Lies", "Madness",
                      "Mist", "Prophecy", "Runes", "Terror"],

    # ---- Dungeon generator ----
    "dungeon_next_area": ["Passage", "Small Chamber: 3 Doors", "Large Chamber: 3 Doors",
                        "Small Chamber: 2 Doors", "Small Chamber: 1 Door*", "Locked Door",
                        "Known / Expected", "Exit / Stairs", "Connect to Previous Area",
                        "Passage"],
    "dungeon_passage": ["Dead End", "Narrow Crawlspace", "Bridge", "Long", "Wide",
                      "Expected", "Right Angle Turn", "Side Passage", "3-Way Intersection",
                      "4-Way Intersection"],
    "dungeon_condition": ["Partially Collapsed", "Holes in Floor", "Flooded",
                        "Ashes / Burned", "Damaged", "Expected", "Stripped Bare",
                        "Used as Campsite", "Converted to Other Use", "Pristine"],

    # ---- Dungeon encounter ----
    "dungeon_encounter": ["Monster", "Natural Hazard", "Challenge", "Immersion", "Safety",
                        "Known / None", "Trap", "Feature", "Key", "Treasure"],
    "monster_description": ["Agile", "Beast", "Clothed", "Composite", "Decayed",
                          "Elemental", "Inscribed", "Intimidating", "Levitating",
                          "Nightmarish"],
    "monster_ability": ["Climb", "Detect", "Drain", "Entangle", "Illusion", "Immune",
                      "Magic", "Paralyze", "Pierce", "Ranged"],
    "trap_action": ["Ambush", "Collapse", "Divert", "Imitate", "Lure", "Obscure",
                  "Summon", "Surprise", "Surround", "Trigger"],
    "trap_subject": ["Alarm", "Barrier", "Decay", "Denizen", "Fall", "Fire", "Light",
                   "Path", "Poison", "Projectile"],
    "dungeon_feature": ["Library", "Mural", "Mushrooms", "Prison", "Runes", "Shrine",
                      "Storage", "Vault", "Well", "Workshop"],
}

# d6 sub-tables for Object/Treasure (each list is index 1..6)
TREASURE = {
    "Trinket":   {"Quality": ["Broken", "Damaged", "Worn", "Simple", "Exceptional", "Magic"],
                  "Material": ["Wood", "Bone", "Leather", "Silver", "Gold", "Gem"],
                  "Type": ["Toy/Game", "Bottle", "Instrument", "Charm", "Tool", "Key"]},
    "Treasure":  {"Quality": ["Dusty", "Worn", "Sturdy", "Fine", "New", "Ornate"],
                  "Container": ["None", "Pouch", "Box", "Satchel", "Crate", "Chest"],
                  "Contents": ["Food", "Art", "Deed", "Silver Coins", "Gold Coins", "Gems"]},
    "Document":  {"Type": ["Song", "Picture", "Letter/Note", "Scroll", "Journal", "Book"],
                  "Content": ["Lewd", "Common", "Map", "Prophecy", "Arcane", "Forbidden"],
                  "Subject": ["Religion", "Art", "Science", "Creatures", "History", "Magic"]},
    "Accessory": {"Quality": ["Ruined", "Crude", "Simple", "Fine", "Crafted", "Magic"],
                  "Material": ["Wood", "Bone", "Leather", "Silver", "Gold", "Gem"],
                  "Type": ["Headpiece", "Emblem", "Earring", "Bracelet", "Necklace", "Ring"]},
    "Weapon":    {"Quality": ["Broken", "Improvised", "Rough", "Simple", "Martial", "Masterwork"],
                  "Material": ["Wood", "Bone", "Steel", "Silver", "Mithral", "Adamantine"],
                  "Type": ["Axe/Hammer", "Halberd/Spear", "Sword/Dagger", "Staff/Wand", "Bow", "Exotic"]},
    "Armor":     {"Quality": ["Broken", "Improvised", "Tattered", "Simple", "Fine", "Masterwork"],
                  "Material": ["Cloth", "Leather", "Bone/Fur", "Steel", "Mithral", "Adamantine"],
                  "Type": ["Headpiece", "Bottom", "Gloves", "Boots", "Top", "Shield"]},
}
TREASURE_CATEGORY = ["Trinket", "Treasure", "Document", "Accessory", "Weapon", "Armor"]

# Discover Meaning (two d20 columns, Mythic-style verb + subject)
DISCOVER_VERB = ["Ancient", "Betray", "Conceal", "Dangerous", "Helpful", "Loud",
                 "Powerful", "Reveal", "Transform", "Unexpected", "Artificial", "Burning",
                 "Communicate", "Deceive", "Dirty", "Disagreeable", "Oppose", "Peaceful",
                 "Reassuring", "Specialized"]
DISCOVER_SUBJECT = ["Burden", "Complexity", "Conflict", "Control", "Direction", "Happiness",
                    "Memory", "Move", "Shadow", "Trust", "Assist", "Break", "Command",
                    "Delay", "Duration", "Failure", "Fight", "Leave", "Sacrifice", "Threshold"]

# Name generator syllable columns (d20 each). BEST_EFFORT: the source uses a skew
# pattern per row; here we roll each column independently and concatenate.
NAME_START = ["fa", "pe", "vi", "no", "su", "de", "ka", "li", "ma", "ro",
              "be", "da", "ki", "le", "mi", "ne", "ru", "si", "ta", "to"]
NAME_MID = ["hal", "ris", "del", "mor", "bar", "net", "kel", "lim", "tur", "pen",
            "rond", "kay", "jam", "vash", "zab", "yos", "gran", "ched", "sark", "kic"]
NAME_END = ["an", "ar", "er", "ian", "ic", "in", "o", "on", "or", "us",
            "a", "aea", "aya", "elle", "ene", "ess", "ette", "ice", "id", "osa"]

# Extended NPC d100 tables: list of (max_roll, text), roll 1..100
EXT_INFO_TYPE = [
    (3, "A connection between a PC and"), (6, "A connection between an antagonist and"),
    (9, "A connection between an NPC and"), (12, "A financial boon involving"),
    (15, "A financial loss involving"), (18, "A gain in influence involving"),
    (21, "A loss of influence involving"), (24, "A loss of opportunity involving"),
    (27, "A material boon involving"), (30, "A material loss involving"),
    (33, "A mental boon involving"), (36, "A mental loss involving"),
    (39, "A negative change in"), (42, "A physical boon involving"),
    (45, "A physical loss involving"), (48, "A positive change in"),
    (51, "A significant insight related to"), (54, "A spiritual boon involving"),
    (57, "A spiritual loss involving"), (60, "An additional opportunity involving"),
    (63, "An alteration of"), (66, "An ambush concerning"),
    (69, "An emotional boon involving"), (72, "An emotional loss involving"),
    (75, "Historical/background knowledge about"), (78, "Negative news about"),
    (81, "Positive news about"), (84, "The acquisition of an ability involving"),
    (87, "The acquisition of authority involving"), (90, "The identity of"),
    (93, "The location of"), (96, "The loss of an ability involving"),
    (99, "The loss of authority involving"),
    (100, "The truth is the exact opposite of what the PCs thought about"),
]
EXT_INFO_TOPIC = [
    (3, "a beloved NPC"), (6, "a benefactor for the PCs"), (9, "a combative NPC"),
    (12, "a dangerous location for the PCs"), (15, "a despised NPC"), (18, "a distant location"),
    (21, "a group supportive to the PCs"), (24, "a main antagonist"),
    (27, "a necessary artifact for fulfilling a vow"), (30, "a necessary object to complete a vow"),
    (33, "a person with important information about a side quest"),
    (36, "a person with important information about an important thread"),
    (39, "a previously unknown character connected to the plot"),
    (42, "a safe location for the PCs"), (45, "a secret enemy hideout"), (48, "a single PC"),
    (51, "a special status for a main antagonist"), (54, "a special status for a PC"),
    (57, "a special status for an NPC"), (60, "a traitor to the PCs"), (63, "an enemy leader"),
    (66, "an enemy servant"), (69, "an enemy spy"), (72, "an enemy stronghold"),
    (75, "an enemy who is now an ally"), (78, "an enemy's current plan"),
    (81, "an enemy's future plan"), (84, "an important thread"),
    (87, "an oppositional group that is not a main antagonist"), (90, "the current setting"),
    (93, "the current short-term goal"), (96, "the PCs as a whole"),
    (99, "the road or passage to the next location"), (100, "a foundational truth of the world"),
]
EXT_COMPANION = [
    (2, "You must be joking if you think I'll do that."), (4, "I refuse to go along with that plan."),
    (6, "That would never work because... There must be a better way."), (8, "No way, that's too..."),
    (10, "What benefit could... possibly bring us?"), (12, "I'm not comfortable with that idea."),
    (14, "We need to spend more time here doing..."), (16, "Don't you think there's the risk of...?"),
    (18, "Do we have enough... to do that?"), (20, "It's one option, but I would prefer to..."),
    (22, "You go ahead. I'll join you later."), (24, "I have my doubts, but maybe if we tweak it a bit..."),
    (26, "I don't think that is right..."), (28, "Yes, but first we have to..."),
    (30, "There are other priorities to take care of first."),
    (32, "I'm willing to give it a shot, but we need a backup plan."),
    (34, "Okay, I'll go along with it, but only if we take precautions."),
    (36, "I'm in, but let's be careful not to overlook the consequences."),
    (38, "I don't see this ending well."), (40, "Can we also...?"),
    (42, "Wait, what if we do the exact opposite?"),
    (44, "What if we take a completely unexpected route to get to...?"),
    (46, "I've got a wild plan that just might work..."),
    (48, "Yes, but how about we surprise them with..."),
    (50, "We can do that, but we have to tone down the..."), (52, "Who would that benefit?"),
    (54, "What is the next step?"), (56, "When should we...?"), (58, "Where should we...?"),
    (60, "How do you plan on...?"), (62, "What do you want?"), (64, "You just figured this out?"),
    (66, "Did you consider...?"), (68, "Ha!"), (70, "That's a bit unfair."),
    (72, "That is a really bad idea!"), (74, "There is something I need to tell you..."),
    (76, "Why is this happening?"), (78, "This is all very overwhelming!"), (80, "Help!"),
    (82, "Watch out!"), (84, "Lets go!"), (86, "I want to go home!"), (88, "Now is not a good time!"),
    (90, "Sure, I'm on board with that."), (92, "Sounds good, I'm in."),
    (94, "I'm willing to give it a try."), (96, "Let's do it, no objections here."),
    (98, "Okay, I'm with you on this one."), (100, "I'm ready, let's go for it."),
]
EXT_DIALOG_TOPIC = [
    (2, "A PC secret that has been made known"), (4, "A personal injury"),
    (6, "A recent change in the family of an NPC"), (8, "A recent change in their own family"),
    (10, "A recent inaction and the consequences"), (12, "A significant death"),
    (14, "A source of wealth"), (16, "A specific location"),
    (18, "An enemy secret that has been made known"), (20, "Common knowledge about an enemy"),
    (22, "Current events"), (24, "Famous people"), (26, "Famous places"),
    (28, "General knowledge of a region"), (30, "Important political connections"),
    (32, "Important social connections"), (34, "Information that has recently been discovered"),
    (36, "Ingenious or outlandish ideas"), (38, "Items of importance"), (40, "Legends of heroic deeds"),
    (42, "Legends of relics"), (44, "Local warbands"),
    (46, "Particular equipment of a trade, craft, or occupation"),
    (48, "Particular skills of a trade, craft, or occupation"), (50, "Powerful people"),
    (52, "Recent political changes"), (54, "Reported sightings of the First Born"),
    (56, "Rumors of a PC's past"), (58, "Rumors of an NPC's past"), (60, "Shifting political alliances"),
    (62, "Small jobs or side quests that need to be done"), (64, "The acquisition of knowledge"),
    (66, "The background of a PC"), (68, "The background of an NPC"),
    (70, "The background of the community"), (72, "The culture of the community"),
    (74, "The current leadership"), (76, "The distribution of wealth"), (78, "The failures of a PC"),
    (80, "The failures of an NPC"), (82, "The future of the community"),
    (84, "The most valuable experiences"), (86, "The quickest way to fame"),
    (88, "The value of experience"), (90, "Their own background"), (92, "Their own failures"),
    (94, "Upcoming events"), (96, "Useful contacts"), (98, "Where the power lies"),
    (100, "Why the leadership needs to change"),
]

# Wilderness Monster Encounter (pocketfold left extension), verified vs PDF.
# Quantity prefix per monster: '+' = 1d6-1@adv, '' = 1d6-1, '-' = 1d6-1@dis.
# Row keys: '1'..'0' (d6+mod result), '*' = Forest special, '**' = doubles/Bandits.
MONSTER_GRID = {
    "1":  ["+ Wolf", "- Ice Mephit", "- Winter Wolf", "Yeti", "Werebear"],
    "2":  ["+ Skeleton", "- Warhorse Skeleton", "- Wight", "- Nightmare", "Wraith"],
    "3":  ["+ Drow", "- Giant Spider", "Quaggoth", "- Phase Spider", "Drider"],
    "4":  ["+ Goblin", "- Worg", "+ Hobgoblin", "+ Bugbear", "Hobgoblin Captain"],
    "5":  ["Orc", "- Orog", "Orc Eye of Gruumsh", "- Troll", "Orc War Chief"],
    "6":  ["+ Kobold", "+ Giant Weasel", "+ Winged Kobold", "+ Stirge", "Young Dragon"],
    "7":  ["Lizardfolk", "Giant Lizard", "Lizardfolk Shaman", "- Giant Crocodile", "Lizard King"],
    "8":  ["+ Zombie", "Ghoul", "- Mummy", "Ogre Zombie", "Vampire Spawn"],
    "9":  ["Yuan-ti Pureblood", "- Cockatrice", "- Yuan-ti Malison", "Basilisk", "Medusa"],
    "0":  ["Gnoll", "- Giant Hyena", "Gnoll Pack Lord", "+ Jackalwere", "Lamia"],
    "*":  ["+ Twig Blight", "+ Needle Blight", "+ Vine Blight", "- Shambling Mound", "Green Hag"],
    "**": ["+ Bandit", "Thug", "Scout", "- Veteran", "Bandit Captain"],
}

# Wilderness env row (1..10) -> (modifier, skew) for the 1d6 monster-row roll.
# PDF Monster column: 1 Arctic +0@-, 2 Mountains +0@0, 3 Cavern +1@-, 4 Hills +1@0,
# 5 Grassland +3@-, 6 Forest +2@0, 7 Swamp +3@+, 8 Water +3@-, 9 Coast +4@-, 0 Desert +4@+.
MONSTER_ENV_FORMULA = {
    1: (0, -1), 2: (0, 0), 3: (1, -1), 4: (1, 0), 5: (3, -1),
    6: (2, 0), 7: (3, 1), 8: (3, -1), 9: (4, -1), 10: (4, 1),
}

# NPC Dialog 5x5 grid walk, verified vs PDF. Marker starts center (2,2).
# Rows 0-1 are past tense; rows 2-4 present (instructions p96).
DIALOG_GRID = [
    ["Fact", "Denial", "Query", "Denial", "Action"],
    ["Want", "Query", "Need", "Query", "Fact"],
    ["Action", "Need", "Fact", "Action", "Denial"],
    ["Need", "Query", "Denial", "Query", "Want"],
    ["Query", "Support", "Query", "Support", "Need"],
]
# d10 die 1 -> (tone, drow, dcol); die 2 -> subject.
DIALOG_DIRECTION = [  # (max_roll, tone, drow, dcol)
    (2, "Neutral", -1, 0), (5, "Defensive", 0, -1),
    (8, "Aggressive", 0, 1), (10, "Helpful", 1, 0),
]
DIALOG_SUBJECT = [(2, "Them"), (5, "Me"), (8, "You"), (10, "Us")]

# ---------------------------------------------------------------------------
# ENGINE
# ---------------------------------------------------------------------------

def df():
    """One Fate die: -1, 0, or +1 (equal probability)."""
    return random.choice([-1, 0, 1])

def d(n):
    return random.randint(1, n)

# Fate Check result mapping. Key = (primary, secondary). For double-blank (0,0)
# we additionally pass a 'side': 'left' -> Yes But + RE, 'right' -> Invalid Assumption.
FATE_MAP = {
    (1, 1):   {"normal": "Yes And",  "likely": "Yes And", "unlikely": "Yes And"},
    (1, 0):   {"normal": "Yes",      "likely": "Yes",     "unlikely": "Yes"},
    (1, -1):  {"normal": "Yes But",  "likely": "Yes But", "unlikely": "No But"},
    (0, 1):   {"normal": "Favorable","likely": "Yes",     "unlikely": "Yes"},
    (0, 0, "left"):  {"normal": "Yes But + Random Event", "likely": "Yes + Random Event", "unlikely": "No + Random Event"},
    (0, 0, "right"): {"normal": "Invalid Assumption", "likely": "Yes", "unlikely": "No"},
    (0, -1):  {"normal": "Unfavorable","likely": "No",    "unlikely": "No"},
    (-1, 1):  {"normal": "No But",   "likely": "Yes But", "unlikely": "No But"},
    (-1, 0):  {"normal": "No",       "likely": "No",      "unlikely": "No"},
    (-1, -1): {"normal": "No And",   "likely": "No And",  "unlikely": "No And"},
}

def fate_check(likelihood="normal"):
    """Roll a Fate Check. Returns dict with dice, result, intensity."""
    p, s = df(), df()
    intensity_roll = d(6)
    key = (p, s)
    side = None
    if p == 0 and s == 0:
        side = random.choice(["left", "right"])  # physical: position of primary die
        key = (0, 0, side)
    result = FATE_MAP[key][likelihood]
    return {
        "primary": p, "secondary": s, "side": side,
        "intensity_roll": intensity_roll,
        "intensity": TABLES["intensity"][intensity_roll - 1],
        "likelihood": likelihood,
        "result": result,
    }

def roll_table(name, skew=0):
    """Roll 1d10 on a named table. skew: +1 advantage (high), -1 disadvantage (low)."""
    if skew > 0:
        idx = max(d(10), d(10))
    elif skew < 0:
        idx = min(d(10), d(10))
    else:
        idx = d(10)
    label = D10[idx - 1]
    return {"roll": label, "value": TABLES[name][idx - 1]}

def monster_encounter(env_row):
    """Roll a monster encounter for wilderness environment row 1..10."""
    mod, skew = MONSTER_ENV_FORMULA[env_row]
    a, b = d(6), d(6)
    if skew > 0:
        pick = max(a, b)
    elif skew < 0:
        pick = min(a, b)
    else:
        pick = a
    if skew != 0 and a == b:
        row_key = "**"
    else:
        row = min(pick + mod, 10)
        row_key = "0" if row == 10 else str(row)
        if env_row == 6 and row == 6:
            row_key = "*"  # Forest special: Blights
    d1, d2 = d(10), d(10)
    band = 2 if d1 <= 4 else (3 if d1 <= 8 else 4)  # columns 1..band
    boss = d1 == d2
    monsters = []
    for cell in MONSTER_GRID[row_key][:band]:
        prefix, name = (cell[0], cell[2:]) if cell[:2] in ("+ ", "- ") else ("", cell)
        q1, q2 = d(6), d(6)
        qty = (max(q1, q2) if prefix == "+" else min(q1, q2) if prefix == "-" else q1) - 1
        if qty > 0:
            monsters.append((name, qty))
    if boss:
        monsters.append((MONSTER_GRID[row_key][4], 1))
    return {"row": row_key, "difficulty": {2: "Easy", 3: "Medium", 4: "Hard"}[band],
            "boss": boss, "monsters": monsters}

def d100_table(rows):
    """Roll 1d100 on a (max,text) range table."""
    r = d(100)
    for mx, text in rows:
        if r <= mx:
            return {"roll": r, "value": text}
    return {"roll": r, "value": rows[-1][1]}

# ---------------------------------------------------------------------------
# VERIFICATION
# ---------------------------------------------------------------------------

def verify():
    failures = []

    # 1. Documented Fate Check table (1d10 / 2dF / Normal / Likely / Unlikely)
    # from instructions p49. We check our FATE_MAP reproduces it exactly.
    expected = [
        ((1, 1),  "Yes And", "Yes And", "Yes And"),
        ((1, 0),  "Yes", "Yes", "Yes"),
        ((1, -1), "Yes But", "Yes But", "No But"),
        ((0, 1),  "Favorable", "Yes", "Yes"),
        ((0, 0, "left"),  "Yes But + Random Event", "Yes + Random Event", "No + Random Event"),
        ((0, 0, "right"), "Invalid Assumption", "Yes", "No"),
        ((0, -1), "Unfavorable", "No", "No"),
        ((-1, 1), "No But", "Yes But", "No But"),
        ((-1, 0), "No", "No", "No"),
        ((-1, -1),"No And", "No And", "No And"),
    ]
    for key, n, l, u in expected:
        got = FATE_MAP[key]
        if (got["normal"], got["likely"], got["unlikely"]) != (n, l, u):
            failures.append(f"Fate row {key}: expected {(n,l,u)} got "
                            f"{(got['normal'], got['likely'], got['unlikely'])}")

    # 2. Probability targets from instructions p48-49.
    # Normal: ~50% Yes-like, 11% Yes-And, ~5.5% Random Event, ~5.5% Invalid Assumption.
    # Likely: ~66% Yes-like. Unlikely mirrors (~66% No-like by symmetry of the map).
    N = 400_000
    def polarity(res):
        # RE rows contain "Yes"/"No" too; the RES still has a yes/no polarity.
        if "Yes" in res or res == "Favorable":
            return "yes"
        if "No" in res or res == "Unfavorable":
            return "no"
        if res == "Invalid Assumption":
            return "ia"
        return "other"

    # Targets from instructions p48-49: a "Yes But + Random Event" counts as
    # yes-like AND as a random event, so yes-like includes the RE row.
    for mode, yes_target in [("normal", 0.50), ("likely", 0.666)]:
        results = [fate_check(mode)["result"] for _ in range(N)]
        frac_yes = sum(polarity(r) == "yes" for r in results) / N
        if abs(frac_yes - yes_target) > 0.01:
            failures.append(f"{mode}: Yes-like {frac_yes:.3f} != ~{yes_target}")
        if mode == "normal":
            re_rate = sum("Random Event" in r for r in results) / N
            ia_rate = sum(r == "Invalid Assumption" for r in results) / N
            if abs(re_rate - 0.0556) > 0.005:
                failures.append(f"normal: RE rate {re_rate:.4f} != ~0.0556")
            if abs(ia_rate - 0.0556) > 0.005:
                failures.append(f"normal: IA rate {ia_rate:.4f} != ~0.0556")

    # 3. Yes-And rate ~11.1% (1/9) under normal
    c = Counter(fate_check("normal")["result"] for _ in range(N))
    ya = c["Yes And"] / N
    if abs(ya - 1/9) > 0.005:
        failures.append(f"Yes-And rate {ya:.4f} != ~0.1111")

    # 4. Advantage/disadvantage skew on a table: adv should bias toward index 0/10.
    adv = Counter(roll_table("dc", skew=1)["roll"] for _ in range(N))
    dis = Counter(roll_table("dc", skew=-1)["roll"] for _ in range(N))
    # "0" is the 10th slot (lowest DC 8). Advantage -> more "0"; disadvantage -> more "1".
    if adv["0"] <= dis["0"]:
        failures.append("advantage did not skew toward high index")
    if dis["1"] <= adv["1"]:
        failures.append("disadvantage did not skew toward low index")

    # 5. Table length sanity: every d10 table has exactly 10 entries.
    for name, vals in TABLES.items():
        if name == "intensity":
            if len(vals) != 6:
                failures.append(f"{name} len {len(vals)} != 6")
        elif len(vals) != 10:
            failures.append(f"{name} len {len(vals)} != 10")

    # 6. Monster grid shape + mechanics.
    if set(MONSTER_GRID) != {"1","2","3","4","5","6","7","8","9","0","*","**"}:
        failures.append("monster grid keys wrong")
    for k, row in MONSTER_GRID.items():
        if len(row) != 5:
            failures.append(f"monster row {k} len {len(row)} != 5")
        for cell in row:
            if cell[:2] not in ("+ ", "- ") and cell[0] in "+-":
                failures.append(f"monster cell malformed: {cell!r}")
    if len(MONSTER_ENV_FORMULA) != 10:
        failures.append("env formula must cover rows 1..10")
    encs = [monster_encounter(d(10)) for _ in range(N)]
    boss_rate = sum(e["boss"] for e in encs) / N
    if abs(boss_rate - 0.10) > 0.005:
        failures.append(f"boss rate {boss_rate:.4f} != ~0.10")
    diff = Counter(e["difficulty"] for e in encs)
    if abs(diff["Easy"]/N - 0.4) > 0.01 or abs(diff["Hard"]/N - 0.2) > 0.01:
        failures.append("difficulty bands off (want 40/40/20)")
    if not any(e["row"] == "*" for e in (monster_encounter(6) for _ in range(5000))):
        failures.append("forest special row never reached from env 6")

    # 7. Dialog grid shape and anchor.
    if len(DIALOG_GRID) != 5 or any(len(r) != 5 for r in DIALOG_GRID):
        failures.append("dialog grid not 5x5")
    if DIALOG_GRID[2][2] != "Fact":
        failures.append("dialog grid center must be Fact")
    if DIALOG_DIRECTION[-1][0] != 10 or DIALOG_SUBJECT[-1][0] != 10:
        failures.append("dialog bands must cover 1..10")

    return failures


def emit_json(path):
    data = {
        "meta": {
            "source": "github.com/jrruethe/juice",
            "license": "CC BY-NC-SA",
            "version": "7/10/25",
        },
        "tables": TABLES,
        "treasure": {"categories": TREASURE_CATEGORY, "sub": TREASURE},
        "discover": {"verb": DISCOVER_VERB, "subject": DISCOVER_SUBJECT},
        "name": {"start": NAME_START, "mid": NAME_MID, "end": NAME_END},
        "fate_map": {
            "|".join(str(x) for x in k): v for k, v in FATE_MAP.items()
        },
        "ext": {
            "info_type": EXT_INFO_TYPE,
            "info_topic": EXT_INFO_TOPIC,
            "companion": EXT_COMPANION,
            "dialog_topic": EXT_DIALOG_TOPIC,
        },
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    return data


if __name__ == "__main__":
    fails = verify()
    if fails:
        print("VERIFICATION FAILED:")
        for f_ in fails:
            print("  -", f_)
        raise SystemExit(1)
    print("All engine verifications passed.")
    data = emit_json("oracle_data.json")
    n_tables = len(data["tables"]) + 4  # treasure, discover, name, ext groups
    print(f"Emitted oracle_data.json: {len(data['tables'])} d10/d6 tables + "
          f"treasure/discover/name/extended sets.")
