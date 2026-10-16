shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 light_color : source_color = vec4(1.0, 0.67, 0.83, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float ring_radius : hint_range(0.2, 0.7) = 0.5;
uniform float strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float radius = length((UV - vec2(0.5)) * 2.0);
	float flash = exp(-pow((progress - 0.16) / 0.085, 2.0))
		+ 0.65 * exp(-pow((progress - 0.43) / 0.09, 2.0));
	float rim = exp(-pow((radius - ring_radius) / 0.018, 2.0));
	float bloom = exp(-pow((radius - ring_radius) / 0.09, 2.0));
	float wave_radius = ring_radius + 0.34 * (1.0 - pow(1.0 - progress, 2.0));
	float wave = exp(-pow((radius - wave_radius) / 0.022, 2.0));
	float wave_fade = smoothstep(0.04, 0.14, progress) * pow(1.0 - progress, 1.5);
	float alpha = (flash * (rim * 0.85 + bloom * 0.32) + wave * wave_fade * 0.8);
	vec3 light = mix(light_color.rgb, vec3(1.0), rim * 0.75);
	COLOR = vec4(light, alpha * strength * light_color.a);
}
