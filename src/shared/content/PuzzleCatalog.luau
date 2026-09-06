local WordBank = if script
	then require(script.Parent:WaitForChild("WordBank"))
	else require("./WordBank")
local RandomClass = Random

-- Mode puzzle libraries.
local PuzzleLibrary = {
	Standard = {
		{
			title = "Bakery Bash",
			subtitle = "Warm trays, sweet counters, quick finds.",
			gridSize = 7,
			words = { "BAGEL", "BAKER", "BREAD", "COOKIE", "CRUST", "DONUT", "FLOUR", "GLAZE", "ICING", "MUFFIN", "OVEN", "ROLL" },
		},
		{
			title = "Aquarium Run",
			subtitle = "Glass tunnels and bright reef life.",
			gridSize = 8,
			words = { "BUBBLE", "CORAL", "CURRENT", "DOLPHIN", "EEL", "JELLY", "KELP", "OTTER", "REEF", "SHELL", "TURTLE", "WHALE" },
		},
		{
			title = "Space Port",
			subtitle = "Lift off lanes and orbital traffic.",
			gridSize = 8,
			words = { "ASTRO", "COMET", "GALAXY", "LAUNCH", "METEOR", "NEBULA", "ORBIT", "PLANET", "ROCKET", "SATURN", "STAR", "THRUST" },
		},
		{
			title = "Jungle Trek",
			subtitle = "Dense leaves, drums, and hidden trails.",
			gridSize = 8,
			words = { "CANOPY", "DRUM", "JAGUAR", "JUNGLE", "MONKEY", "PARROT", "RIVER", "TEMPLE", "TIGER", "TOTEM", "TRAIL", "VINE" },
		},
		{
			title = "Toy Box",
			subtitle = "Bright shelves and classic playroom finds.",
			gridSize = 7,
			words = { "BLOCK", "CRAYON", "DOLL", "GAME", "MARBLE", "PAINT", "PUZZLE", "ROBOT", "SCOOTER", "TOYBOX", "TRAIN", "YOYO" },
		},
		{
			title = "Movie Night",
			subtitle = "Lights down, projector on.",
			gridSize = 8,
			words = { "ACTOR", "CAMERA", "CINEMA", "COMEDY", "CREDITS", "POPCORN", "POSTER", "REEL", "SCENE", "SCREEN", "TICKET", "USHER" },
		},
		{
			title = "Road Trip",
			subtitle = "Long roads, loud songs, snack stops.",
			gridSize = 8,
			words = { "ATLAS", "BRAKE", "CABIN", "CAMP", "FREEWAY", "GAS", "HOTEL", "MILE", "ROUTE", "SIGN", "TRUCK", "WAGON" },
		},
		{
			title = "Science Lab",
			subtitle = "Bubbling glass and tidy notebooks.",
			gridSize = 8,
			words = { "ATOM", "BEAKER", "BURNER", "FORMULA", "LASER", "MAGNET", "MIXER", "NOTES", "PIPETTE", "SENSOR", "THEORY", "TUBE" },
		},
		{
			title = "Farm Market",
			subtitle = "Fresh rows and early morning crates.",
			gridSize = 7,
			words = { "APPLE", "BARN", "BERRY", "CRATE", "FIELD", "GOAT", "HARVEST", "HAY", "MELON", "PEACH", "TRACTOR", "WHEAT" },
		},
		{
			title = "Mountain Camp",
			subtitle = "Cold air and a glowing fire ring.",
			gridSize = 8,
			words = { "BOOTS", "CAMP", "CLIFF", "ECHO", "FIRE", "HIKE", "LANTERN", "PEAK", "PINE", "RIDGE", "TENT", "TRAIL" },
		},
		{
			title = "Super Store",
			subtitle = "Aisles, carts, and checkout beeps.",
			gridSize = 8,
			words = { "AISLE", "BASKET", "CART", "CASHIER", "CEREAL", "COUPON", "FREEZER", "JUICE", "MARKET", "RECEIPT", "SHELF", "SNACK" },
		},
		{
			title = "Sports Arena",
			subtitle = "Crowds up, scoreboards lit.",
			gridSize = 8,
			words = { "ARENA", "COACH", "CROWD", "GOAL", "HELMET", "JERSEY", "MEDAL", "RALLY", "REFEREE", "SCORE", "TEAM", "WHISTLE" },
		},
		{
			title = "Build Site",
			subtitle = "Steel beams and concrete dust.",
			gridSize = 8,
			words = { "BEAM", "BOLT", "BRICK", "CRANE", "DRILL", "FRAME", "HAMMER", "LADDER", "LEVEL", "PLANK", "SAFETY", "TOOLBOX" },
		},
		{
			title = "Treasure Cove",
			subtitle = "Maps, lanterns, and buried shine.",
			gridSize = 8,
			words = { "ANCHOR", "CHEST", "CLUE", "COIN", "COVE", "GOLD", "ISLAND", "MAP", "PIRATE", "RUMOR", "SHOVEL", "VOYAGE" },
		},
		{
			title = "Dino Dig",
			subtitle = "Dusty bones and giant tracks.",
			gridSize = 8,
			words = { "BONE", "CLAW", "DIG", "DINOSAUR", "FOSSIL", "METEOR", "MUSEUM", "RAPTOR", "ROAR", "SCALES", "SKULL", "TAIL" },
		},
		{
			title = "Magic Show",
			subtitle = "Curtains, sparks, and quick hands.",
			gridSize = 8,
			words = { "CAPE", "CARD", "CRYSTAL", "DOVE", "MAGIC", "RABBIT", "SPELL", "STAGE", "STAR", "TRICK", "WAND", "WIZARD" },
		},
		{
			title = "Robot Room",
			subtitle = "Tiny gears and blinking panels.",
			gridSize = 8,
			words = { "BATTERY", "BOLT", "CIRCUIT", "CODE", "DRONE", "GEAR", "LASER", "METAL", "ROBOT", "SERVO", "SPARK", "SWITCH" },
		},
		{
			title = "Pet Parade",
			subtitle = "Happy paws and wagging tails.",
			gridSize = 7,
			words = { "BOWL", "COLLAR", "HAMSTER", "KITTEN", "LEASH", "PUPPY", "RABBIT", "SADDLE", "TREAT", "VET", "WHISKER", "YARN" },
		},
		{
			title = "Rainy City",
			subtitle = "Wet streets and bright windows.",
			gridSize = 8,
			words = { "AWNING", "BUS", "CROSSWALK", "DRIZZLE", "NEON", "PUDDLE", "RAINCOAT", "SIDEWALK", "STORM", "TAXI", "UMBRELLA", "WINDOW" },
		},
		{
			title = "Desert Trail",
			subtitle = "Sand paths and hot horizon lines.",
			gridSize = 8,
			words = { "CACTUS", "CAMEL", "CANYON", "DUNE", "HEAT", "LIZARD", "MESA", "MIRAGE", "OASIS", "SAND", "SCORPION", "SUNSET" },
		},
		{
			title = "Safari Run",
			subtitle = "Big sky and distant hoofbeats.",
			gridSize = 8,
			words = { "CHEETAH", "ELEPHANT", "GAZELLE", "JEEP", "LION", "RHINO", "SAVANNA", "TRACK", "VULTURE", "WATERHOLE", "ZEBRA", "ZOO" },
		},
		{
			title = "Ice Palace",
			subtitle = "Frozen halls and bright blue stone.",
			gridSize = 8,
			words = { "BLIZZARD", "CRYSTAL", "FROST", "GLACIER", "ICEBERG", "PALACE", "SHIVER", "SKATE", "SLED", "SNOW", "WINTER", "WOOL" },
		},
		{
			title = "Pirate Deck",
			subtitle = "Salt spray and rope swings.",
			gridSize = 8,
			words = { "BARREL", "CAPTAIN", "COMPASS", "CREW", "CUTLASS", "DECK", "FLAG", "HARBOR", "HOOK", "PARROT", "PLANK", "RIGGING" },
		},
		{
			title = "Circus Tent",
			subtitle = "Bright lights and fast applause.",
			gridSize = 8,
			words = { "ACROBAT", "BALLOON", "CLOWN", "JUGGLE", "RING", "SPOTLIGHT", "STALL", "TENT", "TICKET", "TRAPEZE", "TRUMPET", "UNICYCLE" },
		},
		{
			title = "Castle Court",
			subtitle = "Stone walls and echoing steps.",
			gridSize = 8,
			words = { "ARMOR", "CASTLE", "COURT", "CROWN", "GUARD", "KNIGHT", "MOAT", "QUEEN", "SHIELD", "THRONE", "TOWER", "TRUMPET" },
		},
		{
			title = "Music Fest",
			subtitle = "Stage lights and heavy rhythm.",
			gridSize = 8,
			words = { "AMP", "BEAT", "CHORD", "DRUM", "ENCORE", "LYRIC", "MELODY", "NOTE", "RHYTHM", "SONG", "STAGE", "VINYL" },
		},
		{
			title = "Candy Shop",
			subtitle = "Glass jars and sugar rush lanes.",
			gridSize = 7,
			words = { "CANDY", "CARAMEL", "FUDGE", "GUMMY", "JELLY", "LICORICE", "LOLLIPOP", "MINT", "SPRINKLE", "TAFFY", "TOFFEE", "TRUFFLE" },
		},
		{
			title = "Art Studio",
			subtitle = "Paint drops and careful outlines.",
			gridSize = 8,
			words = { "BRUSH", "CANVAS", "CHARCOAL", "COLOR", "EASEL", "FRAME", "INK", "PALETTE", "PASTEL", "SKETCH", "STROKE", "WASH" },
		},
		{
			title = "Forest Trail",
			subtitle = "Mossy turns and hidden streams.",
			gridSize = 8,
			words = { "ACORN", "BIRCH", "BROOK", "DEER", "FERN", "FOX", "MOSS", "OWL", "PATH", "PINECONE", "STREAM", "WOODLAND" },
		},
		{
			title = "Beach Club",
			subtitle = "Salt air and bright umbrellas.",
			gridSize = 8,
			words = { "BOARDWALK", "BUOY", "COAST", "PALM", "SANDCASTLE", "SEASHELL", "SHORE", "SURF", "TIDE", "TOWEL", "WAVE", "WHARF" },
		},
		{
			title = "Airport Rush",
			subtitle = "Rolling bags and flashing gates.",
			gridSize = 8,
			words = { "ARRIVAL", "BAGGAGE", "BOARDING", "COCKPIT", "GATE", "JET", "PILOT", "RADAR", "RUNWAY", "SECURITY", "TERMINAL", "TOWER" },
		},
		{
			title = "Garden Party",
			subtitle = "Late sun and blooming paths.",
			gridSize = 8,
			words = { "ARBOR", "BLOOM", "BUTTERFLY", "FLOWER", "GARDEN", "HEDGE", "LAWN", "PETAL", "ROSE", "SEED", "STEM", "VASE" },
		},
		{
			title = "Volcano Base",
			subtitle = "Heat, sparks, and glowing stone.",
			gridSize = 8,
			words = { "ASH", "BASALT", "CRATER", "ERUPTION", "FLAME", "LAVA", "MAGMA", "RIDGE", "SMOKE", "VENT", "VOLCANO", "STONE" },
		},
		{
			title = "Deep Sea",
			subtitle = "Dark pressure and moving lights.",
			gridSize = 8,
			words = { "ABYSS", "ANGLER", "CURRENT", "DIVER", "JELLY", "LANTERN", "REEF", "SALT", "SQUID", "SUBMARINE", "TRENCH", "WHALE" },
		},
		{
			title = "Comic Corner",
			subtitle = "Panels, ink, and caped pages.",
			gridSize = 8,
			words = { "BUBBLE", "CAPE", "COMIC", "HERO", "INK", "ISSUE", "MASK", "PANEL", "PUNCH", "SIDEKICK", "SPLASH", "VILLAIN" },
		},
		{
			title = "Pixel Arcade",
			subtitle = "Blinking cabinets and score chases.",
			gridSize = 8,
			words = { "ARCADE", "BONUS", "COIN", "COMBO", "HIGHSCORE", "JOYSTICK", "LASER", "LEVEL", "PIXEL", "SCORE", "TOKEN", "WARP" },
		},
		{
			title = "Secret Agent",
			subtitle = "Shadows, codes, and clean exits.",
			gridSize = 8,
			words = { "AGENT", "ALIAS", "BRIEF", "CLUE", "CODE", "GADGET", "LASER", "MISSION", "SHADOW", "STEALTH", "TARGET", "VAULT" },
		},
		{
			title = "Myth Hall",
			subtitle = "Ancient stories carved in stone.",
			gridSize = 8,
			words = { "ATLAS", "CENTAUR", "DRAGON", "GIANT", "HYDRA", "LEGEND", "MEDUSA", "MYTH", "ORACLE", "PHOENIX", "TITAN", "TEMPLE" },
		},
	},
	Mega = {
		{
			title = "Skyport Sprawl",
			subtitle = "A vast airborne city hunt.",
			gridSize = 20,
			words = { "AIRSHIP", "ARRIVAL", "BAZAAR", "CARGO", "CATWALK", "COMPASS", "CONTROL", "DOCK", "ENGINE", "GATEWAY", "GLIDER", "HANGAR", "LANDING", "MARKET", "PROPELLER", "RUNWAY", "SHUTTLE", "SKYBRIDGE", "SKYPORT", "STATION", "TERMINAL", "TOWER", "TRAVELER", "WINCH" },
		},
		{
			title = "Monster Museum",
			subtitle = "Huge halls full of strange exhibits.",
			gridSize = 20,
			words = { "ARCHIVE", "ARTIFACT", "BEAST", "CARVING", "CHAMBER", "CURATOR", "DISPLAY", "EXHIBIT", "FANG", "FOSSIL", "GALLEY", "GIANT", "GOBLIN", "GRIFFIN", "LEGEND", "MANUSCRIPT", "MINOTAUR", "MONSTER", "RELIC", "SKELETON", "SPHINX", "STATUE", "VAULT", "WING" },
		},
		{
			title = "Mythic Kingdom",
			subtitle = "A giant royal board with old magic.",
			gridSize = 20,
			words = { "ARMORY", "BANNER", "BASTION", "CASTLE", "CATAPULT", "CHAMPION", "COURTYARD", "CROWN", "DRAGON", "ENCHANT", "FORTRESS", "GATEHOUSE", "KINGDOM", "KNIGHT", "LANTERN", "LEGEND", "MOAT", "ORACLE", "PALADIN", "QUEEN", "SCEPTER", "THRONE", "TOWER", "WARDEN" },
		},
		{
			title = "Cyber City",
			subtitle = "Neon routes and layered systems.",
			gridSize = 20,
			words = { "ALGORITHM", "ANDROID", "ARCADE", "BATTERY", "CIRCUIT", "CONSOLE", "CYBER", "DATA", "DISPLAY", "DRONE", "ENGINE", "FIREWALL", "GLITCH", "HOLOGRAM", "INTERFACE", "NETWORK", "NEURAL", "PIXEL", "ROUTER", "SERVER", "SIGNAL", "SYNTH", "TERMINAL", "VECTOR" },
		},
		{
			title = "Ocean Trench",
			subtitle = "Cold depths and giant creatures.",
			gridSize = 20,
			words = { "ABYSS", "ANCHOR", "BIOGLOW", "BUBBLE", "CURRENT", "DIVER", "EEL", "GILL", "HADAL", "JELLY", "KELP", "KRILL", "LANTERN", "MARINER", "PRESSURE", "REEF", "SALTWATER", "SEAFLOOR", "SQUID", "SUBMARINE", "TIDE", "TRENCH", "VENT", "WHALE" },
		},
		{
			title = "Jungle Expedition",
			subtitle = "Deep canopy, ruins, and river turns.",
			gridSize = 20,
			words = { "ARCHAEOLOGY", "BACKPACK", "CANOPY", "COMPASS", "DRUM", "EXPEDITION", "FERN", "JAGUAR", "JOURNAL", "JUNGLE", "LANTERN", "MACAW", "MONKEY", "MOSS", "PARROT", "RUINS", "RIVER", "SATCHEL", "SCOUT", "TEMPLE", "TOTEM", "TRAIL", "VINE", "WATERFALL" },
		},
		{
			title = "Snow Fortress",
			subtitle = "A giant frozen stronghold board.",
			gridSize = 20,
			words = { "AVALANCHE", "BLIZZARD", "CITADEL", "CRYSTAL", "DRIFT", "FROST", "GLACIER", "ICEBERG", "LANTERN", "PALACE", "RAMPART", "SHIVER", "SLED", "SNOWFALL", "SNOWMAN", "SPARKLE", "SPIRE", "SUMMIT", "TUNDRA", "WATCHTOWER", "WHITEOUT", "WINTER", "WOOL", "YETI" },
		},
		{
			title = "Space Colony",
			subtitle = "A huge off-world station hunt.",
			gridSize = 20,
			words = { "AIRLOCK", "ANTENNA", "ASTEROID", "CAPSULE", "COLONY", "COMMAND", "COSMIC", "DOCKING", "GALAXY", "GRAVITY", "HABITAT", "LAUNCH", "LUNAR", "MISSION", "NEBULA", "ORBIT", "PANEL", "PLANET", "RADIANT", "ROVER", "SATELLITE", "SHUTTLE", "SOLAR", "THRUSTER" },
		},
		{
			title = "Treasure Fleet",
			subtitle = "Ships, maps, and stormy water.",
			gridSize = 20,
			words = { "ADMIRAL", "ANCHOR", "BARREL", "CAPTAIN", "CHART", "CHEST", "COMPASS", "CORSAIR", "CUTLASS", "DECK", "FLEET", "GALLEON", "HARBOR", "ISLAND", "LANTERN", "PLANK", "PRIVATEER", "RIGGING", "ROPE", "SAIL", "SHIPYARD", "TIDE", "TREASURE", "VOYAGE" },
		},
		{
			title = "Ancient Wonders",
			subtitle = "Massive ruins and forgotten halls.",
			gridSize = 20,
			words = { "ARCHWAY", "CARVING", "CHAMBER", "COLUMN", "DESERT", "EMPIRE", "FRESCO", "GLYPH", "GRANITE", "HIEROGLYPH", "LABYRINTH", "MARBLE", "MONUMENT", "OBELISK", "ORACLE", "PYRAMID", "RELIC", "RUINS", "SANDSTONE", "SCROLL", "TEMPLE", "TRIBUTE", "VAULT", "WONDER" },
		},
		{
			title = "Festival Plaza",
			subtitle = "A wide board full of lights and noise.",
			gridSize = 20,
			words = { "BALLOON", "BANNER", "BOOTH", "CARNIVAL", "CONFETTI", "DANCER", "DRUM", "FESTIVAL", "FIREWORK", "FLOAT", "FOODSTALL", "LANTERN", "MARKET", "MUSIC", "PARADE", "PLAZA", "PRIZE", "RIBBON", "SPARKLER", "SPOTLIGHT", "STAGE", "STREAMER", "TICKET", "VENDOR" },
		},
		{
			title = "Wild Safari",
			subtitle = "Open plains and fast-moving herds.",
			gridSize = 20,
			words = { "ACACIA", "ANTELOPE", "CAMPFIRE", "CHEETAH", "ELEPHANT", "EXPEDITION", "GAZELLE", "JEEP", "LANTERN", "LEOPARD", "LION", "OUTPOST", "RANGER", "RHINO", "RIVERBED", "SAVANNA", "SCOUT", "SUNRISE", "TRACKER", "VULTURE", "WATERHOLE", "WILDLIFE", "ZEBRA", "ZONE" },
		},
	},
	Daily = {
		{
			title = "World Expo",
			subtitle = "A huge daily map packed with global sights.",
			gridSize = 25,
			words = { "AIRPORT", "AMPHITHEATER", "ARCHWAY", "AVENUE", "BAZAAR", "BRIDGE", "CANAL", "CAPITAL", "CATHEDRAL", "COURTYARD", "DISTRICT", "EMBASSY", "EXHIBIT", "FESTIVAL", "FOUNTAIN", "GARDENS", "HARBOR", "LIBRARY", "MARKET", "METRO", "MONUMENT", "MUSEUM", "PAVILION", "PLAZA", "SKYLINE", "STATION", "STREET", "THEATER", "TOWER", "TRAVEL" },
		},
		{
			title = "Mythic Atlas",
			subtitle = "One giant daily hunt across old legends.",
			gridSize = 25,
			words = { "ALTAR", "AMULET", "ATLAS", "BEHEMOTH", "CENTAUR", "CHIMERA", "COLOSSUS", "CRYSTAL", "DRAGON", "ENCHANT", "FORTRESS", "GIANT", "GRIFFIN", "HYDRA", "KINGDOM", "LABYRINTH", "LEGEND", "MEDUSA", "MINOTAUR", "ORACLE", "PHOENIX", "SCEPTER", "SPHINX", "TEMPLE", "THUNDER", "TITAN", "TRIDENT", "VALKYRIE", "WARDEN", "ZEPHYR" },
		},
		{
			title = "Future Metropolis",
			subtitle = "A dense daily city board with neon layers.",
			gridSize = 25,
			words = { "ANDROID", "ANTENNA", "ARCADE", "AUTOPILOT", "BATTERY", "CIRCUIT", "CONSOLE", "CYBER", "DATASTREAM", "DISPLAY", "DRONE", "ELEVATOR", "FIREWALL", "GLITCH", "HOLOGRAM", "INTERFACE", "MEGACITY", "NETWORK", "NEURAL", "OVERPASS", "PIXEL", "ROUTER", "SERVER", "SKYBRIDGE", "SKYLINE", "STATION", "SYNTH", "TERMINAL", "TRANSIT", "VECTOR" },
		},
		{
			title = "Grand Safari",
			subtitle = "A wide daily route through wild country.",
			gridSize = 25,
			words = { "ACACIA", "ANTELOPE", "BACKTRACK", "CAMPGROUND", "CHEETAH", "ELEPHANT", "EXPLORER", "FIELDGUIDE", "GAZELLE", "HORIZON", "JEEP", "LANTERN", "LEOPARD", "LOOKOUT", "MIGRATION", "OUTPOST", "PANORAMA", "RANGER", "RHINO", "RIVERBED", "SAVANNA", "SUNRISE", "TRACKER", "VULTURE", "WATERHOLE", "WILDLIFE", "WINDSWEPT", "WOODLAND", "ZEBRA", "ZONE" },
		},
		{
			title = "Deep Blue Daily",
			subtitle = "A huge underwater board for the day.",
			gridSize = 25,
			words = { "ABYSS", "ANGLER", "BARNACLE", "BIOGLOW", "BUBBLE", "CURRENT", "DIVER", "EEL", "GILL", "JELLYFISH", "KELPFOREST", "KRILL", "LANTERN", "MARINER", "OCEAN", "OCTOPUS", "PRESSURE", "REEF", "SALTWATER", "SEAFLOOR", "SHIPWRECK", "SQUID", "SUBMARINE", "TIDEPOOL", "TRIDENT", "TRENCH", "TURTLE", "VENT", "WAVEFORM", "WHALE" },
		},
		{
			title = "Sky Kingdom",
			subtitle = "A giant high-altitude daily board.",
			gridSize = 25,
			words = { "AIRSHIP", "BALLOON", "BASTION", "BRIDGEWAY", "CASTLE", "CITADEL", "CLOUD", "COMPASS", "COURT", "DRAGON", "FLIGHTPATH", "GALLEON", "GATEHOUSE", "GLIDER", "KINGDOM", "LANTERN", "PALACE", "PARAPET", "PAVILION", "PROPELLER", "RAMPART", "RUNWAY", "SHUTTLE", "SKYBRIDGE", "SKYPORT", "SUMMIT", "TERMINAL", "THRONE", "TOWER", "WINDWAY" },
		},
		{
			title = "Ancient Empire",
			subtitle = "Massive stonework and hidden chambers.",
			gridSize = 25,
			words = { "AMPHORA", "ARCHWAY", "BASILICA", "CARVING", "CHAMBER", "COLUMN", "CORRIDOR", "DESERT", "EMPIRE", "FRESCO", "GLYPH", "GRANITE", "HALLWAY", "HIEROGLYPH", "MARBLE", "MONUMENT", "MOSAIC", "OBELISK", "PALACE", "PYRAMID", "RELIC", "RUINS", "SANCTUM", "SANDSTONE", "SCROLL", "STATUE", "TEMPLE", "THRONE", "TRIBUTE", "VAULT" },
		},
		{
			title = "Carnival Crown",
			subtitle = "A busy daily board full of lights and prizes.",
			gridSize = 25,
			words = { "ARCADE", "BALLOON", "BANNER", "BOOTH", "CARNIVAL", "CAROUSEL", "CONFETTI", "DANCER", "FERRIS", "FESTIVAL", "FIREWORK", "FLOAT", "FUNHOUSE", "LANTERN", "MIDWAY", "MUSIC", "PARADE", "PLAZA", "PRIZE", "RIBBON", "ROLLERCOASTER", "SPARKLER", "SPOTLIGHT", "STALL", "STAGE", "STREAMER", "TICKET", "TRUMPET", "VENDOR", "WONDER" },
		},
		{
			title = "Frozen Frontier",
			subtitle = "A giant daily ice field with sharp weather.",
			gridSize = 25,
			words = { "AURORA", "AVALANCHE", "BLIZZARD", "CRYSTAL", "DRIFT", "FROST", "GLACIER", "HAILSTONE", "ICEBERG", "LANTERN", "OUTPOST", "PALACE", "RIDGELINE", "SHIVER", "SLED", "SNOWDRIFT", "SNOWFIELD", "SNOWMAN", "SPARKLE", "SPIRE", "SUMMIT", "TUNDRA", "WATCHTOWER", "WHITEOUT", "WINDCHILL", "WINTER", "WOOL", "YETI", "ZONE", "ZEPHYR" },
		},
		{
			title = "Lost Jungle City",
			subtitle = "Ruins, rivers, and a huge green canopy.",
			gridSize = 25,
			words = { "ARCHAEOLOGY", "BACKPACK", "CANOPY", "CARVING", "CATARACT", "COMPASS", "DRUM", "EXPEDITION", "FERN", "JAGUAR", "JOURNAL", "JUNGLE", "LANTERN", "MONKEY", "MOSS", "OUTPOST", "PARROT", "PYRAMID", "RIVER", "RUINS", "SCOUT", "STATUE", "TEMPLE", "TOTEM", "TRAIL", "TRIBUTE", "VINE", "WATERFALL", "WOODLAND", "ZONE" },
		},
	},
}



