extends "res://features/technology_tree_preview/technology_tree_preview.gd"

const GithubPageScript = preload(
	"res://features/github_tech_tree_preview/github_technology_page.gd"
)

@onready var _github_page: GithubPageScript = $TechnologyPage


func _layout() -> void:
	var factor: float = minf(size.x / 1280.0, size.y / 800.0)
	page.scale = Vector2.ONE * factor
	page.size = size / factor - Vector2(0.0, 64.0)
	$PreviewControls.scale = Vector2.ONE * factor
	$PreviewControls.position = Vector2(24.0 * factor, size.y - 54.0 * factor)
