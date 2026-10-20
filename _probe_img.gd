extends SceneTree
func _init():
	var img := Image.load_from_file("res://assets/textures/ui/shadowaa.png")
	var w := img.get_width()
	var h := img.get_height()
	for thr in [0.3, 0.6, 0.9]:
		var minx := w; var miny := h; var maxx := -1; var maxy := -1
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > thr:
					if x < minx: minx = x
					if x > maxx: maxx = x
					if y < miny: miny = y
					if y > maxy: maxy = y
		print("thr %.1f -> used [%d,%d to %d,%d]" % [thr, minx, miny, maxx, maxy])
	quit()
