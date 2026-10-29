shader_type canvas_item;
// Dash bar: a pill that fills from the centre outward. Driven by dash_bar.gd.

uniform vec2 rect_size = vec2(120.0, 16.0);         // set by the script
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float usable : hint_range(0.0, 1.0) = 1.0;  // 0 = charging look, 1 = ready look
uniform float pop : hint_range(0.0, 1.0) = 0.0;     // flash and swell when it becomes usable
uniform float hold : hint_range(0.0, 1.0) = 0.0;    // 1 while aiming a hold dash
uniform float pulse : hint_range(0.0, 1.0) = 0.0;   // warning flash near the end of a hold

uniform vec4 track_color : source_color = vec4(1.0, 1.0, 1.0, 0.12);
uniform vec4 charge_color : source_color = vec4(0.55, 0.62, 0.75, 0.55);
uniform vec4 ready_color : source_color = vec4(0.4, 0.8, 1.0, 0.95);
uniform vec4 hold_color : source_color = vec4(1.0, 0.82, 0.4, 1.0);
uniform float bar_width : hint_range(0.1, 1.0) = 0.8;   // share of the rect; the rest is room for the pop
uniform float bar_height : hint_range(0.1, 1.0) = 0.35;
uniform float pop_swell = 0.15;      // how much bigger the bar gets at the peak of a pop
uniform float glow_strength = 0.5;

// Signed distance to a pill (rounded box with fully round ends). Negative inside.
float sd_pill(vec2 p, vec2 half_size) {
	float r = half_size.y;
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = (UV - 0.5) * rect_size;
	vec2 half_size = rect_size * vec2(bar_width, bar_height) * 0.5 * (1.0 + pop * pop_swell);
	float d = sd_pill(px, half_size);
	float inside = clamp(0.5 - d, 0.0, 1.0);

	// Fill grows from the centre out to both ends.
	float filled = clamp(half_size.x * fill - abs(px.x) + 0.5, 0.0, 1.0) * step(0.001, fill);

	vec4 fill_col = mix(charge_color, ready_color, usable);
	fill_col = mix(fill_col, hold_color, hold);
	fill_col.rgb = mix(fill_col.rgb, vec3(1.0), max(pop * 0.85, pulse * 0.6));

	vec4 bar = mix(track_color, fill_col, filled);
	bar.a *= inside;

	// Soft glow around the bar when it's ready, popping or held.
	float glow = exp(-max(d, 0.0) / max(half_size.y * 1.2, 0.001));
	float glow_amt = glow_strength * glow * max(max(usable * 0.4, pop), hold * 0.6) * fill;

	// Bar drawn over its glow.
	float a = bar.a + glow_amt * (1.0 - bar.a);
	vec3 rgb = (bar.rgb * bar.a + fill_col.rgb * glow_amt * (1.0 - bar.a)) / max(a, 0.0001);
	COLOR = vec4(rgb, a);
}
