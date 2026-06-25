shader_type canvas_item;

// 是否开启闪烁
uniform bool blink_enabled = false;
// 闪烁速度
uniform float blink_speed : hint_range(1.0, 30.0) = 12.0;
// 隐藏状态的时间占比
uniform float hidden_ratio : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	
	if (blink_enabled && color.a > 0.0) {
		float blink_phase = fract(TIME * blink_speed);
		if (blink_phase < hidden_ratio) {
			color.a = 0.0;
		}
	}
	
	COLOR = color;
}
