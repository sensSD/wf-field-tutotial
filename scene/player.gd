extends CharacterBody2D
class_name Player

const NORMAL_ANIMATION_PREFIX := &"normal"

const BULLET_SCENE := preload("res://scene/bullet.tscn")
const ARMED_ANIMATION_PREFIX := &"armed"
const DEFAULT_MOVE_SPEED_MULTIPLIER := 1.0
const DEFAULT_FIRE_RATE_MULTIPLIER := 1.0
const SPIRAL_PHASE_STEP := PI / 12

# 角色节点动画，负责播放四方向移动动画
@onready var body_sprite: AnimatedSprite2D = $BodySprite
# 螺旋强化形态下额外显示的浮游炮特效
@onready var armed_effect_sprite: AnimatedSprite2D = $ArmedEffctSprite
# 射击计时器，只负责限制开火频率
@onready var shooting_timer: Timer = $ShootingTimer

# 当前朝向后缀
var facing_suffix: StringName = &"right"

# 当前移速倍率，由道具效果驱动
var current_move_speed_multiplier: float = DEFAULT_MOVE_SPEED_MULTIPLIER
# 普通射速道具提供的射速倍率
var rapid_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLIER
# 形态道具提供的专属射速倍率
var form_fire_rate_multiplier: float = DEFAULT_FIRE_RATE_MULTIPLIER
# 当前玩家形态
var current_form_mode: int = PickupConfig.PlayerFormMode.NORMAL
# 当前弹幕模式
var current_shot_pattern: int = PickupConfig.ShotPattern.NORMAL
# 三类 Buff 分别维护剩余持续时间，避免互相覆盖
var speed_buff_time_left: float = 0.0
var rapid_buff_time_left: float = 0.0
var form_buff_time_left: float = 0.0
# 螺旋弹幕的相位
var spiral_phase: float = 0.0

# 连续开火间的最短间隔
@export var fire_interval: float = 0.18
# 子弹生成时相对玩家中心的偏移距离，避免子弹生成在身体内部
@export var bullet_spawn_distance: float = 18.0

# 玩家移动速度，单位是 像素/秒。
@export var move_speed:float = 120.0

func _ready() -> void:
  shooting_timer.one_shot = true
  shooting_timer.wait_time = _get_effective_fire_interval()
  _update_animation()
  _update_armed_effect()

func _physics_process(delta: float) -> void:
  _update_pickup_effects(delta)

  # 读取四个方向输入，并得到标准化后的八项输入向量
  var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
  var shoot_input := Input.get_vector("shoot_left", "shoot_right", "shoot_up", "shoot_down")
  
  velocity = move_input * _get_effective_move_speed()
  move_and_slide()
  
  if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
    _try_auto_spiral_shoot()
  elif shoot_input != Vector2.ZERO:
    _try_shoot(shoot_input)

  _update_facing(move_input, shoot_input)
  _update_animation()
  _update_armed_effect()
  
func _update_animation() -> void:
  var animation_name := StringName("%s_%s" % [_get_animation_prefix(), facing_suffix])
  
  if not body_sprite.sprite_frames.has_animation(animation_name):
    var fallback_animation_name := StringName("%s_%s" % [NORMAL_ANIMATION_PREFIX, facing_suffix])
    if not body_sprite.sprite_frames.has_animation(fallback_animation_name):
      push_warning("Missing player animation: %s" % animation_name)
      return
    animation_name = fallback_animation_name

  if body_sprite.animation != animation_name:
    body_sprite.play(animation_name)

    
  if body_sprite.animation != animation_name:
    body_sprite.play(animation_name)
    
# 将任意二维向量映射为四方向动画
func _vector_to_facing_suffix(direction: Vector2) -> StringName:
  if abs(direction.x) >= abs(direction.y):
    return &"right" if direction.x > 0.0 else &"left"
    
  return &"down" if direction.y > 0.0 else &"up"

