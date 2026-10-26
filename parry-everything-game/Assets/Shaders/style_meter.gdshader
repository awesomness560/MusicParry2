// Style meter bar: a simple bar with an uneven, hand-inked black border.
// Fills from the bottom up. Rotate the node however you like.
// Driven by style_meter_bar.gd (fill, trail, spark, rect_size, fill_color).

shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(40.0, 260.0);         // node size in px, set by the script
uniform float fill  : hint_range(0.0, 1.0) = 0.6;
uniform float trail : hint_range(0.0, 1.0) = 0.6;   // below fill = the white "just gained" part
uniform float spark : hint_range(0.0, 1.0) = 0.0;   // spark strength at the end of the fill

group_uniforms colors;
uniform vec4 fill_color    : source_color = vec4(0.86, 0.16, 0.14, 1.0);
uniform vec4 gain_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 track_color   : source_color = vec4(0.12, 0.12, 0.12, 0.85);
uniform vec4 border_color  : source_color = vec4(0.02, 0.02, 0.02, 1.0);
uniform vec4 spark_color   : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 warning_color : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform float warning : hint_range(0.0, 1.0) = 0.0;   // brink pulse, driven by the script

group_uniforms border;
uniform float margin       = 10.0;  // px around the bar for the border and spark glow
uniform float border_out   = 2.5;   // average thickness outside the bar
uniform float border_in    = 1.5;   // average depth the ink bites into the bar
uniform float border_vary  = 2.0;   // how uneven the thickness is
uniform float border_scale = 0.06;  // how quickly it varies along the edge
uniform float border_seed  = 0.0;   // change for a different ink pattern

group_uniforms spark_shape;
uniform float spark_line   = 2.0;   // px thickness of the bright line at the fill end
uniform float spark_reach  = 1.6;   // how far the glow spreads sideways, relative to bar width
uniform float spark_height = 10.0;  // px vertical size of the glow
group_uniforms;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
	           mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return (vnoise(p) * 0.6 + vnoise(p * 2.1 + 5.3) * 0.3 + vnoise(p * 4.3 + 9.1) * 0.1);
}

vec4 over(vec4 top, vec4 bottom) {   // premultiplied
	return top + bottom * (1.0 - top.a);
}

vec4 pm(vec3 rgb, float a) {
	return vec4(rgb * a, a);
}

void fragment() {
	vec4 tint = COLOR;
	// px coordinates: origin at bottom centre, +y up the bar
	vec2 p = vec2((UV.x - 0.5) * rect_size.x, (1.0 - UV.y) * rect_size.y);
	float px = max(length(fwidth(p)), 0.5);

	// bar rectangle inside the margin
	vec2 half_size = vec2(rect_size.x * 0.5 - margin, rect_size.y * 0.5 - margin);
	vec2 q = abs(p - vec2(0.0, rect_size.y * 0.5)) - half_size;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);   // <0 inside the bar

	// fill: bottom of the bar up to fill height
	float bottom = margin;
	float bar_len = rect_size.y - 2.0 * margin;
	float y = p.y - bottom;
	float fill_y = fill * bar_len;
	float trail_y = trail * bar_len;
	float inside = 1.0 - smoothstep(-px, px, d);
	float c_fill = 1.0 - smoothstep(fill_y - px, fill_y + px, y);
	float c_trail = 1.0 - smoothstep(trail_y - px, trail_y + px, y);
	float gained = c_fill * (1.0 - c_trail);

	vec4 col = vec4(0.0);
	col = over(pm(track_color.rgb, track_color.a * inside), col);
	col = over(pm(fill_color.rgb, fill_color.a * c_fill * inside), col);
	col = over(pm(gain_color.rgb, gain_color.a * gained * inside), col);

	// uneven ink border: thickness varies along the edge, sometimes biting into the fill
	vec2 np = p * border_scale + vec2(border_seed * 7.13, border_seed * 3.71);
	float n_out = fbm(np);
	float n_in = fbm(np + 31.7);
	float outer = max(border_out + (n_out - 0.5) * 2.0 * border_vary, 0.5);
	float inner = max(border_in + (n_in - 0.5) * 2.0 * border_vary, 0.0);
	float ink = (1.0 - smoothstep(outer - px, outer + px, d)) * smoothstep(-inner - px, -inner + px, d);
	vec3 ink_rgb = mix(border_color.rgb, warning_color.rgb, warning * 0.8);
	col = over(pm(ink_rgb, border_color.a * ink), col);

	// brink warning: the fill's edge pulses
	float warn_line = (1.0 - smoothstep(1.5, 1.5 + px, abs(y - fill_y))) * inside * warning * step(0.001, fill);
	col = over(pm(warning_color.rgb, warn_line), col);
	// spark at the end of the fill: bright line across the bar plus a soft glow spilling past the edges
	float on = spark * step(0.001, fill) * (1.0 - step(0.999, fill));
	float dy = y - fill_y;
	float line = (1.0 - smoothstep(spark_line * 0.5, spark_line * 0.5 + px, abs(dy))) * inside;
	float gx = p.x / (half_size.x * spark_reach);
	float gy = dy / spark_height;
	float glow = exp(-(gx * gx + gy * gy) * 2.5);
	float s = clamp((line + glow * 0.8) * on, 0.0, 1.0);
	col = over(pm(spark_color.rgb, s * spark_color.a), col);

	vec3 rgb = col.a > 0.0001 ? col.rgb / col.a : vec3(0.0);
	COLOR = vec4(rgb * tint.rgb, col.a * tint.a);
}