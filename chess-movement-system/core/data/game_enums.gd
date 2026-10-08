class_name GameEnums
extends RefCounted

## Game Enums for Chess Movement System
## Clean typed enumerations for movement, audio triggers, and board behavior.

enum HopSoundTrigger {
	ON_HOP_START,
	ON_LANDING,
	ON_BOTH,
}

enum BoardMode {
	FIXED,
	DYNAMIC_EXPAND,
}