-- Themed puzzle collections.
local ThemedModeLibrary = {}

local themes = {
	{
		id = "Countries",
		title = "Countries",
		subtitle = "Places, flags, and world travel words.",
		gridSize = 9,
		words = {
			"ARGENTINA",
			"BRAZIL",
			"CANADA",
			"CHILE",
			"CHINA",
			"EGYPT",
			"FRANCE",
			"GHANA",
			"GREECE",
			"INDIA",
			"ITALY",
			"JAPAN",
			"KENYA",
			"MEXICO",
			"NEPAL",
			"NORWAY",
			"PERU",
			"POLAND",
			"QATAR",
			"SPAIN",
			"TURKEY",
		},
	},
	{
		id = "Animals",
		title = "Animals",
		subtitle = "Land, sea, and sky creatures.",
		gridSize = 9,
		words = {
			"BADGER",
			"BEAVER",
			"CAMEL",
			"CHEETAH",
			"DOLPHIN",
			"EAGLE",
			"FERRET",
			"FOX",
			"GIRAFFE",
			"HAMSTER",
			"JAGUAR",
			"KOALA",
			"LEMUR",
			"OTTER",
			"PANTHER",
			"RABBIT",
			"SEAL",
			"TIGER",
			"TURTLE",
			"WALRUS",
			"ZEBRA",
		},
	},
	{
		id = "Food",
		title = "Food",
		subtitle = "Meals, treats, and kitchen picks.",
		gridSize = 8,
		words = {
			"APPLE",
			"AVOCADO",
			"BAGEL",
			"BURGER",
			"CARROT",
			"CHEESE",
			"COOKIE",
			"CURRY",
			"DONUT",
			"GRAPES",
			"HONEY",
			"LEMON",
			"MUFFIN",
			"NOODLE",
			"PEACH",
			"PIZZA",
			"SALAD",
			"SOUP",
			"STEAK",
			"TACO",
			"WAFFLE",
		},
	},
	{
		id = "Sports",
		title = "Sports",
		subtitle = "Teams, gear, and big match words.",
		gridSize = 9,
		words = {
			"ARCHERY",
			"ARENA",
			"BATON",
			"COACH",
			"CRICKET",
			"DRIBBLE",
			"FIELD",
			"GOAL",
			"HELMET",
			"JERSEY",
			"LEAGUE",
			"MEDAL",
			"RALLY",
			"REFEREE",
			"ROWING",
			"SCORE",
			"SKATE",
			"TENNIS",
			"VOLLEY",
			"WHISTLE",
			"WRESTLE",
		},
	},
	{
		id = "Space",
		title = "Space",
		subtitle = "Planets, stars, and launch words.",
		gridSize = 9,
		words = {
			"ASTEROID",
			"ASTRONAUT",
			"COMET",
			"COSMOS",
			"ECLIPSE",
			"GALAXY",
			"GRAVITY",
			"LAUNCH",
			"METEOR",
			"MOON",
			"NEBULA",
			"ORBIT",
			"PLANET",
			"ROCKET",
			"SATELLITE",
			"SATURN",
			"SOLAR",
			"STAR",
			"THRUST",
			"VENUS",
			"VOID",
		},
	},
	{
		id = "Ocean",
		title = "Ocean",
		subtitle = "Waves, coastlines, and sea life.",
		gridSize = 9,
		words = {
			"ANCHOR",
			"CORAL",
			"CURRENT",
			"DEEPSEA",
			"HARBOR",
			"ISLAND",
			"JELLY",
			"KELP",
			"LAGOON",
			"MARINA",
			"OCEAN",
			"PEARL",
			"REEF",
			"SALTWATER",
			"SHELL",
			"SHORE",
			"SQUID",
			"TIDE",
			"TRENCH",
			"WAVE",
			"WHALE",
		},
	},
	{
		id = "Weather",
		title = "Weather",
		subtitle = "Forecasts, storms, and sky changes.",
		gridSize = 8,
		words = {
			"AURORA",
			"BLIZZARD",
			"BREEZE",
			"CLOUD",
			"CYCLONE",
			"DRIZZLE",
			"FOG",
			"FREEZE",
			"FROST",
			"HAIL",
			"HEATWAVE",
			"HUMID",
			"LIGHTNING",
			"RAIN",
			"RAINBOW",
			"SNOW",
			"STORM",
			"SUNSHINE",
			"THUNDER",
			"TORNADO",
			"WINDY",
		},
	},
	{
		id = "Music",
		title = "Music",
		subtitle = "Sounds, stages, and rhythm words.",
		gridSize = 8,
		words = {
			"ALBUM",
			"AMP",
			"BEAT",
			"CHORD",
			"CHORUS",
			"DRUM",
			"ENCORE",
			"FLUTE",
			"GUITAR",
			"HARMONY",
			"LYRIC",
			"MELODY",
			"MICROPHONE",
			"NOTE",
			"PIANO",
			"RHYTHM",
			"SONG",
			"STAGE",
			"TEMPO",
			"TRUMPET",
			"VINYL",
		},
	},
	{
		id = "Jobs",
		title = "Jobs",
		subtitle = "Workers, tools, and career words.",
		gridSize = 9,
		words = {
			"ARTIST",
			"BAKER",
			"BUILDER",
			"CHEF",
			"DENTIST",
			"DOCTOR",
			"ENGINEER",
			"FARMER",
			"FIREFIGHTER",
			"JUDGE",
			"LAWYER",
			"MECHANIC",
			"NURSE",
			"PILOT",
			"PLUMBER",
			"SCIENTIST",
			"SHERIFF",
			"TEACHER",
			"TRAINER",
			"VETERINARIAN",
			"WRITER",
		},
	},
	{
		id = "Fantasy",
		title = "Fantasy",
		subtitle = "Magic, myths, and adventure words.",
		gridSize = 9,
		words = {
			"CASTLE",
			"CROWN",
			"CRYSTAL",
			"DRAGON",
			"ELIXIR",
			"ENCHANT",
			"FAIRY",
			"GIANT",
			"GOBLIN",
			"GRIFFIN",
			"KNIGHT",
			"LEGEND",
			"MAGIC",
			"ORACLE",
			"PHOENIX",
			"QUEST",
			"RELIC",
			"SORCERER",
			"SPELL",
			"SWORD",
			"WIZARD",
		},
	},
	{
		id = "Dinosaurs",
		title = "Dinosaurs",
		subtitle = "Fossils, giants, and prehistoric finds.",
		gridSize = 10,
		words = {
			"ANKYLOSAURUS",
			"BRONTOSAURUS",
			"DINOSAUR",
			"EXTINCTION",
			"FOSSIL",
			"JURASSIC",
			"METEOR",
			"RAPTOR",
			"SAUROPOD",
			"SKELETON",
			"TRICERATOPS",
			"TYRANNOSAURUS",
			"VELOCIRAPTOR",
		},
	},
	{
		id = "Vehicles",
		title = "Vehicles",
		subtitle = "Road, rail, and sky transport words.",
		gridSize = 10,
		words = {
			"AIRPLANE",
			"AMBULANCE",
			"BICYCLE",
			"BOAT",
			"BULLDOZER",
			"HELICOPTER",
			"LOCOMOTIVE",
			"MOTORBIKE",
			"ROADSTER",
			"SCOOTER",
			"SKATEBOARD",
			"SUBMARINE",
			"TRACTOR",
			"TRAILER",
			"TRUCK",
		},
	},
	{
		id = "School",
		title = "School",
		subtitle = "Lessons, classrooms, and campus words.",
		gridSize = 10,
		words = {
			"BACKPACK",
			"BLACKBOARD",
			"CALCULATOR",
			"CLASSROOM",
			"HOMEWORK",
			"LOCKER",
			"NOTEBOOK",
			"PENCIL",
			"PLAYGROUND",
			"PRINCIPAL",
			"RECESS",
			"SCIENCE",
			"TEXTBOOK",
			"WHITEBOARD",
		},
	},
	{
		id = "ArtStudio",
		title = "Art Studio",
		subtitle = "Color, craft, and maker words.",
		gridSize = 9,
		words = {
			"BRUSH",
			"CANVAS",
			"CHARCOAL",
			"CLAY",
			"COLLAGE",
			"DRAWING",
			"EASEL",
			"GLITTER",
			"MARKER",
			"PALETTE",
			"PASTEL",
			"POTTERY",
			"SCULPTURE",
			"SKETCH",
			"WATERCOLOR",
		},
	},
	{
		id = "Garden",
		title = "Garden",
		subtitle = "Blooming plants and outdoor care words.",
		gridSize = 9,
		words = {
			"ARBOR",
			"BUTTERFLY",
			"COMPOST",
			"FLOWERPOT",
			"GARDENER",
			"GREENHOUSE",
			"HEDGE",
			"PETAL",
			"SEEDLING",
			"SHOVEL",
			"SOIL",
			"SPRINKLER",
			"SUNFLOWER",
			"TROWEL",
			"VIOLET",
		},
	},
	{
		id = "Movies",
		title = "Movies",
		subtitle = "Cinema, sets, and film-night words.",
		gridSize = 10,
		words = {
			"BLOCKBUSTER",
			"CAMERAMAN",
			"CINEMA",
			"CREDITS",
			"DIRECTOR",
			"FILMMAKER",
			"POPCORN",
			"PREMIERE",
			"PROJECTOR",
			"SCREENPLAY",
			"SOUNDTRACK",
			"STUDIO",
			"TICKET",
			"TRAILER",
		},
	},
	{
		id = "Technology",
		title = "Technology",
		subtitle = "Devices, systems, and digital words.",
		gridSize = 10,
		words = {
			"ALGORITHM",
			"BROWSER",
			"CHARGER",
			"DATABASE",
			"DOWNLOAD",
			"HARDWARE",
			"KEYBOARD",
			"LAPTOP",
			"PASSWORD",
			"SOFTWARE",
			"TABLET",
			"UPLOAD",
			"WEBSITE",
			"WIFI",
		},
	},
	{
		id = "House",
		title = "House",
		subtitle = "Rooms, furniture, and home words.",
		gridSize = 10,
		words = {
			"ATTIC",
			"BACKYARD",
			"BEDROOM",
			"BOOKSHELF",
			"DOORBELL",
			"FIREPLACE",
			"GARAGE",
			"KITCHEN",
			"LIVINGROOM",
			"PANTRY",
			"PILLOW",
			"SHOWER",
			"STAIRCASE",
			"WINDOW",
		},
	},
	{
		id = "Insects",
		title = "Insects",
		subtitle = "Tiny crawlers and flying bug words.",
		gridSize = 11,
		words = {
			"ANTENNA",
			"BEETLE",
			"BUTTERFLY",
			"CATERPILLAR",
			"CRICKET",
			"DRAGONFLY",
			"FIREFLY",
			"GRASSHOPPER",
			"HONEYBEE",
			"LADYBUG",
			"MANTIS",
			"MOSQUITO",
			"SCARAB",
		},
	},
	{
		id = "Pirates",
		title = "Pirates",
		subtitle = "Ships, treasure, and swashbuckling words.",
		gridSize = 9,
		words = {
			"ANCHOR",
			"BUCCANEER",
			"CAPTAIN",
			"COMPASS",
			"CUTLASS",
			"GALLEON",
			"HARBOR",
			"MAROONED",
			"NAVIGATOR",
			"PARROT",
			"PIRATE",
			"RIGGING",
			"TREASURE",
			"TRIDENT",
		},
	},
	{
		id = "Holidays",
		title = "Holidays",
		subtitle = "Seasonal celebrations and festive words.",
		gridSize = 10,
		words = {
			"CANDYCANE",
			"COSTUME",
			"FESTIVAL",
			"FIREWORKS",
			"GARLAND",
			"HALLOWEEN",
			"HOLIDAY",
			"LANTERN",
			"ORNAMENT",
			"PARADE",
			"PRESENT",
			"REINDEER",
			"SNOWGLOBE",
			"SPARKLER",
		},
	},
	{
		id = "Mountains",
		title = "Mountains",
		subtitle = "Peaks, cliffs, and climbing words.",
		gridSize = 10,
		words = {
			"ALPINE",
			"AVALANCHE",
			"BOULDER",
			"CANYON",
			"GLACIER",
			"HORIZON",
			"MOUNTAIN",
			"RIDGELINE",
			"SUMMIT",
			"TRAILHEAD",
			"VALLEY",
			"WATERFALL",
		},
	},
	{
		id = "Robots",
		title = "Robots",
		subtitle = "Mechanics, code, and machine words.",
		gridSize = 10,
		words = {
			"ANDROID",
			"AUTOMATON",
			"BATTERY",
			"CIRCUIT",
			"GEARBOX",
			"HARDWARE",
			"MECHANICAL",
			"PROCESSOR",
			"ROBOTICS",
			"SENSOR",
			"SERVO",
			"SWITCH",
			"UPGRADE",
		},
	},
	{
		id = "City",
		title = "City",
		subtitle = "Busy streets and downtown words.",
		gridSize = 12,
		words = {
			"APARTMENT",
			"BOULEVARD",
			"CROSSWALK",
			"DOWNTOWN",
			"ELEVATOR",
			"INTERSECTION",
			"SKYLINE",
			"SKYSCRAPER",
			"STREETCAR",
			"SUBWAY",
			"TRAFFIC",
			"TUNNEL",
		},
	},
	{
		id = "Mythology",
		title = "Mythology",
		subtitle = "Gods, monsters, and ancient legend words.",
		gridSize = 9,
		words = {
			"APOLLO",
			"ATHENA",
			"CERBERUS",
			"HERCULES",
			"HYDRA",
			"MINOTAUR",
			"ODYSSEY",
			"OLYMPUS",
			"PEGASUS",
			"POSEIDON",
			"TEMPLE",
			"TRIDENT",
			"ZEUS",
		},
	},
	{
		id = "Superheroes",
		title = "Superheroes",
		subtitle = "Masks, rescues, and comic-book words.",
		gridSize = 9,
		words = {
			"CAPE",
			"CITIZEN",
			"EMBLEM",
			"GADGET",
			"HERO",
			"HIDEOUT",
			"JUSTICE",
			"MASKED",
			"POWERS",
			"RESCUE",
			"ROOFTOP",
			"SIDEKICK",
			"VILLAIN",
		},
	},
}

