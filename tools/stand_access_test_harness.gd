extends "res://scripts/stand/stand_unit.gd"


func _init() -> void:
	for node_name in ["DeliveryMarker", "QueueMarkerActive", "QueueMarker1", "QueueMarker2"]:
		var marker := Marker3D.new()
		marker.name = node_name
		add_child(marker)
	for node_name in ["DeliveryGrid", "PriceBoard", "Thermometer", "WaterDispenser", "Stand"]:
		var node := Node3D.new()
		node.name = node_name
		add_child(node)


func _ready() -> void:
	pass
