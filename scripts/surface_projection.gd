extends RefCounted


static func get_visual_compensation(node: Node2D) -> Transform2D:
	var linear: Transform2D = node.get_global_transform_with_canvas()
	linear.origin = Vector2.ZERO
	var horizontal_squared: float = linear.x.length_squared()
	var vertical_squared: float = linear.y.length_squared()
	var cross_term: float = linear.x.dot(linear.y)
	var discriminant: float = (
		(horizontal_squared - vertical_squared) * (horizontal_squared - vertical_squared)
		+ 4.0 * cross_term * cross_term
	)
	var nominal_scale: float = sqrt(
		maxf((horizontal_squared + vertical_squared - sqrt(discriminant)) * 0.5, 0.0)
	)
	var tangent: Vector2 = linear.x.normalized()
	var desired: Transform2D = Transform2D(
		tangent * nominal_scale, Vector2(-tangent.y, tangent.x) * nominal_scale, Vector2.ZERO
	)
	return linear.affine_inverse() * desired
