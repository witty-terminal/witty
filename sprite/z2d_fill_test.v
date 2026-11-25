module sprite

// These are direct translations of focused tests alongside z2d v0.10.0's
// Polygon, sparse coverage buffer, and multisample rasterizer.

fn test_z2d_polygon_add_edge() {
	mut polygon := Z2dPolygon{}
	polygon.add_edge(Point{ x: 5, y: 0 }, Point{ x: 10, y: 10 })
	polygon.add_edge(Point{ x: 10, y: 10 }, Point{ x: 0, y: 10 })
	polygon.add_edge(Point{ x: 0, y: 10 }, Point{ x: 5, y: 0 })
	assert polygon.edges == [
		Z2dEdge{
			y0: 0
			y1: 10
			x_start: 5
			x_inc: 0.5
		},
		Z2dEdge{
			y0: 10
			y1: 0
			x_start: 5
			x_inc: -0.5
		},
	]
}

fn test_z2d_polygon_in_box() {
	inside := Z2dPolygon{
		edges: [Z2dEdge{ y0: 10, y1: 20 }]
		extent_left: 10
		extent_top: 10
		extent_right: 20
		extent_bottom: 20
	}
	assert inside.in_box(1, 30, 30)
	assert !inside.in_box(1, 5, 5)

	scaled := Z2dPolygon{
		edges: [Z2dEdge{ y0: 20, y1: 60 }]
		extent_left: 20
		extent_top: 20
		extent_right: 60
		extent_bottom: 60
	}
	assert scaled.in_box(4, 10, 10)
}

fn test_z2d_sparse_coverage_extend() {
	mut coverage := Z2dSparseCoverageBuffer.init(10)
	coverage.put(0, 0, 4)
	coverage.put(4, 0, 4)
	coverage.len = 8
	coverage.extend(2, 5)
	assert coverage.len == 8
	mut got_value, mut got_len := coverage.get(0)
	assert got_value == 0 && got_len == 2
	got_value, got_len = coverage.get(2)
	assert got_value == 0 && got_len == 2
	got_value, got_len = coverage.get(4)
	assert got_value == 0 && got_len == 3
	got_value, got_len = coverage.get(7)
	assert got_value == 0 && got_len == 1
}

fn test_z2d_multisample_add_span() {
	mut coverage := Z2dSparseCoverageBuffer.init(1024)
	z2d_add_multisample_span(mut coverage, 200, 400)
	mut got_value, mut got_len := coverage.get(50)
	assert got_value == 4 && got_len == 100

	z2d_add_multisample_span(mut coverage, 201, 398)
	got_value, got_len = coverage.get(50)
	assert got_value == 7 && got_len == 1
	got_value, got_len = coverage.get(51)
	assert got_value == 8 && got_len == 98
	got_value, got_len = coverage.get(149)
	assert got_value == 7 && got_len == 1

	z2d_add_multisample_span(mut coverage, 202, 396)
	got_value, got_len = coverage.get(50)
	assert got_value == 9 && got_len == 1
	got_value, got_len = coverage.get(51)
	assert got_value == 12 && got_len == 98
	got_value, got_len = coverage.get(149)
	assert got_value == 9 && got_len == 1

	z2d_add_multisample_span(mut coverage, 203, 394)
	got_value, got_len = coverage.get(50)
	assert got_value == 10 && got_len == 1
	got_value, got_len = coverage.get(51)
	assert got_value == 16 && got_len == 98
	got_value, got_len = coverage.get(149)
	assert got_value == 10 && got_len == 1

	mut x := u32(0)
	mut tracked_span_len := 0
	for x < coverage.len {
		_, x_inc := coverage.get(x)
		x += x_inc
		tracked_span_len += 1
	}
	assert tracked_span_len == 4
}

fn test_z2d_fill_plot_degenerate_line() {
	path := Path{
		nodes: [
			PathNode(PathMoveTo{ point: Point{ x: 5, y: 0 } }),
			PathNode(PathLineTo{ point: Point{ x: 10, y: 10 } }),
			PathNode(PathLineTo{ point: Point{ x: 10, y: 10 } }),
			PathNode(PathLineTo{ point: Point{ x: 0, y: 10 } }),
			PathNode(PathClose{}),
			PathNode(PathMoveTo{ point: Point{ x: 5, y: 0 } }),
		]
	}
	polygon := z2d_fill_plot(path, 1, 1)!
	assert polygon.edges == [
		Z2dEdge{
			y0: 0
			y1: 10
			x_start: 5
			x_inc: 0.5
		},
		Z2dEdge{
			y0: 10
			y1: 0
			x_start: 5
			x_inc: -0.5
		},
	]
}

fn test_z2d_src_over_alpha_composition() {
	mut canvas := Canvas.init(1, 1, 0, 0)
	canvas.surface.pixels[0] = u32(221) << 24
	z2d_composite_span(mut canvas, 0, 0, 1, .medium, 255)
	assert canvas.surface.pixels[0] == u32(239) << 24
}
