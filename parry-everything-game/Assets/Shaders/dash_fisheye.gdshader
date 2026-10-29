shader_type canvas_item;
// Full-screen dash effect: fisheye bulge, radial streaks, colour split and a blue tint.
// Put it on a full-screen ColorRect in a CanvasLayer that sits below the HUD,
// so the crosshair and bars aren't distorted. Driven by dash_effect.gd.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

uniform float bulge = 0.35;        // fisheye strength at full intensity
uniform float zoom = 0.05;         // slight zoom in at full intensity
uniform float streak = 0.05;       // length of the radial blur
uniform float aberration = 0.015;  // colour split at the edges
uniform vec4 tint : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform float tint_center = 0.15;  // tint in the middle of the screen
uniform float tint_edge = 0.75;    // tint at the edges
uniform float vignette = 0.35;     // edge darkening

const int SAMPLES = 6;

// Samples the screen at a point given in aspect-corrected, centred coordinates.
vec4 screen_at(vec2 q, float aspect) {
	return texture(screen_texture, vec2(q.x / aspect, q.y) + 0.5);
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // width / height
	vec2 p = SCREEN_UV - 0.5;
	p.x *= aspect;

	// Fisheye: the further from the centre, the closer to the centre we sample,
	// so the middle of the view bulges outward.
	float r2 = dot(p, p);
	vec2 warped = p * (1.0 - bulge * intensity * r2) * (1.0 - zoom * intensity);

	// Radial streaks (several samples toward the centre) with red and blue pulled apart.
	vec3 col = vec3(0.0);
	float ca = aberration * intensity;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		vec2 q = warped * (1.0 - streak * intensity * t);
		col.r += screen_at(q * (1.0 + ca), aspect).r;
		col.g += screen_at(q, aspect).g;
		col.b += screen_at(q * (1.0 - ca), aspect).b;
	}
	col /= float(SAMPLES);

	// 0 at the centre, 1 in the corners.
	float edge = smoothstep(0.3, 1.0, length(p) / (0.5 * sqrt(aspect * aspect + 1.0)));

	// Blue grade, stronger toward the edges, then darken the rim and add a faint blue glow.
	float amount = mix(tint_center, tint_edge, edge) * intensity;
	col = mix(col, col * tint.rgb + tint.rgb * 0.06, amount);
	col *= 1.0 - vignette * edge * intensity;
	col += tint.rgb * edge * edge * 0.12 * intensity;

	COLOR = vec4(col, 1.0);
}
