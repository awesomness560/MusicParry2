// Crosshair / receptor: a ring, a centre dot and four short ticks.
// Pulses to the beat and flashes with an outward shockwave when an attack arrives.
// Put on a square ColorRect (colour white). AttackNotes drives `pulse` and `flash`.

shader_type canvas_item;
render_mode unshaded;

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

group_uniforms colors;
uniform vec4 color         : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform vec4 flash_color   : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);

group_uniforms shape;           // all sizes are fractions of the half-size (1 = edge of the rect)
uniform float ring_radius   = 0.4;
uniform float ring_width    = 0.06;
uniform float dot_radius    = 0.06;
uniform float tick_length   = 0.14;
uniform float tick_width    = 0.05;
uniform float tick_gap      = 0.05;
uniform float outline_width = 0.035;
uniform float pulse_amount  = 0.08;
uniform float wave_reach    = 0.45;   // how far the arrival shockwave travels
group_uniforms;

vec4 over(vec4 top, vec4 bottom) {   // premultiplied
	return top + bottom * (1.0 - top.a);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float px = length(fwidth(p));
	float r = length(p);

	float rr = ring_radius * (1.0 + pulse_amount * pulse + 0.15 * flash);
	float d_ring = abs(r - rr) - ring_width * 0.5 * (1.0 + flash);
	float d_dot = r - dot_radius * (1.0 + 0.5 * flash);

	// four ticks just outside the ring: fold every quadrant onto the +x axis
	vec2 a = abs(p);
	vec2 q = a.x > a.y ? a : a.yx;
	float t0 = rr + ring_width * 0.5 + tick_gap;
	float d_tick = max(abs(q.y) - tick_width * 0.5, abs(q.x - (t0 + tick_length * 0.5)) - tick_length * 0.5);

	float d = min(min(d_ring, d_dot), d_tick);
	float fill = 1.0 - smoothstep(-px, px, d);
	float ol = (1.0 - smoothstep(outline_width, outline_width + px, d)) * (1.0 - fill);

	vec3 rgb = mix(color.rgb, flash_color.rgb, flash);
	float fa = mix(color.a, flash_color.a, flash) * fill;

	vec4 col = vec4(outline_color.rgb, 1.0) * outline_color.a * ol;
	col = over(vec4(rgb, 1.0) * fa, col);

	// shockwave: a thin ring expanding outward as the flash decays
	float wave_r = rr + (1.0 - flash) * wave_reach;
	float wave = (1.0 - smoothstep(0.0, 0.03 + px, abs(r - wave_r))) * flash;
	col = over(vec4(flash_color.rgb, 1.0) * wave, col);

	vec3 out_rgb = col.a > 0.0001 ? col.rgb / col.a : vec3(0.0);
	COLOR = vec4(out_rgb, col.a) * COLOR;
}