local function getLongestWordLength(words)
	local longestLength = 0

	for _, word in ipairs(words or {}) do
		local wordLength = string.len(tostring(word or ""))
		if wordLength > longestLength then
			longestLength = wordLength
		end
	end

	return longestLength
end

local themesById = {}
local themeIds = {}

for _, theme in ipairs(themes) do
	theme.gridSize = math.max(
		6,
		math.floor(tonumber(theme.gridSize) or 0),
		getLongestWordLength(theme.words)
	)
	themesById[theme.id] = theme
	table.insert(themeIds, theme.id)
end

ThemedModeLibrary.Themes = themes
ThemedModeLibrary.ById = themesById
ThemedModeLibrary.ThemeIds = themeIds

function ThemedModeLibrary.GetTheme(themeId)
	return themesById[tostring(themeId or "")]
end

function ThemedModeLibrary.GetThemes()
	return themes
end



-- Generated 150-board Classic catalog.
local function cloneArray(values)
	local result = {}

	for index, value in ipairs(values) do
		result[index] = value
	end

	return result
end

local function appendUnique(target, seen, word)
	if not seen[word] then
		seen[word] = true
		table.insert(target, word)
	end
end

local function buildPool(sources, minLength, maxLength)
	local pool = {}
	local seen = {}

	for _, source in ipairs(sources) do
		for _, word in ipairs(source) do
			if #word >= minLength and #word <= maxLength then
				appendUnique(pool, seen, word)
			end
		end
	end

	return pool
