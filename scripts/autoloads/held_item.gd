extends Node
## Autoload holding the shared item-type constants that used to live in
## Player.gd as an enum. Using an autoload avoids forcing every interactable
## to import the entire Player script just to check what kind of object a
## player is holding.

const NONE := 0
const CUP_EMPTY := 1
const CUP_FILLED := 2
const SUPPLY_BOX := 3
const CONTAINER := 4
const TRASH := 5

const CONTAINER_NAMES := {
	"fruit_bin": "Crate",
	"sugar_bin": "Bowl",
	"ice_bin": "Bucket",
	"workstation": "Table",
}


func container_name(container_type: String) -> String:
	return CONTAINER_NAMES.get(container_type, container_type.capitalize().replace("_", " "))