func _update_facing(move_input: Vector2, shoot_input: Vector2) -> void:
  if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
    if move_input !=  Vector2.ZERO:
      facing_suffix = _vector_to_facing_suffix(move_input)
    return

  if shoot_input != Vector2.ZERO:
    facing_suffix = _vector_to_facing_suffix(shoot_input)
  elif move_input != Vector2.ZERO:
    facing_suffix = _vector_to_facing_suffix(move_input)

# 尝试发射子弹：先检查冷却，再根据当前弹幕模式发射
func _try_shoot(shoot_input: Vector2) -> void:
  if not shooting_timer.is_stopped():
    return

  var shoot_direction := shoot_input.normalized()
  var has_spawned_bullet := _fire_bullets(shoot_direction)
  if has_spawned_bullet:
    shooting_timer.start(_get_effective_fire_interval())

# 道具统一通过这个入口影响玩家
func apply_pickup(config: PickupConfig) -> bool:
  if config == null:
    return false

  var applied := false
  var should_refresh_shooting_timer := false
  var buff_duration := maxf(config.duration, 0.0)
  var has_form_override := (
    config.player_form_mode != PickupConfig.PlayerFormMode.NORMAL
    or config.shot_pattern != PickupConfig.ShotPattern.NORMAL
  )
  var has_fire_rate_override := not is_equal_approx(
    config.fire_rate_multiplier,
    DEFAULT_FIRE_RATE_MULTIPLIER
  )

  if not is_equal_approx(config.move_speed_multiplier, DEFAULT_MOVE_SPEED_MULTIPLIER):
    current_move_speed_multiplier = config.move_speed_multiplier
    speed_buff_time_left = buff_duration
    applied = true

  # 普通射速道具与形态专属射速拆开维护，避免螺旋形态的射速被其他 Buff 覆盖
  if has_fire_rate_override and not has_form_override:
    rapid_fire_rate_multiplier = config.fire_rate_multiplier
    rapid_buff_time_left = buff_duration
    should_refresh_shooting_timer = true
    applied = true

  if has_form_override:
    current_form_mode = config.player_form_mode
    current_shot_pattern = config.shot_pattern
    form_fire_rate_multiplier = (
      config.fire_rate_multiplier if has_fire_rate_override else DEFAULT_FIRE_RATE_MULTIPLIER
    )
    form_buff_time_left = buff_duration
    spiral_phase = 0.0
    should_refresh_shooting_timer = true
    applied = true

  if should_refresh_shooting_timer:
    _refresh_shooting_timer_wait_time()

  return applied
  

# 根据当前弹幕模式发射子弹，并返回这次是否至少生成了一枚子弹
func _fire_bullets(base_direction: Vector2) -> bool:
  if current_shot_pattern == PickupConfig.ShotPattern.SPIRAL:
    var has_spawned_forward_bullet := _spawn_bullet(base_direction)
    var has_spawned_backward_bullet := _spawn_bullet(base_direction.rotated(PI))
    spiral_phase = wrapf(spiral_phase + SPIRAL_PHASE_STEP, 0.0, TAU)
    return has_spawned_forward_bullet or has_spawned_backward_bullet

  return _spawn_bullet(base_direction)

# 实例化生成一枚子弹
func _spawn_bullet(shoot_direction: Vector2) -> bool:
  var bullet := BULLET_SCENE.instantiate() as Bullet
  if bullet == null:
    return false

  bullet.top_level = true
  bullet.setup(shoot_direction)

  # 子弹挂载到当前主场景下，避免与玩家一同移动
  var spawn_parent := get_tree().current_scene
  if spawn_parent == null:
    return false

  spawn_parent.add_child(bullet)
  bullet.global_position = global_position + shoot_direction * bullet_spawn_distance
  return true

