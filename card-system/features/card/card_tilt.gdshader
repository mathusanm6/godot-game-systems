shader_type canvas_item;

uniform float tilt_deg : hint_range(-70.0, 70.0) = 0.0;
uniform float cam_dist : hint_range(0.5, 5.0) = 1.4;
uniform float margin : hint_range(0.0, 1.0) = 0.3;

varying vec4 v_color;

void vertex() {
	v_color = COLOR;  // modulate / vertex color, independent of the texture
	VERTEX *= 1.0 + margin;
	UV = (UV - 0.5) * (1.0 + margin) + 0.5;
}

void fragment() {
	float a = radians(tilt_deg);
	float s = sin(a);
	float c = cos(a);

	vec2 p = UV - 0.5;
	float denom = c * cam_dist + p.y * s;
	float y = p.y * cam_dist / denom;
	float x = p.x * (cam_dist - y * s) / cam_dist;
	vec2 uv = vec2(x, y) + 0.5;

	if (denom <= 0.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(TEXTURE, uv) * v_color;
	}
}