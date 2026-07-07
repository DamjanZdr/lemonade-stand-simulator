class_name ItemGrid
extends Node3D

## Per-grid settings for a FruitBin fruit type.
## Attach this script to each ItemGrid_* child of a FruitBin.

## Max items this grid can hold. Leave at -1 to auto-detect from child count.
@export var capacity: int = -1

## Starting amount for this fruit type. If -1, falls back to parent FruitBin.starting_amount.
@export var starting_amount: float = -1.0

## Drop height for the visual "fall in" animation. If -1, falls back to parent FruitBin.drop_height.
@export var drop_height: float = -1.0