end

local function interpolateInt(minValue, maxValue, offset, total)
	if minValue == maxValue or total <= 1 then
		return minValue
	end

	local alpha = (offset - 1) / (total - 1)
	return math.floor(minValue + (maxValue - minValue) * alpha + 0.5)
end

local function shuffle(values, randomObject)
	local result = cloneArray(values)

	for index = #result, 2, -1 do
		local swapIndex = randomObject:NextInteger(1, index)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end

	return result
end

local function wordsOverlap(candidate, chosenWords)
	for _, existing in ipairs(chosenWords) do
		if existing == candidate then
			return true
		end

		if string.find(existing, candidate, 1, true) or string.find(candidate, existing, 1, true) then
			return true
		end
	end

	return false
end

local function chooseWords(pool, wordCount, seed)
	local randomObject = RandomClass.new(seed)
	local orderedPool = shuffle(pool, randomObject)
	local chosenWords = {}

	for _, candidate in ipairs(orderedPool) do
		if not wordsOverlap(candidate, chosenWords) then
			table.insert(chosenWords, candidate)
		end

		if #chosenWords >= wordCount then
			return chosenWords
		end
	end

	for _, candidate in ipairs(orderedPool) do
		if not table.find(chosenWords, candidate) then
			table.insert(chosenWords, candidate)
		end

		if #chosenWords >= wordCount then
			return chosenWords
		end
	end

	error(string.format("Unable to choose %d unique words from a pool of %d.", wordCount, #pool))
end

local LEVEL_TIERS = {
	{
		name = "Very Easy",
		packName = "VeryEasy",
		stages = {
			{
				count = 2,
				subtitle = "Starter lanes",
				gridMin = 5,
				gridMax = 5,
				wordMin = 2,
				wordMax = 2,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 1,
				subtitle = "Tiny stretch",
				gridMin = 5,
				gridMax = 5,
				wordMin = 3,
				wordMax = 3,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 2,
				subtitle = "Wide open",
				gridMin = 5,
				gridMax = 6,
				wordMin = 2,
				wordMax = 3,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 1,
				subtitle = "Longer look",
				gridMin = 6,
				gridMax = 6,
				wordMin = 3,
				wordMax = 3,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Steady search",
				gridMin = 6,
				gridMax = 6,
				wordMin = 3,
				wordMax = 4,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 1,
				subtitle = "Crowded lane",
				gridMin = 6,
				gridMax = 6,
				wordMin = 4,
				wordMax = 4,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Bigger board",
				gridMin = 6,
				gridMax = 7,
				wordMin = 4,
				wordMax = 4,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 1,
				subtitle = "First diagonals",
				gridMin = 7,
				gridMax = 7,
				wordMin = 4,
				wordMax = 4,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S", "SE" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Diagonal warmup",
				gridMin = 7,
				gridMax = 7,
				wordMin = 4,
				wordMax = 5,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S", "SE" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 1,
				subtitle = "Cross search",
				gridMin = 7,
				gridMax = 7,
				wordMin = 5,
				wordMax = 5,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Open corners",
				gridMin = 7,
				gridMax = 8,
				wordMin = 5,
				wordMax = 5,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 1,
				subtitle = "Denser sweep",
				gridMin = 8,
				gridMax = 8,
				wordMin = 6,
				wordMax = 6,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Warmup finish",
				gridMin = 8,
				gridMax = 8,
				wordMin = 6,
				wordMax = 6,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Packed finish",
				gridMin = 8,
				gridMax = 8,
				wordMin = 6,
				wordMax = 7,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 3,
				subtitle = "Ready for Easy",
				gridMin = 8,
				gridMax = 9,
				wordMin = 6,
				wordMax = 7,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
		},
	},
	{
		name = "Easy",
		packName = "Easy",
		stages = {
			{
				count = 5,
				subtitle = "Diagonal warmup",
				gridMin = 7,
				gridMax = 8,
				wordMin = 5,
				wordMax = 5,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 5,
				subtitle = "Open corners",
				gridMin = 8,
				gridMax = 8,
				wordMin = 5,
				wordMax = 6,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 5,
				subtitle = "Search sweep",
				gridMin = 8,
				gridMax = 9,
				wordMin = 6,
				wordMax = 6,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 5,
				subtitle = "Denser lanes",
				gridMin = 9,
				gridMax = 9,
				wordMin = 6,
				wordMax = 7,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
			{
				count = 5,
				subtitle = "Packed corners",
				gridMin = 9,
				gridMax = 10,
				wordMin = 7,
				wordMax = 8,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
		},
	},
	{
		name = "Hard",
		packName = "Hard",
		stages = {
			{
				count = 5,
				subtitle = "Climb begins",
				gridMin = 10,
				gridMax = 10,
				wordMin = 8,
				wordMax = 8,
				minLength = 5,
				maxLength = 6,
				directions = { "E", "S", "SE" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
			{
				count = 5,
				subtitle = "Dense lanes",
				gridMin = 10,
				gridMax = 11,
				wordMin = 8,
				wordMax = 9,
				minLength = 5,
				maxLength = 7,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
			{
				count = 5,
				subtitle = "Crowded middle",
				gridMin = 11,
				gridMax = 11,
				wordMin = 9,
				wordMax = 9,
				minLength = 5,
				maxLength = 7,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Longer clues",
				gridMin = 11,
				gridMax = 12,
				wordMin = 9,
				wordMax = 10,
				minLength = 5,
				maxLength = 8,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Sharp search",
				gridMin = 12,
				gridMax = 12,
				wordMin = 10,
				wordMax = 10,
				minLength = 6,
				maxLength = 8,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
		},
	},
	{
		name = "Very Hard",
		packName = "VeryHard",
		stages = {
			{
				count = 5,
				subtitle = "Heavy boards",
				gridMin = 12,
				gridMax = 13,
				wordMin = 10,
				wordMax = 11,
				minLength = 6,
				maxLength = 8,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Big sweeps",
				gridMin = 13,
				gridMax = 13,
				wordMin = 11,
				wordMax = 11,
				minLength = 6,
				maxLength = 9,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Dense giants",
				gridMin = 13,
				gridMax = 14,
				wordMin = 11,
				wordMax = 12,
				minLength = 6,
				maxLength = 9,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Final climb",
				gridMin = 14,
				gridMax = 14,
				wordMin = 12,
				wordMax = 12,
				minLength = 6,
				maxLength = 9,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Master boards",
				gridMin = 14,
				gridMax = 15,
				wordMin = 12,
				wordMax = 13,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
		},
	},
	{
		name = "Expert",
		packName = "Expert",
		stages = {
			{
				count = 5,
				subtitle = "Endgame opens",
				gridMin = 15,
				gridMax = 15,
				wordMin = 13,
				wordMax = 13,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Longer sweeps",
				gridMin = 15,
				gridMax = 16,
				wordMin = 13,
				wordMax = 14,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Tight spacing",
				gridMin = 16,
				gridMax = 16,
				wordMin = 14,
				wordMax = 14,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Heavy search",
				gridMin = 16,
				gridMax = 17,
				wordMin = 14,
				wordMax = 15,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Brutal finish",
				gridMin = 17,
				gridMax = 17,
				wordMin = 15,
				wordMax = 15,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
		},
	},
	{
		name = "Master",
		packName = "Master",
		stages = {
			{
				count = 5,
				subtitle = "Master rise",
				gridMin = 17,
				gridMax = 18,
				wordMin = 15,
				wordMax = 16,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Packed giant boards",
				gridMin = 18,
				gridMax = 18,
				wordMin = 16,
				wordMax = 16,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Needle hunt",
				gridMin = 18,
				gridMax = 19,
				wordMin = 16,
				wordMax = 17,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Massive density",
				gridMin = 19,
				gridMax = 19,
				wordMin = 17,
				wordMax = 17,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Final gauntlet",
				gridMin = 19,
				gridMax = 20,
				wordMin = 17,
				wordMax = 18,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
		},
	},
}

local Levels = {}

for _, tier in ipairs(LEVEL_TIERS) do
	local tierStartLevel = #Levels + 1

	for stageIndex, stage in ipairs(tier.stages) do
		local pool = buildPool(stage.sources, stage.minLength, stage.maxLength)
		assert(#pool >= stage.wordMax, string.format("Word pool too small for %s stage %d.", tier.name, stageIndex))

		for offset = 1, stage.count do
			local levelNumber = #Levels + 1
			local tierLevelNumber = levelNumber - tierStartLevel + 1
			local wordCount = interpolateInt(stage.wordMin, stage.wordMax, offset, stage.count)
			local gridSize = math.max(
				interpolateInt(stage.gridMin, stage.gridMax, offset, stage.count),
				stage.maxLength + 1
			)
			local seed = 4100 + levelNumber * 977 + stageIndex * 131
			local words = chooseWords(pool, wordCount, seed)
			local directions = cloneArray(stage.directions)
			local subtitle = string.format("%s - %s", tier.name, stage.subtitle)

			-- Board 1 is a deliberate onboarding board: two familiar words,
			-- a smaller grid, and left-to-right placement only.
			if levelNumber == 1 then
				gridSize = 4
				words = { "CAT", "DOG" }
				directions = { "E" }
				subtitle = "Very Easy - First steps"
			end

			table.insert(Levels, {
				level = levelNumber,
				title = string.format("Level %d", levelNumber),
				subtitle = subtitle,
				tier = tier.name,
				pack = tier.packName or tier.name,
				tierLevel = tierLevelNumber,
				packLevel = tierLevelNumber,
				gridSize = gridSize,
				words = words,
				directions = directions,
				seed = seed,
			})
		end
	end
end

Levels.ModeLibraries = PuzzleLibrary
Levels.Themes = ThemedModeLibrary

return Levels
