extends CharacterBody2D

const NORMAL_ANIMATION_PREFIX := &"normal"

# 角色节点动画，负责播放四方向移动动画
@onready var body_sprite: AnimatedSprite2D = $BodySprite

# 当前朝向后缀
var facing_suffix: StringName = &"right"

# 玩家移动速度，单位是 像素/秒。
@export var move_speed:float = 120.0

func _ready() -> void:
	_update_animation()

func _physics_process(delta: float) -> void:
	# 读取四个方向输入，并得到标准化后的八项输入向量
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	velocity = move_input * move_speed
	move_and_slide()
	
	if move_input != Vector2.ZERO:
		facing_suffix = _vector_to_facing_suffix(move_input)
		
	_update_animation()
	
func _update_animation() -> void:
	var animation_name := StringName("%s_%s" % [NORMAL_ANIMATION_PREFIX, facing_suffix])
	
	if not body_sprite.sprite_frames.has_animation(animation_name):
		push_warning("Missing player animation: %s" % animation_name)
		return 
		
	if body_sprite.animation != animation_name:
		body_sprite.play(animation_name)
		
func _vector_to_facing_suffix(direction: Vector2) -> StringName:
	if abs(direction.x) >= abs(direction.y):
		return &"right" if direction.x > 0.0 else &"left"
		
	return &"down" if direction.y > 0.0 else &"up"
