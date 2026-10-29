// Spinning knife: one flat quad lying in the spin plane. Draws a simple knife silhouette at the
// current spin angle plus motion-blur smears trailing the blade and handle.
// The quad doesn't rotate; the script advances spin_angle.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;   // overall fade (spin up / down)
uniform float speed : hint_range(0.0, 1.0) = 1.0;       // normalised spin speed -> trail length
uniform float spin_angle = 0.0;                         // radians, set by the script
uniform float direction = 1.0;                          // set by the script (1 or -1)
uniform float blade_angle_deg = 0.0;                    // rotate the whole knife within the quad

group_uniforms knife;            // sizes as fractions of the quad's half-size (1 = quad edge)
uniform float blade_inner = 0.12;
uniform float blade_outer = 0.98;
uniform float blade_width = 0.07;
uniform float handle_inner = 0.05;
uniform float handle_outer = 0.45;
uniform float handle_width = 0.06;
uniform vec4 blade_color : source_color = vec4(0.75, 0.77, 0.82, 1.0);
uniform vec4 handle_color : source_color = vec4(0.12, 0.1, 0.09, 1.0);
uniform float knife_opacity = 0.9;     // the silhouette itself; lower it if the smear alone reads better

group_uniforms smear;
uniform float smear_arc = 2.6;         // radians of trail at full speed
uniform float handle_strength = 0.35;
uniform float edge_softness = 0.04;
uniform vec4 smear_color : source_color = vec4(0.8, 0.84, 0.9, 1.0);
uniform vec4 tip_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float smear_opacity = 0.55;
uniform float streak_count = 14.0;
uniform float streak_strength = 0.5;
uniform float glint_angle = 0.8;       // where in the rotation the blade catches the light
uniform float glint_strength = 0.8;
group_uniforms;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), u);
}

float band(float r, float a, float b) {
	return smoothstep(a, a + edge_softness, r) * (1.0 - smoothstep(b - edge_softness, b, r));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;
	float px = length(fwidth(p));
	float r = length(p);
	float theta = spin_angle + radians(blade_angle_deg);

	// ---- smear: angle behind the blade (0 at the blade, growing backwards along the trail)
	float a = atan(p.y, p.x) - theta;
	float d_blade = mod(-direction * a, TAU);
	float d_handle = mod(-direction * (a - PI), TAU);
	float arc = max(smear_arc * speed, 0.001);
	float trail_blade = pow(clamp(1.0 - d_blade / arc, 0.0, 1.0), 2.0);
	float trail_handle = pow(clamp(1.0 - d_handle / arc, 0.0, 1.0), 2.0);
	float streak = mix(1.0, 0.4 + 0.6 * noise1(r * streak_count), streak_strength);

	float tip = smoothstep(blade_outer * 0.6, blade_outer, r) * trail_blade;
	float glint = pow(max(cos(spin_angle - glint_angle), 0.0), 24.0) * glint_strength;
	vec3 smear_rgb = mix(smear_color.rgb, tip_color.rgb, tip) + glint * pow(trail_blade, 4.0);
	float smear_a = (trail_blade * band(r, blade_inner, blade_outer)
	              + handle_strength * trail_handle * band(r, handle_inner, handle_outer))
	              * streak * smear_opacity;

	// ---- knife silhouette at the current angle (blade along +X, handle along -X)
	vec2 q = vec2(cos(theta) * p.x + sin(theta) * p.y, -sin(theta) * p.x + cos(theta) * p.y);
	float taper = clamp((q.x - blade_inner) / (blade_outer - blade_inner), 0.0, 1.0);
	float d_bl = max(abs(q.y) - blade_width * (1.0 - taper),
	                 max(blade_inner - q.x, q.x - blade_outer));
	float d_hd = max(abs(q.y) - handle_width, max(-handle_outer - q.x, q.x + handle_inner));
	float on_blade = 1.0 - smoothstep(-px, px, d_bl);
	float on_handle = 1.0 - smoothstep(-px, px, d_hd);
	vec3 knife_rgb = blade_color.rgb + glint * 0.5;
	knife_rgb = mix(knife_rgb, handle_color.rgb, on_handle);
	float knife_a = max(on_blade, on_handle) * knife_opacity;

	// knife over smear
	float out_a = knife_a + smear_a * (1.0 - knife_a);
	vec3 out_rgb = (knife_rgb * knife_a + smear_rgb * smear_a * (1.0 - knife_a)) / max(out_a, 0.0001);
	ALBEDO = out_rgb;
	ALPHA = clamp(out_a * intensity, 0.0, 1.0);
}