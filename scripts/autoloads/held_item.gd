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