# 螺旋形态下自动按固定节奏朝 360 度方向旋转发射
func _try_auto_spiral_shoot() -> void:
  if not shooting_timer.is_stopped():
    return

  var spiral_direction := Vector2.RIGHT.rotated(spiral_phase)
  var has_spawned_bullet := _fire_bullets(spiral_direction)
  if has_spawned_bullet:
    shooting_timer.start(_get_effective_fire_interval())

# 每帧更新道具 Buff 剩余时间，并在到期后恢复默认状态
func _update_pickup_effects(delta: float) -> void:
  if speed_buff_time_left > 0.0:
    speed_buff_time_left = maxf(speed_buff_time_left - delta, 0.0)
    if speed_buff_time_left <= 0.0:
      current_move_speed_multiplier = DEFAULT_MOVE_SPEED_MULTIPLIER
      _refresh_shooting_timer_wait_time()

  if rapid_buff_time_left > 0.0:
    rapid_buff_time_left = maxf(rapid_buff_time_left - delta, 0.0)
    if rapid_buff_time_left <= 0.0:
      rapid_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLIER
      _refresh_shooting_timer_wait_time()

  if form_buff_time_left > 0.0:
    form_buff_time_left = maxf(form_buff_time_left - delta, 0.0)
    if form_buff_time_left <= 0.0:
      current_form_mode = PickupConfig.PlayerFormMode.NORMAL
      current_shot_pattern = PickupConfig.ShotPattern.NORMAL
      form_fire_rate_multiplier = DEFAULT_FIRE_RATE_MULTIPLIER
      spiral_phase = 0.0
      _refresh_shooting_timer_wait_time()

# 计算当前有效开火间隔，倍率越高，间隔越短
func _get_effective_fire_interval() -> float:
  return maxf(fire_interval / _get_effective_fire_rate_multiplier(), 0.01)

func _get_effective_move_speed() -> float:
  return move_speed * current_move_speed_multiplier

# 强化形态激活时优先使用形态自带的射速倍率，否则返回普通射速倍率
func _get_effective_fire_rate_multiplier() -> float:
  if _has_active_form_override():
    return maxf(form_fire_rate_multiplier, 0.01)

  return maxf(rapid_fire_rate_multiplier, 0.01)

# 只要玩家处于特殊形态或特殊弹幕模式，就视为强化仍在生效
func _has_active_form_override() -> bool:
  return (
    current_form_mode != PickupConfig.PlayerFormMode.NORMAL
    or current_shot_pattern != PickupConfig.ShotPattern.NORMAL
  )

# 根据当前形态选择动画前缀
func _get_animation_prefix() -> StringName:
  if current_form_mode != PickupConfig.PlayerFormMode.ARMED:
    return ARMED_ANIMATION_PREFIX

  return NORMAL_ANIMATION_PREFIX

# 统一刷新射击计时器的基础间隔，避免 Buff 生效后仍使用旧数值
func _refresh_shooting_timer_wait_time() -> void:
  var new_interval := _get_effective_fire_interval()
  shooting_timer.wait_time = new_interval

  # 如果玩家在冷却途中拾取了更快射速的 Buff，需要让当前的这次冷却也立刻缩短
  if shooting_timer.is_stopped():
    return
  if shooting_timer.time_left <= new_interval:
    return
  
  shooting_timer.start(new_interval)

# 强化螺旋状态下显示浮游炮动画，结束后隐藏并停止播放
func _update_armed_effect() -> void:
  var is_armed := current_form_mode == PickupConfig.PlayerFormMode.ARMED

  if not is_armed:
    if armed_effect_sprite.visible:
      armed_effect_sprite.visible = false
    if armed_effect_sprite.is_playing():
      armed_effect_sprite.stop()
    return

  if not armed_effect_sprite.visible:
    armed_effect_sprite.visible = true
  if armed_effect_sprite.is_playing():
    return
  if armed_effect_sprite.sprite_frames == null:
    return

  if armed_effect_sprite.sprite_frames.has_animation(&"default"):
    armed_effect_sprite.play(&"default")
