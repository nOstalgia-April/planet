// Adapted from Paper Shaders' Metaballs by Lost Coast Labs, Inc. (Apache-2.0).
// Source revision: 43cd68db79fa0b1759f72ffc941b3238e2a3954c.
// Changes: Godot CanvasItem coordinates/uniforms, up to three editable colors,
// baked samples of the original noise PNG, and deterministic preview time.
// See THIRD_PARTY_NOTICES.txt for the original notice and license.
shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform vec4 background_color : source_color = vec4(0.055, 0.012, 0.024, 1.0);
uniform vec4 color_a : source_color = vec4(0.33, 0.055, 0.11, 1.0);
uniform vec4 color_b : source_color = vec4(0.45, 0.10, 0.17, 1.0);
uniform vec4 color_c : source_color = vec4(0.20, 0.025, 0.065, 1.0);
uniform int color_count : hint_range(1, 3, 1) = 1;
uniform float ball_count : hint_range(1.0, 20.0, 0.1) = 13.0;
uniform float ball_size : hint_range(0.0, 1.0) = 0.81;
uniform float speed : hint_range(-3.0, 3.0) = 0.5;
uniform float pattern_scale : hint_range(0.01, 4.0) = 4.0;
uniform float rotation_degrees : hint_range(0.0, 360.0) = 0.0;
uniform vec2 offset = vec2(-0.3, 0.0);
// Ordinary elapsed seconds before speed. Negative selects Godot TIME.
uniform float effect_time = -1.0;

// Metaballs only samples randomR(vec2(integer, 0)). These are the exact
// bilinear red-channel samples of Paper's 128x128 PNG at
// (fract(integer / 100 + 0.5), 0.5), with CLAMP_TO_EDGE and LINEAR filtering.
const float NOISE_SAMPLES[100] = {
	0.6058823529, 0.6507450980, 0.5030196078, 0.0941568627, 0.3195686275,
	0.1403921569, 0.4563137255, 0.3108627451, 0.1545098039, 0.6772549020,
	0.2307843137, 0.4946274510, 0.0752156863, 0.5049803922, 0.5564705882,
	0.6760784314, 0.3254509804, 0.5121176471, 0.4161960784, 0.3093725490,
	0.5911764706, 0.2869019608, 0.4356862745, 0.8907450980, 0.1220392157,
	0.1107843137, 0.4252941176, 0.2190980392, 0.3648627451, 0.1741176471,
	0.4684313725, 0.4773725490, 0.3117647059, 0.8094509804, 0.3610980392,
	0.4249019608, 0.5461568627, 0.2594901961, 0.4143921569, 0.6940784314,
	0.2429411765, 0.9140392157, 0.3619607843, 0.2563137255, 0.3301176471,
	0.4864705882, 0.3378431373, 0.7763921569, 0.5325098039, 0.6187450980,
	0.7117647059, 0.5924705882, 0.2344705882, 0.0372549020, 0.1746274510,
	0.4882352941, 0.4865882353, 0.3542352941, 0.3518431373, 0.4907058824,
	0.2388235294, 0.7296470588, 0.4241568627, 0.6000000000, 0.5571764706,
	0.2852941176, 0.9781176471, 0.0422745098, 0.3633333333, 0.5216862745,
	0.7064705882, 0.4858431373, 0.7163921569, 0.7936078431, 0.4525490196,
	0.2343137255, 0.6813725490, 0.5002352941, 0.4352549020, 0.7298823529,
	0.6462745098, 0.8784705882, 0.5480000000, 0.8413725490, 0.4288235294,
	0.5125490196, 0.6249019608, 0.8858431373, 0.2629803922, 0.8897254902,
	0.4905882353, 0.8420000000, 0.4578823529, 0.2045098039, 0.3976078431,
	0.4227450980, 0.8645098039, 0.7786274510, 0.1599215686, 0.6741960784
};

float original_random(float index) {
	return NOISE_SAMPLES[int(mod(index, 100.0))];
}

float motion_noise(float x) {
	float index = floor(x);
	float fraction = fract(x);
	float blend = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(original_random(index), original_random(index + 1.0), blend);
}

float ball_shape(vec2 point, vec2 position, float power) {
	float shape = 0.5 * length(point - position);
	shape = 1.0 - clamp(shape, 0.0, 1.0);
	return pow(shape, power);
}

void fragment() {
	// Match Paper's centered, contain-fit square and upward-positive object UV.
	vec2 rectangle_size = 1.0 / fwidth(UV);
	vec2 shape_uv = (UV - vec2(0.5)) * vec2(1.0, -1.0);
	shape_uv *= rectangle_size / min(rectangle_size.x, rectangle_size.y);
	shape_uv += vec2(-offset.x, offset.y);
	shape_uv /= pattern_scale;
	float rotation = radians(rotation_degrees);
	shape_uv = mat2(
		vec2(cos(rotation), sin(rotation)),
		vec2(-sin(rotation), cos(rotation))
	) * shape_uv;
	shape_uv += vec2(0.5);

	float elapsed_seconds = effect_time >= 0.0 ? effect_time : TIME;
	float time = 0.2 * (elapsed_seconds * speed + 2503.4);
	vec3 total_color = vec3(0.0);
	float total_shape = 0.0;
	float total_opacity = 0.0;
	int active_colors = clamp(color_count, 1, 3);

	for (int i = 0; i < 20; i++) {
		if (i >= int(ceil(ball_count))) {
			break;
		}
		float index_fraction = float(i) / 20.0;
		float angle = TAU * index_fraction;
		float ball_speed = 1.0 - 0.2 * index_fraction;
		float noise_x = motion_noise(angle * 10.0 + float(i) + time * ball_speed);
		float noise_y = motion_noise(angle * 20.0 + float(i) - time * ball_speed);
		vec2 position = vec2(0.5) + vec2(0.0001) + 0.9 * (vec2(noise_x, noise_y) - vec2(0.5));

		int color_index = i % active_colors;
		vec4 ball_color = color_a;
		if (color_index == 1) {
			ball_color = color_b;
		} else if (color_index == 2) {
			ball_color = color_c;
		}
		ball_color.rgb *= ball_color.a;

		float size_fraction = 1.0;
		if (float(i) > floor(ball_count - 1.0)) {
			size_fraction *= fract(ball_count);
		}
		float shape = ball_shape(shape_uv, position, 45.0 - 30.0 * ball_size * size_fraction);
		shape *= pow(ball_size, 0.2);
		shape = smoothstep(0.0, 1.0, shape);
		total_color += ball_color.rgb * shape;
		total_shape += shape;
		total_opacity += ball_color.a * shape;
	}

	total_color /= max(total_shape, 0.0001);
	total_opacity /= max(total_shape, 0.0001);
	float edge_width = fwidth(total_shape);
	float final_shape = smoothstep(0.4, 0.4 + edge_width, total_shape);
	vec3 color = total_color * final_shape;
	float opacity = total_opacity * final_shape;
	vec3 background = background_color.rgb * background_color.a;
	color += background * (1.0 - opacity);
	opacity += background_color.a * (1.0 - opacity);
	// Preserve the original sub-8-bit dithering for gradient color transitions.
	color += (1.0 / 256.0) * (
		fract(sin(dot(0.014 * FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453123) - 0.5
	);
	COLOR = vec4(color, opacity);
}
